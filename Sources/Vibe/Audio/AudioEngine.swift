import AppKit
import Combine
import CoreAudio
import Foundation

/// UI 展示用的应用条目
struct RunningAudioApp: Identifiable {
    var id: pid_t { pid }
    let pid: pid_t
    let bundleID: String
    let name: String
    let icon: NSImage?
    let objectID: AudioObjectID
    let isPlaying: Bool
    let config: AppConfig
    let isControlled: Bool
}

/// 全局协调器:进程扫描、管线生命周期、配置持久化
@MainActor
final class AudioEngine: ObservableObject {

    @Published private(set) var apps: [RunningAudioApp] = []
    @Published private(set) var outputDevices: [AudioOutputDevice] = []
    @Published var lastError: String?
    @Published var config: VibeConfig

    private var pipelines: [pid_t: AppPipeline] = [:]
    private var latestScan: [pid_t: AudioProcessInfo] = [:]
    private let store = SettingsStore()
    private var timer: Timer?

    var controlledCount: Int { pipelines.count }

    init() {
        config = SettingsStore.load()
        refreshDevices()
        refreshApps()
        registerDefaultDeviceListener()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDevices()
                self?.refreshApps()
            }
        }
    }

    // MARK: - 扫描

    func refreshDevices() {
        outputDevices = DeviceManager.outputDevices()
    }

    func refreshApps() {
        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let scan = ProcessScanner.scan()
        latestScan = Dictionary(scan.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        // 清理已退出进程的管线
        let alivePIDs = Set(scan.map(\.pid))
        for (pid, pipeline) in pipelines where !alivePIDs.contains(pid) {
            pipeline.stop()
            pipelines[pid] = nil
        }

        // 总开关关闭时停掉全部管线
        if !config.masterEnabled {
            stopAllPipelines()
        }

        var rows: [RunningAudioApp] = []
        var seen = Set<pid_t>()
        for info in scan {
            guard info.pid != myPID, !seen.contains(info.pid) else { continue }
            let running = NSRunningApplication(processIdentifier: info.pid)
            // 跳过既无 bundleID 又无法识别的纯系统守护进程
            if info.bundleID.isEmpty && running == nil { continue }
            if info.bundleID == "com.daidai.vibe" { continue }

            let key = configKey(bundleID: info.bundleID, pid: info.pid)
            let cfg = config.apps[key] ?? AppConfig()
            let controlled = pipelines[info.pid] != nil

            // 只展示:正在发声 / 已被接管 / 用户标记过接管 的应用
            guard info.isRunningOutput || controlled || cfg.enhanced else { continue }
            seen.insert(info.pid)

            // 自动接管(配置里 enhanced 且正在发声)
            if config.masterEnabled, cfg.enhanced, !controlled, info.isRunningOutput {
                createPipeline(pid: info.pid, bundleID: info.bundleID, objectID: info.objectID, cfg: cfg)
            }

            let name = running?.localizedName
                ?? info.bundleID.components(separatedBy: ".").last
                ?? "PID \(info.pid)"
            rows.append(RunningAudioApp(
                pid: info.pid,
                bundleID: info.bundleID,
                name: name,
                icon: running?.icon,
                objectID: info.objectID,
                isPlaying: info.isRunningOutput,
                config: cfg,
                isControlled: pipelines[info.pid] != nil
            ))
        }
        apps = rows.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: - 单应用控制

    func setControl(_ app: RunningAudioApp, enabled: Bool) {
        let key = configKey(bundleID: app.bundleID, pid: app.pid)
        var cfg = config.apps[key] ?? AppConfig()
        cfg.enhanced = enabled
        config.apps[key] = cfg

        if enabled {
            if config.masterEnabled, pipelines[app.pid] == nil {
                createPipeline(pid: app.pid, bundleID: app.bundleID, objectID: app.objectID, cfg: cfg)
            }
        } else {
            pipelines[app.pid]?.stop()
            pipelines[app.pid] = nil
        }
        persist()
        refreshApps()
    }

    func setVolume(_ app: RunningAudioApp, _ volume: Float) {
        let key = configKey(bundleID: app.bundleID, pid: app.pid)
        var cfg = config.apps[key] ?? AppConfig()
        cfg.volume = volume
        cfg.enhanced = true
        config.apps[key] = cfg

        ensurePipeline(app, cfg: cfg)
        pipelines[app.pid]?.dsp.setAppGain(volume)
        persist()
        refreshApps()
    }

    func setMuted(_ app: RunningAudioApp, _ muted: Bool) {
        let key = configKey(bundleID: app.bundleID, pid: app.pid)
        var cfg = config.apps[key] ?? AppConfig()
        cfg.muted = muted
        cfg.enhanced = true
        config.apps[key] = cfg

        ensurePipeline(app, cfg: cfg)
        pipelines[app.pid]?.dsp.setMuted(muted)
        persist()
        refreshApps()
    }

    func setDevice(_ app: RunningAudioApp, uid: String?) {
        let key = configKey(bundleID: app.bundleID, pid: app.pid)
        var cfg = config.apps[key] ?? AppConfig()
        cfg.deviceUID = uid
        config.apps[key] = cfg

        // 路由变更需要重建管线
        if pipelines[app.pid] != nil {
            pipelines[app.pid]?.stop()
            pipelines[app.pid] = nil
            createPipeline(pid: app.pid, bundleID: app.bundleID, objectID: app.objectID, cfg: cfg)
        }
        persist()
        refreshApps()
    }

    // MARK: - 音效

    func applyEffects() {
        for pipeline in pipelines.values {
            pipeline.dsp.setEffects(config.effects)
        }
        persist()
    }

    func applyPreset(_ preset: Preset) {
        config.effects = preset.params
        applyEffects()
    }

    func saveCurrentAsPreset(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        config.customPresets.append(Preset(name: trimmed, params: config.effects))
        persist()
    }

    func deletePreset(_ preset: Preset) {
        config.customPresets.removeAll { $0.id == preset.id }
        persist()
    }

    // MARK: - 总开关

    func setMasterEnabled(_ enabled: Bool) {
        config.masterEnabled = enabled
        if !enabled {
            stopAllPipelines()
        }
        persist()
        refreshApps()
    }

    // MARK: - 内部

    private func ensurePipeline(_ app: RunningAudioApp, cfg: AppConfig) {
        guard config.masterEnabled, pipelines[app.pid] == nil else { return }
        createPipeline(pid: app.pid, bundleID: app.bundleID, objectID: app.objectID, cfg: cfg)
    }

    private func createPipeline(pid: pid_t, bundleID: String, objectID: AudioObjectID, cfg: AppConfig) {
        do {
            let pipeline = try AppPipeline(
                processObjectID: objectID,
                pid: pid,
                bundleID: bundleID,
                deviceUID: cfg.deviceUID
            )
            pipeline.dsp.setEffects(config.effects)
            pipeline.dsp.setAppGain(cfg.volume)
            pipeline.dsp.setMuted(cfg.muted)
            pipelines[pid] = pipeline
            lastError = nil
        } catch {
            lastError = "接管失败:\(error.localizedDescription)"
        }
    }

    private func stopAllPipelines() {
        for pipeline in pipelines.values {
            pipeline.stop()
        }
        pipelines.removeAll()
    }

    private func configKey(bundleID: String, pid: pid_t) -> String {
        bundleID.isEmpty ? "pid.fallback.\(pid)" : bundleID
    }

    private func persist() {
        store.save(config)
    }

    func persistNow() {
        store.saveNow(config)
    }

    func deviceName(forUID uid: String?) -> String {
        guard let uid else { return "系统默认" }
        return outputDevices.first { $0.uid == uid }?.name ?? "系统默认"
    }

    // 默认输出设备变化时,重建跟随默认设备的管线
    private func registerDefaultDeviceListener() {
        var address = CA.addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.handleDefaultDeviceChange()
            }
        }
    }

    private func handleDefaultDeviceChange() {
        let followingDefault = pipelines.filter { $0.value.deviceUID == nil }
        for (pid, pipeline) in followingDefault {
            pipeline.stop()
            pipelines[pid] = nil
            if let info = latestScan[pid] {
                let key = configKey(bundleID: info.bundleID, pid: pid)
                let cfg = config.apps[key] ?? AppConfig()
                createPipeline(pid: pid, bundleID: info.bundleID, objectID: info.objectID, cfg: cfg)
            }
        }
        refreshApps()
    }
}
