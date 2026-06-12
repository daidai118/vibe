import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// 输出设备枚举与查询
enum DeviceManager {

    /// 所有具有输出通道的设备(Vibe 自建的私有聚合设备不会出现在这里)
    static func outputDevices() -> [AudioOutputDevice] {
        CA.getObjectIDList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
            .compactMap { devID in
                guard outputChannelCount(devID) > 0 else { return nil }
                guard let uid = CA.getString(devID, kAudioDevicePropertyDeviceUID) else { return nil }
                let name = CA.getString(devID, kAudioObjectPropertyName) ?? "未知设备"
                return AudioOutputDevice(id: devID, uid: uid, name: name)
            }
    }

    static func outputChannelCount(_ device: AudioDeviceID) -> Int {
        var address = CA.addr(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        let abl = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        var channels = 0
        for buf in abl {
            channels += Int(buf.mNumberChannels)
        }
        return channels
    }

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        var dev = AudioDeviceID(kAudioObjectUnknown)
        let status = CA.get(
            AudioObjectID(kAudioObjectSystemObject),
            CA.addr(kAudioHardwarePropertyDefaultOutputDevice),
            &dev
        )
        guard status == noErr, dev != kAudioObjectUnknown else { return nil }
        return dev
    }

    static func uid(of device: AudioDeviceID) -> String? {
        CA.getString(device, kAudioDevicePropertyDeviceUID)
    }

    static func device(forUID uid: String) -> AudioDeviceID? {
        outputDevices().first { $0.uid == uid }?.id
    }

    static func nominalSampleRate(_ device: AudioDeviceID) -> Double {
        var rate: Double = 0
        _ = CA.get(device, CA.addr(kAudioDevicePropertyNominalSampleRate), &rate)
        return rate > 0 ? rate : 48000
    }
}
