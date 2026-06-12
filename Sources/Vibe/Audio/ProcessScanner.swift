import CoreAudio
import Foundation

/// HAL 中注册的一个音频进程
struct AudioProcessInfo {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let isRunningOutput: Bool
}

/// 枚举系统中所有向 Core Audio 注册过的进程
enum ProcessScanner {
    static func scan() -> [AudioProcessInfo] {
        CA.getObjectIDList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            .compactMap { obj in
                var pid: pid_t = -1
                guard CA.get(obj, CA.addr(kAudioProcessPropertyPID), &pid) == noErr, pid > 0 else {
                    return nil
                }
                let bundleID = CA.getString(obj, kAudioProcessPropertyBundleID) ?? ""
                var running: UInt32 = 0
                _ = CA.get(obj, CA.addr(kAudioProcessPropertyIsRunningOutput), &running)
                return AudioProcessInfo(
                    objectID: obj,
                    pid: pid,
                    bundleID: bundleID,
                    isRunningOutput: running != 0
                )
            }
    }
}
