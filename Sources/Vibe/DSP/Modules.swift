import Foundation

// 所有模块约定:
// - update(...) 仅在参数变化时调用(渲染线程上,但只做少量数学,不分配内存)
// - process(...) 在渲染线程逐块调用,channel 取 0/1

// MARK: - 10 段图示 EQ

final class GraphicEQ {
    private let sampleRate: Float
    private var coeffs = [BiquadCoeffs](repeating: .identity, count: 10)
    private var bandActive = [Bool](repeating: false, count: 10)
    private var states: [[BiquadState]]
    private var preampGain: Float = 1
    private var anyActive = false

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        states = [
            [BiquadState](repeating: BiquadState(), count: 10),
            [BiquadState](repeating: BiquadState(), count: 10),
        ]
    }

    func update(gains: [Float], preampDB: Float) {
        for i in 0..<10 {
            let g = i < gains.count ? gains[i] : 0
            bandActive[i] = abs(g) > 0.05
            if bandActive[i] {
                coeffs[i] = .peaking(
                    freq: EffectParameters.eqFrequencies[i],
                    q: 1.0,
                    gainDB: g,
                    sampleRate: sampleRate
                )
            }
        }
        preampGain = powf(10, preampDB / 20)
        anyActive = bandActive.contains(true) || abs(preampDB) > 0.05
    }

    func process(_ buf: UnsafeMutablePointer<Float>, _ count: Int, channel: Int) {
        guard anyActive else { return }
        if abs(preampGain - 1) > 0.0001 {
            for i in 0..<count { buf[i] *= preampGain }
        }
        for b in 0..<10 where bandActive[b] {
            states[channel][b].process(buf, count, coeffs[b])
        }
    }
}

// MARK: - 纯净低音 P.Bass(心理声学低音)
// 原理:提取低频 → 软饱和产生谐波(在小喇叭上"听到"不存在的低音)→
//       带通限制谐波范围 → 回混 + 低架补偿

final class BassEnhancer {
    private let sampleRate: Float
    private var lpCoef = BiquadCoeffs.identity        // 低频提取(两级 = 24dB/oct)
    private var dcCoef = BiquadCoeffs.identity        // 去直流
    private var postCoef = BiquadCoeffs.identity      // 谐波带宽控制
    private var shelfCoef = BiquadCoeffs.identity     // 低架补偿
    private var lp1 = [BiquadState](repeating: BiquadState(), count: 2)
    private var lp2 = [BiquadState](repeating: BiquadState(), count: 2)
    private var dc = [BiquadState](repeating: BiquadState(), count: 2)
    private var post = [BiquadState](repeating: BiquadState(), count: 2)
    private var shelf = [BiquadState](repeating: BiquadState(), count: 2)
    private var drive: Float = 2
    private var mix: Float = 0

    init(sampleRate: Float) { self.sampleRate = sampleRate }

    func update(amount: Float, frequency: Float) {
        let a = max(0, min(1, amount))
        let f = max(60, min(160, frequency))
        lpCoef = .lowpass(freq: f, sampleRate: sampleRate)
        dcCoef = .highpass(freq: 30, sampleRate: sampleRate)
        postCoef = .lowpass(freq: min(f * 3.5, 400), sampleRate: sampleRate)
        shelfCoef = .lowShelf(freq: f * 1.1, gainDB: a * 3.5, sampleRate: sampleRate)
        drive = 1.5 + a * 5
        mix = a * 0.9
    }

    func process(_ buf: UnsafeMutablePointer<Float>, _ count: Int, channel: Int) {
        guard mix > 0.001 else { return }
        let ch = channel
        for i in 0..<count {
            let x = buf[i]
            var low = lp1[ch].processSample(x, lpCoef)
            low = lp2[ch].processSample(low, lpCoef)
            var h = fastTanh(low * drive)
            h = dc[ch].processSample(h, dcCoef)
            h = post[ch].processSample(h, postCoef)
            let y = x + h * mix
            buf[i] = shelf[ch].processSample(y, shelfCoef)
        }
    }
}

// MARK: - 清晰度激励(BBE 风格)
// 原理:高通取 2.2kHz 以上 → 软饱和激励出泛音 → 少量回混提升"解析感",
//       配合 Lo Contour 低架,模拟 BBE 的 Process / Lo Contour 双旋钮

final class ClarityExciter {
    private let sampleRate: Float
    private var hpCoef = BiquadCoeffs.identity
    private var shelfCoef = BiquadCoeffs.identity
    private var hp1 = [BiquadState](repeating: BiquadState(), count: 2)
    private var hp2 = [BiquadState](repeating: BiquadState(), count: 2)
    private var shelf = [BiquadState](repeating: BiquadState(), count: 2)
    private var drive: Float = 1
    private var mix: Float = 0
    private var shelfActive = false

    init(sampleRate: Float) { self.sampleRate = sampleRate }

    func update(amount: Float, lowContourDB: Float) {
        let a = max(0, min(1, amount))
        hpCoef = .highpass(freq: 2200, sampleRate: sampleRate)
        shelfCoef = .lowShelf(freq: 90, gainDB: max(0, min(6, lowContourDB)), sampleRate: sampleRate)
        shelfActive = lowContourDB > 0.05
        drive = 1 + a * 5
        mix = a * 0.4
    }

    func process(_ buf: UnsafeMutablePointer<Float>, _ count: Int, channel: Int) {
        let ch = channel
        for i in 0..<count {
            let x = buf[i]
            var h = hp1[ch].processSample(x, hpCoef)
            h = hp2[ch].processSample(h, hpCoef)
            let e = fastTanh(h * drive)
            var y = x + e * mix
            if shelfActive {
                y = shelf[ch].processSample(y, shelfCoef)
            }
            buf[i] = y
        }
    }
}

// MARK: - 空间环绕(SRS 风格)
// 原理:M/S 分解,放大 Side 并对其高频增亮;Side 低于 180Hz 高通,
//       低音保持单声道居中,既宽又不散

final class SpatialWidener {
    private let sampleRate: Float
    private var hpCoef = BiquadCoeffs.identity
    private var shelfCoef = BiquadCoeffs.identity
    private var sideHP = BiquadState()
    private var sideShelf = BiquadState()
    private var widthGain: Float = 1

    init(sampleRate: Float) { self.sampleRate = sampleRate }

    func update(width: Float, brightness: Float) {
        widthGain = 1 + max(0, min(1, width)) * 1.1
        hpCoef = .highpass(freq: 180, sampleRate: sampleRate)
        shelfCoef = .highShelf(freq: 3800, gainDB: max(0, min(1, brightness)) * 4.5, sampleRate: sampleRate)
    }

    /// 需要双声道
    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, _ count: Int) {
        for i in 0..<count {
            let l = left[i]
            let r = right[i]
            let mid = (l + r) * 0.5
            var side = (l - r) * 0.5
            side = sideHP.processSample(side, hpCoef)
            side = sideShelf.processSample(side, shelfCoef)
            side *= widthGain
            left[i] = mid + side
            right[i] = mid - side
        }
    }
}

// MARK: - 动感响度(LifeVibes 风格等响度补偿)
// 原理:Fletcher–Munson 等响曲线补偿——小音量下人耳对低/高频不敏感,
//       低架 + 高架 + 轻微中频凹陷,一个旋钮控制整体"饱满度"

final class LoudnessContour {
    private let sampleRate: Float
    private var lowCoef = BiquadCoeffs.identity
    private var highCoef = BiquadCoeffs.identity
    private var dipCoef = BiquadCoeffs.identity
    private var low = [BiquadState](repeating: BiquadState(), count: 2)
    private var high = [BiquadState](repeating: BiquadState(), count: 2)
    private var dip = [BiquadState](repeating: BiquadState(), count: 2)

    init(sampleRate: Float) { self.sampleRate = sampleRate }

    func update(amount: Float) {
        let a = max(0, min(1, amount))
        lowCoef = .lowShelf(freq: 110, gainDB: a * 6.5, sampleRate: sampleRate)
        highCoef = .highShelf(freq: 7500, gainDB: a * 4.0, sampleRate: sampleRate)
        dipCoef = .peaking(freq: 900, q: 0.9, gainDB: -a * 1.2, sampleRate: sampleRate)
    }

    func process(_ buf: UnsafeMutablePointer<Float>, _ count: Int, channel: Int) {
        let ch = channel
        low[ch].process(buf, count, lowCoef)
        high[ch].process(buf, count, highCoef)
        dip[ch].process(buf, count, dipCoef)
    }
}
