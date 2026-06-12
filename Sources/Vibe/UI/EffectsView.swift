import SwiftUI

struct EffectsView: View {
    @EnvironmentObject private var engine: AudioEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if engine.controlledCount == 0 {
                    Text("提示:先在「应用」页接管应用,音效才会生效")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                eqCard

                EffectCard(
                    title: "纯净低音 P.Bass",
                    subtitle: "心理声学谐波,小音箱也有深沉低频",
                    enabled: binding(\.bassEnabled)
                ) {
                    ParamSlider(label: "强度", value: binding(\.bassAmount), range: 0...1)
                    ParamSlider(
                        label: "频率",
                        value: binding(\.bassFrequency),
                        range: 60...160,
                        format: { String(format: "%.0f Hz", $0) }
                    )
                }

                EffectCard(
                    title: "清晰度激励(BBE 风格)",
                    subtitle: "高频泛音激励,提升解析与齿音细节",
                    enabled: binding(\.clarityEnabled)
                ) {
                    ParamSlider(label: "强度", value: binding(\.clarityAmount), range: 0...1)
                    ParamSlider(
                        label: "低频轮廓",
                        value: binding(\.clarityLowContour),
                        range: 0...6,
                        format: { String(format: "+%.1f dB", $0) }
                    )
                }

                EffectCard(
                    title: "水晶人声",
                    subtitle: "3.2kHz 亮度 + 11kHz 空气感,透亮不刺耳",
                    enabled: binding(\.crystalEnabled)
                ) {
                    ParamSlider(label: "亮度", value: binding(\.crystalAmount), range: 0...1)
                    ParamSlider(label: "气感", value: binding(\.crystalAir), range: 0...1)
                }

                EffectCard(
                    title: "空间环绕(SRS 风格)",
                    subtitle: "拓宽声场,低音保持居中不发散",
                    enabled: binding(\.spatialEnabled)
                ) {
                    ParamSlider(label: "宽度", value: binding(\.spatialWidth), range: 0...1)
                    ParamSlider(label: "亮度", value: binding(\.spatialBrightness), range: 0...1)
                }

                EffectCard(
                    title: "临场感 C.Sound",
                    subtitle: "音乐厅早期反射,营造现场氛围",
                    enabled: binding(\.concertEnabled)
                ) {
                    ParamSlider(label: "强度", value: binding(\.concertAmount), range: 0...1)
                    ParamSlider(label: "空间", value: binding(\.concertSize), range: 0...1)
                }

                EffectCard(
                    title: "动感响度(LifeVibes 风格)",
                    subtitle: "等响度补偿,小音量也饱满",
                    enabled: binding(\.loudnessEnabled)
                ) {
                    ParamSlider(label: "强度", value: binding(\.loudnessAmount), range: 0...1)
                }

                limiterCard
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - EQ

    private var eqCard: some View {
        EffectCard(
            title: "10 段均衡器 EQ",
            subtitle: "全局 EQ,-12 ~ +12 dB",
            enabled: binding(\.eqEnabled)
        ) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<10, id: \.self) { i in
                    VStack(spacing: 2) {
                        VerticalSlider(value: eqGainBinding(i))
                        Text(EffectParameters.eqLabels[i])
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            ParamSlider(
                label: "前级",
                value: binding(\.eqPreamp),
                range: -12...0,
                format: { String(format: "%.1f dB", $0) }
            )

            HStack {
                Menu("快速曲线") {
                    eqQuickButton("平直", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: 0)
                    eqQuickButton("流行", [1.5, 2.5, 2, 0.5, -0.5, 0, 1, 2, 2.5, 2], preamp: -2)
                    eqQuickButton("摇滚", [3, 2.5, 1, 0, -1, 0, 1.5, 2.5, 3, 3], preamp: -3)
                    eqQuickButton("人声", [-1, -1, 0, 1, 2.5, 3, 2.5, 1.5, 0.5, 0], preamp: -2)
                    eqQuickButton("低音强化", [4.5, 4, 2.5, 1, 0, 0, 0, 0.5, 1, 1], preamp: -3.5)
                    eqQuickButton("V 型", [5, 4, 2, 0, -1.5, -1.5, 0, 2, 4, 4.5], preamp: -4)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
        }
    }

    private func eqQuickButton(_ name: String, _ gains: [Float], preamp: Float) -> some View {
        Button(name) {
            engine.config.effects.eqGains = gains
            engine.config.effects.eqPreamp = preamp
            engine.config.effects.eqEnabled = true
            engine.applyEffects()
        }
    }

    private var limiterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("自动增益保护").font(.subheadline.bold())
                    Text("Lookahead 限幅 + 软削波,常开防破音")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "shield.checkered")
                    .foregroundStyle(.green)
            }
            ParamSlider(
                label: "输出上限",
                value: binding(\.limiterCeilingDB),
                range: -3...0,
                format: { String(format: "%.1f dB", $0) }
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - 绑定

    private func binding<T>(_ keyPath: WritableKeyPath<EffectParameters, T>) -> Binding<T> {
        Binding(
            get: { engine.config.effects[keyPath: keyPath] },
            set: {
                engine.config.effects[keyPath: keyPath] = $0
                engine.applyEffects()
            }
        )
    }

    private func eqGainBinding(_ index: Int) -> Binding<Float> {
        Binding(
            get: { engine.config.effects.eqGains[index] },
            set: {
                engine.config.effects.eqGains[index] = $0
                engine.applyEffects()
            }
        )
    }
}

// MARK: - 通用控件

struct EffectCard<Content: View>: View {
    let title: String
    let subtitle: String
    @Binding var enabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.bold())
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            if enabled {
                content()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

struct ParamSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var format: (Float) -> String = { String(format: "%.0f%%", $0 * 100) }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 56, alignment: .leading)
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Float($0) }),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .controlSize(.small)
            Text(format(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

struct VerticalSlider: View {
    @Binding var value: Float

    var body: some View {
        Slider(
            value: Binding(get: { Double(value) }, set: { value = Float($0) }),
            in: -12...12
        )
        .controlSize(.mini)
        .frame(width: 84)
        .rotationEffect(.degrees(-90))
        .frame(width: 26, height: 84)
    }
}
