import CoreAudio
import Foundation
import os

/// 渲染线程使用的参数快照
struct RenderParams {
    var effects = EffectParameters()
    var appGain: Float = 1
    var muted = false
}

/// 每个被接管应用一条 DSP 链。
/// 信号链:EQ → 动感响度 → 清晰度激励 → 水晶人声 → 纯净低音 → 空间环绕 → 临场感 → 应用音量 → 限幅保护
///
/// 线程模型:UI 线程通过 set* 写入参数(加锁 + 版本号);
/// 渲染线程每个回调用 trylock 拿快照,拿不到就沿用上次的,绝不阻塞音频线程。
final class DSPChain {
    private let sampleRate: Float
    private let maxFrames = 4096

    // 参数共享区
    private let lockPtr: UnsafeMutablePointer<os_unfair_lock>
    private var shared = RenderParams()
    private var sharedRev: UInt64 = 1

    // 渲染线程私有
    private var rp = RenderParams()
    private var seenRev: UInt64 = 0
    private var dirty = true

    // 模块
    private let eq: GraphicEQ
    private let loudness: LoudnessContour
    private let clarity: ClarityExciter
    private let crystal: CrystalVoice
    private let bass: BassEnhancer
    private let spatial: SpatialWidener
    private let reverb: ConcertReverb
    private let limiter: Limiter

    // 音量平滑
    private var smoothedGain: Float = 1
    private let gainSmooth: Float

    // 工作缓冲(预分配,渲染线程零分配)
    private let scratchL: UnsafeMutablePointer<Float>
    private let scratchR: UnsafeMutablePointer<Float>

    init(sampleRate: Double) {
        let sr = Float(sampleRate > 0 ? sampleRate : 48000)
        self.sampleRate = sr
        eq = GraphicEQ(sampleRate: sr)
        loudness = LoudnessContour(sampleRate: sr)
        clarity = ClarityExciter(sampleRate: sr)
        crystal = CrystalVoice(sampleRate: sr)
        bass = BassEnhancer(sampleRate: sr)
        spatial = SpatialWidener(sampleRate: sr)
        reverb = ConcertReverb(sampleRate: sr)
        limiter = Limiter(sampleRate: sr)
        gainSmooth = 1 - expf(-1 / (0.02 * sr))
        scratchL = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        scratchR = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        scratchL.initialize(repeating: 0, count: maxFrames)
        scratchR.initialize(repeating: 0, count: maxFrames)
        lockPtr = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lockPtr.initialize(to: os_unfair_lock())
    }

    deinit {
        scratchL.deallocate()
        scratchR.deallocate()
        lockPtr.deallocate()
    }

    // MARK: - UI 线程接口

    func setEffects(_ e: EffectParameters) {
        withLock { $0.effects = e }
    }

    func setAppGain(_ g: Float) {
        withLock { $0.appGain = max(0, min(1.5, g)) }
    }

    func setMuted(_ m: Bool) {
        withLock { $0.muted = m }
    }

    private func withLock(_ f: (inout RenderParams) -> Void) {
        os_unfair_lock_lock(lockPtr)
        f(&shared)
        sharedRev &+= 1
        os_unfair_lock_unlock(lockPtr)
    }

    // MARK: - 渲染线程

    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        // 1. 收集输出声道并清零(无输入时保持静音)
        let outABL = UnsafeMutableAudioBufferListPointer(output)
        var out0: UnsafeMutablePointer<Float>? = nil
        var out0Stride = 1
        var out1: UnsafeMutablePointer<Float>? = nil
        var out1Stride = 1
        var outChannelCount = 0
        var outFrames = Int.max
        for buf in outABL {
            guard let data = buf.mData else { continue }
            memset(data, 0, Int(buf.mDataByteSize))
            let ch = max(Int(buf.mNumberChannels), 1)
            let frames = Int(buf.mDataByteSize) / (MemoryLayout<Float>.size * ch)
            guard frames > 0 else { continue }
            outFrames = min(outFrames, frames)
            let p = data.assumingMemoryBound(to: Float.self)
            var c = 0
            while c < ch {
                if outChannelCount == 0 {
                    out0 = p + c
                    out0Stride = ch
                } else if outChannelCount == 1 {
                    out1 = p + c
                    out1Stride = ch
                }
                outChannelCount += 1
                c += 1
            }
        }
        guard let o0 = out0, outFrames != Int.max else { return }

        // 2. 收集输入(tap)声道
        let inABL = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var in0: UnsafeMutablePointer<Float>? = nil
        var in0Stride = 1
        var in1: UnsafeMutablePointer<Float>? = nil
        var in1Stride = 1
        var inChannelCount = 0
        var inFrames = Int.max
        for buf in inABL {
            guard let data = buf.mData else { continue }
            let ch = max(Int(buf.mNumberChannels), 1)
            let frames = Int(buf.mDataByteSize) / (MemoryLayout<Float>.size * ch)
            guard frames > 0 else { continue }
            inFrames = min(inFrames, frames)
            let p = data.assumingMemoryBound(to: Float.self)
            var c = 0
            while c < ch {
                if inChannelCount == 0 {
                    in0 = p + c
                    in0Stride = ch
                } else if inChannelCount == 1 {
                    in1 = p + c
                    in1Stride = ch
                }
                inChannelCount += 1
                c += 1
            }
        }
        guard let i0 = in0, inFrames != Int.max else { return }

        // 3. 参数快照(非阻塞)
        if os_unfair_lock_trylock(lockPtr) {
            if sharedRev != seenRev {
                rp = shared
                seenRev = sharedRev
                dirty = true
            }
            os_unfair_lock_unlock(lockPtr)
        }
        if dirty {
            reconfigure()
            dirty = false
        }

        // 4. 分块处理
        let total = min(inFrames, outFrames)
        var offset = 0
        while offset < total {
            let n = min(maxFrames, total - offset)

            // 拷入工作缓冲(解交织)
            var s0 = i0 + offset * in0Stride
            for k in 0..<n {
                scratchL[k] = s0.pointee
                s0 += in0Stride
            }
            if let i1 = in1 {
                var s1 = i1 + offset * in1Stride
                for k in 0..<n {
                    scratchR[k] = s1.pointee
                    s1 += in1Stride
                }
            } else {
                memcpy(scratchR, scratchL, n * MemoryLayout<Float>.size)
            }

            processChunk(n, stereoInput: in1 != nil)

            // 写回输出
            if let o1 = out1 {
                var d0 = o0 + offset * out0Stride
                var d1 = o1 + offset * out1Stride
                for k in 0..<n {
                    d0.pointee = scratchL[k]
                    d0 += out0Stride
                    d1.pointee = scratchR[k]
                    d1 += out1Stride
                }
            } else {
                var d0 = o0 + offset * out0Stride
                for k in 0..<n {
                    d0.pointee = (scratchL[k] + scratchR[k]) * 0.5
                    d0 += out0Stride
                }
            }
            offset += n
        }
    }

    private func reconfigure() {
        let e = rp.effects
        eq.update(gains: e.eqGains, preampDB: e.eqPreamp)
        loudness.update(amount: e.loudnessAmount)
        clarity.update(amount: e.clarityAmount, lowContourDB: e.clarityLowContour)
        crystal.update(amount: e.crystalAmount, air: e.crystalAir)
        bass.update(amount: e.bassAmount, frequency: e.bassFrequency)
        spatial.update(width: e.spatialWidth, brightness: e.spatialBrightness)
        reverb.update(amount: e.concertAmount, size: e.concertSize)
        limiter.setCeiling(dB: e.limiterCeilingDB)
    }

    private func processChunk(_ n: Int, stereoInput: Bool) {
        let e = rp.effects

        if e.eqEnabled {
            eq.process(scratchL, n, channel: 0)
            eq.process(scratchR, n, channel: 1)
        }
        if e.loudnessEnabled {
            loudness.process(scratchL, n, channel: 0)
            loudness.process(scratchR, n, channel: 1)
        }
        if e.clarityEnabled {
            clarity.process(scratchL, n, channel: 0)
            clarity.process(scratchR, n, channel: 1)
        }
        if e.crystalEnabled {
            crystal.process(scratchL, n, channel: 0)
            crystal.process(scratchR, n, channel: 1)
        }
        if e.bassEnabled {
            bass.process(scratchL, n, channel: 0)
            bass.process(scratchR, n, channel: 1)
        }
        if e.spatialEnabled && stereoInput {
            spatial.process(left: scratchL, right: scratchR, n)
        }
        if e.concertEnabled {
            reverb.process(left: scratchL, right: scratchR, n)
        }

        // 应用音量(平滑防爆音)
        let target: Float = rp.muted ? 0 : rp.appGain
        for k in 0..<n {
            smoothedGain += (target - smoothedGain) * gainSmooth
            scratchL[k] *= smoothedGain
            scratchR[k] *= smoothedGain
        }

        // 自动增益保护(常开)
        limiter.process(left: scratchL, right: scratchR, n)
    }
}
