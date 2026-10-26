import Foundation

struct CodexUsageService {
    private let executableCandidates = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex"
    ]

    func fetch() async throws -> CodexUsage {
        try await Task.detached(priority: .utility) {
            guard let executable = executableCandidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
                throw UsageError.codexNotFound
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["app-server", "--stdio"]

            let input = Pipe()
            let output = Pipe()
            let error = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = error

            do { try process.run() } catch {
                throw UsageError.codexProtocol("Codex App Server 启动失败：\(error.localizedDescription)")
            }

            let timeout = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 25, execute: timeout)
            defer {
                timeout.cancel()
                try? input.fileHandleForWriting.close()
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
            }

            var buffer = Data()
            func send(_ json: String) throws {
                guard process.isRunning else { throw UsageError.codexProtocol("Codex App Server 已提前退出") }
                input.fileHandleForWriting.write(Data((json + "\n").utf8))
            }
            func receive(id: Int) throws -> RateLimitEnvelope {
                while process.isRunning {
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let lineData = Data(buffer[..<newline])
                        buffer.removeSubrange(...newline)
                        guard let envelope = try? JSONDecoder().decode(RateLimitEnvelope.self, from: lineData),
                              envelope.id == id else { continue }
                        return envelope
                    }
                    let chunk = output.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    guard buffer.count <= 4_000_000 else {
                        throw UsageError.codexProtocol("Codex App Server 返回数据异常过大")
                    }
                }
                throw UsageError.codexProtocol("25 秒内未收到 Codex App Server 响应")
            }

            try send(#"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"tokenpeek","title":"TokenPeek","version":"1.0.0"}}}"#)
            let initialization = try receive(id: 1)
            if let message = initialization.error?.message { throw UsageError.codexProtocol(message) }

            try send(#"{"method":"initialized","params":{}}"#)
            try send(#"{"method":"account/rateLimits/read","id":2}"#)
            let reply = try receive(id: 2)
            if let message = reply.error?.message {
                if message.localizedCaseInsensitiveContains("login") || message.localizedCaseInsensitiveContains("auth") {
                    throw UsageError.codexAuthentication("Codex 登录已失效，请先在终端重新登录")
                }
                throw UsageError.codexProtocol(message)
            }
            guard let limits = reply.result?.preferredRateLimits else { throw UsageError.invalidResponse }
            return CodexUsage(primary: limits.primary?.model, secondary: limits.secondary?.model)
        }.value
    }
}

private struct RateLimitEnvelope: Decodable {
    let id: Int?
    let result: ResultPayload?
    let error: ErrorPayload?

    struct ResultPayload: Decodable {
        let rateLimits: RateLimits?
        let rateLimitsByLimitId: [String: RateLimits]?

        var preferredRateLimits: RateLimits? {
            rateLimits ?? rateLimitsByLimitId?["codex"] ?? rateLimitsByLimitId?.values.first
        }
    }
    struct ErrorPayload: Decodable { let message: String }
    struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
    }
    struct Window: Decodable {
        let usedPercent: Int
        let windowDurationMins: Int?
        let resetsAt: Int?

        var model: QuotaWindow {
            QuotaWindow(
                usedPercent: usedPercent,
                windowDurationMins: windowDurationMins,
                resetsAt: resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
    }
}
