import SwiftUI
import WidgetKit
import LeoMacMonitorWidgetShared

private let widgetKind = "LeoMacMonitorOverview"

private struct MonitorEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

private struct MonitorProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonitorEntry {
        MonitorEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (MonitorEntry) -> Void) {
        completion(MonitorEntry(date: .now, snapshot: WidgetSnapshotStore.read() ?? Self.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonitorEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.read() ?? Self.sample
        completion(Timeline(entries: [MonitorEntry(date: .now, snapshot: snapshot)],
                            policy: .after(Date().addingTimeInterval(60))))
    }

    static let sample = WidgetSnapshot(
        chipName: "Apple M4 Max", cpuPercent: 28, gpuPercent: 46,
        memoryPercent: 61, memoryUsedGB: 39.1, memoryTotalGB: 64,
        bandwidthGBs: 42, networkDown: 3_400_000, networkUp: 420_000,
        diskRead: 22_000_000, diskWrite: 8_000_000, diskUsedPercent: 55,
        temperatureC: 57, socWatts: 18.9, aiStatus: "GPU 活跃",
        cpuHistory: [0.1, 0.2, 0.18, 0.36, 0.28], gpuHistory: [0.2, 0.3, 0.25, 0.5, 0.46],
        memoryHistory: [0.57, 0.58, 0.59, 0.6, 0.61], bandwidthHistory: [12, 20, 16, 44, 42],
        networkDownHistory: [1, 2, 1.5, 4, 3.4], networkUpHistory: [0.2, 0.4, 0.3, 0.5, 0.42],
        diskReadHistory: [2, 6, 4, 28, 22], diskWriteHistory: [1, 3, 2, 10, 8],
        temperatureHistory: [52, 53, 54, 56, 57])
}

private struct LeoMacWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MonitorEntry

    private let blue = Color(red: 0.25, green: 0.56, blue: 0.98)
    private let green = Color(red: 0.24, green: 0.72, blue: 0.52)
    private let purple = Color(red: 0.73, green: 0.35, blue: 0.72)
    private let cyan = Color(red: 0.24, green: 0.68, blue: 0.72)
    private let orange = Color(red: 0.92, green: 0.53, blue: 0.22)

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            default: large
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                    Color(nsColor: .controlBackgroundColor)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "leomacmonitor://dashboard"))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .foregroundStyle(blue)
            Text("LeoMac监控器").font(.caption.bold()).lineLimit(1)
            Spacer(minLength: 2)
            Circle().fill(green).frame(width: 5, height: 5)
            Text(entry.snapshot.updatedAt, style: .time)
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .firstTextBaseline) {
                Text("CPU").font(.caption).foregroundStyle(.secondary)
                Text("\(Int(entry.snapshot.cpuPercent.rounded()))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                Text(String(format: "%.0f°C", entry.snapshot.temperatureC))
                    .font(.headline).foregroundStyle(orange)
            }
            MiniTrend(series: [(entry.snapshot.cpuHistory, blue)], fixedCeiling: 1)
                .frame(height: 34)
            HStack {
                compactValue("GPU", entry.snapshot.gpuPercent)
                Spacer()
                compactValue("内存", entry.snapshot.memoryPercent)
            }
            Text(String(format: "%.1f W · %@", entry.snapshot.socWatts, entry.snapshot.chipName))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
    }

    private var medium: some View {
        VStack(spacing: 8) {
            header
            HStack(spacing: 8) {
                MetricCell(title: "CPU", value: percent(entry.snapshot.cpuPercent), color: blue,
                           series: [(entry.snapshot.cpuHistory, blue)], fixedCeiling: 1)
                MetricCell(title: "GPU", value: percent(entry.snapshot.gpuPercent), color: green,
                           series: [(entry.snapshot.gpuHistory, green)], fixedCeiling: 1)
                MetricCell(title: "内存", value: percent(entry.snapshot.memoryPercent), color: purple,
                           series: [(entry.snapshot.memoryHistory, purple)], fixedCeiling: 1)
                MetricCell(title: "温度", value: String(format: "%.0f°", entry.snapshot.temperatureC), color: orange,
                           series: [(entry.snapshot.temperatureHistory, orange)])
            }
            HStack {
                Label(entry.snapshot.aiStatus, systemImage: "brain.head.profile")
                Spacer()
                Text("↓ \(rate(entry.snapshot.networkDown))  ↑ \(rate(entry.snapshot.networkUp))")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var large: some View {
        VStack(spacing: 8) {
            header
            HStack(spacing: 8) {
                MetricCell(title: "CPU", value: percent(entry.snapshot.cpuPercent), color: blue,
                           series: [(entry.snapshot.cpuHistory, blue)], fixedCeiling: 1)
                MetricCell(title: "GPU", value: percent(entry.snapshot.gpuPercent), color: green,
                           series: [(entry.snapshot.gpuHistory, green)], fixedCeiling: 1)
                MetricCell(title: "内存", value: percent(entry.snapshot.memoryPercent), color: purple,
                           subtitle: String(format: "%.1f / %.0f GB", entry.snapshot.memoryUsedGB, entry.snapshot.memoryTotalGB),
                           series: [(entry.snapshot.memoryHistory, purple)], fixedCeiling: 1)
                MetricCell(title: "带宽", value: String(format: "%.0f GB/s", entry.snapshot.bandwidthGBs), color: cyan,
                           series: [(entry.snapshot.bandwidthHistory, cyan)])
            }
            HStack(spacing: 8) {
                MetricCell(title: "AI 工作负载", value: entry.snapshot.aiStatus, color: green,
                           subtitle: String(format: "SoC %.1f W", entry.snapshot.socWatts),
                           series: [(entry.snapshot.gpuHistory, green)], fixedCeiling: 1)
                MetricCell(title: "传感器", value: String(format: "%.0f°C", entry.snapshot.temperatureC), color: orange,
                           subtitle: entry.snapshot.chipName,
                           series: [(entry.snapshot.temperatureHistory, orange)])
                MetricCell(title: "网络", value: "↓ \(rate(entry.snapshot.networkDown))", color: green,
                           subtitle: "↑ \(rate(entry.snapshot.networkUp))",
                           series: [(entry.snapshot.networkDownHistory, green), (entry.snapshot.networkUpHistory, orange)])
                MetricCell(title: "磁盘", value: "读 \(rate(entry.snapshot.diskRead))", color: cyan,
                           subtitle: "写 \(rate(entry.snapshot.diskWrite)) · 已用 \(Int(entry.snapshot.diskUsedPercent))%",
                           series: [(entry.snapshot.diskReadHistory, cyan), (entry.snapshot.diskWriteHistory, orange)])
            }
        }
        .padding(12)
    }

    private func compactValue(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(percent(value)).fontWeight(.semibold)
        }.font(.caption)
    }

    private func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    private func rate(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1fG/s", bytes / 1_000_000_000) }
        if bytes >= 1_000_000 { return String(format: "%.1fM/s", bytes / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.0fK/s", bytes / 1_000) }
        return String(format: "%.0fB/s", bytes)
    }
}

private struct MetricCell: View {
    let title: String
    let value: String
    let color: Color
    var subtitle: String? = nil
    let series: [([Double], Color)]
    var fixedCeiling: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.headline).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            Spacer(minLength: 0)
            MiniTrend(series: series, fixedCeiling: fixedCeiling).frame(height: 28)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MiniTrend: View {
    let series: [([Double], Color)]
    var fixedCeiling: Double? = nil

    var body: some View {
        Canvas { context, size in
            let all = series.flatMap(\.0)
            let ceiling = max(fixedCeiling ?? all.max() ?? 1, 0.0001)
            for (values, color) in series where values.count > 1 {
                var path = Path()
                for index in values.indices {
                    let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = size.height * (1 - CGFloat(max(0, min(1, values[index] / ceiling))))
                    index == values.startIndex ? path.move(to: CGPoint(x: x, y: y))
                                               : path.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 1.4)
            }
        }
    }
}

private struct LeoMacMonitorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: MonitorProvider()) { entry in
            LeoMacWidgetView(entry: entry)
        }
        .configurationDisplayName("LeoMac 实时监控")
        .description("查看 CPU、GPU、内存、AI、网络、磁盘与温度概览。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct LeoMacWidgetBundle: WidgetBundle {
    var body: some Widget { LeoMacMonitorWidget() }
}
