import Foundation
import WidgetKit
import LeoMacMonitorWidgetShared

/// Publishes a lightweight, private-API-free snapshot for the WidgetKit extension. Disk writes are
/// throttled because the monitor itself samples every second; WidgetKit is a glanceable surface and
/// macOS decides its actual refresh cadence.
@MainActor
enum WidgetSnapshotPublisher {
    static let kind = "LeoMacMonitorOverview"
    private static var lastWrite = Date.distantPast
    private static var lastReload = Date.distantPast

    static func publish(_ monitor: LeoMacMonitorMonitor) {
        let now = Date()
        guard now.timeIntervalSince(lastWrite) >= 5 else { return }
        lastWrite = now
        let s = monitor.snapshot
        let aiStatus: String
        if s.power.aneWatts > 1.5 { aiStatus = "ANE 活跃" }
        else if s.aiModelActive { aiStatus = "LLM / GPU" }
        else if monitor.activity.gpu { aiStatus = "GPU 活跃" }
        else if monitor.activity.cpu { aiStatus = "CPU 活跃" }
        else { aiStatus = "空闲" }

        let snapshot = WidgetSnapshot(
            updatedAt: now,
            chipName: monitor.topology?.chipName ?? "Apple Silicon",
            cpuPercent: max(s.cpu.eUsagePercent, s.cpu.pUsagePercent),
            gpuPercent: s.gpu.usagePercent,
            memoryPercent: s.memory.usedPercent,
            memoryUsedGB: s.memory.usedGB,
            memoryTotalGB: s.memory.totalGB,
            bandwidthGBs: s.bandwidth.totalGBs,
            networkDown: s.network.downloadBytesPerSec,
            networkUp: s.network.uploadBytesPerSec,
            diskRead: s.disk.readBytesPerSec,
            diskWrite: s.disk.writeBytesPerSec,
            diskUsedPercent: s.disk.usedFraction * 100,
            temperatureC: s.temperature.cpuMaxCelsius > 0 ? s.temperature.cpuMaxCelsius : s.temperature.cpuCelsius,
            socWatts: s.power.socWatts,
            aiStatus: aiStatus,
            cpuHistory: monitor.history.pCPU,
            gpuHistory: monitor.history.gpu,
            memoryHistory: monitor.history.memFraction,
            bandwidthHistory: monitor.history.bandwidth,
            networkDownHistory: monitor.history.netDown,
            networkUpHistory: monitor.history.netUp,
            diskReadHistory: monitor.history.diskRead,
            diskWriteHistory: monitor.history.diskWrite,
            temperatureHistory: monitor.history.dieTemp)
        try? WidgetSnapshotStore.write(snapshot)

        if now.timeIntervalSince(lastReload) >= 30 {
            lastReload = now
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
