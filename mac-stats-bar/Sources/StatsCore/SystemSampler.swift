import Foundation
import Darwin
import IOKit.ps

public struct CPUTicks: Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32 = 0) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    public func utilization(since previous: CPUTicks) -> Double? {
        let active = UInt64(user &- previous.user) + UInt64(system &- previous.system) + UInt64(nice &- previous.nice)
        let total = active + UInt64(idle &- previous.idle)
        guard total > 0 else { return nil }
        return Double(active) / Double(total) * 100
    }
}

public struct InterfaceCounters: Sendable {
    public let received: UInt64
    public let sent: UInt64
    public init(received: UInt64, sent: UInt64) { self.received = received; self.sent = sent }
}

public struct NetworkRate: Sendable {
    public let download: Double
    public let upload: Double

    public static func calculate(current: [String: InterfaceCounters], previous: [String: InterfaceCounters],
                                 elapsed: TimeInterval) -> NetworkRate? {
        guard elapsed > 0, elapsed.isFinite else { return nil }
        var received: Double = 0
        var sent: Double = 0
        for (name, counters) in current {
            guard let old = previous[name], counters.received >= old.received, counters.sent >= old.sent else { continue }
            received += Double(counters.received - old.received)
            sent += Double(counters.sent - old.sent)
        }
        return NetworkRate(download: received / elapsed, upload: sent / elapsed)
    }
}

public struct MemoryReading: Sendable {
    public let used: UInt64
    public let total: UInt64
    public let compressed: UInt64
    public let swapUsed: UInt64?
    public let pressure: Int?
    public var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    public var pressureLabel: String {
        switch pressure {
        case 1: return "压力正常"
        case 2: return "内存压力偏高"
        case 4: return "内存压力很高"
        default: return "压力未知"
        }
    }
}

public struct DiskReading: Sendable {
    public let total: UInt64
    public let available: UInt64
    public var percent: Double { total > 0 ? Double(total - min(total, available)) / Double(total) * 100 : 0 }
}

public struct BatteryReading: Sendable {
    public let percent: Double
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public var label: String {
        if isCharging { return "正在充电" }
        if isPluggedIn { return percent >= 99 ? "已充满 · 电源供电" : "电源供电" }
        return "电池供电"
    }
}

public struct SystemReading: Sendable {
    public let timestamp: Date
    public let cpuPercent: Double?
    public let memory: MemoryReading?
    public let network: NetworkRate?
    public let disk: DiskReading?
    public let battery: BatteryReading?
    public let coreCount: Int
    public let thermalLabel: String

    public static let empty = SystemReading(timestamp: Date(), cpuPercent: nil, memory: nil, network: nil,
                                            disk: nil, battery: nil, coreCount: ProcessInfo.processInfo.processorCount,
                                            thermalLabel: "正在采样")
}

/// Native measurements with all mutable sampling state protected by one lock.
public final class SystemSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousCPU: CPUTicks?
    private var previousNetwork: [String: InterfaceCounters]?
    private var previousUptime: TimeInterval?
    private var cachedDisk: DiskReading?
    private var cachedBattery: BatteryReading?
    private var lastSlowSample: TimeInterval = -.infinity

    public init() {}

    public func resetBaseline() {
        lock.lock()
        defer { lock.unlock() }
        previousCPU = nil; previousNetwork = nil; previousUptime = nil
        lastSlowSample = -.infinity
    }

    public func sample() -> SystemReading {
        lock.lock()
        defer { lock.unlock() }
        let uptime = ProcessInfo.processInfo.systemUptime
        let cpu = readCPU()
        let cpuPercent = cpu.flatMap { current in previousCPU.flatMap { current.utilization(since: $0) } }
        previousCPU = cpu
        let counters = readNetwork()
        var rate: NetworkRate?
        if let counters, let previousNetwork, let previousUptime {
            rate = NetworkRate.calculate(current: counters, previous: previousNetwork, elapsed: uptime - previousUptime)
        }
        previousNetwork = counters
        previousUptime = uptime
        if uptime - lastSlowSample >= 30 {
            cachedDisk = readDisk()
            cachedBattery = readBattery()
            lastSlowSample = uptime
        }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "散热正常"
        case .fair: thermal = "轻微升温"
        case .serious: thermal = "温度偏高"
        case .critical: thermal = "温度很高"
        @unknown default: thermal = "散热状态未知"
        }
        return SystemReading(timestamp: Date(), cpuPercent: cpuPercent, memory: readMemory(), network: rate,
                             disk: cachedDisk, battery: cachedBattery, coreCount: ProcessInfo.processInfo.processorCount,
                             thermalLabel: thermal)
    }

    private func readCPU() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private func readMemory() -> MemoryReading? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let internalPages = UInt64(info.internal_page_count)
        let appPages = internalPages - min(internalPages, UInt64(info.purgeable_count))
        let used = (appPages + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * UInt64(pageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        var pressure: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        let pressureOK = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0
        return MemoryReading(used: min(total, used), total: total,
                             compressed: UInt64(info.compressor_page_count) * UInt64(pageSize),
                             swapUsed: swapOK ? swap.xsu_used : nil, pressure: pressureOK ? Int(pressure) : nil)
    }

    private func readNetwork() -> [String: InterfaceCounters]? {
        // NET_RT_IFLIST2 exposes 64-bit counters. Physical en* interfaces avoid
        // counting loopback, VPN, AWDL and bridge traffic a second time.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0, size < 16_777_216 else { return nil }
        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) }
        guard result == 0 else { return nil }
        return data.withUnsafeBytes { bytes -> [String: InterfaceCounters] in
            var counters: [String: InterfaceCounters] = [:]
            var offset = 0
            while offset + 4 <= size {
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= size else { break }
                let type = bytes[offset + 3]
                if type == UInt8(RTM_IFINFO2), length >= MemoryLayout<if_msghdr2>.size {
                    let header = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if header.ifm_flags & IFF_UP != 0 {
                        var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                        if if_indextoname(UInt32(header.ifm_index), &nameBuffer) != nil {
                            let name = String(cString: nameBuffer)
                            if name.hasPrefix("en") {
                                counters["\(name):\(header.ifm_index)"] = InterfaceCounters(
                                    received: header.ifm_data.ifi_ibytes, sent: header.ifm_data.ifi_obytes)
                            }
                        }
                    }
                }
                offset += length
            }
            return counters
        }
    }

    private func readDisk() -> DiskReading? {
        let url = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage, available >= 0 else { return nil }
        return DiskReading(total: UInt64(total), available: min(UInt64(total), UInt64(available)))
    }

    private func readBattery() -> BatteryReading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let value = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  value[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = value[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = value[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return BatteryReading(percent: min(100, max(0, Double(current) / Double(maximum) * 100)),
                                  isCharging: value[kIOPSIsChargingKey] as? Bool ?? false,
                                  isPluggedIn: value[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}
