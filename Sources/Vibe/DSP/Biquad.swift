import Foundation

/// 双二阶滤波器系数(RBJ Audio EQ Cookbook)
struct BiquadCoeffs {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0

    static let identity = BiquadCoeffs()

    private static func clampFreq(_ f: Float, _ sr: Float) -> Float {
        max(10, min(f, sr * 0.45))
    }

    /// 峰值(钟形)EQ
    static func peaking(freq: Float, q: Float, gainDB: Float, sampleRate: Float) -> BiquadCoeffs {
        let f = clampFreq(freq, sampleRate)
        let A = powf(10, max(-24, min(24, gainDB)) / 40)
        let w0 = 2 * Float.pi * f / sampleRate
        let alpha = sinf(w0) / (2 * max(0.1, q))
        let cosw = cosf(w0)
        let b0 = 1 + alpha * A
        let b1 = -2 * cosw
        let b2 = 1 - alpha * A
        let a0 = 1 + alpha / A
        let a1 = -2 * cosw
        let a2 = 1 - alpha / A
        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// 低架滤波(slope = 1)
    static func lowShelf(freq: Float, gainDB: Float, sampleRate: Float) -> BiquadCoeffs {
        let f = clampFreq(freq, sampleRate)
        let A = powf(10, max(-24, min(24, gainDB)) / 40)
        let w0 = 2 * Float.pi * f / sampleRate
        let cosw = cosf(w0)
        let alpha = sinf(w0) / 2 * sqrtf(2)
        let sqA = sqrtf(A)
        let b0 = A * ((A + 1) - (A - 1) * cosw + 2 * sqA * alpha)
        let b1 = 2 * A * ((A - 1) - (A + 1) * cosw)
        let b2 = A * ((A + 1) - (A - 1) * cosw - 2 * sqA * alpha)
        let a0 = (A + 1) + (A - 1) * cosw + 2 * sqA * alpha
        let a1 = -2 * ((A - 1) + (A + 1) * cosw)
        let a2 = (A + 1) + (A - 1) * cosw - 2 * sqA * alpha
        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// 高架滤波(slope = 1)
    static func highShelf(freq: Float, gainDB: Float, sampleRate: Float) -> BiquadCoeffs {
        let f = clampFreq(freq, sampleRate)
        let A = powf(10, max(-24, min(24, gainDB)) / 40)
        let w0 = 2 * Float.pi * f / sampleRate
        let cosw = cosf(w0)
        let alpha = sinf(w0) / 2 * sqrtf(2)
        let sqA = sqrtf(A)
        let b0 = A * ((A + 1) + (A - 1) * cosw + 2 * sqA * alpha)
        let b1 = -2 * A * ((A - 1) + (A + 1) * cosw)
        let b2 = A * ((A + 1) + (A - 1) * cosw - 2 * sqA * alpha)
        let a0 = (A + 1) - (A - 1) * cosw + 2 * sqA * alpha
        let a1 = 2 * ((A - 1) - (A + 1) * cosw)
        let a2 = (A + 1) - (A - 1) * cosw - 2 * sqA * alpha
        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func lowpass(freq: Float, q: Float = 0.7071, sampleRate: Float) -> BiquadCoeffs {
        let f = clampFreq(freq, sampleRate)
        let w0 = 2 * Float.pi * f / sampleRate
        let cosw = cosf(w0)
        let alpha = sinf(w0) / (2 * max(0.1, q))
        let a0 = 1 + alpha
        return BiquadCoeffs(
            b0: ((1 - cosw) / 2) / a0,
            b1: (1 - cosw) / a0,
            b2: ((1 - cosw) / 2) / a0,
            a1: (-2 * cosw) / a0,
            a2: (1 - alpha) / a0
        )
    }

    static func highpass(freq: Float, q: Float = 0.7071, sampleRate: Float) -> BiquadCoeffs {
        let f = clampFreq(freq, sampleRate)
        let w0 = 2 * Float.pi * f / sampleRate
        let cosw = cosf(w0)
        let alpha = sinf(w0) / (2 * max(0.1, q))
        let a0 = 1 + alpha
        return BiquadCoeffs(
            b0: ((1 + cosw) / 2) / a0,
            b1: (-(1 + cosw)) / a0,
            b2: ((1 + cosw) / 2) / a0,
            a1: (-2 * cosw) / a0,
            a2: (1 - alpha) / a0
        )
    }
}

/// 双二阶滤波器状态(转置直接 II 型),每声道每滤波器一份
struct BiquadState {
    var z1: Float = 0
    var z2: Float = 0

    mutating func reset() {
        z1 = 0
        z2 = 0
    }

    @inline(__always)
    mutating func processSample(_ x: Float, _ c: BiquadCoeffs) -> Float {
        let y = c.b0 * x + z1
        z1 = c.b1 * x - c.a1 * y + z2
        z2 = c.b2 * x - c.a2 * y
        return y
    }

    mutating func process(_ buffer: UnsafeMutablePointer<Float>, _ count: Int, _ c: BiquadCoeffs) {
        var lz1 = z1
        var lz2 = z2
        for i in 0..<count {
            let x = buffer[i]
            let y = c.b0 * x + lz1
            lz1 = c.b1 * x - c.a1 * y + lz2
            lz2 = c.b2 * x - c.a2 * y
            buffer[i] = y
        }
        // 防 denormal
        z1 = abs(lz1) < 1e-15 ? 0 : lz1
        z2 = abs(lz2) < 1e-15 ? 0 : lz2
    }
}

/// 快速 tanh 软饱和(谐波发生器用)
@inline(__always)
func fastTanh(_ x: Float) -> Float {
    let c = max(-3, min(3, x))
    let c2 = c * c
    return c * (27 + c2) / (27 + 9 * c2)
}
