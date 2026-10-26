import Foundation
import os
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    private let logger = Logger(subsystem: "local.wangqing.tokenpeek", category: "usage")

    @Published var codex: CodexUsage?
    @Published var poe: PoeUsage?
    @Published var codexState: SourceState = .loading
    @Published var poeState: SourceState = .unconfigured
    @Published var isRefreshing = false
    @Published var poeKeyDraft = ""
    @Published var settingsMessage: String?
    @Published var launchAtLogin = false
    @Published var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    private let codexService = CodexUsageService()
    private let poeService = PoeUsageService()
    private let keychain = KeychainStore()
    private let cacheURL: URL
    private var timerTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var hasStarted = false

    init() {
        appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "system") ?? .system
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TokenPeek", isDirectory: true)
        cacheURL = support.appendingPathComponent("usage-cache.json")
        loadCache()
        poeKeyDraft = keychain.readPoeKey() ?? ""
        if poeKeyDraft.isEmpty { poeState = .unconfigured }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        timerTask = Task { [weak self] in
            await self?.refreshAll()
            while !Task.isCancelled {
                let failures = await MainActor.run { self?.consecutiveFailures ?? 0 }
                let delay = min(1_800, 300 * (1 << min(failures, 3)))
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { break }
                await self?.refreshAll()
            }
        }
    }

    deinit { timerTask?.cancel() }

    var menuBarCodex: String { codex?.tightestRemaining.map { "\($0)%" } ?? "—" }
    var menuBarPoe: String { poe.map { Self.compactPoints($0.balance) } ?? "—" }
    var hasDegradedData: Bool { isFailure(codexState) || isFailure(poeState) }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        if codex == nil { codexState = .loading }
        if poe == nil, !poeKeyDraft.isEmpty { poeState = .loading }

        async let codexResult: Void = refreshCodex()
        async let poeResult: Void = refreshPoe()
        _ = await (codexResult, poeResult)
        isRefreshing = false

        let failed = isFailure(codexState) || (!poeKeyDraft.isEmpty && isFailure(poeState))
        consecutiveFailures = failed ? consecutiveFailures + 1 : 0
    }

    func saveSettings() {
        let trimmed = poeKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try keychain.savePoeKey(trimmed)
            poeKeyDraft = trimmed
            poeState = trimmed.isEmpty ? .unconfigured : .loading
            settingsMessage = trimmed.isEmpty ? "已移除 Poe API Key" : "Poe API Key 已安全存入钥匙串"
            Task { await refreshAll() }
        } catch {
            settingsMessage = "钥匙串保存失败：\(error.localizedDescription)"
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
            settingsMessage = enabled ? "已启用登录时启动" : "已关闭登录时启动"
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settingsMessage = "启动项更新失败：\(error.localizedDescription)"
        }
    }

    private func refreshCodex() async {
        do {
            codex = try await codexService.fetch()
            codexState = .fresh(Date())
            saveCache()
        } catch {
            logger.error("Codex refresh failed: \(error.localizedDescription, privacy: .public)")
            codexState = stateFor(error: error, cachedAt: cachedTimestamp(for: .codex))
        }
    }

    private func refreshPoe() async {
        guard let key = keychain.readPoeKey(), !key.isEmpty else {
            poeState = .unconfigured
            return
        }
        do {
            poe = try await poeService.fetch(apiKey: key)
            poeState = .fresh(Date())
            saveCache()
        } catch {
            logger.error("Poe refresh failed: \(error.localizedDescription, privacy: .public)")
            poeState = stateFor(error: error, cachedAt: cachedTimestamp(for: .poe))
        }
    }

    private enum Source { case codex, poe }
    private func cachedTimestamp(for source: Source) -> Date? {
        guard let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(UsageCache.self, from: data) else { return nil }
        return source == .codex ? cache.codexUpdatedAt : cache.poeUpdatedAt
    }

    private func stateFor(error: Error, cachedAt: Date?) -> SourceState {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if case UsageError.poeAuthentication = error { return .authenticationFailed(message) }
        if case UsageError.codexAuthentication = error { return .authenticationFailed(message) }
        if let cachedAt { return .stale(cachedAt, message) }
        return .failed(message)
    }

    private func isFailure(_ state: SourceState) -> Bool {
        switch state {
        case .stale, .authenticationFailed, .failed: return true
        default: return false
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(UsageCache.self, from: data) else { return }
        codex = cache.codex
        poe = cache.poe
        if let date = cache.codexUpdatedAt { codexState = .stale(date, "正在获取最新数据") }
        if let date = cache.poeUpdatedAt { poeState = .stale(date, "正在获取最新数据") }
    }

    private func saveCache() {
        let codexDate: Date? = { if case .fresh(let date) = codexState { return date }; return cachedTimestamp(for: .codex) }()
        let poeDate: Date? = { if case .fresh(let date) = poeState { return date }; return cachedTimestamp(for: .poe) }()
        let cache = UsageCache(codex: codex, codexUpdatedAt: codexDate, poe: poe, poeUpdatedAt: poeDate)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    nonisolated static func compactPoints(_ value: Int) -> String {
        guard abs(value) >= 1_000 else { return value.formatted() }
        let number = Double(value) / 1_000
        return number.formatted(.number.precision(.fractionLength(number < 10 ? 1 : 0))) + "k"
    }
}
