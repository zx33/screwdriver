import Foundation
import StatsCore

final class TransportTests {
    private var directory: URL!

    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("mac-stats-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func script(_ body: String) throws -> URL {
        let url = directory.appendingPathComponent("codex")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    func testRealPipesHandshakeIgnoreNotificationsAndCloseOnEOF() throws {
        let program = try script(#"""
        read -r init
        case "$init" in *'"initialize"'*) ;; *) exit 1;; esac
        printf '%s\n' '{"method":"notice","params":{"text":"ignored"}}' '{"id":1,"result":{}}'
        read -r ready
        case "$ready" in *'"initialized"'*) ;; *) exit 1;; esac
        read -r request
        case "$request" in *'"account\/rateLimits\/read"'*|*'"account/rateLimits/read"'*) ;; *) exit 1;; esac
        printf '%s' '{"id":2,"result":{"rateLimits":{"primary":'
        printf '%s\n' '{"usedPercent":25,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":1,"credits":null}}}'
        while read -r line; do exit 2; done
        """#)
        let reading = try CodexUsageClient(executableURL: program, timeout: 3).read()
        try expectEqual(reading.snapshot.rateLimits?.primary?.remainingPercent, 75)
        try expectEqual(reading.snapshot.rateLimitResetCredits?.count, 1)
    }

    func testHungServerHasBoundedDeadlineAndCleanup() throws {
        let program = try script("exec /bin/sleep 30")
        let start = Date()
        try expectThrows(try CodexUsageClient(executableURL: program, timeout: 0.15).read()) { error in
            guard case CodexClientError.timeout = error else { throw CheckFailure("Unexpected error: \(error)") }
        }
        try expectLessThan(Date().timeIntervalSince(start), 2)
    }

    func testServerErrorBecomesLoginMessageWithoutLeakingRawDetails() throws {
        let program = try script(#"""
        read -r init
        printf '%s\n' '{"id":1,"result":{}}'
        read -r ready
        read -r request
        printf '%s\n' '{"id":2,"error":{"code":-32000,"message":"401 auth failure PRIVATE_DETAIL"}}'
        """#)
        try expectThrows(try CodexUsageClient(executableURL: program, timeout: 2).read()) { error in
            try expectTrue(error.localizedDescription.contains("登录"))
            try expectFalse(error.localizedDescription.contains("PRIVATE_DETAIL"))
        }
    }

    func testCancellationStopsPendingRead() async throws {
        let program = try script("exec /bin/sleep 30")
        let start = Date()
        let task = Task { try await CodexUsageClient(executableURL: program, timeout: 20).fetch() }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { _ = try await task.value; throw CheckFailure("Expected cancellation") }
        catch { try expectTrue(error is CancellationError) }
        try expectLessThan(Date().timeIntervalSince(start), 2)
    }
}
