import SwiftUI
import AppKit
import LeoMacMonitorCore

/// The combined menu-bar cockpit. This surface deliberately owns a fixed 100% layout because it
/// opens on the normal display; the dashboard's 90–250% auxiliary-screen zoom must never reach it.
struct MenuBarView: View {
    let monitor: LeoMacMonitorMonitor
    @AppStorage("temperatureFahrenheit") private var fahrenheit = false
    @AppStorage("compactGPUMode") private var compactGPU = false

    private let panelWidth: CGFloat = 430
    private let gap: CGFloat = 8

    var body: some View {
        let snapshot = monitor.snapshot
        VStack(alignment: .leading, spacing: 10) {
            if compactGPU {
                compactGPURow(snapshot)
            } else {
                cockpit(snapshot)
            }

            Divider()
            actions
        }
        .padding(14)
        .frame(width: compactGPU ? 360 : panelWidth)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
    }

    @ViewBuilder
    private func cockpit(_ s: SystemSnapshot) -> some View {
        header(s)

        Grid(horizontalSpacing: gap, verticalSpacing: gap) {
            GridRow {
                metricTile(
                    "CPU", Palette.pCPU.color,
                    value: String(format: "P %.0f%% · E %.0f%%", s.cpu.pUsagePercent, s.cpu.eUsagePercent),
                    detail: String(format: "%.0f / %.0f MHz", s.cpu.pFreqMHz, s.cpu.eFreqMHz),
                    traces: [Trace(monitor.history.pCPU, Palette.pCPU.color),
                             Trace(monitor.history.eCPU, Palette.eCPU.color)],
                    axis: .fraction
                )
                metricTile(
                    "GPU", Palette.gpu.color,
                    value: String(format: "%.0f%%", s.gpu.usagePercent),
                    detail: String(format: "%.1f W · %.0f MHz", s.power.gpuWatts, s.gpu.freqMHz),
                    traces: [Trace(monitor.history.gpu, Palette.gpu.color)],
                    axis: .fraction
                )
                metricTile(
                    "MEMORY", Palette.memory.color,
                    value: String(format: "%.1f / %.0f GB", s.memory.usedGB, s.memory.totalGB),
                    detail: String(format: "%.0f%% used · %.0f%% pressure", s.memory.usedPercent,
                                   s.memory.pressurePercent),
                    traces: [Trace(monitor.history.memFraction, Palette.memory.color)],
                    axis: .fraction
                )
            }

            GridRow {
                metricTile(
                    "BANDWIDTH", Palette.bandwidth.color,
                    value: String(format: "%.0f GB/s", s.bandwidth.totalGBs),
                    detail: String(format: "CPU %.0f · GPU %.0f", s.bandwidth.cpuGBs, s.bandwidth.gpuGBs),
                    traces: [Trace(monitor.history.bandwidth, Palette.bandwidth.color)],
                    axis: .ceiling(max(monitor.bandwidthPeakGBs, 1))
                )
                metricTile(
                    "NETWORK", Palette.flowIn.color,
                    value: "↓ \(formatRate(s.network.downloadBytesPerSec))",
                    detail: "↑ \(formatRate(s.network.uploadBytesPerSec))",
                    traces: [Trace(monitor.history.netDown, Palette.flowIn.color),
                             Trace(monitor.history.netUp, Palette.flowOut.color)],
                    axis: .auto
                )
                metricTile(
                    "DISK", Palette.flowIn.color,
                    value: "R \(formatRate(s.disk.readBytesPerSec))",
                    detail: "W \(formatRate(s.disk.writeBytesPerSec))",
                    traces: [Trace(monitor.history.diskRead, Palette.flowIn.color),
                             Trace(monitor.history.diskWrite, Palette.flowOut.color)],
                    axis: .auto
                )
            }
        }

        acceleratorStrip(s)
        busyProcesses(s)
    }

    private func header(_ s: SystemSnapshot) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(monitor.bottleneck.color.opacity(0.14))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(monitor.bottleneck.color)
            }
            .frame(width: 27, height: 27)

            VStack(alignment: .leading, spacing: 1) {
                Text("LeoMac监控器")
                    .font(MenuBarTheme.font(.emphasis, .strong))
                Text("LIVE COCKPIT")
                    .font(MenuBarTheme.font(.caption, .strong))
                    .tracking(1.1)
                    .foregroundStyle(Theme.faint)
            }

            Spacer(minLength: 6)

            Text(LocalizedStringKey(workloadLabel(s)))
                .font(MenuBarTheme.font(.detail, .strong))
                .foregroundStyle(monitor.bottleneck.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(monitor.bottleneck.color.opacity(0.12), in: Capsule())

            Text(String(format: "%.1f W", s.power.socWatts))
                .font(MenuBarTheme.font(.body, .strong))
                .foregroundStyle(Theme.dim)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }

    private func metricTile(_ title: String, _ color: Color, value: String, detail: String,
                            traces: [Trace], axis: ChartAxis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(MenuBarTheme.font(.caption, .strong))
                    .tracking(0.8)
                    .foregroundStyle(Theme.faint)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(MenuBarTheme.font(.emphasis, .strong))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(MenuBarTheme.font(.caption))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Sparkline(traces, role: .inline(height: 15, axis: axis))
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func acceleratorStrip(_ s: SystemSnapshot) -> some View {
        HStack(spacing: gap) {
            statusChip("ANE", String(format: "%.1f W", s.power.aneWatts), MetricPalette.aneC)
            statusChip("MEDIA", String(format: "%.1f GB/s", s.bandwidth.mediaGBs), MetricPalette.mediaC)
            statusChip("AI", s.aiRuntimeLabel, monitor.bottleneck.color)
            statusChip("FITS", s.memoryBudget.fitsNow.first?.label ?? "—", Palette.memory.color)
        }
    }

    private func statusChip(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(MenuBarTheme.font(.caption, .strong))
                .tracking(0.7)
                .foregroundStyle(color)
            Text(value)
                .font(MenuBarTheme.font(.detail, .strong))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(color.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private func busyProcesses(_ s: SystemSnapshot) -> some View {
        let top = Array(s.processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(3))
        VStack(alignment: .leading, spacing: 5) {
            Text("BUSY PROCESSES")
                .font(MenuBarTheme.font(.caption, .strong))
                .tracking(0.9)
                .foregroundStyle(Theme.faint)
            if top.isEmpty {
                Text("—").font(MenuBarTheme.font(.body)).foregroundStyle(Theme.dim)
            } else {
                HStack(spacing: gap) {
                    ForEach(top) { process in
                        HStack(spacing: 5) {
                            Text(process.name)
                                .font(MenuBarTheme.font(.detail))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 2)
                            Text(String(format: "%.0f%%", process.cpuPercent))
                                .font(MenuBarTheme.font(.detail, .strong))
                                .foregroundStyle(Theme.heat(min(1, process.cpuPercent / 100)))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 7) {
            Button { openMainDashboard() } label: {
                Label("Open Dashboard", systemImage: "macwindow")
            }
            .buttonStyle(PopoverButtonStyle(prominent: true))

            HStack(spacing: 7) {
                Button("Settings") { openAppSettings() }
                    .buttonStyle(PopoverButtonStyle())
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(PopoverButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func compactGPURow(_ s: SystemSnapshot) -> some View {
        HStack(spacing: 8) {
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
        }
    }

    private func compactValue(_ text: String, color: Color = Theme.text) -> some View {
        Text(text).font(MenuBarTheme.font(.emphasis)).foregroundStyle(color)
    }

    private var compactSeparator: some View {
        Text("·").font(MenuBarTheme.font(.emphasis)).foregroundStyle(Theme.faint)
    }

    private func workloadLabel(_ snapshot: SystemSnapshot) -> String {
        let label = monitor.bottleneck.label
        guard monitor.bottleneck == .bandwidthBound, snapshot.bandwidth.isEstimated else { return label }
        return label + " (est.)"
    }
}
