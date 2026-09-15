import Foundation
import StatsCore

final class SamplingTests {
    func testCPUUsesIntervalDelta() throws {
        let previous = CPUTicks(user: 100, system: 100, idle: 800)
        let current = CPUTicks(user: 115, system: 105, idle: 880)
        try expectEqual(current.utilization(since: previous), 20)
        try expectNil(previous.utilization(since: previous))
    }

    func testCPUTickRollover() throws {
        let previous = CPUTicks(user: UInt32.max - 9, system: 0, idle: 0)
        let current = CPUTicks(user: 10, system: 0, idle: 80)
        try expectEqual(current.utilization(since: previous), 20)
    }

    func testNetworkCountersAre64BitAndUseActualElapsedTime() throws {
        let previous = ["en0": InterfaceCounters(received: 5_000_000_000, sent: 7_000_000_000)]
        let current = ["en0": InterfaceCounters(received: 5_000_004_000, sent: 7_000_002_000)]
        let rate = NetworkRate.calculate(current: current, previous: previous, elapsed: 2)
        try expectEqual(rate?.download, 2_000)
        try expectEqual(rate?.upload, 1_000)
    }

    func testNetworkReconnectDoesNotProduceTrafficSpike() throws {
        let previous = ["en0": InterfaceCounters(received: 5_000_000_000, sent: 100)]
        let current = ["en0": InterfaceCounters(received: 50, sent: 25),
                       "en1": InterfaceCounters(received: 1_000_000, sent: 100)]
        let rate = NetworkRate.calculate(current: current, previous: previous, elapsed: 1)
        try expectEqual(rate?.download, 0)
        try expectEqual(rate?.upload, 0)
        try expectNil(NetworkRate.calculate(current: current, previous: previous, elapsed: 0))
    }
}
