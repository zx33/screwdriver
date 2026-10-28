import Foundation
import Darwin

public enum CodexClientError: LocalizedError {
    case missingExecutable, launchFailed, disconnected, timeout, invalidResponse, oversizedResponse
    case server(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutable: return "未找到 Codex。请在设置中选择已安装的 Codex 程序。"
        case .launchFailed: return "Codex 无法启动。请检查程序路径和访问权限。"
        case .disconnected: return "Codex 连接已关闭。请确认 Codex 可以正常启动。"
        case .timeout: return "额度同步超时，请检查网络后重试。"
        case .invalidResponse: return "无法识别 Codex 返回的额度数据。"
        case .oversizedResponse: return "Codex 返回的数据过大，已停止本次同步。"
        case .server(_, let message):
            let lower = message.lowercased()
            if lower.contains("auth") || lower.contains("login") || lower.contains("sign in") || lower.contains("401") {
                return "请先在 Codex 中登录 ChatGPT 账户，再同步额度。"
            }
            if lower.contains("api key") || lower.contains("api-key") || lower.contains("chatgpt") {
                return "当前登录方式不提供订阅额度，请使用 ChatGPT 账户登录 Codex。"
            }
            return "Codex 暂时无法读取额度，请稍后重试。"
        }
    }
}

public enum CodexExecutable {
    public static func locate(customPath: String? = nil) -> URL? {
        let manager = FileManager.default
        if let customPath, !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let path = NSString(string: customPath).expandingTildeInPath
            return manager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let home = manager.homeDirectoryForCurrentUser.path
        var paths = [
            "\(home)/.local/bin/codex",
            "\(home)/.codex/packages/standalone/current/bin/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ]
        paths += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }.map { "\($0)/codex" }
        return paths.first(where: manager.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}

/// A short-lived, read-only app-server connection. No thread or model turn is created.
public struct CodexUsageClient: Sendable {
    public let executableURL: URL
    public let timeout: TimeInterval

    public init(executableURL: URL, timeout: TimeInterval = 25) {
        self.executableURL = executableURL
        self.timeout = max(0.1, timeout)
    }

    public func fetch() async throws -> UsageReading {
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try read(cancellation: cancellation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    /// Used by the diagnostic command and transport tests, off the UI thread.
    public func read() throws -> UsageReading { try read(cancellation: CancellationFlag()) }

    private func read(cancellation: CancellationFlag) throws -> UsageReading {
        try cancellation.check()
        let connection = RPCConnection(executableURL: executableURL, timeout: timeout, cancellation: cancellation)
        try connection.start()
        defer { connection.close() }
        _ = try connection.request(id: 1, method: "initialize", params: [
            "clientInfo": ["name": "mac_stats_bar", "title": "Mac Stats Bar", "version": "0.1.0"],
            "capabilities": ["experimentalApi": false, "requestAttestation": false]
        ])
        try connection.send(["method": "initialized"])
        let result = try connection.request(id: 2, method: "account/rateLimits/read", params: nil)
        let data = try JSONSerialization.data(withJSONObject: result)
        let snapshot: UsageSnapshot
        do { snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data) }
        catch { throw CodexClientError.invalidResponse }
        // Completely unrelated or empty JSON must not be shown as a successful read.
        guard result.keys.contains("rateLimits") || result.keys.contains("rateLimitsByLimitId") else {
            throw CodexClientError.invalidResponse
        }
        return UsageReading(snapshot: snapshot)
    }
}

private final class RPCConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let cancellation: CancellationFlag
    private let deadline: TimeInterval
    private var buffer = Data()
    private var started = false
    private var closed = false

    init(executableURL: URL, timeout: TimeInterval, cancellation: CancellationFlag) {
        self.cancellation = cancellation
        deadline = ProcessInfo.processInfo.systemUptime + timeout
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://", "-c", "analytics.enabled=false"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        // Avoid collecting authentication or unrelated diagnostic content in app logs.
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .utility
    }

    func start() throws {
        do { try process.run(); started = true }
        catch { close(); throw CodexClientError.launchFailed }
        let descriptor = output.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        // Writing to a server that exits between messages must never kill the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func send(_ value: [String: Any]) throws {
        try cancellation.check()
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(0x0A)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw CodexClientError.disconnected }
    }

    func request(id: Int, method: String, params: [String: Any]?) throws -> [String: Any] {
        var request: [String: Any] = ["id": id, "method": method]
        if let params { request["params"] = params }
        try send(request)
        while true {
            let value = try nextMessage()
            if value["method"] != nil {
                // This client has no interactive capabilities and accepts no work requests.
                if let requestID = value["id"] {
                    try send(["id": requestID, "error": ["code": -32601, "message": "Unsupported client request"]])
                }
                continue
            }
            guard value["id"] as? Int == id else { continue }
            if let error = value["error"] as? [String: Any] {
                throw CodexClientError.server(code: error["code"] as? Int ?? -1,
                                              message: error["message"] as? String ?? "")
            }
            guard let result = value["result"] as? [String: Any] else { throw CodexClientError.invalidResponse }
            return result
        }
    }

    private func nextMessage() throws -> [String: Any] {
        while true {
            try cancellation.check()
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw CodexClientError.timeout }
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                guard let result = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                    throw CodexClientError.invalidResponse
                }
                return result
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(250, max(1, remaining * 1_000))))
            if ready < 0 {
                if errno == EINTR { continue }
                throw CodexClientError.disconnected
            }
            if ready == 0 { continue }
            var chunk = [UInt8](repeating: 0, count: 8_192)
            let count = Darwin.read(descriptor.fd, &chunk, chunk.count)
            if count == 0 { throw CodexClientError.disconnected }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                throw CodexClientError.disconnected
            }
            buffer.append(contentsOf: chunk.prefix(count))
            guard buffer.count <= 2_097_152 else { throw CodexClientError.oversizedResponse }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        if started {
            // EOF normally shuts down our child. Bound cleanup even if Codex is stuck.
            waitForExit(seconds: 0.3)
            if process.isRunning { process.terminate(); waitForExit(seconds: 0.3) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
    }

    private func waitForExit(seconds: TimeInterval) {
        let until = ProcessInfo.processInfo.systemUptime + seconds
        while process.isRunning && ProcessInfo.processInfo.systemUptime < until { usleep(10_000) }
    }

    deinit { close() }
}
