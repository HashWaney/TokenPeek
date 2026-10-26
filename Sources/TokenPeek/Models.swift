import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func resolvedColorScheme(system: ColorScheme) -> ColorScheme {
        colorScheme ?? system
    }
}

struct QuotaWindow: Codable, Equatable, Sendable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Date?

    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }

    var durationLabel: String {
        guard let minutes = windowDurationMins else { return "配额窗口" }
        if minutes % 10_080 == 0 { return "\(minutes / 10_080) 周额度" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) 天额度" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }
}

struct CodexUsage: Codable, Equatable, Sendable {
    let primary: QuotaWindow?
    let secondary: QuotaWindow?

    var tightestRemaining: Int? {
        [primary, secondary].compactMap { $0?.remainingPercent }.min()
    }
}

struct PoeUsage: Codable, Equatable, Sendable {
    let balance: Int
}

enum SourceState: Equatable, Sendable {
    case unconfigured
    case loading
    case fresh(Date)
    case stale(Date, String)
    case authenticationFailed(String)
    case failed(String)

    var statusLabel: String {
        switch self {
        case .unconfigured: return "未配置"
        case .loading: return "读取中"
        case .fresh: return "已连接"
        case .stale: return "数据已过期"
        case .authenticationFailed: return "授权失效"
        case .failed: return "读取失败"
        }
    }
}

struct UsageCache: Codable, Sendable {
    var codex: CodexUsage?
    var codexUpdatedAt: Date?
    var poe: PoeUsage?
    var poeUpdatedAt: Date?
}

enum UsageError: LocalizedError {
    case codexNotFound
    case codexAuthentication(String)
    case codexProtocol(String)
    case poeAuthentication
    case rateLimited
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "未找到 Codex CLI"
        case .codexAuthentication(let message): return message
        case .codexProtocol(let message): return message
        case .poeAuthentication: return "Poe API Key 无效或已失效"
        case .rateLimited: return "请求过于频繁，请稍后再试"
        case .invalidResponse: return "服务返回了无法识别的数据"
        case .network(let message): return message
        }
    }
}
