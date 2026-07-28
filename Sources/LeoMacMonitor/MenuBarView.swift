//
//  File:      MenuBarView.swift
//  Created:   2026-06-08
//  Updated:   2026-06-24
//  Developer: Leo Yuan
//  Overview:  Compact menu-bar popover content: the essentials at a glance (E/P, mem,
//             GPU, bandwidth, power, die temp), trend sparklines, top processes, plus
//             "Open Dashboard" (brings the full window forward) / Settings / Quit.
//  Notes:     Shares the same LeoMacMonitorMonitor as the full window, so both stay in sync.
//             "compactGPUMode" (UserDefaults) swaps the full readout for a single
//             GPU-focused line: GPU% / GPU W / GPU GB/s / die °C.
//             "Open Dashboard" raises the window identified by "leomacmonitor-main".
//
import SwiftUI
import AppKit
import LeoMacMonitorCore

struct MenuBarView: View {
    // Each of these is its own SwiftUI root (an NSHostingController popover, a sibling
    // Scene, or the window), so it must observe the scale keys itself — an environment
    // value injected upstream never arrives here. Read only to invalidate on change; the
    // tokens themselves read the store (see UIScale).
    @AppStorage(UIScale.zoomKey) private var uiZoom = 1.0
    @AppStorage(UIScale.densityKey) private var uiDensity = Density.standard.rawValue
    let monitor: LeoMacMonitorMonitor
    @AppStorage("temperatureFahrenheit") private var fahrenheit = false
    @AppStorage("compactGPUMode") private var compactGPU = false

    var body: some View {
        let snapshot = monitor.snapshot
        VStack(alignment: .leading, spacing: Space.hair) {
            if compactGPU {
                compactGPURow(snapshot)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.hair) {
                        fullReadout(snapshot)
                    }
                }
                .frame(maxHeight: UIScale.scaled(520))
            }

            Divider()
                .padding(.bottom, Space.hair)
            // One full-width primary action, then two equal-width secondary buttons — all
            // share PopoverButtonStyle so they match the cards (panel fill, hairline border,
            // mono label) at a uniform height. "Check for Updates…" lives in Settings.
            VStack(spacing: Space.row) {
                Button {
                    openMainDashboard()
                } label: {
                    Label("Open Dashboard", systemImage: "macwindow")
                }
                .buttonStyle(PopoverButtonStyle(prominent: true))

                HStack(spacing: Space.row) {
                    Button("Settings") { openAppSettings() }
                        .buttonStyle(PopoverButtonStyle())
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(PopoverButtonStyle())
                }
            }
        }
        .padding(Space.section)
        .frame(width: compactGPU ? Layout.Surface.combinedWidthCompactGPU : Layout.Surface.combinedWidth)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
    }

    /// Single-line GPU-focused readout: GPU% / GPU W / GPU bandwidth / die °C.
    @ViewBuilder
    private func compactGPURow(_ s: SystemSnapshot) -> some View {
        HStack(spacing: Space.card) {
            Text("GPU")
                .font(MenuBarTheme.font(.body, .strong))
                .foregroundStyle(Theme.accent)
            compactValue(String(format: "%.0f%%", s.gpu.usagePercent), color: Theme.heat(s.gpu.usage))
            compactSeparator
            compactValue(String(format: "%.1f W", s.power.gpuWatts))
            compactSeparator
            compactValue(String(format: "%.0f GB/s", s.bandwidth.gpuGBs))
            compactSeparator
            compactValue(formatTemperature(s.temperature.cpuCelsius, fahrenheit: fahrenheit),
                         color: monitor.gpuThrottling ? Theme.heat(1) : Theme.text)
            if monitor.gpuThrottling {
                Image(systemName: "flame.fill")
                    .font(.system(size: Icon.large))
                    .foregroundStyle(Theme.heat(1))
                    .help("GPU thermal throttling")
            }
        }
    }

    private func compactValue(_ text: String, color: Color = Theme.text) -> some View {
        Text(text)
            .font(MenuBarTheme.font(.emphasis))
            .foregroundStyle(color)
    }

    private var compactSeparator: some View {
        Text("·").font(MenuBarTheme.font(.emphasis)).foregroundStyle(Theme.faint)
    }

    /// "Workload" label, qualified with "(est.)" when the bandwidth-bound verdict rests on an
    /// estimated reading (BandwidthSampler's PMP-histogram fallback — see BandwidthSample.isEstimated)
    /// rather than a real per-requestor byte-delta measurement, so the label doesn't overstate
    /// precision it doesn't have.
    private func workloadLabel(_ snapshot: SystemSnapshot) -> String {
        let label = monitor.bottleneck.label
        guard monitor.bottleneck == .bandwidthBound, snapshot.bandwidth.isEstimated else { return label }
        return label + " (est.)"
    }

    /// The standard multi-line readout (E/P, memory, GPU, ANE, bandwidth, power, temps).
    @ViewBuilder
    private func fullReadout(_ snapshot: SystemSnapshot) -> some View {
        HStack(spacing: Space.row) {
            Text("LeoMac监控器")
                .font(MenuBarTheme.font(.headline, .strong))
                .foregroundStyle(Theme.accent)
            Spacer()
            Circle().fill(Palette.State.calm.color)
                .frame(width: Layout.Dot.status, height: Layout.Dot.status)
            Text("Live").font(MenuBarTheme.font(.caption, .strong)).foregroundStyle(Theme.dim)
        }

        MenuKV(label: "Workload", value: workloadLabel(snapshot), color: monitor.bottleneck.color)

        Divider()
        MenuKV(label: "CPU", value: String(format: "P %.0f%% · E %.0f%%",
                                      snapshot.cpu.pUsagePercent, snapshot.cpu.eUsagePercent))
        MenuKV(label: "GPU", value: String(format: "%.0f%% · %.1f W", snapshot.gpu.usagePercent, snapshot.power.gpuWatts))
        MenuKV(label: "Memory", value: String(format: "%.1f / %.0f GB · %.0f%% pressure",
                                         snapshot.memory.usedGB, snapshot.memory.totalGB,
                                         snapshot.memory.pressurePercent))
        MenuKV(label: "Network", value: "↓ \(formatRate(snapshot.network.downloadBytesPerSec)) · ↑ \(formatRate(snapshot.network.uploadBytesPerSec))")
        MenuKV(label: "Disk", value: "R \(formatRate(snapshot.disk.readBytesPerSec)) · W \(formatRate(snapshot.disk.writeBytesPerSec))")
        MenuKV(label: "ANE", value: String(format: "%.1f W", snapshot.power.aneWatts))
        MenuKV(label: "Media", value: String(format: "%.1f GB/s", snapshot.bandwidth.mediaGBs))
        MenuKV(label: "Mem BW", value: String(format: "%.0f GB/s", snapshot.bandwidth.totalGBs))
        MenuKV(label: "SoC power", value: String(format: "%.1f W", snapshot.power.socWatts))
        MenuKV(label: "CPU temp", value: formatTemperature(snapshot.temperature.cpuCelsius, fahrenheit: fahrenheit))
        if snapshot.temperature.hasBattery {
            MenuKV(label: "Battery", value: formatTemperature(snapshot.temperature.batteryCelsius, fahrenheit: fahrenheit))
        }

        Divider()
        MenuKV(label: "AI runtime", value: snapshot.aiRuntimeLabel)
        MenuKV(label: "Fits now", value: snapshot.memoryBudget.fitsNow.first?.label ?? "—")

        Divider()
        metricGraphs(snapshot)

        Divider()
        topProcesses(snapshot)
    }

    /// Six trend graphs — same metrics, colors AND normalization as the menu-bar glyph.
    /// Each is plotted on a FIXED Y domain matching its bar (utilization 0...1, ANE/Media
    /// vs their tracked peaks, Mem BW vs the chip ceiling), so a small or flat signal reads
    /// small. Auto-scaling would stretch any series to fill the row — looks exaggerated.
    @ViewBuilder
    private func metricGraphs(_ s: SystemSnapshot) -> some View {
        let c = MenuBarIcon.barColors.map(Color.init(nsColor:))
        Text("TRENDS")
            .font(MenuBarTheme.font(.sectionMinor))
            .foregroundStyle(Theme.faint)
        graphRow("CPU", c[0], monitor.history.pCPU, String(format: "%.0f%%", s.cpu.pUsagePercent),
                 axis: .fraction)
        graphRow("GPU", c[1], monitor.history.gpu, String(format: "%.0f%%", s.gpu.usagePercent),
                 axis: .fraction)
        graphRow("ANE", c[2], monitor.history.ane, String(format: "%.1f W", s.power.aneWatts),
                 axis: .ceiling(max(monitor.anePeakWatts, 0.1)))
        graphRow("MED", c[3], monitor.history.media, String(format: "%.1f GB/s", s.bandwidth.mediaGBs),
                 axis: .ceiling(max(monitor.mediaPeakGBs, 0.5)))
        graphRow("MEM", c[4], monitor.history.memFraction, String(format: "%.0f%%", s.memory.usedPercent),
                 axis: .fraction)
        graphRow("MBW", c[5], monitor.history.bandwidth, String(format: "%.0f GB/s", s.bandwidth.totalGBs),
                 axis: .ceiling(max(monitor.bandwidthPeakGBs, 1)))
    }

    private func graphRow(_ label: String, _ color: Color, _ values: [Double], _ value: String,
                          axis: ChartAxis = .auto) -> some View {
        HStack(spacing: Space.row) {
            Text(label)
                .font(MenuBarTheme.font(.caption, .strong))
                .foregroundStyle(color)
                .frame(width: Layout.Column.trendLabel, alignment: .leading)
            Sparkline(values, color: color, role: .inline(height: Layout.Meter.sparklineListRow, axis: axis))
            Text(value)
                .font(MenuBarTheme.font(.detail, .strong))
                .foregroundStyle(Theme.dim)
                .frame(width: Layout.Column.trendValue, alignment: .trailing)
        }
    }

    /// Top three processes by CPU — iStat-style at-a-glance "what's busy".
    @ViewBuilder
    private func topProcesses(_ s: SystemSnapshot) -> some View {
        let top = s.processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(3)
        Text("TOP PROCESSES")
            .font(MenuBarTheme.font(.sectionMinor))
            .foregroundStyle(Theme.faint)
        if top.isEmpty {
            Text("—").font(MenuBarTheme.font(.body)).foregroundStyle(Theme.dim)
        } else {
            ForEach(Array(top)) { p in
                HStack(spacing: Space.row) {
                    Text(p.name)
                        .font(MenuBarTheme.font(.body))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(String(format: "%.0f%%", p.cpuPercent))
                        .font(MenuBarTheme.font(.body, .strong))
                        .foregroundStyle(Theme.heat(min(1, p.cpuPercent / 100)))
                }
            }
        }
    }
}
