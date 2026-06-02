import SwiftUI

// MARK: - Adjust View (Icon-based card UI)

struct AdjustView: View {
    @ObservedObject var viewModel: FilmEditorViewModel
    @State private var selectedSection: AdjustmentSection = .light
    @State private var expandedParam: String? = nil
    @State private var selectedHSLChannel: HSLChannel = .red

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("细调参数")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: {
                    viewModel.resetAdjustments()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("重置")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(viewModel.adjustments.isDefault ? .gray : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .disabled(viewModel.adjustments.isDefault)
            }

            // Section tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AdjustmentSection.allCases) { section in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSection = section
                                expandedParam = nil
                            }
                        }) {
                            Text(section.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selectedSection == section ? .black : .white.opacity(0.7))
                                .frame(width: 72, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedSection == section ? Color.orange : Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            // Icon cards grid + expandable sliders
            ScrollView(.vertical, showsIndicators: false) {
                if selectedSection == .hsl {
                    HSLAdjustmentPanel(
                        selectedChannel: $selectedHSLChannel,
                        hue: hslBinding(for: selectedHSLChannel, component: .hue),
                        saturation: hslBinding(for: selectedHSLChannel, component: .saturation),
                        luminance: hslBinding(for: selectedHSLChannel, component: .luminance),
                        isDefault: isHSLChannelDefault(selectedHSLChannel),
                        reset: { resetHSLChannel(selectedHSLChannel) }
                    )
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows(for: selectedSection)) { row in
                            VStack(spacing: 0) {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedParam = (expandedParam == row.id) ? nil : row.id
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: row.icon)
                                            .font(.system(size: 16))
                                            .foregroundStyle(row.isDefault ? .gray : .orange)
                                            .frame(width: 28, height: 28)
                                            .background(
                                                (expandedParam == row.id ? Color.orange : Color.white).opacity(row.isDefault ? 0.06 : 0.12)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8))

                                        Text(row.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white)

                                        Spacer()

                                        Text(row.formattedValue)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(row.isDefault ? .gray : .orange)
                                            .monospacedDigit()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(expandedParam == row.id ? Color.orange.opacity(0.08) : Color.white.opacity(0.04))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())

                                if expandedParam == row.id {
                                    VStack(spacing: 0) {
                                        Divider()
                                            .background(Color.white.opacity(0.1))
                                            .padding(.horizontal, 14)

                                        AdjustmentSliderCompact(
                                            title: row.title,
                                            value: row.binding,
                                            range: row.range,
                                            valueStyle: row.valueStyle,
                                            defaultValue: row.defaultValue
                                        )
                                    }
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.03))
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func rows(for section: AdjustmentSection) -> [AdjustmentParamRow] {
        switch section {
        case .light:
            return [
                AdjustmentParamRow(id: "exposure", title: "曝光", icon: "sun.max.fill", binding: $viewModel.adjustments.exposure, range: -50...50, valueStyle: .signed, defaultValue: 0),
                AdjustmentParamRow(id: "contrast", title: "对比", icon: "circle.lefthalf.filled", binding: $viewModel.adjustments.contrast, range: -50...50, valueStyle: .signed, defaultValue: 0),
                AdjustmentParamRow(id: "highlights", title: "高光", icon: "sparkle", binding: $viewModel.adjustments.highlights, range: -100...100, valueStyle: .signed, defaultValue: 0),
                AdjustmentParamRow(id: "shadows", title: "阴影", icon: "moon.fill", binding: $viewModel.adjustments.shadows, range: -100...100, valueStyle: .signed, defaultValue: 0),
                AdjustmentParamRow(id: "whites", title: "白色色阶", icon: "sun.min.fill", binding: $viewModel.adjustments.whites, range: -100...100, valueStyle: .signed, defaultValue: 0),
                AdjustmentParamRow(id: "blacks", title: "黑色色阶", icon: "moon.circle.fill", binding: $viewModel.adjustments.blacks, range: -100...100, valueStyle: .signed, defaultValue: 0)
            ]
        case .color:
            return [
                AdjustmentParamRow(id: "temperature", title: "色温", icon: "thermometer.medium", binding: $viewModel.adjustments.temperature, range: -50...50, valueStyle: .signed, defaultValue: 0),
                AdjustmentParamRow(id: "tint", title: "色调", icon: "paintpalette.fill", binding: $viewModel.adjustments.tint, range: -50...50, valueStyle: .signed, defaultValue: 0),
                AdjustmentParamRow(id: "saturation", title: "饱和度", icon: "drop.fill", binding: $viewModel.adjustments.saturation, range: -50...50, valueStyle: .signed, defaultValue: 0),
                AdjustmentParamRow(id: "clarity", title: "清晰度", icon: "eye.fill", binding: $viewModel.adjustments.clarity, range: -50...50, valueStyle: .signed, defaultValue: 0),
                AdjustmentParamRow(id: "sharpness", title: "锐化", icon: "wand.and.stars", binding: $viewModel.adjustments.sharpness, range: -50...50, valueStyle: .signed, defaultValue: 0)
            ]
        case .hsl:
            return []
        case .tone:
            return [
                AdjustmentParamRow(id: "splitShadowHue", title: "阴影色相", icon: "paintpalette", binding: $viewModel.adjustments.splitShadowHue, range: 0...360, valueStyle: .degrees, defaultValue: 220),
                AdjustmentParamRow(id: "splitShadowSaturation", title: "阴影强度", icon: "moon.fill", binding: $viewModel.adjustments.splitShadowSaturation, range: 0...100, valueStyle: .percentage, defaultValue: 0),
                AdjustmentParamRow(id: "splitHighlightHue", title: "高光色相", icon: "paintpalette.fill", binding: $viewModel.adjustments.splitHighlightHue, range: 0...360, valueStyle: .degrees, defaultValue: 40),
                AdjustmentParamRow(id: "splitHighlightSaturation", title: "高光强度", icon: "sun.max.fill", binding: $viewModel.adjustments.splitHighlightSaturation, range: 0...100, valueStyle: .percentage, defaultValue: 0),
                AdjustmentParamRow(id: "splitBalance", title: "色调平衡", icon: "circle.lefthalf.filled", binding: $viewModel.adjustments.splitBalance, range: -50...50, valueStyle: .signed, defaultValue: 0)
            ]
        case .effects:
            return [
                AdjustmentParamRow(id: "opacity", title: "胶片强度", icon: "film.fill", binding: $viewModel.adjustments.opacity, range: 0...100, valueStyle: .percentage, defaultValue: 100),
                AdjustmentParamRow(id: "vignette", title: "暗角", icon: "inset.filled.rectangle", binding: $viewModel.adjustments.vignette, range: -100...100, valueStyle: .signed, defaultValue: 0),
                AdjustmentParamRow(id: "softGlow", title: "柔光", icon: "sparkles", binding: $viewModel.adjustments.softGlow, range: 0...100, valueStyle: .percentage, defaultValue: 0),
                AdjustmentParamRow(id: "halation", title: "红色光晕", icon: "camera.filters", binding: $viewModel.adjustments.halation, range: 0...100, valueStyle: .percentage, defaultValue: 0),
                AdjustmentParamRow(id: "fade", title: "褪色", icon: "circle.dashed", binding: $viewModel.adjustments.fade, range: 0...100, valueStyle: .percentage, defaultValue: 0),
                AdjustmentParamRow(id: "fadeWarmth", title: "褪色冷暖", icon: "thermometer.sun.fill", binding: $viewModel.adjustments.fadeWarmth, range: 0...100, valueStyle: .percentage, defaultValue: 50)
            ]
        case .grain:
            return [
                AdjustmentParamRow(id: "grain", title: "颗粒强度", icon: "circle.dotted", binding: $viewModel.adjustments.grain, range: 0...100, valueStyle: .percentage, defaultValue: 0),
                AdjustmentParamRow(id: "grainSize", title: "颗粒大小", icon: "circle.grid.2x2.fill", binding: $viewModel.adjustments.grainSize, range: 0...100, valueStyle: .percentage, defaultValue: 50),
                AdjustmentParamRow(id: "grainRoughness", title: "颗粒粗糙", icon: "circle.grid.cross", binding: $viewModel.adjustments.grainRoughness, range: 0...100, valueStyle: .percentage, defaultValue: 50),
                AdjustmentParamRow(id: "grainColor", title: "彩色颗粒", icon: "camera.macro", binding: $viewModel.adjustments.grainColor, range: 0...100, valueStyle: .percentage, defaultValue: 0)
            ]
        }
    }

    private func hslBinding(for channel: HSLChannel, component: HSLComponent) -> Binding<Double> {
        switch (channel, component) {
        case (.red, .hue): return $viewModel.adjustments.hslRedHue
        case (.red, .saturation): return $viewModel.adjustments.hslRedSaturation
        case (.red, .luminance): return $viewModel.adjustments.hslRedLuminance
        case (.orange, .hue): return $viewModel.adjustments.hslOrangeHue
        case (.orange, .saturation): return $viewModel.adjustments.hslOrangeSaturation
        case (.orange, .luminance): return $viewModel.adjustments.hslOrangeLuminance
        case (.yellow, .hue): return $viewModel.adjustments.hslYellowHue
        case (.yellow, .saturation): return $viewModel.adjustments.hslYellowSaturation
        case (.yellow, .luminance): return $viewModel.adjustments.hslYellowLuminance
        case (.green, .hue): return $viewModel.adjustments.hslGreenHue
        case (.green, .saturation): return $viewModel.adjustments.hslGreenSaturation
        case (.green, .luminance): return $viewModel.adjustments.hslGreenLuminance
        case (.cyan, .hue): return $viewModel.adjustments.hslCyanHue
        case (.cyan, .saturation): return $viewModel.adjustments.hslCyanSaturation
        case (.cyan, .luminance): return $viewModel.adjustments.hslCyanLuminance
        case (.blue, .hue): return $viewModel.adjustments.hslBlueHue
        case (.blue, .saturation): return $viewModel.adjustments.hslBlueSaturation
        case (.blue, .luminance): return $viewModel.adjustments.hslBlueLuminance
        case (.purple, .hue): return $viewModel.adjustments.hslPurpleHue
        case (.purple, .saturation): return $viewModel.adjustments.hslPurpleSaturation
        case (.purple, .luminance): return $viewModel.adjustments.hslPurpleLuminance
        case (.magenta, .hue): return $viewModel.adjustments.hslMagentaHue
        case (.magenta, .saturation): return $viewModel.adjustments.hslMagentaSaturation
        case (.magenta, .luminance): return $viewModel.adjustments.hslMagentaLuminance
        }
    }

    private func isHSLChannelDefault(_ channel: HSLChannel) -> Bool {
        hslBinding(for: channel, component: .hue).wrappedValue == 0 &&
        hslBinding(for: channel, component: .saturation).wrappedValue == 0 &&
        hslBinding(for: channel, component: .luminance).wrappedValue == 0
    }

    private func resetHSLChannel(_ channel: HSLChannel) {
        hslBinding(for: channel, component: .hue).wrappedValue = 0
        hslBinding(for: channel, component: .saturation).wrappedValue = 0
        hslBinding(for: channel, component: .luminance).wrappedValue = 0
    }
}

private enum AdjustmentSection: String, CaseIterable, Identifiable {
    case light
    case color
    case hsl
    case tone
    case effects
    case grain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "调光"
        case .color: return "颜色"
        case .hsl: return "HSL"
        case .tone: return "色调"
        case .effects: return "效果"
        case .grain: return "颗粒"
        }
    }
}

private enum HSLComponent {
    case hue
    case saturation
    case luminance
}

private enum HSLChannel: String, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case cyan
    case blue
    case purple
    case magenta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: return "红"
        case .orange: return "橙"
        case .yellow: return "黄"
        case .green: return "绿"
        case .cyan: return "青"
        case .blue: return "蓝"
        case .purple: return "紫"
        case .magenta: return "洋红"
        }
    }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .cyan: return .cyan
        case .blue: return .blue
        case .purple: return .purple
        case .magenta: return .pink
        }
    }
}

private struct HSLAdjustmentPanel: View {
    @Binding var selectedChannel: HSLChannel
    @Binding var hue: Double
    @Binding var saturation: Double
    @Binding var luminance: Double
    let isDefault: Bool
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HSLChannel.allCases) { channel in
                        Button(action: { selectedChannel = channel }) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(channel.color)
                                    .frame(width: 10, height: 10)
                                Text(channel.title)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(selectedChannel == channel ? .black : .white.opacity(0.72))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(
                                Capsule()
                                    .fill(selectedChannel == channel ? Color.orange : Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            HSLSliderCard(title: "\(selectedChannel.title)色色相", icon: "paintpalette", value: $hue)
            HSLSliderCard(title: "\(selectedChannel.title)色饱和", icon: "drop.fill", value: $saturation)
            HSLSliderCard(title: "\(selectedChannel.title)色明度", icon: "sun.max.fill", value: $luminance)

            Button(action: reset) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("重置当前颜色")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(isDefault ? .gray : .orange)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isDefault)
        }
    }
}

private struct HSLSliderCard: View {
    let title: String
    let icon: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(value == 0 ? .gray : .orange)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(value == 0 ? 0.06 : 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                Text(formattedValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(value == 0 ? .gray : .orange)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 14)

            AdjustmentSliderCompact(
                title: title,
                value: $value,
                range: -50...50,
                valueStyle: .signed,
                defaultValue: 0
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var formattedValue: String {
        let intValue = Int(value)
        if intValue > 0 { return "+\(intValue)" }
        return "\(intValue)"
    }
}

private struct AdjustmentParamRow: Identifiable {
    var id: String
    let title: String
    let icon: String
    let binding: Binding<Double>
    let range: ClosedRange<Double>
    let valueStyle: AdjustmentValueStyle
    let defaultValue: Double

    var isDefault: Bool {
        Double(Int(binding.wrappedValue)) == defaultValue
    }

    var formattedValue: String {
        let intValue = Int(binding.wrappedValue)
        switch valueStyle {
        case .signed:
            if intValue > 0 { return "+\(intValue)" }
            return "\(intValue)"
        case .percentage:
            return "\(intValue)%"
        case .degrees:
            return "\(intValue)°"
        }
    }
}

private enum AdjustmentValueStyle {
    case signed
    case percentage
    case degrees
}

private struct AdjustmentSliderCompact: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueStyle: AdjustmentValueStyle
    let defaultValue: Double

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            Slider(value: $value, in: range, step: 1) { editing in
                isDragging = editing
            }
            .tint(.orange)
            .frame(height: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            value = defaultValue
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            value = defaultValue
        }
    }
}

// MARK: - Preview

#Preview {
    EditorView(viewModel: FilmEditorViewModel())
}
