//
//  File:      SettingsView.swift
//  Created:   2026-06-08
//  Updated:   2026-07-27
//  Developer: Leo Yuan
//  Overview:  Preferences window (Cmd+,). Refresh cadence, temperature unit, menu-bar
//             compact GPU mode, launch-at-login, threshold alerts, and the AI runtime API
//             — persisted in UserDefaults via @AppStorage.
//  Notes:     Keys: "refreshInterval" (s), "temperatureFahrenheit" (Bool),
//             "compactGPUMode" (Bool), "notificationsEnabled" (Bool). Launch-at-login is
//             owned by SMAppService (LoginItem), not UserDefaults. LeoMacMonitorMonitor
//             reads refreshInterval + notificationsEnabled each loop. All update live.
//
import SwiftUI
import AppKit
import WidgetKit

struct SettingsView: View {
    // Each of these is its own SwiftUI root (an NSHostingController popover, a sibling
    // Scene, or the window), so it must observe the scale keys itself — an environment
    // value injected upstream never arrives here. Read only to invalidate on change; the
    // tokens themselves read the store (see UIScale).
    @AppStorage(UIScale.zoomKey) private var uiZoom = 1.0
    @AppStorage(UIScale.densityKey) private var uiDensity = Density.standard.rawValue
    @AppStorage(AppAppearance.key) private var appearanceMode = AppAppearance.system.rawValue
    @AppStorage("refreshInterval") private var refreshInterval = 1.0
    @AppStorage("temperatureFahrenheit") private var fahrenheit = false
    @AppStorage("compactGPUMode") private var compactGPU = false
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("aiRuntimeAPIEnabled") private var aiRuntimeAPIEnabled = false
    @AppStorage("aiRuntimeOllamaPort") private var ollamaPort = 11434
    @AppStorage("aiRuntimeLMStudioPort") private var lmStudioPort = 1234
    @AppStorage("aiRuntimeOmlxPort") private var omlxPort = 8000
    @AppStorage("aiRuntimeOmlxApiKey") private var omlxApiKey = ""
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("showWarningBanner") private var showWarningBanner = true
    @AppStorage("shareThisMac") private var shareThisMac = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var agentToken: String?
    @State private var tokenCopied = false

    var body: some View {
        Form {
            Section {
                Picker("Refresh interval", selection: $refreshInterval) {
                    Text("0.5 s").tag(0.5)
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("3 s").tag(3.0)
                }
                Picker("Temperature unit", selection: $fahrenheit) {
                    Text("Celsius (°C)").tag(false)
                    Text("Fahrenheit (°F)").tag(true)
                }
                Toggle("Compact GPU mode (menu bar)", isOn: $compactGPU)
                Toggle("Show Dock icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, _ in applyDockIconPolicy() }
            } footer: {
                Text("Turn off the Dock icon to run LeoMac Monitor as a pure menu-bar utility — the dashboard still opens from any menu-bar item's dropdown.")
            }

            // Zoom and density must be reachable HERE, not only on ⌘+/⌘−/⌘0: with the Dock icon
            // off the app runs as .accessory and has no menu bar to hang those shortcuts on — and
            // the footer just above actively recommends that mode.
            Section {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { mode in
                        Text(LocalizedStringKey(mode.label)).tag(mode.rawValue)
                    }
                }
                .onChange(of: appearanceMode) { _, value in AppAppearance.apply(value) }

                LabeledContent("Zoom") {
                    HStack(spacing: 8) {
                        Button { uiZoom = Double(UIScale.step(-1)) } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .help("Zoom Out")

                        Slider(value: $uiZoom,
                               in: Double(UIScale.steps.first ?? 0.9)...Double(UIScale.steps.last ?? 1.3),
                               step: 0.05)
                            .frame(minWidth: 150)

                        Text("\(Int((uiZoom * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)

                        Button { uiZoom = Double(UIScale.step(+1)) } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .help("Zoom In")

                        Button { uiZoom = 1.0 } label: {
                            Text("100%")
                        }
                        .help("Actual Size")
                    }
                }
                Picker("Density", selection: $uiDensity) {
                    ForEach(Density.allCases, id: \.rawValue) { d in
                        Text(LocalizedStringKey(d.label)).tag(d.rawValue)
                    }
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Zoom scales text and layout together (also ⌘+ / ⌘− / ⌘0). Density adjusts spacing only, leaving text size alone. LeoMac Monitor uses its own guaranteed scale range for this dense dashboard.")
            }

            MenuBarItemsSettings()

            Section {
                Label("Small, medium and large widgets are enabled", systemImage: "rectangle.3.group")
                    .foregroundStyle(Theme.text)
                Button("Refresh widget data") {
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotPublisher.kind)
                }
            } header: {
                Text("Desktop widgets")
            } footer: {
                Text("Right-click the desktop, choose Edit Widgets, then search for LeoMac Monitor. Widgets show the latest published snapshot; the menu bar remains the second-by-second view.")
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LoginItem.setEnabled(on) }
                Toggle("Show warning banner", isOn: $showWarningBanner)
                Toggle("Alert notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, on in if on { Notifier.requestAuthorization() } }
            } header: {
                Text("Startup & alerts")
            } footer: {
                Text("On GPU thermal throttle or memory pressure, the affected card's border turns amber/red. The in-app warning banner is on by default (turn it off above); optional macOS notifications fire once per event.")
            }

            Section {
                Toggle("Connect to local AI runtimes", isOn: $aiRuntimeAPIEnabled)
                if aiRuntimeAPIEnabled {
                    Group {
                        TextField("Ollama port", value: $ollamaPort, format: .number.grouping(.never))
                        TextField("LM Studio port", value: $lmStudioPort, format: .number.grouping(.never))
                        TextField("oMLX port", value: $omlxPort, format: .number.grouping(.never))
                        TextField("oMLX API Key (optional)", text: $omlxApiKey)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Text("Local AI runtime API (opt-in)")
            } footer: {
                Text("Reads the loaded model, processor split, and tokens/sec from AI runtimes on 127.0.0.1. Nothing leaves your Mac.")
            }

            Section {
                Toggle("Share this Mac to Fleet", isOn: $shareThisMac)
                    .onChange(of: shareThisMac) { _, on in
                        if on {
                            MacAgentController.shared.startIfConfigured()
                            Task { try? await Task.sleep(for: .seconds(1)); agentToken = MacAgentController.shared.pairingToken }
                        } else {
                            MacAgentController.shared.stop()
                            agentToken = nil
                        }
                    }
                if shareThisMac {
                    if let token = agentToken {
                        LabeledContent("Pairing token") {
                            HStack(spacing: Space.row) {
                                Text(token)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(token, forType: .string)
                                    tokenCopied = true
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(1.4))
                                        tokenCopied = false
                                    }
                                } label: {
                                    Image(systemName: tokenCopied ? "checkmark" : "doc.on.doc")
                                        .foregroundStyle(tokenCopied ? Palette.State.calm.color : Theme.text)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                    .buttonStyle(.borderless).help("Copy token")
                            }
                        }
                    } else {
                        Text("Starting…").font(Theme.font(.caption)).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Fleet")
            } footer: {
                Text("Let other Macs on your network monitor this Mac, encrypted. Enter this token in their LeoMac Monitor (Fleet sidebar → this Mac → Pair).")
            }
        }
        .formStyle(.grouped)
        .frame(width: Layout.Surface.settingsWidth, height: aiRuntimeAPIEnabled ? Layout.Surface.settingsHeightExpanded : Layout.Surface.settingsHeight)
        .animation(Motion.disclosure, value: aiRuntimeAPIEnabled)
        .animation(Motion.disclosure, value: shareThisMac)
        .animation(Motion.state, value: tokenCopied)
        .onAppear {
            if shareThisMac { agentToken = MacAgentController.shared.pairingToken }
        }
    }
}
