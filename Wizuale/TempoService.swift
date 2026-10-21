import Foundation

/// Result of one title + artist lookup. `.unavailable` is not cached:
/// a missing key, a network error, or a rate limit should be tried again later.
enum TempoOutcome: Sendable, Equatable {
    case matched(TrackTempo)
    case noMatch
    case unavailable
}

/// GetSongBPM search. The key is read from Info.plist (`GetSongBPMAPIKey`),
/// which the build fills from `GETSONGBPM_API_KEY` in Config/Secrets.xcconfig.
actor TempoService {
    static let shared = TempoService()

    private struct Record: Codable {
        var miss: Bool
        var bpm: Double?
        var beatsPerBar: Int?
        var timeSignature: String?
        var musicalKey: String?
        var matchedTitle: String?
        var matchedArtist: String?
        var savedAt: Date
    }

    private struct DiskCache: Codable {
        var records: [String: Record]
    }

    private enum TempoError: Error {
        case badResponse
        case rejected
        case limited
    }

    private var records: [String: Record] = [:]
    private var loaded = false
    private var keyRejected = false
    private var backoffUntil = Date.distantPast

    func lookup(title: String, artist: String) async -> TempoOutcome {
        let trimmedTitle = clip(title)
        let trimmedArtist = clip(artist)
        guard !trimmedTitle.isEmpty else { return .unavailable }

        let key = TempoText.cacheKey(title: trimmedTitle, artist: trimmedArtist)
        loadIfNeeded()
        if let record = records[key], isFresh(record) {
            return outcome(from: record)
        }
        guard let apiKey = TempoConfig.apiKey else { return .unavailable }
        if keyRejected { return .unavailable }
        if Date() < backoffUntil { return .unavailable }

        do {
            var hits: [TempoHit]
            if trimmedArtist.isEmpty {
                hits = try await search(apiKey: apiKey, type: "song", title: trimmedTitle, artist: "")
            } else {
                hits = try await search(apiKey: apiKey, type: "both", title: trimmedTitle, artist: trimmedArtist)
                // The documented title+artist query sometimes returns nothing useful.
                // A title-only search is the second chance; artist scoring still has to agree.
                if TempoText.bestMatch(hits: hits, title: trimmedTitle, artist: trimmedArtist) == nil {
                    hits += try await search(apiKey: apiKey, type: "song", title: trimmedTitle, artist: "")
                }
            }
            if let tempo = TempoText.bestMatch(hits: hits, title: trimmedTitle, artist: trimmedArtist) {
                store(key, record: Record(
                    miss: false,
                    bpm: tempo.bpm,
                    beatsPerBar: tempo.beatsPerBar,
                    timeSignature: tempo.timeSignature,
                    musicalKey: tempo.musicalKey,
                    matchedTitle: tempo.matchedTitle,
                    matchedArtist: tempo.matchedArtist,
                    savedAt: Date()
                ))
                return .matched(tempo)
            }
            store(key, record: Record(miss: true, savedAt: Date()))
            return .noMatch
        } catch TempoError.rejected {
            keyRejected = true
            return .unavailable
        } catch TempoError.limited {
            backoffUntil = Date().addingTimeInterval(15 * 60)
            return .unavailable
        } catch {
            return .unavailable
        }
    }

    /// `type=both` uses the documented `song:TITLE artist:ARTIST` lookup.
    /// Title and artist are encoded on their own so the `song:` / `artist:` markers stay literal.
    private func search(apiKey: String, type: String, title: String, artist: String) async throws -> [TempoHit] {
        let lookup: String
        if type == "both" {
            lookup = "song:\(TempoText.queryEscape(title))+artist:\(TempoText.queryEscape(artist))"
        } else {
            lookup = TempoText.queryEscape(title)
        }
        let urlString = "https://api.getsong.co/search/?api_key=\(TempoText.queryEscape(apiKey))&type=\(TempoText.queryEscape(type))&lookup=\(lookup)&limit=10"
        guard let url = URL(string: urlString) else { throw TempoError.badResponse }

        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TempoError.badResponse
        }
        guard let http = response as? HTTPURLResponse else { throw TempoError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw TempoError.rejected }
        if http.statusCode == 429 { throw TempoError.limited }
        guard (200...299).contains(http.statusCode) else { throw TempoError.badResponse }
        return TempoText.decodeSearch(data)
    }

    private func outcome(from record: Record) -> TempoOutcome {
        guard !record.miss, let bpm = record.bpm else { return .noMatch }
        return .matched(TrackTempo(
            bpm: bpm,
            beatsPerBar: record.beatsPerBar ?? 4,
            timeSignature: record.timeSignature ?? "4/4",
            musicalKey: record.musicalKey,
            matchedTitle: record.matchedTitle ?? "",
            matchedArtist: record.matchedArtist ?? ""
        ))
    }

    private func isFresh(_ record: Record) -> Bool {
        let age = Date().timeIntervalSince(record.savedAt)
        if record.miss { return age < 3 * 24 * 3600 }
        return age < 30 * 24 * 3600
    }

    private func store(_ key: String, record: Record) {
        records[key] = record
        if records.count > 400 {
            let oldest = records.sorted { $0.value.savedAt < $1.value.savedAt }
            for entry in oldest.prefix(records.count - 400) {
                records.removeValue(forKey: entry.key)
            }
        }
        persist()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let disk = try? decoder.decode(DiskCache.self, from: data) else { return }
        records = disk.records
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(DiskCache(records: records)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("getsongbpm-tempo.json")
    }

    private func clip(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 180 { return trimmed }
        return String(trimmed.prefix(180))
    }
}

enum TempoConfig {
    /// Empty, unresolved `$(GETSONGBPM_API_KEY)`, and the example placeholder all mean "no key".
    static var apiKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GetSongBPMAPIKey") as? String else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty || key.contains("$(") || key == "YOUR_KEY_HERE" {
            return nil
        }
        return key
    }
}
