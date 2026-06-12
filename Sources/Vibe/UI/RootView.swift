import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var engine: AudioEngine
    @State private var tab: Tab = .apps

    enum Tab: String, CaseIterable {
        case apps = "应用"
        case effects = "音效"
        case presets = "预设"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Group {
                switch tab {
                case .apps: AppsView()
                case .effects: EffectsView()
                case .presets: PresetsView()
                }
            }
            .frame(height: 400)

            if let error = engine.lastError {
                errorBanner(error)
            }

            Text("音效作用于已接管的应用 · 需要 macOS 14.4+ 与系统音频录制权限")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 6)
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("Vibe").font(.headline)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { engine.config.masterEnabled },
                set: { engine.setMasterEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help("总开关:关闭后所有应用恢复原声")
            Button {
                engine.persistNow()
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("退出 Vibe")
        }
        .padding(12)
    }

    private var statusText: String {
        if !engine.config.masterEnabled { return "已暂停,所有应用原声直通" }
        let n = engine.controlledCount
        return n > 0 ? "已接管 \(n) 个应用" : "未接管任何应用"
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.caption2).lineLimit(2)
            Spacer()
            Button("打开设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption2)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
