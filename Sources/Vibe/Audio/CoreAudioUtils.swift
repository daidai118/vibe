import CoreAudio
import Foundation

enum CoreAudioError: Error, LocalizedError {
    case osStatus(OSStatus, String)

    var errorDescription: String? {
        switch self {
        case let .osStatus(code, what):
            return "\(what)(OSStatus \(code))"
        }
    }
}

/// Core Audio 属性读取小工具
enum CA {
    static func addr(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// 读取定长属性(仅用于 POD 类型:UInt32 / Double / AudioDeviceID / pid_t 等)
    static func get<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: inout T) -> OSStatus {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, ptr)
        }
    }

    /// 读取 CFString 属性
    static func getString(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var address = addr(selector, scope: scope)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>? = nil
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// 读取 AudioObjectID 数组属性
    static func getObjectIDList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = addr(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &list) == noErr else {
            return []
        }
        return list
    }
}
