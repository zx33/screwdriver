import Foundation

public struct QuotaWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: TimeInterval?

    public var remainingPercent: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }

    public var resetDate: Date? {
        guard let resetsAt, resetsAt > 0, resetsAt.isFinite else { return nil }
        return Date(timeIntervalSince1970: resetsAt)
    }

    public var title: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return "额度窗口" }
        switch minutes {
        case 300: return "5 小时额度"
        case 1_440: return "每日额度"
        case 10_080: return "每周额度"
        case let m where m % 1_440 == 0: return "\(m / 1_440) 天额度"
        case let m where m % 60 == 0: return "\(m / 60) 小时额度"
        default: return "\(minutes) 分钟额度"
        }
    }

    public func isAwaitingReset(at now: Date) -> Bool {
        resetDate.map { $0 <= now } ?? false
    }
}

public struct UsageCredits: Codable, Equatable, Sendable {
    public let hasCredits: Bool?
    public let unlimited: Bool?
    public let balance: String?
}

public struct QuotaBucket: Codable, Equatable, Sendable {
    public let limitId: String?
    public let limitName: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let credits: UsageCredits?
    public let planType: String?
    public let spendControlReached: Bool?
    public let rateLimitReachedType: String?

    public var windows: [(id: String, value: QuotaWindow)] {
        var result: [(String, QuotaWindow)] = []
        if let primary { result.append(("primary", primary)) }
        if let secondary { result.append(("secondary", secondary)) }
        return result
    }

    public func displayName(fallback: String) -> String {
        if let limitName, !limitName.isEmpty { return limitName }
        return fallback == "codex" ? "Codex" : fallback
    }

    /// A spent or expired window cannot be inferred to have replenished locally.
    public func remainingPercent(at now: Date) -> Double? {
        guard !windows.isEmpty,
              !windows.contains(where: { $0.value.isAwaitingReset(at: now) }),
              windows.allSatisfy({ $0.value.remainingPercent != nil }) else { return nil }
        return windows.compactMap { $0.value.remainingPercent }.min()
    }

    public var planLabel: String? {
        guard let planType else { return nil }
        switch planType.lowercased() {
        case "prolite": return "Pro Lite"
        case "pro": return "Pro"
        case "plus": return "Plus"
        case "free": return "Free"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        default: return planType
        }
    }
}

public struct ResetCredit: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let resetType: String?
    public let status: String?
    public let grantedAt: TimeInterval?
    public let expiresAt: TimeInterval?
    public let title: String?
    public let description: String?

    public var expiryDate: Date? {
        guard let expiresAt, expiresAt > 0 else { return nil }
        return Date(timeIntervalSince1970: expiresAt)
    }
}

public struct ResetCreditsSummary: Codable, Equatable, Sendable {
    // The server can truncate detail rows. Never use credits.count as the balance.
    public let availableCount: Int?
    public let credits: [ResetCredit]?

    public var count: Int? { availableCount.map { max(0, $0) } }
    public var nextKnownExpiry: Date? {
        credits?.filter { $0.status == "available" }.compactMap(\.expiryDate).min()
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let rateLimits: QuotaBucket?
    public let rateLimitsByLimitId: [String: QuotaBucket?]?
    public let rateLimitResetCredits: ResetCreditsSummary?

    public var buckets: [(id: String, value: QuotaBucket)] {
        if let map = rateLimitsByLimitId, !map.isEmpty {
            return map.compactMap { key, value in value.map { (id: key, value: $0) } }
                .sorted {
                    if $0.id == "codex" { return $1.id != "codex" }
                    if $1.id == "codex" { return false }
                    return $0.id < $1.id
                }
        }
        if let rateLimits { return [(rateLimits.limitId ?? "codex", rateLimits)] }
        return []
    }

    public func bucket(id: String) -> QuotaBucket? {
        buckets.first { $0.id == id }?.value
    }
}

public struct UsageReading: Sendable {
    public let snapshot: UsageSnapshot
    public let fetchedAt: Date

    public init(snapshot: UsageSnapshot, fetchedAt: Date = Date()) {
        self.snapshot = snapshot
        self.fetchedAt = fetchedAt
    }

    public func isStale(at now: Date, refreshInterval: TimeInterval) -> Bool {
        now.timeIntervalSince(fetchedAt) > max(120, refreshInterval * 2)
    }
}

public enum DisplayFormat {
    public static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f%%", min(100, max(0, value)))
    }

    public static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
    }

    public static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        if value < 1_024 { return String(format: "%.0f B/s", value) }
        if value < 1_048_576 { return String(format: "%.1f KB/s", value / 1_024) }
        return String(format: "%.1f MB/s", value / 1_048_576)
    }

    public static func countdown(to date: Date?, now: Date) -> String {
        guard let date else { return "恢复时间未知" }
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "已到恢复时间 · 等待同步" }
        let minutes = Int(ceil(seconds / 60))
        if minutes < 60 { return "\(minutes) 分钟后恢复" }
        if minutes < 1_440 { return "\(minutes / 60) 小时 \(minutes % 60) 分钟后恢复" }
        return "\(minutes / 1_440) 天 \((minutes % 1_440) / 60) 小时后恢复"
    }
}
