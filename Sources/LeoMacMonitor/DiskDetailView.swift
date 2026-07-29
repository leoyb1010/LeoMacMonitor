import SwiftUI
import LeoMacMonitorCore

/// Detailed disk intelligence stays one click behind the existing Disk card so the 4×2
/// secondary-display dashboard remains unchanged.
struct DiskDetailView: View {
    let monitor: LeoMacMonitorMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let snapshot = monitor.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                activity(snapshot)
                processRanking(snapshot.processes)
                deviceList(snapshot.disk.physicalDevices)
            }
            .padding(20)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 680)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("磁盘智能监控").font(MenuBarTheme.font(.headline, .strong))
                Text("进程速率为跨设备总量；设备速率来自物理磁盘计数器")
                    .font(MenuBarTheme.font(.detail)).foregroundStyle(Theme.faint)
            }
            Spacer()
            Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private func activity(_ s: SystemSnapshot) -> some View {
        HStack(spacing: 12) {
            summaryTile("总读取", formatRate(s.disk.readBytesPerSec), MetricPalette.downC)
            summaryTile("总写入", formatRate(s.disk.writeBytesPerSec), MetricPalette.upC)
            summaryTile("内置容量", formatBytesOfTotal(s.disk.totalBytes - s.disk.freeBytes, s.disk.totalBytes), Palette.memory.color)
            summaryTile("物理设备", "\(s.disk.physicalDevices.count)", Theme.accent)
        }
    }

    private func summaryTile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(MenuBarTheme.font(.detail)).foregroundStyle(Theme.faint)
            Text(value).font(MenuBarTheme.font(.emphasis, .strong)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
    }

    private func processRanking(_ processes: [ProcessRow]) -> some View {
        let ranked = processes
            .filter { ($0.diskTotalBytesPerSec ?? 0) > 0 }
            .sorted { ($0.diskTotalBytesPerSec ?? 0) > ($1.diskTotalBytesPerSec ?? 0) }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("进程读写排行", icon: "list.number")
            if ranked.isEmpty {
                Text("正在建立五秒平滑采样…").font(MenuBarTheme.font(.body)).foregroundStyle(Theme.dim)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(ranked.prefix(8))) { process in
                    HStack(spacing: 10) {
                        Text(process.name).font(MenuBarTheme.font(.body, .strong))
                            .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        Text("读 \(formatRate(process.diskReadBytesPerSec ?? 0))")
                            .font(MenuBarTheme.font(.detail)).foregroundStyle(MetricPalette.downC)
                            .frame(width: 120, alignment: .trailing)
                        Text("写 \(formatRate(process.diskWriteBytesPerSec ?? 0))")
                            .font(MenuBarTheme.font(.detail)).foregroundStyle(MetricPalette.upC)
                            .frame(width: 120, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    @ViewBuilder private func deviceList(_ devices: [DiskDeviceSample]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("物理磁盘与健康度", icon: "internaldrive")
            if devices.isEmpty {
                Text("暂未取得物理磁盘信息").font(MenuBarTheme.font(.body)).foregroundStyle(Theme.dim)
            } else {
                ForEach(devices) { device in
                    DisclosureGroup {
                        healthDetails(device.health)
                            .padding(.top, 8)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: device.isInternal == false ? "externaldrive" : "internaldrive")
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).font(MenuBarTheme.font(.body, .strong)).lineLimit(1)
                                Text("\(device.bsdName) · \(deviceLocation(device))")
                                    .font(MenuBarTheme.font(.caption)).foregroundStyle(Theme.faint)
                            }
                            Spacer()
                            Text("读 \(formatRate(device.readBytesPerSec)) · 写 \(formatRate(device.writeBytesPerSec))")
                                .font(MenuBarTheme.font(.detail)).foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(healthColor(device.health).opacity(0.45)))
                }
            }
        }
    }

    @ViewBuilder private func healthDetails(_ health: DiskHealthSnapshot?) -> some View {
        if let health {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                healthKV("SMART", health.smartStatus ?? "不可用")
                healthKV("温度", health.temperatureCelsius.map { String(format: "%.0f °C", $0) } ?? "不可用")
                healthKV("寿命消耗", health.percentageUsed.map { "\($0)%" } ?? "不可用")
                healthKV("累计读取", health.hostBytesRead.map(formatApproxBytes) ?? "不可用")
                healthKV("累计写入", health.hostBytesWritten.map(formatApproxBytes) ?? "不可用")
                healthKV("异常关机", health.unsafeShutdowns.map(String.init) ?? "不可用")
                healthKV("通电时间", health.powerOnHours.map { "\($0) 小时" } ?? "不可用")
                healthKV("介质错误", health.mediaErrors.map(String.init) ?? "不可用")
                healthKV("错误日志", health.errorLogEntries.map(String.init) ?? "不可用")
            }
        } else {
            Text("健康信息正在后台读取；不支持的 USB 转接盒可能不会提供 SMART/NVMe 数据。")
                .font(MenuBarTheme.font(.detail)).foregroundStyle(Theme.dim)
        }
    }

    private func healthKV(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(MenuBarTheme.font(.caption)).foregroundStyle(Theme.faint)
            Text(value).font(MenuBarTheme.font(.body, .strong)).lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(MenuBarTheme.font(.emphasis, .strong)).foregroundStyle(Theme.accent)
    }

    private func healthColor(_ health: DiskHealthSnapshot?) -> Color {
        guard let health else { return Theme.border }
        return health.assessment.isWarning ? Palette.State.critical.color : Palette.State.calm.color
    }

    private func deviceLocation(_ device: DiskDeviceSample) -> String {
        guard let internalDisk = device.isInternal else { return "位置检测中" }
        return internalDisk ? "内置" : "外置"
    }

    private func formatApproxBytes(_ bytes: Double) -> String {
        if bytes >= 1e12 { return String(format: "%.2f TB", bytes / 1e12) }
        if bytes >= 1e9 { return String(format: "%.1f GB", bytes / 1e9) }
        return String(format: "%.0f MB", bytes / 1e6)
    }
}
