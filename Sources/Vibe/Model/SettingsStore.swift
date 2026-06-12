import Foundation

/// 单个应用的本地配置(以 bundleID 为键,跨启动保留)
struct AppConfig: Codable, Equatable {
    /// 0...1.5(>1 时由限幅器保护)
    var volume: Float = 1.0
    var muted = false
    /// 输出设备 UID,nil = 跟随系统默认输出
    var deviceUID: String? = nil
    /// 是否接管该应用(音量/静音/路由/音效都需要先接管)
    var enhanced = false
}

/// 全部持久化配置
struct VibeConfig: Codable {
    var masterEnabled = true
    var effects = BuiltinPresets.recommended.params
    var apps: [String: AppConfig] = [:]
    var customPresets: [Preset] = []
}

/// JSON 持久化:~/Library/Application Support/Vibe/settings.json
final class SettingsStore {

    static let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vibe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }()

    static func load() -> VibeConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let cfg = try? JSONDecoder().decode(VibeConfig.self, from: data)
        else { return VibeConfig() }
        return cfg
    }

    private var pending: DispatchWorkItem?

    /// 防抖保存(0.5s),拖动滑块时不会频繁写盘
    func save(_ config: VibeConfig) {
        pending?.cancel()
        let item = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(config) {
                try? data.write(to: Self.fileURL, options: .atomic)
            }
        }
        pending = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    /// 退出前立即保存
    func saveNow(_ config: VibeConfig) {
        pending?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
