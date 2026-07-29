//
//  File:      DiskHealth.swift
//  Created:   2026-07-29
//  Developer: Leo Yuan
//  Overview:  Strict diskutil-plist SMART/NVMe parser plus a bounded asynchronous cache.
//  Attribution: design and NVMe field mapping adapted from jianyintang/find-disk-killer (MIT).
//               See THIRD_PARTY_NOTICES.md.
//
import Foundation
import Darwin

public enum DiskHealthAssessment: String, Sendable, Equatable, Codable {
    case verified, partial, temperatureWarning, deviceWarning, spareBelowThreshold, mediaErrors, smartFailure

    public var isWarning: Bool {
        switch self {
        case .verified, .partial: return false
        default: return true
        }
    }
}

public struct DiskHealthSnapshot: Sendable, Equatable, Codable {
    public var bsdName: String
    public var model: String
    public var connection: String?
    public var capacity: UInt64?
    public var isPhysical: Bool?
    public var isInternal: Bool?
    public var isSolidState: Bool?
    public var smartStatus: String?
    public var criticalWarning: UInt64?
    public var percentageUsed: UInt64?
    public var availableSpare: UInt64?
    public var availableSpareThreshold: UInt64?
    public var temperatureCelsius: Double?
    public var hostBytesRead: Double?
    public var hostBytesWritten: Double?
    public var powerOnHours: UInt64?
    public var powerCycles: UInt64?
    public var unsafeShutdowns: UInt64?
    public var mediaErrors: UInt64?
    public var errorLogEntries: UInt64?
    public var sampledAt: Date

    public var assessment: DiskHealthAssessment {
        if smartStatus?.localizedCaseInsensitiveContains("fail") == true { return .smartFailure }
        if let warning = criticalWarning, warning & 0x02 != 0 { return .temperatureWarning }
        if let warning = criticalWarning, warning & 0x1f != 0 { return .deviceWarning }
        if let spare = availableSpare, let threshold = availableSpareThreshold, spare < threshold {
            return .spareBelowThreshold
        }
        if let mediaErrors, mediaErrors > 0 { return .mediaErrors }
        if smartStatus?.caseInsensitiveCompare("Verified") == .orderedSame { return .verified }
        return .partial
    }
}

public enum DiskHealthParser {
    public static func parse(data: Data, expectedBSDName: String, sampledAt: Date = Date()) -> DiskHealthSnapshot? {
        guard isWholeDisk(expectedBSDName),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let d = plist as? [String: Any],
              d["DeviceIdentifier"] as? String == expectedBSDName,
              d["WholeDisk"] as? Bool == true else { return nil }

        let details = d["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any]
        let protocolName = d["BusProtocol"] as? String
        let path = d["DeviceTreePath"] as? String
        let nvme = protocolName?.localizedCaseInsensitiveContains("nvme") == true
            || protocolName?.localizedCaseInsensitiveContains("apple fabric") == true
            || path?.localizedCaseInsensitiveContains("nvme") == true

        func u(_ value: Any?) -> UInt64? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let text = number.stringValue
            guard !text.hasPrefix("-"), !text.contains("."), !text.lowercased().contains("e") else { return nil }
            return UInt64(text)
        }
        func bounded(_ value: Any?, _ maximum: UInt64) -> UInt64? {
            guard let result = u(value), result <= maximum else { return nil }
            return result
        }
        func wideLow(_ key: String) -> UInt64? {
            guard nvme, let low = u(details?["\(key)_0"]), (u(details?["\(key)_1"]) ?? 0) == 0 else { return nil }
            return low
        }
        func hostBytes(_ key: String) -> Double? { wideLow(key).map { Double($0) * 512_000 } }

        let kelvin = nvme ? u(details?["TEMPERATURE"]) : nil
        let temperature = kelvin.flatMap { (250...400).contains($0) ? Double($0) - 273.15 : nil }
        return DiskHealthSnapshot(
            bsdName: expectedBSDName,
            model: (d["MediaName"] as? String) ?? (d["IORegistryEntryName"] as? String) ?? expectedBSDName,
            connection: protocolName,
            capacity: u(d["TotalSize"] ?? d["Size"]),
            isPhysical: physicalFlag(d["VirtualOrPhysical"] as? String),
            isInternal: d["Internal"] as? Bool,
            isSolidState: d["SolidState"] as? Bool,
            smartStatus: d["SMARTStatus"] as? String,
            criticalWarning: nvme ? bounded(details?["CRITICAL_WARNING"], 255) : nil,
            percentageUsed: nvme ? bounded(details?["PERCENTAGE_USED"], 255) : nil,
            availableSpare: nvme ? bounded(details?["AVAILABLE_SPARE"], 100) : nil,
            availableSpareThreshold: nvme ? bounded(details?["AVAILABLE_SPARE_THRESHOLD"], 100) : nil,
            temperatureCelsius: temperature,
            hostBytesRead: hostBytes("DATA_UNITS_READ"),
            hostBytesWritten: hostBytes("DATA_UNITS_WRITTEN"),
            powerOnHours: wideLow("POWER_ON_HOURS"),
            powerCycles: wideLow("POWER_CYCLES"),
            unsafeShutdowns: wideLow("UNSAFE_SHUTDOWNS"),
            mediaErrors: wideLow("MEDIA_ERRORS"),
            errorLogEntries: wideLow("NUM_ERROR_INFO_LOG_ENTRIES"),
            sampledAt: sampledAt
        )
    }

    private static func isWholeDisk(_ value: String) -> Bool {
        value.hasPrefix("disk") && value.count > 4 && value.dropFirst(4).allSatisfy(\.isNumber)
    }

    private static func physicalFlag(_ value: String?) -> Bool? {
        guard let value else { return nil }
        if value.caseInsensitiveCompare("Physical") == .orderedSame { return true }
        if value.caseInsensitiveCompare("Virtual") == .orderedSame { return false }
        return nil
    }
}

/// A private serial worker owns diskutil. The hot sampling thread only reads a lock-protected
/// dictionary and schedules successful devices at most once every ten minutes. A missing or
/// temporarily unavailable device is retried quickly so a newly attached drive does not remain
/// in “detecting” state for the full cache interval.
final class DiskHealthCache: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.leoyuan.LeoMacMonitor.disk-health", qos: .utility)
    private var values: [String: DiskHealthSnapshot] = [:]
    private var lastAttempts: [String: Date] = [:]
    private var refreshing = false
    private let interval: TimeInterval = 600
    private let retryInterval: TimeInterval = 20

    var snapshots: [String: DiskHealthSnapshot] { lock.withLock { values } }

    func refreshIfNeeded(bsdNames: [String]) {
        let names = Array(Set(bsdNames.filter { !$0.isEmpty })).sorted()
        guard !names.isEmpty else { return }
        let dueNames = lock.withLock { () -> [String] in
            guard !refreshing else { return [] }
            let now = Date()
            let due = names.filter { name in
                let cadence = values[name] == nil ? retryInterval : interval
                return now.timeIntervalSince(lastAttempts[name] ?? .distantPast) >= cadence
            }
            guard !due.isEmpty else { return [] }
            refreshing = true
            for name in due { lastAttempts[name] = now }
            return due
        }
        guard !dueNames.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            var fresh: [String: DiskHealthSnapshot] = [:]
            for name in dueNames {
                if let data = Self.runDiskutil(name), let parsed = DiskHealthParser.parse(data: data, expectedBSDName: name) {
                    fresh[name] = parsed
                }
            }
            self.lock.withLock {
                if !fresh.isEmpty { self.values.merge(fresh) { _, new in new } }
                self.refreshing = false
            }
        }
    }

    private static func runDiskutil(_ bsdName: String) -> Data? {
        guard bsdName.hasPrefix("disk"), bsdName.dropFirst(4).allSatisfy(\.isNumber) else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", bsdName]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = DispatchTime.now() + .seconds(5)
        while process.isRunning && DispatchTime.now() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); usleep(100_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return data.count <= 1_048_576 ? data : nil
    }
}
