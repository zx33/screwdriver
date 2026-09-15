import Foundation

/// The user's collection survives temporary display changes. Suspending its
/// presentation must not mean disabling the collection or forgetting its IDs.
public struct TrayCollectionState {
    public private(set) var isEnabled = false
    public private(set) var isArranging = false
    public private(set) var collectedIDs = Set<String>()
    public private(set) var prefersCollapsed = false
    public private(set) var isSuspended = false

    public init() {}

    public var shouldCollapse: Bool {
        isEnabled && !isArranging && prefersCollapsed && !isSuspended
    }

    public mutating func beginArrangement() {
        isEnabled = true
        isArranging = true
        prefersCollapsed = false
        isSuspended = false
    }

    @discardableResult
    public mutating func finishArrangement(collecting ids: Set<String>) -> Bool {
        guard isEnabled, isArranging, !ids.isEmpty else { return false }
        collectedIDs = ids
        isArranging = false
        prefersCollapsed = true
        isSuspended = false
        return true
    }

    public mutating func setCollapsed(_ collapsed: Bool) {
        guard isEnabled, !isArranging else { return }
        prefersCollapsed = collapsed
    }

    public mutating func suspend() {
        if isEnabled { isSuspended = true }
    }

    public mutating func resume() {
        isSuspended = false
    }

    public mutating func stop() {
        self = Self()
    }
}
