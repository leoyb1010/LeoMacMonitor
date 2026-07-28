//
//  File:      PeripheralBatteryTests.swift
//  Created:   2026-06-22
//  Updated:   2026-06-22
//  Developer: Leo Yuan
//  Overview:  Pins PeripheralBatterySampler.kind() — the pure HID-usage / class-name / Product
//             classifier that labels accessory batteries. Trackpads use a vendor HID usage page,
//             so the class-name fallback is what catches them; that path is easy to break.
//
import XCTest
@testable import LeoMacMonitorCore

final class PeripheralBatteryTests: XCTestCase {

    func testKindByHIDUsage() {
        // Generic Desktop page (1): usage 2 = mouse, usage 6 = keyboard.
        XCTAssertEqual(PeripheralBatterySampler.kind(usage: 2, usagePage: 1, className: "", product: ""), .mouse)
        XCTAssertEqual(PeripheralBatterySampler.kind(usage: 6, usagePage: 1, className: "", product: ""), .keyboard)
    }

    func testKindByClassName() {
        // Trackpads report a vendor usage page (0xFF00), so the class name must catch them.
        XCTAssertEqual(PeripheralBatterySampler.kind(usage: 11, usagePage: 65280,
                                                     className: "BNBTrackpadDevice", product: ""), .trackpad)
        XCTAssertEqual(PeripheralBatterySampler.kind(usage: 0, usagePage: 0,
                                                     className: "AppleBluetoothHIDKeyboard", product: ""), .keyboard)
    }

    func testKindByProduct() {
        XCTAssertEqual(PeripheralBatterySampler.kind(usage: 0, usagePage: 0, className: "", product: "Magic Mouse"), .mouse)
        XCTAssertEqual(PeripheralBatterySampler.kind(usage: 0, usagePage: 0, className: "", product: "AirPods Pro"), .headphones)
    }

    func testKindUnknownFallsBackToOther() {
        XCTAssertEqual(PeripheralBatterySampler.kind(usage: 0, usagePage: 0, className: "SomeDongle", product: ""), .other)
    }

    func testDefaultName() {
        XCTAssertEqual(PeripheralKind.mouse.defaultName, "Mouse")
        XCTAssertEqual(PeripheralKind.trackpad.defaultName, "Trackpad")
    }

    // MARK: - system_profiler parsing (AirPods tier)

    func testParseAirPodsFromSystemProfiler() {
        let sp = [
            "    Bluetooth:",
            "      Connected:",
            "          AirPods Pro:",
            "              Address: 74:65:0C:9B:E7:86",
            "              Case Battery Level: 21%",
            "              Left Battery Level: 9%",
            "              Right Battery Level: 99%",
            "              Minor Type: Headphones",
            "          Magic Mouse:",                 // connected but no battery line → skipped
            "              Address: 3C:A6:F6:C3:33:F6",
            "              Minor Type: Mouse",
            "      Not Connected:",
            "          Old Thing:",                   // not connected → ignored
            "              Battery Level: 50%",
        ].joined(separator: "\n")

        let devices = PeripheralBatterySampler.parseBluetoothBatteries(sp)
        XCTAssertEqual(devices.count, 1)
        let a = devices.first
        XCTAssertEqual(a?.name, "AirPods Pro")
        XCTAssertEqual(a?.kind, .headphones)
        XCTAssertEqual(a?.leftPercent, 9)
        XCTAssertEqual(a?.rightPercent, 99)
        XCTAssertEqual(a?.casePercent, 21)
        XCTAssertEqual(a?.percent, 9)                 // headline = lower bud
        XCTAssertEqual(a?.address, "74:65:0C:9B:E7:86")
        XCTAssertEqual(a?.detail, "L 9% · R 99% · Case 21%")
    }

    func testBatteryValueParsing() {
        XCTAssertEqual(PeripheralBatterySampler.batteryValue("Left Battery Level: 9%", "Left Battery Level"), 9)
        XCTAssertEqual(PeripheralBatterySampler.batteryValue("Battery Level: 100%", "Battery Level"), 100)
        XCTAssertNil(PeripheralBatterySampler.batteryValue("Minor Type: Mouse", "Battery Level"))
    }

    func testNormalizedAddressMatchesAcrossFormats() {
        XCTAssertEqual(PeripheralBatterySampler.normalizedAddress("3C:A6:F6:C3:33:F6"),
                       PeripheralBatterySampler.normalizedAddress("3c-a6-f6-c3-33-f6"))
    }
}
