import Foundation

public struct WidgetSnapshot: Codable, Sendable {
    public var updatedAt: Date
    public var chipName: String
    public var cpuPercent: Double
    public var gpuPercent: Double
    public var memoryPercent: Double
    public var memoryUsedGB: Double
    public var memoryTotalGB: Double
    public var bandwidthGBs: Double
    public var networkDown: Double
    public var networkUp: Double
    public var diskRead: Double
    public var diskWrite: Double
    public var diskUsedPercent: Double
    public var temperatureC: Double
    public var socWatts: Double
    public var aiStatus: String
    public var cpuHistory: [Double]
    public var gpuHistory: [Double]
    public var memoryHistory: [Double]
    public var bandwidthHistory: [Double]
    public var networkDownHistory: [Double]
    public var networkUpHistory: [Double]
    public var diskReadHistory: [Double]
    public var diskWriteHistory: [Double]
    public var temperatureHistory: [Double]

    public init(updatedAt: Date = .now, chipName: String = "Apple Silicon",
                cpuPercent: Double = 0, gpuPercent: Double = 0,
                memoryPercent: Double = 0, memoryUsedGB: Double = 0, memoryTotalGB: Double = 0,
                bandwidthGBs: Double = 0, networkDown: Double = 0, networkUp: Double = 0,
                diskRead: Double = 0, diskWrite: Double = 0, diskUsedPercent: Double = 0,
                temperatureC: Double = 0, socWatts: Double = 0, aiStatus: String = "空闲",
                cpuHistory: [Double] = [], gpuHistory: [Double] = [], memoryHistory: [Double] = [],
                bandwidthHistory: [Double] = [], networkDownHistory: [Double] = [],
                networkUpHistory: [Double] = [], diskReadHistory: [Double] = [],
                diskWriteHistory: [Double] = [], temperatureHistory: [Double] = []) {
        self.updatedAt = updatedAt; self.chipName = chipName
        self.cpuPercent = cpuPercent; self.gpuPercent = gpuPercent
        self.memoryPercent = memoryPercent; self.memoryUsedGB = memoryUsedGB
        self.memoryTotalGB = memoryTotalGB; self.bandwidthGBs = bandwidthGBs
        self.networkDown = networkDown; self.networkUp = networkUp
        self.diskRead = diskRead; self.diskWrite = diskWrite; self.diskUsedPercent = diskUsedPercent
        self.temperatureC = temperatureC; self.socWatts = socWatts; self.aiStatus = aiStatus
        self.cpuHistory = cpuHistory; self.gpuHistory = gpuHistory; self.memoryHistory = memoryHistory
        self.bandwidthHistory = bandwidthHistory; self.networkDownHistory = networkDownHistory
        self.networkUpHistory = networkUpHistory; self.diskReadHistory = diskReadHistory
        self.diskWriteHistory = diskWriteHistory; self.temperatureHistory = temperatureHistory
    }
}

public enum WidgetSnapshotStore {
    public static var fileURL: URL {
        // The WidgetKit extension is sandboxed. The unsandboxed host writes directly into that
        // extension's own container; inside the extension, Application Support resolves to the
        // same path. This keeps widget data private without requiring an App Store app-group
        // provisioning profile for this locally built app.
        let root: URL
        if Bundle.main.bundleIdentifier?.hasSuffix(".Widget") == true {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.leoyuan.LeoMacMonitor.Widget/Data/Library/Application Support",
                                        isDirectory: true)
        }
        return root.appendingPathComponent("LeoMacMonitor", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }

    public static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public static func write(_ snapshot: WidgetSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
