import AppKit
import SwiftUI

struct AppsView: View {
    @EnvironmentObject private var engine: AudioEngine

    var body: some View {
        if engine.apps.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "speaker.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("当前没有应用在播放声音")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("播放音乐或视频后会自动出现在这里")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(engine.apps) { app in
                        AppRow(app: app)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
}

struct AppRow: View {
    let app: RunningAudioApp
    @EnvironmentObject private var engine: AudioEngine

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                iconView
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    deviceMenu
                }
                Spacer()
                if app.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .help("正在播放")
                }
                Toggle("", isOn: Binding(
                    get: { app.isControlled },
                    set: { engine.setControl(app, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!engine.config.masterEnabled)
                .help("接管该应用(音量 / 静音 / 路由 / 音效)")
            }

            if app.isControlled {
                HStack(spacing: 8) {
                    Button {
                        engine.setMuted(app, !app.config.muted)
                    } label: {
                        Image(systemName: app.config.muted ? "speaker.slash.fill" : "speaker.fill")
                            .foregroundStyle(app.config.muted ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(app.config.muted ? "取消静音" : "静音")

                    Slider(
                        value: Binding(
                            get: { Double(app.config.volume) },
                            set: { engine.setVolume(app, Float($0)) }
                        ),
                        in: 0...1.5
                    )
                    .controlSize(.small)
                    .disabled(app.config.muted)

                    Text("\(Int(app.config.volume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var iconView: some View {
        Group {
            if let icon = app.icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .frame(width: 30, height: 30)
    }

    private var deviceMenu: some View {
        Menu {
            Button("系统默认") {
                engine.setDevice(app, uid: nil)
            }
            Divider()
            ForEach(engine.outputDevices) { device in
                Button(device.name) {
                    engine.setDevice(app, uid: device.uid)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "headphones")
                Text(engine.deviceName(forUID: app.config.deviceUID))
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("输出设备路由")
    }
}
