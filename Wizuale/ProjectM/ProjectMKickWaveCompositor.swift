import Foundation
import OpenGLES
import UIKit

/// Brightness-neutral radial UV warp after libprojectM — outward tsunami rings on kick envelope.
final class ProjectMKickWaveCompositor {
    private var program: GLuint = 0
    private var sceneFBO: GLuint = 0
    private var sceneColor: GLuint = 0
    private var depthRB: GLuint = 0
    private var vao: GLuint = 0
    private var size = CGSize.zero

    private var locTex = GLint(-1)
    private var locEnvelope = GLint(-1)
    private var locKickAge = GLint(-1)
    private var locAspect = GLint(-1)
    private var locRingFreq = GLint(-1)
    private var locWaveSpeed = GLint(-1)
    private var locMaxDisp = GLint(-1)

    var sceneFramebuffer: GLuint { sceneFBO }

    func createIfNeeded(in context: EAGLContext) {
        guard program == 0 else { return }
        EAGLContext.setCurrent(context)
        program = linkProgram(vertex: Self.vertexSource, fragment: Self.fragmentSource)
        locTex = glGetUniformLocation(program, "uScene")
        locEnvelope = glGetUniformLocation(program, "uEnvelope")
        locKickAge = glGetUniformLocation(program, "uKickAge")
        locAspect = glGetUniformLocation(program, "uAspect")
        locRingFreq = glGetUniformLocation(program, "uRingFreq")
        locWaveSpeed = glGetUniformLocation(program, "uWaveSpeed")
        locMaxDisp = glGetUniformLocation(program, "uMaxDisp")

        glGenVertexArrays(1, &vao)
    }

    func destroy(in context: EAGLContext?) {
        guard let context else { return }
        EAGLContext.setCurrent(context)
        if vao != 0 { glDeleteVertexArrays(1, &vao); vao = 0 }
        if program != 0 { glDeleteProgram(program); program = 0 }
        deleteSceneTargets()
        size = .zero
    }

    func resizeIfNeeded(_ pixelSize: CGSize, context: EAGLContext) {
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return }
        if size == pixelSize, sceneFBO != 0 { return }
        EAGLContext.setCurrent(context)
        deleteSceneTargets()
        size = pixelSize
        let w = GLsizei(pixelSize.width.rounded())
        let h = GLsizei(pixelSize.height.rounded())

        glGenTextures(1, &sceneColor)
        glBindTexture(GLenum(GL_TEXTURE_2D), sceneColor)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glTexImage2D(
            GLenum(GL_TEXTURE_2D), 0, GL_RGBA,
            w, h, 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil
        )

        glGenRenderbuffers(1, &depthRB)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), depthRB)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH_COMPONENT16), w, h)

        glGenFramebuffers(1, &sceneFBO)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), sceneFBO)
        glFramebufferTexture2D(
            GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_TEXTURE_2D), sceneColor, 0
        )
        glFramebufferRenderbuffer(
            GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT),
            GLenum(GL_RENDERBUFFER), depthRB
        )
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GLenum(GL_FRAMEBUFFER_COMPLETE) {
            NSLog("[Wizuale] kick-wave FBO incomplete: %u", status)
        }
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    /// Sample projectM offscreen texture with radial displacement into the bound drawable FBO.
    func drawKickWave(
        envelope: Float,
        kickAgeSeconds: Float,
        strengthScale: Float,
        drawableSize: CGSize
    ) {
        guard program != 0, sceneColor != 0 else { return }
        let env = min(max(envelope, 0), 1.4)
        let strength = min(max(strengthScale, 0), 1)
        let maxDisp = MicTuning.kickWaveShaderMaxDisplacement(strengthScale: strength)
        guard env > 1e-4, maxDisp > 1e-5 else {
            blitScenePassthrough(drawableSize: drawableSize)
            return
        }

        glUseProgram(program)
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), sceneColor)
        glUniform1i(locTex, 0)
        glUniform1f(locEnvelope, env)
        glUniform1f(locKickAge, max(0, kickAgeSeconds))
        let aspect = drawableSize.height > 1 ? Float(drawableSize.width / drawableSize.height) : 1
        glUniform1f(locAspect, aspect)
        glUniform1f(locRingFreq, MicTuning.kickWaveRingFrequency)
        glUniform1f(locWaveSpeed, MicTuning.kickWavePhaseSpeed)
        glUniform1f(locMaxDisp, maxDisp)

        glDisable(GLenum(GL_DEPTH_TEST))
        glBindVertexArray(vao)
        glDrawArrays(GLenum(GL_TRIANGLES), 0, 3)
        glBindVertexArray(0)
    }

    /// When envelope is ~0, still copy projectM texture to the drawable (no-op warp was invisible).
    private func blitScenePassthrough(drawableSize: CGSize) {
        guard program != 0, sceneColor != 0 else { return }
        glUseProgram(program)
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), sceneColor)
        glUniform1i(locTex, 0)
        glUniform1f(locEnvelope, 0)
        glUniform1f(locKickAge, 0)
        let aspect = drawableSize.height > 1 ? Float(drawableSize.width / drawableSize.height) : 1
        glUniform1f(locAspect, aspect)
        glUniform1f(locRingFreq, MicTuning.kickWaveRingFrequency)
        glUniform1f(locWaveSpeed, MicTuning.kickWavePhaseSpeed)
        glUniform1f(locMaxDisp, 0)
        glDisable(GLenum(GL_DEPTH_TEST))
        glBindVertexArray(vao)
        glDrawArrays(GLenum(GL_TRIANGLES), 0, 3)
        glBindVertexArray(0)
    }

    private func deleteSceneTargets() {
        if depthRB != 0 { glDeleteRenderbuffers(1, &depthRB); depthRB = 0 }
        if sceneColor != 0 { glDeleteTextures(1, &sceneColor); sceneColor = 0 }
        if sceneFBO != 0 { glDeleteFramebuffers(1, &sceneFBO); sceneFBO = 0 }
    }

    private func linkProgram(vertex: String, fragment: String) -> GLuint {
        let vs = compileShader(type: GLenum(GL_VERTEX_SHADER), source: vertex)
        let fs = compileShader(type: GLenum(GL_FRAGMENT_SHADER), source: fragment)
        guard vs != 0, fs != 0 else {
            if vs != 0 { glDeleteShader(vs) }
            if fs != 0 { glDeleteShader(fs) }
            return 0
        }
        let prog = glCreateProgram()
        glAttachShader(prog, vs)
        glAttachShader(prog, fs)
        glLinkProgram(prog)
        glDeleteShader(vs)
        glDeleteShader(fs)
        var ok: GLint = 0
        glGetProgramiv(prog, GLenum(GL_LINK_STATUS), &ok)
        if ok == GL_FALSE {
            var log = [GLchar](repeating: 0, count: 512)
            glGetProgramInfoLog(prog, 512, nil, &log)
            NSLog("[Wizuale] kick-wave link: %@", String(cString: log))
            glDeleteProgram(prog)
            return 0
        }
        return prog
    }

    private func compileShader(type: GLenum, source: String) -> GLuint {
        let shader = glCreateShader(type)
        source.withCString { ptr in
            var p: UnsafePointer<GLchar>? = ptr
            glShaderSource(shader, 1, &p, nil)
        }
        glCompileShader(shader)
        var ok: GLint = 0
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &ok)
        if ok == GL_FALSE {
            var log = [GLchar](repeating: 0, count: 512)
            glGetShaderInfoLog(shader, 512, nil, &log)
            NSLog("[Wizuale] kick-wave shader: %@", String(cString: log))
            glDeleteShader(shader)
            return 0
        }
        return shader
    }

    private static let vertexSource = """
    #version 300 es
    out vec2 vUV;
    void main() {
        vec2 pos = vec2((gl_VertexID == 1) ? 3.0 : -1.0, (gl_VertexID == 2) ? 3.0 : -1.0);
        vUV = vec2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
        gl_Position = vec4(pos, 0.0, 1.0);
    }
    """

    private static let fragmentSource = """
    #version 300 es
    precision highp float;
    in vec2 vUV;
    uniform sampler2D uScene;
    uniform float uEnvelope;
    uniform float uKickAge;
    uniform float uAspect;
    uniform float uRingFreq;
    uniform float uWaveSpeed;
    uniform float uMaxDisp;
    out vec4 fragColor;
    void main() {
        vec2 p = vUV - 0.5;
        p.x *= uAspect;
        float r = length(p);
        vec2 dir = (r > 1e-5) ? p / r : vec2(0.0, 1.0);
        float phase = uKickAge * uWaveSpeed;
        float ring = sin(r * uRingFreq - phase);
        ring *= exp(-r * 0.85);
        ring *= uEnvelope;
        float disp = ring * uMaxDisp;
        vec2 warped = vUV + dir * disp / vec2(uAspect, 1.0);
        warped = clamp(warped, 0.001, 0.999);
        fragColor = texture(uScene, warped);
    }
    """
}
