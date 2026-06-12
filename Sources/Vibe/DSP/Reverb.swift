import Foundation

// 临场感 C.Sound(Concert Sound 风格)
// Schroeder/Freeverb 简化结构:预延迟 → 4 梳状(带阻尼)→ 2 全通,
// 左右通道长度错开制造立体声,湿声叠加在干声上(不衰减干声,保持响度)

private final class CombFilter {
    private var buffer: [Float]
    private var index = 0
    private var store: Float = 0
    var feedback: Float = 0.78
    var damp: Float = 0.3
    private(set) var length: Int

    init(maxLength: Int) {
        let n = max(8, maxLength)
        buffer = [Float](repeating: 0, count: n)
        length = n
    }

    func setLength(_ n: Int) {
        length = max(8, min(n, buffer.count))
        if index >= length { index = 0 }
    }

    @inline(__always)
    func process(_ x: Float) -> Float {
        let out = buffer[index]
        store = out * (1 - damp) + store * damp
        if abs(store) < 1e-15 { store = 0 }
        buffer[index] = x + store * feedback
        index += 1
        if index >= length { index = 0 }
        return out
    }
}

private final class AllpassFilter {
    private var buffer: [Float]
    private var index = 0
    private let gain: Float = 0.5
    private(set) var length: Int

    init(maxLength: Int) {
        let n = max(8, maxLength)
        buffer = [Float](repeating: 0, count: n)
        length = n
    }

    func setLength(_ n: Int) {
        length = max(8, min(n, buffer.count))
        if index >= length { index = 0 }
    }

    @inline(__always)
    func process(_ x: Float) -> Float {
        let buffered = buffer[index]
        let out = buffered - gain * x
        buffer[index] = x + gain * buffered
        index += 1
        if index >= length { index = 0 }
        return out
    }
}

private final class DelayLine {
    private var buffer: [Float]
    private var index = 0

    init(length: Int) {
        buffer = [Float](repeating: 0, count: max(1, length))
    }

    @inline(__always)
    func process(_ x: Float) -> Float {
        let out = buffer[index]
        buffer[index] = x
        index += 1
        if index >= buffer.count { index = 0 }
        return out
    }
}

final class ConcertReverb {
    private let sampleRate: Float
    // 44.1kHz 基准长度(经典 Freeverb 数值),右声道 +23 错开
    private static let combBase = [1116, 1188, 1277, 1356]
    private static let allpassBase = [556, 441]
    private static let stereoSpread = 23

    private var combsL: [CombFilter] = []
    private var combsR: [CombFilter] = []
    private var allpassL: [AllpassFilter] = []
    private var allpassR: [AllpassFilter] = []
    private let predelayL: DelayLine
    private let predelayR: DelayLine
    private var wet: Float = 0

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        let srScale = sampleRate / 44100
        // 预留最大空间(size = 1.0 时的长度)
        let maxScale = srScale * 1.3
        for base in Self.combBase {
            combsL.append(CombFilter(maxLength: Int(Float(base) * maxScale) + 8))
            combsR.append(CombFilter(maxLength: Int(Float(base + Self.stereoSpread) * maxScale) + 8))
        }
        for base in Self.allpassBase {
            allpassL.append(AllpassFilter(maxLength: Int(Float(base) * maxScale) + 8))
            allpassR.append(AllpassFilter(maxLength: Int(Float(base + Self.stereoSpread) * maxScale) + 8))
        }
        let pre = Int(sampleRate * 0.012) // 12ms 预延迟
        predelayL = DelayLine(length: pre)
        predelayR = DelayLine(length: pre)
    }

    func update(amount: Float, size: Float) {
        let a = max(0, min(1, amount))
        let s = max(0, min(1, size))
        wet = a * 0.35
        let feedback = 0.7 + s * 0.14
        let scale = (0.8 + s * 0.45) * sampleRate / 44100
        for (i, base) in Self.combBase.enumerated() {
            combsL[i].setLength(Int(Float(base) * scale))
            combsR[i].setLength(Int(Float(base + Self.stereoSpread) * scale))
            combsL[i].feedback = feedback
            combsR[i].feedback = feedback
        }
        for (i, base) in Self.allpassBase.enumerated() {
            allpassL[i].setLength(Int(Float(base) * scale))
            allpassR[i].setLength(Int(Float(base + Self.stereoSpread) * scale))
        }
    }

    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, _ count: Int) {
        guard wet > 0.001 else { return }
        for i in 0..<count {
            let l = left[i]
            let r = right[i]
            // 轻微左右交叉馈入,增强包围感
            let inL = predelayL.process(l * 0.85 + r * 0.15)
            let inR = predelayR.process(r * 0.85 + l * 0.15)

            var wetL: Float = 0
            var wetR: Float = 0
            for c in combsL { wetL += c.process(inL) }
            for c in combsR { wetR += c.process(inR) }
            wetL *= 0.25
            wetR *= 0.25
            for a in allpassL { wetL = a.process(wetL) }
            for a in allpassR { wetR = a.process(wetR) }

            left[i] = l + wetL * wet
            right[i] = r + wetR * wet
        }
    }
}
