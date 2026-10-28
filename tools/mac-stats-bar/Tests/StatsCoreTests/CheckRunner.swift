import Foundation

// A dependency-free runner so the same checks work with Apple's Command Line
// Tools, which do not include XCTest. Any failed check gives a nonzero exit.
struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #fileID, line: UInt = #line) throws {
    guard actual == expected else { throw CheckFailure("\(file):\(line): expected \(expected), received \(actual)") }
}
func expectNil<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) throws {
    guard value == nil else { throw CheckFailure("\(file):\(line): expected nil") }
}
func expectTrue(_ value: Bool, file: StaticString = #fileID, line: UInt = #line) throws {
    guard value else { throw CheckFailure("\(file):\(line): expected true") }
}
func expectFalse(_ value: Bool, file: StaticString = #fileID, line: UInt = #line) throws {
    guard !value else { throw CheckFailure("\(file):\(line): expected false") }
}
func expectLessThan<T: Comparable>(_ value: T, _ upper: T, file: StaticString = #fileID, line: UInt = #line) throws {
    guard value < upper else { throw CheckFailure("\(file):\(line): \(value) is not below \(upper)") }
}
func require<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) throws -> T {
    guard let value else { throw CheckFailure("\(file):\(line): missing required value") }
    return value
}
func expectThrows(_ expression: @autoclosure () throws -> Any, verify: (Error) throws -> Void) throws {
    do { _ = try expression() }
    catch { try verify(error); return }
    throw CheckFailure("Expected an error but operation succeeded")
}

@main
enum CheckRunner {
    static func main() async {
        let usage = UsageTests()
        let sampling = SamplingTests()
        let transport = TransportTests()
        let tray = TrayTests()
        var passed = 0
        var failed = 0
        let checks: [(String, () throws -> Void)] = [
            ("weekly primary window", usage.testWeeklyPrimaryIsNotLabelledFiveHours),
            ("multi-bucket precedence", usage.testMultiBucketTakesPrecedenceOverLegacy),
            ("unknown values", usage.testUnknownIsNotZeroOrUnlimited),
            ("null bucket", usage.testNullBucketDoesNotDiscardOtherBuckets),
            ("authoritative reset count", usage.testResetCountIsAuthoritativeWhenDetailsAreTruncated),
            ("balance vs reset cards", usage.testCreditBalanceIsNotResetCards),
            ("expired window", usage.testExpiredWindowWaitsForServerInsteadOfRefilling),
            ("minimum remaining", usage.testMenuUsesLowerRemainingWindow),
            ("percentage clamping", usage.testRemainingClampedToValidRange),
            ("snapshot staleness", usage.testStalenessUsesReadTimestamp),
            ("CPU interval delta", sampling.testCPUUsesIntervalDelta),
            ("CPU counter rollover", sampling.testCPUTickRollover),
            ("64-bit network counters", sampling.testNetworkCountersAre64BitAndUseActualElapsedTime),
            ("network reconnect", sampling.testNetworkReconnectDoesNotProduceTrafficSpike),
            ("pipe handshake and EOF", transport.testRealPipesHandshakeIgnoreNotificationsAndCloseOnEOF),
            ("bounded timeout", transport.testHungServerHasBoundedDeadlineAndCleanup),
            ("safe login error", transport.testServerErrorBecomesLoginMessageWithoutLeakingRawDetails),
            ("tray notch and edge", tray.testNotchAndRightEdge),
            ("tray external screen", tray.testExternalDisplayWithNegativeOrigin),
            ("tray small screen and Dock", tray.testSmallDisplayAndSideDock),
            ("tray auto-hidden menu bar", tray.testAutohiddenMenuStillAvoidsNotch),
            ("tray order across relaunches", tray.testOrderHandlesRelaunchesAndNewItems)
        ]
        for (name, check) in checks {
            do {
                try transport.setUpWithError()
                defer { try? transport.tearDownWithError() }
                try check()
                print("PASS \(name)")
                passed += 1
            } catch {
                print("FAIL \(name): \(error)")
                failed += 1
            }
        }
        do {
            try transport.setUpWithError()
            defer { try? transport.tearDownWithError() }
            try await transport.testCancellationStopsPendingRead()
            print("PASS cancellation")
            passed += 1
        } catch { print("FAIL cancellation: \(error)"); failed += 1 }
        print("\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
