//
//  File:      LeoMacMonitorApp.swift
//  Created:   2026-06-08
//  Updated:   2026-06-30
//  Developer: Leo Yuan
//  Overview:  App entry point. Declares the full dashboard Window and Settings, backed by one
//             shared LeoMacMonitorMonitor. The menu-bar items are NOT scenes here — they're AppKit
//             NSStatusItems owned by MetricBarController, so each stays individually toggleable.
//  Notes:     Runs as an SPM executable (xcrun swift run LeoMacMonitor); activation
//             policy is set to .regular at runtime so the window + Dock icon appear
//             without a bundled Info.plist. A proper .app bundle comes in packaging.
//             Icon is loaded via loadAppIcon() — never SwiftPM's Bundle.module, whose
//             generated accessor fatalErrors when the flat resource bundle is not a
//             valid bundle (crashes on macOS 27's stricter bundle validation).
//
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LeoMacMonitorCore

extension Notification.Name {
    /// Posted by menu-bar dropdowns to open Settings; handled by SettingsOpenerBridge.
    static let openLeoMacMonitorSettings = Notification.Name("com.leoyuan.LeoMacMonitor.openSettings")
    /// Posted by the "Open Recording…" command (carries the .ssrec URL); handled by DashboardContainer.
    static let openLeoMacMonitorRecording = Notification.Name("com.leoyuan.LeoMacMonitor.openRecording")
}

/// Invisible view in the dashboard scene that routes the menu-bar dropdowns' Settings request to
/// SwiftUI's `openSettings`. The dropdowns are AppKit NSPopovers where `@Environment(\.openSettings)`
/// isn't available and `showSettingsWindow:` doesn't surface the window — but a scene-attached view
/// like this one can call openSettings() directly, which does.
private struct SettingsOpenerBridge: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .openLeoMacMonitorSettings)) { _ in
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
    }
}

/// Keeps the app alive when the dashboard window is closed — it lives on in the menu bar — instead
/// of quitting the whole app (the macOS default for the last-window-closed). Reopens the dashboard
/// on a Dock-icon click. This is the right behavior for a menu-bar-resident monitor (issue #13).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.apply()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { MainActor.assumeIsolated { openMainDashboard() } }
        return true
    }
}

/// Sets the Dock-icon presence from the user's "Show Dock icon" setting (default on). Off =
/// `.accessory` — a pure menu-bar utility with no Dock icon (the dashboard still opens from any
/// menu-bar dropdown). A single stable policy, not a per-window toggle, so the icon never flickers.
@MainActor func applyDockIconPolicy() {
    let showDock = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
    NSApplication.shared.setActivationPolicy(showDock ? .regular : .accessory)
}

@main
struct LeoMacMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor = LeoMacMonitorMonitor()
    // Fleet — machines are discovered automatically via mDNS ("_leomacmon._tcp"); no hardcoded
    // endpoints. FleetMonitor owns discovery + polling behind the MachineMetrics boundary.
    @State private var fleet = FleetMonitor()
    // Which device the single window's detail pane shows. Optional to satisfy List(selection:).
    @State private var deviceSelection: DeviceSelection? = .thisMac

    // The combined "SS" menu-bar item and all per-metric items are AppKit NSStatusItems managed
    // by MetricBarController (driven from the monitor loop), so each can be toggled — including
    // hiding the combined SS on notch-limited menu bars. (SwiftUI's MenuBarExtra can't: its
    // isInserted: init has no custom-label form for the live glyph, and toggling it loops the
    // main menu.) The monitor is started from the main window's onAppear at launch.
    init() {
        UIScale.registerDefaults()
        AppAppearance.registerDefaults()
    }

    var body: some Scene {
        mainWindow
            // Zoom lives in the View menu as well as on ⌘+/⌘−/⌘0, because the shortcut alone is
            // not reachable: with "Show Dock icon" off the app runs as .accessory and has no menu
            // bar at all — and Settings actively recommends that mode. Settings carries the same
            // control (design-system D1, requirement 1).
            .commands {
                CommandGroup(after: .toolbar) {
                    Button("Zoom In")  { UIScale.step(+1) }.keyboardShortcut("+", modifiers: .command)
                    // "+" is really ⌘⇧= on a US layout, so bind the unshifted key too — that is
                    // what people actually press, and what Safari/Xcode/Finder accept. Hidden so
                    // the View menu shows one Zoom In, not two.
                    Button("Zoom In")  { UIScale.step(+1) }
                        .keyboardShortcut("=", modifiers: .command).hidden()
                    Button("Zoom Out") { UIScale.step(-1) }.keyboardShortcut("-", modifiers: .command)
                    Button("Actual Size") { UIScale.reset() }.keyboardShortcut("0", modifiers: .command)
                    Divider()
                }
            }
        Settings { SettingsView() }
    }

    /// The single app window: a Devices sidebar (This Mac + discovered fleet agents) driving a
    /// detail dashboard. Replaces the old separate dashboard + ⌘⇧F Fleet windows.
    private var mainWindow: some Scene {
        Window("LeoMac监控器", id: "leomacmonitor-main") {
            LeoMacMonitorRootView(monitor: monitor, fleet: fleet, selection: $deviceSelection)
                .background(SettingsOpenerBridge())   // routes dropdown "Settings" → openSettings()
                .onOpenURL { url in
                    if url.scheme == "leomacmonitor" { openMainDashboard() }
                }
                .onAppear {
                    applyDockIconPolicy()
                    if let icon = Self.loadAppIcon() {
                        NSApplication.shared.applicationIconImage = icon
                    }
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    // Closing the window hides it (we stay in the menu bar) rather than destroying
                    // it, so openMainDashboard() can bring the same window back. Pairs with the
                    // AppDelegate's terminate-after-last-window = false.
                    NSApplication.shared.windows
                        .first { $0.identifier?.rawValue == "leomacmonitor-main" }?
                        .isReleasedWhenClosed = false
                    monitor.start()
                    // This Mac is always the first Fleet-overview tile: feed the live monitor to the
                    // fleet aggregator so it samples this Mac on the same cadence as remote agents.
                    fleet.localProvider = {
                        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
                        let v = ProcessInfo.processInfo.operatingSystemVersion
                        let os = "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
                        return monitor.machineMetricsMac(machineId: "local", hostname: host,
                                                         osName: os, agentVersion: "local")
                    }
                    // Start discovery immediately: mDNS takes a moment, so machines are already
                    // listed by the time the user opens the Devices sidebar.
                    fleet.start()
                    // Share this Mac to the fleet when enabled (Settings toggle, or LEOMAC_SHARE=1 for dev).
                    MacAgentController.shared.configure(monitor: monitor)
                    if UserDefaults.standard.bool(forKey: "shareThisMac")
                        || ProcessInfo.processInfo.environment["LEOMAC_SHARE"] == "1" {
                        MacAgentController.shared.startIfConfigured()
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 940, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdaterController.shared.checkForUpdates() }
                    .disabled(!UpdaterController.shared.canCheck)
            }
            CommandGroup(after: .newItem) {
                Button("Open Recording…") { Self.openRecordingPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    /// File → Open Recording…: pick a .ssrec and hand it to DashboardContainer via notification.
    private static func openRecordingPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let ssrec = UTType(filenameExtension: "ssrec") { panel.allowedContentTypes = [ssrec] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        NotificationCenter.default.post(name: .openLeoMacMonitorRecording, object: nil, userInfo: ["url": url])
    }


    /// Resolves the app icon without ever touching SwiftPM's `Bundle.module`.
    /// `Bundle.module`'s generated accessor calls `fatalError` when its resource
    /// bundle is not recognized as a bundle; the SwiftPM bundle is a flat folder
    /// with no Info.plist, which macOS 27's stricter validation rejects -> crash.
    private static func loadAppIcon() -> NSImage? {
        // Packaged .app: AppIcon.icns sits directly in Contents/Resources.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return nil
    }
}
