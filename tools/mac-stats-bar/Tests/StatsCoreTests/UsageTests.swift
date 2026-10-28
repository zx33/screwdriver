import Foundation
import StatsCore

final class UsageTests {
    private func decode(_ json: String) throws -> UsageSnapshot {
        try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
    }

    func testWeeklyPrimaryIsNotLabelledFiveHours() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":24,"windowDurationMins":10080,"resetsAt":2000000000},"secondary":null}}"#)
        let window = try require(snapshot.buckets.first?.value.primary)
        try expectEqual(window.title, "每周额度")
        try expectEqual(window.remainingPercent, 76)
        try expectEqual(snapshot.buckets.first?.value.windows.count, 1)
    }

    func testMultiBucketTakesPrecedenceOverLegacy() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"spark":{"primary":{"usedPercent":10}},"codex":{"primary":{"usedPercent":55}}}}"#)
        try expectEqual(snapshot.buckets.map(\.id), ["codex", "spark"])
        try expectEqual(snapshot.bucket(id: "codex")?.primary?.remainingPercent, 45)
    }

    func testUnknownIsNotZeroOrUnlimited() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":null},"secondary":null},"rateLimitResetCredits":null}"#)
        try expectNil(snapshot.buckets.first?.value.primary?.remainingPercent)
        try expectNil(snapshot.buckets.first?.value.remainingPercent(at: Date()))
        try expectNil(snapshot.rateLimitResetCredits?.count)
        try expectEqual(DisplayFormat.percent(nil), "—")
    }

    func testNullBucketDoesNotDiscardOtherBuckets() throws {
        let snapshot = try decode(#"{"rateLimitsByLimitId":{"unavailable":null,"codex":{"primary":{"usedPercent":17}}}}"#)
        try expectEqual(snapshot.buckets.map(\.id), ["codex"])
    }

    func testResetCountIsAuthoritativeWhenDetailsAreTruncated() throws {
        let snapshot = try decode(#"{"rateLimitResetCredits":{"availableCount":4,"credits":[{"id":"fixture-card","status":"available","expiresAt":2000000000}]}}"#)
        try expectEqual(snapshot.rateLimitResetCredits?.count, 4)
        try expectEqual(snapshot.rateLimitResetCredits?.credits?.count, 1)
        try expectEqual(snapshot.rateLimitResetCredits?.nextKnownExpiry?.timeIntervalSince1970, 2_000_000_000)
    }

    func testCreditBalanceIsNotResetCards() throws {
        let snapshot = try decode(#"{"rateLimits":{"credits":{"hasCredits":true,"balance":"20","unlimited":false}},"rateLimitResetCredits":{"availableCount":2,"credits":null}}"#)
        try expectEqual(snapshot.rateLimits?.credits?.balance, "20")
        try expectEqual(snapshot.rateLimitResetCredits?.count, 2)
        try expectNil(snapshot.rateLimitResetCredits?.credits)
    }

    func testExpiredWindowWaitsForServerInsteadOfRefilling() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":98,"resetsAt":100},"secondary":{"usedPercent":50,"resetsAt":500}}}"#)
        let bucket = try require(snapshot.rateLimits)
        try expectEqual(bucket.remainingPercent(at: Date(timeIntervalSince1970: 99)), 2)
        try expectNil(bucket.remainingPercent(at: Date(timeIntervalSince1970: 100)))
        try expectEqual(bucket.primary?.remainingPercent, 2)
    }

    func testMenuUsesLowerRemainingWindow() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":8},"secondary":{"usedPercent":71}}}"#)
        try expectEqual(snapshot.rateLimits?.remainingPercent(at: Date()), 29)
    }

    func testRemainingClampedToValidRange() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":-2},"secondary":{"usedPercent":110}}}"#)
        try expectEqual(snapshot.rateLimits?.primary?.remainingPercent, 100)
        try expectEqual(snapshot.rateLimits?.secondary?.remainingPercent, 0)
    }

    func testStalenessUsesReadTimestamp() throws {
        let reading = UsageReading(snapshot: try decode(#"{"rateLimits":null}"#), fetchedAt: Date(timeIntervalSince1970: 100))
        try expectFalse(reading.isStale(at: Date(timeIntervalSince1970: 650), refreshInterval: 300))
        try expectTrue(reading.isStale(at: Date(timeIntervalSince1970: 701), refreshInterval: 300))
    }
}
