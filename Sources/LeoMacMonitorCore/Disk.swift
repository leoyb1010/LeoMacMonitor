//
//  File:      Disk.swift
//  Created:   2026-06-08
//  Updated:   2026-07-29
//  Developer: Leo Yuan
//  Overview:  Aggregate and per-device disk throughput, boot-volume capacity, and cached
//             SMART/NVMe health. All hot-path I/O is IOKit; diskutil health probes run on a
//             separate low-frequency worker and never block the one-second monitor tick.
//
import Foundation
import IOKit

public struct DiskDeviceSample: Sendable, Equatable, Codable, Identifiable {
    public var registryID: UInt64
    public var bsdName: String
    public var name: String
    public var isPhysical: Bool
    public var readBytesPerSec: Double
    public var writeBytesPerSec: Double
    public var totalBytes: UInt64
    public var health: DiskHealthSnapshot?

    public var id: UInt64 { registryID }
    public var isInternal: Bool? { health?.isInternal }

    public init(registryID: UInt64, bsdName: String, name: String, isPhysical: Bool,
                readBytesPerSec: Double = 0, writeBytesPerSec: Double = 0,
                totalBytes: UInt64 = 0, health: DiskHealthSnapshot? = nil) {
        self.registryID = registryID
        self.bsdName = bsdName
        self.name = name
        self.isPhysical = isPhysical
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
        self.totalBytes = totalBytes
        self.health = health
    }
}

public struct DiskSample: Sendable, Equatable, Codable {
    public var readBytesPerSec: Double = 0
    public var writeBytesPerSec: Double = 0
    public var totalBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0
    /// Optional preserves decoding of 1.0/1.1 recordings that did not carry device rows.
    public var deviceSamples: [DiskDeviceSample]?

    public init() {}

    public var devices: [DiskDeviceSample] { deviceSamples ?? [] }
    public var physicalDevices: [DiskDeviceSample] { devices.filter(\.isPhysical) }
    public var healthAlerts: [DiskDeviceSample] {
        physicalDevices.filter { $0.health?.assessment.isWarning == true }
    }

    private static let gb = 1024.0 * 1024.0 * 1024.0
    public var totalGB: Double { Double(totalBytes) / Self.gb }
    public var freeGB: Double { Double(freeBytes) / Self.gb }
    public var usedFraction: Double {
        totalBytes > 0 ? Double(totalBytes - min(freeBytes, totalBytes)) / Double(totalBytes) : 0
    }
}

public final class DiskSampler {
    private struct RawDevice {
        let registryID: UInt64
        let bsdName: String
        let name: String
        let className: String
        let read: UInt64
        let write: UInt64
        let capacity: UInt64

        var isPhysical: Bool {
            className == "IOBlockStorageDriver" && Self.isWholeDisk(bsdName)
                && !name.localizedCaseInsensitiveContains("disk image")
        }

        private static func isWholeDisk(_ value: String) -> Bool {
            guard value.hasPrefix("disk"), value.count > 4 else { return false }
            return value.dropFirst(4).allSatisfy(\.isNumber)
        }
    }
    private struct Counters { let read: UInt64; let write: UInt64 }

    private var previous: [UInt64: Counters] = [:]
    private var previousTimeNs: UInt64 = 0
    private let healthCache = DiskHealthCache()

    // Capacity on a slow cadence: querying volumeAvailableCapacityForImportantUsage triggers
    // CacheDelete to revalidate mounted volumes. Free space does not need per-second precision.
    private var cachedCapacity: (total: UInt64, free: UInt64) = (0, 0)
    private var lastCapacitySample: Date = .distantPast
    private let capacityInterval: TimeInterval = 30

    public init() {}

    public func sample() -> DiskSample {
        var result = DiskSample()
        let raw = Self.collectDevices()
        let now = DispatchTime.now().uptimeNanoseconds
        let seconds = previousTimeNs > 0 ? Double(now &- previousTimeNs) / 1_000_000_000 : 0
        let health = healthCache.snapshots

        let devices = raw.map { device -> DiskDeviceSample in
            let old = previous[device.registryID]
            let readRate = old.flatMap { seconds > 0 ? Double(device.read >= $0.read ? device.read - $0.read : 0) / seconds : nil } ?? 0
            let writeRate = old.flatMap { seconds > 0 ? Double(device.write >= $0.write ? device.write - $0.write : 0) / seconds : nil } ?? 0
            let healthSnapshot = health[device.bsdName]
            return DiskDeviceSample(
                registryID: device.registryID,
                bsdName: device.bsdName,
                name: health[device.bsdName]?.model.nonEmpty ?? device.name,
                isPhysical: healthSnapshot?.isPhysical ?? device.isPhysical,
                readBytesPerSec: readRate,
                writeBytesPerSec: writeRate,
                totalBytes: health[device.bsdName]?.capacity ?? device.capacity,
                health: healthSnapshot
            )
        }
        previous = Dictionary(uniqueKeysWithValues: raw.map { ($0.registryID, Counters(read: $0.read, write: $0.write)) })
        previousTimeNs = now

        let physical = devices.filter(\.isPhysical)
        let aggregate = physical.isEmpty ? devices : physical
        result.readBytesPerSec = aggregate.reduce(0) { $0 + $1.readBytesPerSec }
        result.writeBytesPerSec = aggregate.reduce(0) { $0 + $1.writeBytesPerSec }
        result.deviceSamples = devices.sorted {
            if $0.isPhysical != $1.isPhysical { return $0.isPhysical }
            if $0.isInternal != $1.isInternal { return $0.isInternal == true }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        if Date().timeIntervalSince(lastCapacitySample) >= capacityInterval {
            lastCapacitySample = Date()
            cachedCapacity = Self.capacity()
        }
        result.totalBytes = cachedCapacity.total
        result.freeBytes = cachedCapacity.free

        healthCache.refreshIfNeeded(bsdNames: physical.map(\.bsdName))
        return result
    }

    private static func capacity() -> (UInt64, UInt64) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        return (UInt64(values.volumeTotalCapacity ?? 0),
                UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0))
    }

    private static func collectDevices() -> [RawDevice] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var devices: [RawDevice] = []
        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer { entry = IOIteratorNext(iterator) }
            defer { IOObjectRelease(entry) }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as NSDictionary?,
                  let stats = dictionary["Statistics"] as? NSDictionary else { continue }

            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &registryID)
            var classBuffer = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(entry, &classBuffer)

            var bsdName = ""
            var name = "Storage"
            var size: UInt64 = 0
            var media = io_registry_entry_t()
            if IORegistryEntryGetChildEntry(entry, kIOServicePlane, &media) == KERN_SUCCESS {
                defer { IOObjectRelease(media) }
                if let value = IORegistryEntryCreateCFProperty(media, "BSD Name" as CFString,
                                                                kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                    bsdName = value
                }
                if let value = IORegistryEntryCreateCFProperty(media, "Size" as CFString,
                                                                kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                    size = value.uint64Value
                }
                var mediaName = [CChar](repeating: 0, count: 128)
                if IORegistryEntryGetName(media, &mediaName) == KERN_SUCCESS {
                    name = decodeCString(mediaName)
                }
            }

            let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            let write = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            let isPlaceholder = read == 0 && write == 0 && name == "IOBlockStorageDriver"
            if !isPlaceholder {
                devices.append(RawDevice(registryID: registryID, bsdName: bsdName, name: name,
                                         className: decodeCString(classBuffer), read: read,
                                         write: write, capacity: size))
            }
        }
        return devices
    }

    private static func decodeCString(_ value: [CChar]) -> String {
        String(decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
