import Darwin
import Foundation
import Observation

/// CPU / memory / network sampling. Runs ONLY while a stats view is on screen
/// (reference-counted), so an idle island costs nothing.
@MainActor
@Observable
final class SystemStatsService {
    static let shared = SystemStatsService()

    private(set) var cpu: Double = 0           // 0...1
    private(set) var memoryUsed: Double = 0    // bytes
    private(set) var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    private(set) var downRate: Double = 0      // bytes/s
    private(set) var upRate: Double = 0
    private(set) var cpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []
    private(set) var netHistory: [Double] = []

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }

    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: (used: UInt64, total: UInt64)?
    @ObservationIgnored private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?

    func beginObserving() {
        viewers += 1
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func endObserving() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
        lastTicks = nil
        lastNet = nil
    }

    private func sample() {
        if let c = cpuUsage() { cpu = c; push(&cpuHistory, c) }
        memoryUsed = memoryUsage()
        push(&memHistory, memoryFraction)
        if let (down, up) = networkRates() {
            downRate = down; upRate = up
            push(&netHistory, down + up)
        }
    }

    private func push(_ array: inout [Double], _ value: Double) {
        array.append(value)
        if array.count > 40 { array.removeFirst(array.count - 40) }
    }

    private func cpuUsage() -> Double? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }

        var used: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(count) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let sys = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            used += user + sys + nice
            total += user + sys + nice + idle
        }
        defer { lastTicks = (used, total) }
        guard let last = lastTicks, total > last.total else { return nil }
        return Double(used - last.used) / Double(total - last.total)
    }

    private func memoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return memoryUsed }
        let page = Double(vm_kernel_page_size)
        let used = Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
            - Double(stats.purgeable_count)
        return used * page
    }

    private func networkRates() -> (Double, Double)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("pdp_ip") else { continue }
            rx += UInt64(data.pointee.ifi_ibytes)
            tx += UInt64(data.pointee.ifi_obytes)
        }
        let now = Date()
        defer { lastNet = (rx, tx, now) }
        guard let last = lastNet else { return nil }
        let dt = max(now.timeIntervalSince(last.at), 0.1)
        let down = rx >= last.rx ? Double(rx - last.rx) / dt : 0
        let up = tx >= last.tx ? Double(tx - last.tx) / dt : 0
        return (down, up)
    }
}
