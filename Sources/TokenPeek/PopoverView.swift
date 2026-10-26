import AppKit
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var showingSettings = false

    var body: some View {
        let effectiveScheme = model.appearance.resolvedColorScheme(system: scheme)
        VStack(spacing: 0) {
            header
            if showingSettings { settings } else { overview }
            footer
        }
        .frame(width: 368)
        .background(TokenPalette(scheme: effectiveScheme).canvas)
        .environment(\.colorScheme, effectiveScheme)
        .preferredColorScheme(effectiveScheme)
    }

    private var effectiveScheme: ColorScheme { model.appearance.resolvedColorScheme(system: scheme) }
    private var palette: TokenPalette { TokenPalette(scheme: effectiveScheme) }

    private var header: some View {
        HStack(spacing: 10) {
            if showingSettings {
                IconButton(symbol: "chevron.left", help: "返回") { showingSettings = false }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.brand)
                    Image(systemName: "waveform.path.ecg").font(.system(size: 15, weight: .semibold)).foregroundStyle(effectiveScheme == .dark ? .black : .white)
                }.frame(width: 30, height: 30)
            }
            Text(showingSettings ? "设置" : "TokenPeek").font(.system(size: 16, weight: .bold, design: .rounded))
            Spacer()
            if !showingSettings {
                IconButton(symbol: "arrow.clockwise", help: "立即刷新", disabled: model.isRefreshing) { Task { await model.refreshAll() } }
                IconButton(symbol: "slider.horizontal.3", help: "设置") { showingSettings = true }
            }
        }.padding(.horizontal, 18).padding(.top, 17).padding(.bottom, 13)
    }

    private var overview: some View {
        VStack(spacing: 10) {
            ServiceCard(title: "Codex", subtitle: "ChatGPT 订阅配额", glyph: "C", tint: palette.codex, state: model.codexState) {
                if let usage = model.codex {
                    VStack(spacing: 14) {
                        if let primary = usage.primary { QuotaRow(window: primary, palette: palette) }
                        if let secondary = usage.secondary { QuotaRow(window: secondary, palette: palette) }
                        StateMessage(state: model.codexState, compact: true)
                    }
                } else { StateMessage(state: model.codexState) }
            }
            ServiceCard(title: "Poe", subtitle: "官方积分余额", glyph: "✳", tint: palette.poe, state: model.poeState) {
                if let usage = model.poe {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(usage.balance.formatted()).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("积分").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    StateMessage(state: model.poeState, compact: true)
                } else { StateMessage(state: model.poeState) }
            }
        }.padding(.horizontal, 13).padding(.bottom, 13)
    }

    private var settings: some View {
        VStack(spacing: 10) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Poe API Key", systemImage: "key.fill").font(.subheadline.weight(.semibold))
                    SecureField("输入 Poe API Key", text: $model.poeKeyDraft).textFieldStyle(.roundedBorder)
                    Text("仅保存在本机钥匙串，不写入日志、源码或普通配置。")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("保存") { model.saveSettings() }.buttonStyle(.borderedProminent).tint(palette.codex)
                        if !model.poeKeyDraft.isEmpty { Button("移除") { model.poeKeyDraft = ""; model.saveSettings() } }
                    }
                }
            }
            SettingsCard {
                VStack(spacing: 13) {
                    HStack { Label("外观", systemImage: "circle.lefthalf.filled"); Spacer() }.font(.subheadline.weight(.semibold))
                    Picker("外观", selection: $model.appearance) {
                        ForEach(AppAppearance.allCases) { item in Text(item.label).tag(item) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Divider()
                    Toggle("登录时启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    HStack { Text("自动刷新"); Spacer(); Text("每 5 分钟").foregroundStyle(.secondary) }.font(.subheadline)
                }
            }
            if let message = model.settingsMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
        }.padding(.horizontal, 13).padding(.bottom, 13)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle().fill(footerColor).frame(width: 6, height: 6)
            Text(footerText).lineLimit(1)
            Spacer()
            if !showingSettings { Button("设置") { showingSettings = true }.buttonStyle(.plain) }
            Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
        }
        .font(.caption2).foregroundStyle(.secondary)
        .padding(.horizontal, 17).padding(.vertical, 11)
        .background(palette.footer)
        .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
    }

    private var footerText: String {
        if model.hasDegradedData { return "连接异常 · 显示可用的上次快照" }
        if model.isRefreshing { return "正在同步两个数据源…" }
        return "数据已同步 · 5 分钟自动刷新"
    }
    private var footerColor: Color { model.hasDegradedData ? .orange : (model.isRefreshing ? .blue : .green) }

    @ViewBuilder private func SettingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 28, height: 28) }
            .buttonStyle(.plain).foregroundStyle(.secondary).disabled(disabled).help(help)
    }
}

private struct ServiceCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let subtitle: String
    let glyph: String
    let tint: Color
    let state: SourceState
    @ViewBuilder let content: Content

    var body: some View {
        let palette = TokenPalette(scheme: scheme)
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Text(glyph).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(tint)
                    .frame(width: 32, height: 32).background(tint.opacity(scheme == .dark ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(state: state)
            }
            content
        }
        .padding(15)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
    }
}

private struct StatusPill: View {
    let state: SourceState
    var body: some View {
        Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.11), in: Capsule())
    }
    private var label: String {
        if case .authenticationFailed = state { return "需重新登录" }
        return state.statusLabel
    }
    private var color: Color {
        switch state {
        case .fresh: return .green
        case .loading: return .blue
        case .unconfigured, .stale: return .orange
        case .authenticationFailed, .failed: return .red
        }
    }
}

private struct QuotaRow: View {
    let window: QuotaWindow
    let palette: TokenPalette
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(window.durationLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(window.remainingPercent)%").font(.subheadline.bold()).monospacedDigit()
                Text("剩余").font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule().fill(tint).frame(width: geometry.size.width * Double(window.remainingPercent) / 100)
                }
            }.frame(height: 6)
            HStack {
                Text("当前窗口")
                Spacer()
                if let reset = window.resetsAt { Text(reset.formatted(date: .numeric, time: .shortened) + " 重置") }
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var tint: Color { window.remainingPercent <= 10 ? .red : (window.remainingPercent <= 30 ? .orange : palette.codex) }
}

private struct StateMessage: View {
    let state: SourceState
    var compact = false
    var body: some View {
        switch state {
        case .loading:
            HStack(spacing: 7) { ProgressView().controlSize(.small); Text("正在读取…") }.font(.caption).foregroundStyle(.secondary)
        case .unconfigured:
            Label("请在设置中填写 Poe API Key", systemImage: "key").font(.caption).foregroundStyle(.secondary)
        case .fresh(let date):
            Text("更新于 \(date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
        case .stale(let date, let message):
            VStack(alignment: .leading, spacing: 3) {
                Label("离线或服务不可用，当前为上次成功快照", systemImage: "wifi.slash")
                Text("上次成功：\(date.formatted(date: .abbreviated, time: .shortened))")
                if !compact { Text(message) }
            }.font(.caption2).foregroundStyle(.orange)
        case .authenticationFailed(let message):
            Label(message, systemImage: "person.crop.circle.badge.exclamationmark").font(.caption).foregroundStyle(.red)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
        }
    }
}

private struct TokenPalette {
    let scheme: ColorScheme
    var canvas: Color { scheme == .dark ? Color(hex: 0x252A33) : Color(hex: 0xFCFCFD) }
    var card: Color { scheme == .dark ? Color(hex: 0x303640) : Color(hex: 0xF6F7F9) }
    var footer: Color { scheme == .dark ? Color(hex: 0x20252D) : Color(hex: 0xFAFAFB) }
    var line: Color { scheme == .dark ? Color(hex: 0x424954) : Color(hex: 0xE9EBEE) }
    var track: Color { scheme == .dark ? Color(hex: 0x535961) : Color(hex: 0xE4E8E9) }
    var brand: Color { scheme == .dark ? Color(hex: 0xF1F3F6) : Color(hex: 0x192333) }
    var codex: Color { scheme == .dark ? Color(hex: 0x79C7AD) : Color(hex: 0x187A67) }
    var poe: Color { scheme == .dark ? Color(hex: 0xB9A0F4) : Color(hex: 0x7053C2) }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
