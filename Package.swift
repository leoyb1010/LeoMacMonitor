// swift-tools-version: 6.1
//
//  File:      Package.swift
//  Created:   2026-06-08
//  Updated:   2026-06-14
//  Developer: Leo Yuan
//  Overview:  SwiftPM manifest for LeoMacMonitor. Builds CIOReport (private-API C
//             shim), LeoMacMonitorCore (sudoless data layer, no UI), leomac-cli
//             (verification), and the LeoMacMonitor SwiftUI app.
//  Notes:     IOReport has no SDK stub, so the final binary links with
//             -undefined dynamic_lookup; symbols resolve at runtime via dyld.
//
import PackageDescription

let package = Package(
    name: "LeoMacMonitor",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LeoMacMonitorCore", targets: ["LeoMacMonitorCore"]),
        .executable(name: "leomac-cli", targets: ["leomac-cli"]),
        .executable(name: "leomac-agent-mac", targets: ["leomac-agent-mac"]),
        .executable(name: "LeoMacMonitor", targets: ["LeoMacMonitor"]),
        .executable(name: "LeoMacMonitorWidget", targets: ["LeoMacMonitorWidget"]),
    ],
    dependencies: [
        // Auto-update for the self-distributed (non-App-Store) app.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Private IOReport declarations exposed to Swift.
        .target(name: "CIOReport"),

        // Sudoless data layer. Must NOT import SwiftUI.
        .target(
            name: "LeoMacMonitorCore",
            dependencies: ["CIOReport"]
        ),

        // Terminal verification tool for the data layer.
        .executableTarget(
            name: "leomac-cli",
            dependencies: ["LeoMacMonitorCore"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"]),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
            ]
        ),

        // Headless fleet agent for this Mac (launchd). Samples via Core's SystemSampler and serves
        // FleetAgentServer — same data + transport as the app's "Share this Mac" mode, no GUI.
        .executableTarget(
            name: "leomac-agent-mac",
            dependencies: ["LeoMacMonitorCore"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"]),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
            ]
        ),

        // SwiftUI app (menu bar + full window). Runs via `xcrun swift run LeoMacMonitor`.
        .executableTarget(
            name: "LeoMacMonitor",
            dependencies: ["LeoMacMonitorCore", "LeoMacMonitorWidgetShared",
                           .product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"]),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
            ]
        ),

        // Small Codable boundary shared by the host and WidgetKit extension. It deliberately does
        // not depend on LeoMacMonitorCore: the widget must never link the private IOReport sampler.
        .target(name: "LeoMacMonitorWidgetShared"),

        .executableTarget(
            name: "LeoMacMonitorWidget",
            dependencies: ["LeoMacMonitorWidgetShared"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("WidgetKit"),
            ]
        ),

        // Unit tests for the data layer. Needs the same dynamic_lookup flag because it
        // links LeoMacMonitorCore, which references IOReport symbols resolved at runtime.
        .testTarget(
            name: "LeoMacMonitorCoreTests",
            dependencies: ["LeoMacMonitorCore"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"]),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
