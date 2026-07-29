import XCTest
@testable import LeoMacMonitorCore

final class DiskIntelligenceTests: XCTestCase {
    private func plist(_ dictionary: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }

    func testNVMeHealthParserUsesStrictDeviceIdentityAndUnits() throws {
        let data = try plist([
            "DeviceIdentifier": "disk0", "WholeDisk": true,
            "MediaName": "APPLE SSD", "BusProtocol": "Apple Fabric",
            "Internal": true, "SolidState": true, "SMARTStatus": "Verified",
            "TotalSize": NSNumber(value: UInt64(1_000_000_000_000)),
            "SMARTDeviceSpecificKeysMayVaryNotGuaranteed": [
                "TEMPERATURE": 308, "PERCENTAGE_USED": 2,
                "AVAILABLE_SPARE": 100, "AVAILABLE_SPARE_THRESHOLD": 99,
                "DATA_UNITS_READ_0": 10, "DATA_UNITS_READ_1": 0,
                "DATA_UNITS_WRITTEN_0": 20, "DATA_UNITS_WRITTEN_1": 0,
                "POWER_ON_HOURS_0": 100, "POWER_ON_HOURS_1": 0,
                "UNSAFE_SHUTDOWNS_0": 3, "UNSAFE_SHUTDOWNS_1": 0,
                "MEDIA_ERRORS_0": 0, "MEDIA_ERRORS_1": 0,
            ],
        ])
        let health = try XCTUnwrap(DiskHealthParser.parse(data: data, expectedBSDName: "disk0"))
        XCTAssertEqual(health.model, "APPLE SSD")
        XCTAssertEqual(health.temperatureCelsius ?? 0, 34.85, accuracy: 0.01)
        XCTAssertEqual(health.hostBytesRead, 5_120_000)
        XCTAssertEqual(health.hostBytesWritten, 10_240_000)
        XCTAssertEqual(health.percentageUsed, 2)
        XCTAssertEqual(health.assessment, .verified)
        XCTAssertNil(DiskHealthParser.parse(data: data, expectedBSDName: "disk1"))
    }

    func testHealthParserRejectsPartitionAndFlagsMediaErrors() throws {
        let partition = try plist(["DeviceIdentifier": "disk0s1", "WholeDisk": false])
        XCTAssertNil(DiskHealthParser.parse(data: partition, expectedBSDName: "disk0s1"))

        let broken = try plist([
            "DeviceIdentifier": "disk8", "WholeDisk": true, "SMARTStatus": "Verified",
            "BusProtocol": "NVMe",
            "SMARTDeviceSpecificKeysMayVaryNotGuaranteed": [
                "MEDIA_ERRORS_0": 4, "MEDIA_ERRORS_1": 0,
            ],
        ])
        XCTAssertEqual(DiskHealthParser.parse(data: broken, expectedBSDName: "disk8")?.assessment,
                       .mediaErrors)
    }

    func testPhysicalFlagOnlyTrustsExplicitDiskutilValues() throws {
        func parse(_ flag: String) throws -> DiskHealthSnapshot {
            let data = try plist([
                "DeviceIdentifier": "disk0", "WholeDisk": true,
                "VirtualOrPhysical": flag,
            ])
            return try XCTUnwrap(DiskHealthParser.parse(data: data, expectedBSDName: "disk0"))
        }
        XCTAssertEqual(try parse("Physical").isPhysical, true)
        XCTAssertEqual(try parse("Virtual").isPhysical, false)
        XCTAssertNil(try parse("Unknown").isPhysical)
    }

    func testOldRecordingShapesStillDecode() throws {
        let rowJSON = #"{"pid":42,"name":"old","cpuPercent":1,"memoryBytes":2,"path":"","args":null}"#
        let row = try JSONDecoder().decode(ProcessRow.self, from: Data(rowJSON.utf8))
        XCTAssertNil(row.diskReadBytesPerSec)
        XCTAssertNil(row.startAbstime)

        let diskJSON = #"{"readBytesPerSec":1,"writeBytesPerSec":2,"totalBytes":3,"freeBytes":1}"#
        let disk = try JSONDecoder().decode(DiskSample.self, from: Data(diskJSON.utf8))
        XCTAssertTrue(disk.devices.isEmpty)
    }

    func testTopDiskProcessesUseRatesAndIgnoreUnavailableRows() {
        var snapshot = SystemSnapshot()
        snapshot.processes = [
            ProcessRow(pid: 1, name: "none", cpuPercent: 0, memoryBytes: 0),
            ProcessRow(pid: 2, name: "reader", cpuPercent: 0, memoryBytes: 0,
                       diskReadBytesPerSec: 900, diskWriteBytesPerSec: 10),
            ProcessRow(pid: 3, name: "writer", cpuPercent: 0, memoryBytes: 0,
                       diskReadBytesPerSec: 20, diskWriteBytesPerSec: 1_200),
        ]
        XCTAssertEqual(snapshot.topDiskReader?.name, "reader")
        XCTAssertEqual(snapshot.topDiskWriter?.name, "writer")
    }

    func testDiskHealthErrorBecomesCriticalSystemWarning() {
        let health = DiskHealthSnapshot(
            bsdName: "disk0", model: "Leo SSD", connection: "NVMe", capacity: nil,
            isPhysical: true, isInternal: true, isSolidState: true, smartStatus: "Verified",
            criticalWarning: nil, percentageUsed: nil, availableSpare: nil,
            availableSpareThreshold: nil, temperatureCelsius: nil, hostBytesRead: nil,
            hostBytesWritten: nil, powerOnHours: nil, powerCycles: nil, unsafeShutdowns: nil,
            mediaErrors: 2, errorLogEntries: nil, sampledAt: Date()
        )
        XCTAssertEqual(health.assessment, .mediaErrors)

        var disk = DiskSample()
        disk.deviceSamples = [
            DiskDeviceSample(registryID: 1, bsdName: "disk0", name: "Leo SSD",
                             isPhysical: true, health: health),
        ]
        var snapshot = SystemSnapshot()
        snapshot.disk = disk
        XCTAssertTrue(snapshot.warnings.contains {
            $0.level == .critical && $0.message.contains("介质错误")
        })
    }
}
