import AudioToolbox
import CoreAudio
import Foundation

/// 单个应用的音频接管管线:
///
///   应用原始输出 ──(Process Tap, mutedWhenTapped:原声被静音)──▶ 私有聚合设备
///        聚合设备 IO 回调 ──▶ DSPChain(音量/静音/音效/限幅)──▶ 目标输出设备
///
/// 销毁管线即恢复应用原声。
final class AppPipeline {
    let pid: pid_t
    let bundleID: String
    let deviceUID: String?   // nil = 跟随系统默认输出
    let dsp: DSPChain

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue: DispatchQueue

    init(processObjectID: AudioObjectID, pid: pid_t, bundleID: String, deviceUID: String?) throws {
        self.pid = pid
        self.bundleID = bundleID
        self.deviceUID = deviceUID
        self.ioQueue = DispatchQueue(label: "vibe.io.\(pid)", qos: .userInteractive)

        // 1. 解析目标输出设备
        let outputID: AudioDeviceID
        if let uid = deviceUID, let dev = DeviceManager.device(forUID: uid) {
            outputID = dev
        } else if let dev = DeviceManager.defaultOutputDeviceID() {
            outputID = dev
        } else {
            throw CoreAudioError.osStatus(-1, "找不到可用的输出设备")
        }
        guard let outputUID = DeviceManager.uid(of: outputID) else {
            throw CoreAudioError.osStatus(-1, "无法读取输出设备 UID")
        }

        // 2. DSP 链(此后所有存储属性已初始化,可安全调用 teardown)
        dsp = DSPChain(sampleRate: DeviceManager.nominalSampleRate(outputID))

        // 3. 创建 Process Tap:接管应用输出,原声静音
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDescription.name = "Vibe Tap \(pid)"
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &tap)
        guard status == noErr, tap != kAudioObjectUnknown else {
            throw CoreAudioError.osStatus(status, "创建进程 Tap 失败,请确认已授予「系统音频录制」权限")
        }
        tapID = tap

        // 4. 私有聚合设备:tap 作为输入,目标设备作为输出
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vibe-\(pid)",
            kAudioAggregateDeviceUIDKey: "com.daidai.vibe.aggregate.\(pid).\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                ]
            ],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard status == noErr, aggregate != kAudioObjectUnknown else {
            teardown()
            throw CoreAudioError.osStatus(status, "创建聚合设备失败")
        }
        aggregateID = aggregate

        // 5. IO 回调:tap 输入 → DSP → 设备输出
        let chain = dsp
        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) {
            _, inInputData, _, outOutputData, _ in
            chain.render(input: inInputData, output: outOutputData)
        }
        guard status == noErr, let procID else {
            teardown()
            throw CoreAudioError.osStatus(status, "创建 IO 回调失败")
        }
        ioProcID = procID

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            teardown()
            throw CoreAudioError.osStatus(status, "启动聚合设备失败")
        }
    }

    func stop() {
        teardown()
    }

    deinit {
        teardown()
    }

    private func teardown() {
        if let procID = ioProcID, aggregateID != kAudioObjectUnknown {
            _ = AudioDeviceStop(aggregateID, procID)
            _ = AudioDeviceDestroyIOProcID(aggregateID, procID)
            ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
