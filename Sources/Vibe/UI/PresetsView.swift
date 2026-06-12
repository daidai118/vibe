import SwiftUI

struct PresetsView: View {
    @EnvironmentObject private var engine: AudioEngine
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("内置预设")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(BuiltinPresets.all) { preset in
                    PresetRow(
                        preset: preset,
                        isActive: engine.config.effects == preset.params,
                        onApply: { engine.applyPreset(preset) },
                        onDelete: nil
                    )
                }

                Divider().padding(.vertical, 4)

                Text("我的预设")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if engine.config.customPresets.isEmpty {
                    Text("还没有自定义预设,在下方保存当前音效设置")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ForEach(engine.config.customPresets) { preset in
                    PresetRow(
                        preset: preset,
                        isActive: engine.config.effects == preset.params,
                        onApply: { engine.applyPreset(preset) },
                        onDelete: { engine.deletePreset(preset) }
                    )
                }

                HStack(spacing: 6) {
                    TextField("新预设名称", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Button("保存当前") {
                        engine.saveCurrentAsPreset(newName)
                        newName = ""
                    }
                    .controlSize(.small)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

struct PresetRow: View {
    let preset: Preset
    let isActive: Bool
    let onApply: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        HStack {
            Button(action: onApply) {
                HStack {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    Text(preset.name)
                        .font(.callout)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除预设")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
    }
}
