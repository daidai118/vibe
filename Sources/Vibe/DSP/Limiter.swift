import Foundation

/// 自动增益保护:lookahead 峰值限幅器 + 软削波,常开,
/// 保证多个音效叠加 / 音量超过 100% 时不破音
final class Limiter {
    private let lookahead: Int
    private var delayL: [Float]
    private var delayR: [Float]
    private var idx = 0
    private var envelope: Float = 0
    private var gain: Float = 1
    private var ceiling: Float = 0.891 // -1 dBFS
    private let attackCoef: Float
    private let releaseCoef: Float
    private let envReleaseCoef: Float

    init(sampleRate: Float) {
        lookahead = max(32, Int(sampleRate * 0.0015)) // ~1.5ms
        delayL = [Float](repeating: 0, count: lookahead)
        delayR = [Float](repeating: 0, count: lookahead)
        attackCoef = 1 - expf(-1 / (0.0005 * sampleRate))
        releaseCoef = 1 - expf(-1 / (0.12 * sampleRate))
        envReleaseCoef = expf(-1 / (0.08 * sampleRate))
    }

    func setCeiling(dB: Float) {
        ceiling = powf(10, max(-12, min(0, dB)) / 20)
    }

    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, _ count: Int) {
        for i in 0..<count {
            let l = left[i]
            let r = right[i]

            // 包络检测(立体声联动):对"将要"输出的样本提前压低增益
            let peak = max(abs(l), abs(r))
            envelope = max(peak, envelope * envReleaseCoef)
            let target: Float = envelope > ceiling ? ceiling / envelope : 1
            if target < gain {
                gain += (target - gain) * attackCoef
            } else {
                gain += (target - gain) * releaseCoef
            }

            // lookahead 延迟线
            let dl = delayL[idx]
            let dr = delayR[idx]
            delayL[idx] = l
            delayR[idx] = r
            idx += 1
            if idx >= lookahead { idx = 0 }

            left[i] = Self.softClip(dl * gain)
            right[i] = Self.softClip(dr * gain)
        }
    }

    /// 软削波:0.92 以内透明,以上平滑压缩,绝不超过 ±1
    @inline(__always)
    private static func softClip(_ x: Float) -> Float {
        let t: Float = 0.92
        let a = abs(x)
        if a <= t { return x }
        let over = a - t
        let y = t + over / (1 + over * 4)
        return min(y, 1.0) * (x < 0 ? -1 : 1)
    }
}
