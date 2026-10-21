import Foundation

/// One row from a GetSongBPM search, before we decide it matches the song.
struct TempoHit: Sendable, Equatable {
    var title: String
    var artist: String
    var tempo: String
    var timeSignature: String
    var musicalKey: String
}

/// Tempo the picture is allowed to follow. `bpm` is beats per minute.
struct TrackTempo: Sendable, Equatable {
    var bpm: Double
    var beatsPerBar: Int
    var timeSignature: String
    var musicalKey: String?
    var matchedTitle: String
    var matchedArtist: String

    /// Short line for the corner card, for example "116 BPM · 4/4 · Fm".
    var detail: String {
        var parts = ["\(Int(bpm.rounded())) BPM"]
        if !timeSignature.isEmpty {
            parts.append(timeSignature)
        }
        if let musicalKey, !musicalKey.isEmpty {
            parts.append(musicalKey)
        }
        return parts.joined(separator: " · ")
    }
}

/// Pure string and beat math. No network, so a bad match cannot leak into the clock.
enum TempoText {
    /// Eight bars. In 4/4 that is 32 beats; in 3/4 it is 24.
    static let barsPerPhrase = 8

    static func cacheKey(title: String, artist: String) -> String {
        normalize(title) + "\n" + normalize(artist)
    }

    /// Letters and digits only, lowercased, accents folded. Used for matching and caching.
    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace, !out.isEmpty {
                    out.append(" ")
                }
                pendingSpace = false
                out.unicodeScalars.append(scalar)
            } else if !out.isEmpty {
                pendingSpace = true
            }
        }
        return out
    }

    static func compact(_ raw: String) -> String {
        normalize(raw).replacingOccurrences(of: " ", with: "")
    }

    /// Percent-encode a query piece. Structural characters (`song:`, `+artist:`) stay outside this.
    static func queryEscape(_ raw: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    /// GetSongBPM sends `tempo` as a string ("116"). The docs also say integer, so both are accepted.
    static func parseBPM(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let numeric = trimmed.prefix { $0.isNumber || $0 == "." || $0 == "-" }
        guard let value = Double(numeric), value.isFinite else { return nil }
        // The tempo endpoint documents 40–220. Allow a little headroom for fast songs.
        guard value >= 40, value <= 250 else { return nil }
        return value
    }

    /// `time_sig` comes back as "4/4". A bare "4" is treated as 4/4. Missing means 4/4.
    static func timeSignature(from raw: String?) -> (beats: Int, label: String) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let numerator: Int
        if trimmed.isEmpty {
            numerator = 4
        } else if let slash = trimmed.firstIndex(of: "/") {
            numerator = Int(trimmed[..<slash]) ?? 4
        } else {
            numerator = Int(trimmed.prefix { $0.isNumber }) ?? 4
        }
        let beats = min(max(numerator, 2), 12)
        if trimmed.contains("/") {
            return (beats, trimmed)
        }
        return (beats, "\(beats)/4")
    }

    static func bestMatch(hits: [TempoHit], title: String, artist: String) -> TrackTempo? {
        let wantTitle = normalize(title)
        guard !wantTitle.isEmpty else { return nil }
        let wantArtist = normalize(artist)
        var bestScore = 0
        var best: TrackTempo?
        for hit in hits {
            guard let bpm = parseBPM(hit.tempo) else { continue }
            let score = matchScore(
                wantTitle: wantTitle,
                wantArtist: wantArtist,
                gotTitle: normalize(hit.title),
                gotArtist: normalize(hit.artist)
            )
            guard score > bestScore else { continue }
            let signature = timeSignature(from: hit.timeSignature)
            let key = hit.musicalKey.trimmingCharacters(in: .whitespacesAndNewlines)
            bestScore = score
            best = TrackTempo(
                bpm: bpm,
                beatsPerBar: signature.beats,
                timeSignature: signature.label,
                musicalKey: key.isEmpty ? nil : key,
                matchedTitle: hit.title,
                matchedArtist: hit.artist
            )
        }
        return best
    }

    /// How long until the next phrase boundary. Zero means we are on it (or just crossed it).
    static func secondsUntilPhrase(trackTime: TimeInterval, bpm: Double, beatsPerBar: Int) -> TimeInterval {
        let safeBPM = max(bpm, 1)
        let phraseBeats = Double(max(beatsPerBar, 1) * barsPerPhrase)
        let beats = max(0, trackTime) * safeBPM / 60
        let phrase = beats / phraseBeats
        let into = phrase - floor(phrase)
        let secondsPerPhrase = phraseBeats * 60 / safeBPM
        let since = into * secondsPerPhrase
        if since <= 0.12 { return 0 }
        return secondsPerPhrase - since
    }

    /// Smooth kick: 1 on the beat, back to 0 over `width` of the beat. Not a strobe.
    static func envelope(phase: Double, width: Double) -> Double {
        guard phase >= 0, phase < width, width > 0 else { return 0 }
        let x = phase / width
        return 0.5 + 0.5 * cos(x * Double.pi)
    }

    struct MusicalFrame: Sendable {
        var kick: Double
        var downbeat: Double
        var beatPhase: Double
        var barPhase: Double
        var phrasePhase: Double
    }

    static func musicalFrame(trackTime: TimeInterval, bpm: Double, beatsPerBar: Int) -> MusicalFrame {
        let safeBPM = max(bpm, 1)
        let barBeats = Double(max(beatsPerBar, 1))
        let beats = max(0, trackTime) * safeBPM / 60
        let beatPhase = beats - floor(beats)
        let bar = beats / barBeats
        let barPhase = bar - floor(bar)
        let phraseBeats = barBeats * Double(barsPerPhrase)
        let phrase = beats / phraseBeats
        let phrasePhase = phrase - floor(phrase)
        let whole = Int(floor(beats))
        let isDownbeat = whole % max(beatsPerBar, 1) == 0
        let kick = envelope(phase: beatPhase, width: 0.22)
        let downbeat = isDownbeat ? envelope(phase: beatPhase, width: 0.34) : 0
        return MusicalFrame(
            kick: kick,
            downbeat: downbeat,
            beatPhase: beatPhase,
            barPhase: barPhase,
            phrasePhase: phrasePhase
        )
    }

    /// Decode a `/search/` body. `tempo` may be a string or a number. A non-array `search` is no hits.
    static func decodeSearch(_ data: Data) -> [TempoHit] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let rows = json["search"] as? [Any] else { return [] }
        var hits: [TempoHit] = []
        for row in rows {
            guard let object = row as? [String: Any] else { continue }
            let title = string(object["title"]) ?? ""
            let artist = artistName(object["artist"])
            guard let tempo = string(object["tempo"]), !tempo.isEmpty else { continue }
            hits.append(TempoHit(
                title: title,
                artist: artist,
                tempo: tempo,
                timeSignature: string(object["time_sig"]) ?? "",
                musicalKey: string(object["key_of"]) ?? ""
            ))
        }
        return hits
    }

    private static func matchScore(wantTitle: String, wantArtist: String, gotTitle: String, gotArtist: String) -> Int {
        let titleScore = titleMatch(wantTitle, gotTitle)
        guard titleScore > 0 else { return 0 }
        // No artist on the now-playing item: only an exact title is safe.
        if wantArtist.isEmpty { return titleScore >= 7 ? titleScore : 0 }
        guard !gotArtist.isEmpty else { return 0 }
        let artistScore = artistMatch(wantArtist, gotArtist)
        guard artistScore > 0 else { return 0 }
        return titleScore + artistScore
    }

    private static func titleMatch(_ want: String, _ got: String) -> Int {
        if want == got { return 8 }
        if compact(want) == compact(got), !compact(want).isEmpty { return 7 }
        if contained(want, got) { return 5 }
        return 0
    }

    private static func artistMatch(_ want: String, _ got: String) -> Int {
        if want == got { return 6 }
        if compact(want) == compact(got), !compact(want).isEmpty { return 5 }
        if contained(want, got) { return 4 }
        let overlap = tokenSet(want).intersection(tokenSet(got))
        if !overlap.isEmpty { return 3 }
        return 0
    }

    /// Shared words such as "the" do not count as the same artist.
    private static func tokenSet(_ normalized: String) -> Set<String> {
        let ignored: Set<String> = ["the", "and", "feat", "featuring", "with", "vs", "pt", "part", "remix"]
        var tokens: Set<String> = []
        for part in normalized.split(separator: " ") {
            let word = String(part)
            guard word.count >= 3, !ignored.contains(word) else { continue }
            tokens.insert(word)
        }
        return tokens
    }

    /// "Get Lucky" matches "Get Lucky (Radio Edit)", not a short word inside another title.
    private static func contained(_ a: String, _ b: String) -> Bool {
        let left = compact(a)
        let right = compact(b)
        guard left.count >= 5, right.count >= 5 else { return false }
        let shorter = left.count <= right.count ? left : right
        let longer = left.count <= right.count ? right : left
        guard longer.contains(shorter) else { return false }
        if shorter.count >= 8 { return true }
        return longer.hasPrefix(shorter) && shorter.count * 2 >= longer.count
    }

    private static func artistName(_ value: Any?) -> String {
        if let object = value as? [String: Any] {
            return string(object["name"]) ?? ""
        }
        if let list = value as? [[String: Any]], let first = list.first {
            return string(first["name"]) ?? ""
        }
        return ""
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            // JSON numbers arrive as NSNumber. `stringValue` is "116" for an integer tempo.
            return number.stringValue
        default:
            return nil
        }
    }
}
