import SwiftUI

private func motionClamp(_ value: Double) -> Double { min(1, max(0, value)) }

private func motionPoint(_ center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
    CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
}

private func motionArc(center: CGPoint, radius: CGFloat, start: Double, sweep: Double) -> Path {
    var path = Path()
    path.addArc(center: center, radius: radius,
                startAngle: .radians(start), endAngle: .radians(start + sweep), clockwise: false)
    return path
}

struct CPUMotionFace: View {
    let eUsage: Double
    let pUsage: Double
    let pFrequencyMHz: Double
    let throttling: Bool

    private var load: Double { max(eUsage, pUsage) }

    var body: some View {
        MotionCardFace(title: "CPU", primary: String(format: "%.0f%% · %.0f MHz", load * 100, pFrequencyMHz),
                       primaryValue: load, status: throttling ? "受限" : load > 0.12 ? "计算中" : "空闲",
                       accent: throttling ? Palette.State.critical.color : Palette.pCPU.color) {
            ActiveMetricCanvas(fps: 20) { date in
                Canvas(rendersAsynchronously: true) { context, size in
                    let t = date.timeIntervalSinceReferenceDate
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let r = min(size.width, size.height) * 0.42
                    let p = motionClamp(pUsage), e = motionClamp(eUsage)
                    let pColor = throttling ? Palette.State.critical.color : Palette.pCPU.color
                    let eColor = Palette.eCPU.color

                    for ring in 0..<3 {
                        let radius = r * (0.55 + CGFloat(ring) * 0.18)
                        let start = t * (0.34 + p * 0.9) + Double(ring) * 1.8
                        context.stroke(motionArc(center: center, radius: radius, start: start,
                                                 sweep: 0.55 + p * 4.8),
                                       with: .color(pColor.opacity(0.48 + p * 0.42)),
                                       style: StrokeStyle(lineWidth: ring == 2 ? 4 : 2.5, lineCap: .round))
                    }
                    for ring in 0..<2 {
                        let radius = r * (0.34 + CGFloat(ring) * 0.13)
                        let start = -t * (0.28 + e * 0.75) + Double(ring) * .pi
                        context.stroke(motionArc(center: center, radius: radius, start: start,
                                                 sweep: 0.7 + e * 4.4),
                                       with: .color(eColor.opacity(0.48 + e * 0.42)),
                                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    let cores = 12
                    for index in 0..<cores {
                        let angle = Double(index) / Double(cores) * .pi * 2 - .pi / 2
                        let point = motionPoint(center, radius: r * 0.84, angle: angle)
                        let active = Double(index) / Double(cores) < p
                        let dot = CGRect(x: point.x - 2.3, y: point.y - 2.3, width: 4.6, height: 4.6)
                        context.fill(Path(ellipseIn: dot), with: .color(active ? pColor : Theme.border))
                    }
                    let hub = CGRect(x: center.x - r * 0.18, y: center.y - r * 0.18,
                                     width: r * 0.36, height: r * 0.36)
                    context.fill(Path(ellipseIn: hub), with: .radialGradient(
                        Gradient(colors: [pColor.opacity(0.9), pColor.opacity(0.08)]),
                        center: center, startRadius: 0, endRadius: r * 0.18))
                }
            }
        }
    }
}

struct GPUMotionFace: View {
    let usage: Double
    let watts: Double
    let memoryFraction: Double
    let throttling: Bool

    var body: some View {
        let u = motionClamp(usage)
        let accent = throttling ? Palette.State.critical.color : Palette.gpu.color
        MotionCardFace(title: "GPU", primary: String(format: "%.0f%% · %.1f W", u * 100, watts),
                       primaryValue: u, status: throttling ? "降频" : u > 0.12 ? "渲染中" : "空闲",
                       accent: accent) {
            ActiveMetricCanvas(fps: 20) { date in
                Canvas(rendersAsynchronously: true) { context, size in
                    let t = date.timeIntervalSinceReferenceDate
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let r = min(size.width, size.height) * 0.43
                    for index in 0..<30 {
                        let seed = Double(index)
                        let orbit = 0.25 + (seed * 0.618).truncatingRemainder(dividingBy: 1) * 0.75
                        let angle = seed * 2.399 + t * (0.22 + u * 1.25) * (index.isMultiple(of: 2) ? 1 : -1)
                        let wobble = 0.82 + sin(t * 0.7 + seed) * 0.16
                        let point = motionPoint(center, radius: r * orbit * wobble, angle: angle)
                        let sizeVariation = seed.truncatingRemainder(dividingBy: 3) * 0.25
                        let particleSize = 1.2 + u * 2.2 + sizeVariation
                        let radius = CGFloat(particleSize)
                        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                          width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(0.28 + u * 0.65)))
                    }
                    let sphere = CGRect(x: center.x - r * 0.31, y: center.y - r * 0.31,
                                        width: r * 0.62, height: r * 0.62)
                    context.fill(Path(ellipseIn: sphere), with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.86), accent.opacity(0.72), accent.opacity(0.08)]),
                        center: CGPoint(x: center.x - r * 0.1, y: center.y - r * 0.12),
                        startRadius: 0, endRadius: r * 0.34))
                    context.stroke(motionArc(center: center, radius: r * 0.91, start: -.pi / 2,
                                             sweep: .pi * 2 * motionClamp(memoryFraction)),
                                   with: .color(MetricPalette.gpuMemC),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            }
        }
    }
}

struct MemoryMotionFace: View {
    let wired: Double
    let active: Double
    let compressed: Double
    let free: Double
    let pressure: Double
    let usedGB: Double
    let totalGB: Double
    let status: String

    var body: some View {
        let accent = pressure >= 0.82 ? Palette.State.critical.color
            : pressure >= 0.55 ? Palette.State.warn.color : Palette.memory.color
        MotionCardFace(title: "Memory", primary: String(format: "%.1f / %.0f GB", usedGB, totalGB),
                       primaryValue: usedGB, status: status, accent: accent) {
            ActiveMetricCanvas(fps: 20) { date in
                Canvas(rendersAsynchronously: true) { context, size in
                    let t = date.timeIntervalSinceReferenceDate
                    let values = [motionClamp(wired), motionClamp(active), motionClamp(compressed), motionClamp(free)]
                    let colors = [Palette.Memory.wired.color, Palette.Memory.active.color,
                                  Palette.Memory.compressed.color, Palette.Memory.free]
                    var y: CGFloat = 0
                    for index in values.indices {
                        let height = size.height * CGFloat(values[index])
                        var band = Path()
                        band.move(to: CGPoint(x: 0, y: y + sin(t + Double(index)) * 2))
                        let samples = 22
                        for sample in 0...samples {
                            let x = size.width * CGFloat(sample) / CGFloat(samples)
                            let wave = sin(Double(sample) * 0.56 + t * (0.8 + Double(index) * 0.15)) * 2.5
                            band.addLine(to: CGPoint(x: x, y: y + CGFloat(wave)))
                        }
                        band.addLine(to: CGPoint(x: size.width, y: y + height))
                        band.addLine(to: CGPoint(x: 0, y: y + height))
                        band.closeSubpath()
                        context.fill(band, with: .color(colors[index].opacity(index == 3 ? 0.14 : 0.68)))
                        y += height
                    }
                    let pressureHeight = size.height * CGFloat(motionClamp(pressure))
                    let gauge = CGRect(x: size.width - 5, y: size.height - pressureHeight,
                                       width: 4, height: pressureHeight)
                    context.fill(Path(roundedRect: gauge, cornerRadius: 2), with: .color(accent))
                    for row in 1..<5 {
                        let lineY = size.height * CGFloat(row) / 5
                        var line = Path(); line.move(to: CGPoint(x: 0, y: lineY)); line.addLine(to: CGPoint(x: size.width, y: lineY))
                        context.stroke(line, with: .color(Theme.border), style: StrokeStyle(lineWidth: 0.7, dash: [3, 5]))
                    }
                }
            }
        }
    }
}

struct BandwidthMotionFace: View {
    let cpu: Double
    let gpu: Double
    let media: Double
    let other: Double
    let total: Double
    let ceiling: Double
    let estimated: Bool

    var body: some View {
        let fraction = motionClamp(total / max(ceiling, 1))
        MotionCardFace(title: "Bandwidth", primary: String(format: "%.0f GB/s", total),
                       primaryValue: total, status: estimated ? "估算" : fraction > 0.7 ? "高流量" : "实时",
                       accent: Palette.bandwidth.color) {
            PacketLanes(values: [cpu, gpu, media, other], ceiling: ceiling,
                        colors: [Palette.pCPU.color, Palette.gpu.color, MetricPalette.mediaC, Theme.dim])
        }
    }
}

private struct PacketLanes: View {
    let values: [Double]
    let ceiling: Double
    let colors: [Color]

    var body: some View {
        ActiveMetricCanvas(fps: 20) { date in
            Canvas(rendersAsynchronously: true) { context, size in
                let t = date.timeIntervalSinceReferenceDate
                let laneHeight = size.height / CGFloat(max(values.count, 1))
                for index in values.indices {
                    let y = laneHeight * (CGFloat(index) + 0.5)
                    var track = Path(); track.move(to: CGPoint(x: 5, y: y)); track.addLine(to: CGPoint(x: size.width - 5, y: y))
                    context.stroke(track, with: .color(Theme.border), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    let fraction = motionClamp(values[index] / max(ceiling, 1))
                    let speed = 0.18 + fraction * 1.8
                    for packet in 0..<4 {
                        let phase = (t * speed + Double(packet) / 4 + Double(index) * 0.13)
                            .truncatingRemainder(dividingBy: 1)
                        let x = 5 + (size.width - 10) * CGFloat(phase)
                        let radius: CGFloat = 2.2 + CGFloat(fraction) * 2.3
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(colors[index].opacity(fraction > 0.01 ? 0.92 : 0.16)))
                    }
                }
            }
        }
    }
}

struct AIWorkloadMotionFace: View {
    let cpu: Bool
    let gpu: Bool
    let ane: Bool
    let media: Bool
    let constrained: Bool
    let primary: String
    let primaryValue: Double

    var body: some View {
        let states = [cpu, gpu, ane, media]
        let accent = constrained ? Palette.State.critical.color
            : ane ? Palette.ane.color : gpu ? Palette.gpu.color : media ? MetricPalette.mediaC : Theme.dim
        MotionCardFace(title: "AI Workload", primary: primary, primaryValue: primaryValue,
                       status: constrained ? "受限" : states.contains(true) ? "推理中" : "等待",
                       accent: accent) {
            ActiveMetricCanvas(fps: 20) { date in
                Canvas(rendersAsynchronously: true) { context, size in
                    let t = date.timeIntervalSinceReferenceDate
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let r = min(size.width, size.height) * 0.38
                    let colors = [Palette.pCPU.color, Palette.gpu.color, Palette.ane.color, MetricPalette.mediaC]
                    let angles = [-2.45, -0.68, 0.68, 2.45]
                    for index in states.indices {
                        let node = motionPoint(center, radius: r, angle: angles[index])
                        var link = Path(); link.move(to: node); link.addLine(to: center)
                        context.stroke(link, with: .color(states[index] ? colors[index].opacity(0.68) : Theme.border),
                                       style: StrokeStyle(lineWidth: states[index] ? 2.4 : 1.2, dash: states[index] ? [5, 5] : [] ,
                                                          dashPhase: states[index] ? -t * 20 : 0))
                        let nodeRect = CGRect(x: node.x - 7, y: node.y - 7, width: 14, height: 14)
                        context.fill(Path(ellipseIn: nodeRect), with: .color(states[index] ? colors[index] : Theme.border))
                        if states[index] {
                            let phase = (t * 0.82 + Double(index) * 0.21).truncatingRemainder(dividingBy: 1)
                            let pulse = CGPoint(x: node.x + (center.x - node.x) * phase,
                                                y: node.y + (center.y - node.y) * phase)
                            let pulseRect = CGRect(x: pulse.x - 3, y: pulse.y - 3, width: 6, height: 6)
                            context.fill(Path(ellipseIn: pulseRect), with: .color(colors[index]))
                        }
                    }
                    let breathe = 0.84 + sin(t * 2.2) * 0.08
                    let hubR = r * 0.34 * breathe
                    let hub = CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2)
                    context.fill(Path(ellipseIn: hub), with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.82), accent.opacity(0.72), accent.opacity(0.04)]),
                        center: center, startRadius: 0, endRadius: hubR))
                    context.stroke(Path(ellipseIn: hub.insetBy(dx: -6, dy: -6)), with: .color(accent.opacity(0.55)), lineWidth: 2)
                }
            }
        }
    }
}

struct SensorsMotionFace: View {
    let maximumCelsius: Double
    let rpm: Double
    let pressureLabel: String

    var body: some View {
        let fraction = motionClamp(maximumCelsius / Theme.hotCelsius)
        let accent = Theme.heat(celsius: maximumCelsius)
        MotionCardFace(title: "Sensors", primary: String(format: "%.0f°C · %.0f rpm", maximumCelsius, rpm),
                       primaryValue: maximumCelsius, status: pressureLabel, accent: accent) {
            ActiveMetricCanvas(fps: 20) { date in
                let t = date.timeIntervalSinceReferenceDate
                ZStack {
                    Canvas(rendersAsynchronously: true) { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let r = min(size.width, size.height) * 0.44
                        for ring in 0..<5 {
                            let radius = r * (0.30 + CGFloat(ring) * 0.15)
                            let wobble = 1 + CGFloat(sin(t * 0.55 + Double(ring))) * 0.035
                            let rect = CGRect(x: center.x - radius * wobble, y: center.y - radius / wobble,
                                              width: radius * 2 * wobble, height: radius * 2 / wobble)
                            context.stroke(Path(ellipseIn: rect),
                                           with: .color(accent.opacity(0.20 + Double(ring) * 0.10 + fraction * 0.12)),
                                           style: StrokeStyle(lineWidth: 1.4 + CGFloat(fraction), dash: [5, 6],
                                                              dashPhase: t * (ring.isMultiple(of: 2) ? 5 : -5)))
                        }
                    }
                    Image(systemName: "fanblades.fill")
                        .font(.system(size: min(UIScale.scaled(42), 58), weight: .medium))
                        .foregroundStyle(accent)
                        .rotationEffect(.degrees(rpm < 200 ? 0 : t * 360 * min(1.4, max(0.2, rpm / 4_000))))
                        .shadow(color: accent.opacity(0.42), radius: 8)
                }
            }
        }
    }
}

struct NetworkMotionFace: View {
    let download: Double
    let upload: Double
    let ceiling: Double

    var body: some View {
        let down = motionClamp(download / max(ceiling, 1))
        let up = motionClamp(upload / max(ceiling, 1))
        MotionCardFace(title: "Network", primary: "↓ \(formatRate(download)) · ↑ \(formatRate(upload))",
                       primaryValue: download + upload, status: download + upload > 4_096 ? "双向" : "待机",
                       accent: Palette.flowIn.color) {
            DuplexWave(down: down, up: up, downColor: Palette.flowIn.color, upColor: Palette.flowOut.color)
        }
    }
}

private struct DuplexWave: View {
    let down: Double
    let up: Double
    let downColor: Color
    let upColor: Color

    var body: some View {
        ActiveMetricCanvas(fps: 20) { date in
            Canvas(rendersAsynchronously: true) { context, size in
                let t = date.timeIntervalSinceReferenceDate
                drawWave(context: &context, size: size, value: down, color: downColor,
                         baseline: size.height * 0.36, direction: 1, time: t)
                drawWave(context: &context, size: size, value: up, color: upColor,
                         baseline: size.height * 0.67, direction: -1, time: t + 0.4)
            }
        }
    }

    private func drawWave(context: inout GraphicsContext, size: CGSize, value: Double, color: Color,
                          baseline: CGFloat, direction: Double, time: Double) {
        var path = Path()
        let count = 34
        for index in 0...count {
            let x = size.width * CGFloat(index) / CGFloat(count)
            let envelope = sin(.pi * Double(index) / Double(count))
            let y = baseline + CGFloat(sin(Double(index) * 0.55 - time * direction * (1.4 + value * 4))
                                       * envelope * (5 + value * 18))
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(path, with: .color(color.opacity(0.35 + value * 0.62)),
                       style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
        let phase = (time * direction * (0.22 + value * 1.35)).truncatingRemainder(dividingBy: 1)
        let normalized = phase < 0 ? phase + 1 : phase
        let x = size.width * CGFloat(normalized)
        let packet = CGRect(x: x - 4, y: baseline - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: packet), with: .color(color.opacity(value > 0.01 ? 1 : 0.16)))
    }
}

struct DiskMotionFace: View {
    let read: Double
    let write: Double
    let ceiling: Double
    let usedFraction: Double
    let healthy: Bool

    var body: some View {
        let activity = motionClamp((read + write) / max(ceiling, 1))
        let accent = healthy ? Palette.flowIn.color : Palette.State.critical.color
        MotionCardFace(title: "Disk", primary: "读 \(formatRate(read)) · 写 \(formatRate(write))",
                       primaryValue: read + write, status: healthy ? "I/O 实时" : "健康警告", accent: accent) {
            ActiveMetricCanvas(fps: 20) { date in
                Canvas(rendersAsynchronously: true) { context, size in
                    let t = date.timeIntervalSinceReferenceDate
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let r = min(size.width, size.height) * 0.42
                    let readF = motionClamp(read / max(ceiling, 1))
                    let writeF = motionClamp(write / max(ceiling, 1))
                    for ring in 0..<4 {
                        let radius = r * (0.35 + CGFloat(ring) * 0.17)
                        let clockwise = ring.isMultiple(of: 2) ? 1.0 : -1.0
                        let start = t * clockwise * (0.35 + activity * 2.2) + Double(ring)
                        let fraction = ring.isMultiple(of: 2) ? readF : writeF
                        let color = ring.isMultiple(of: 2) ? Palette.flowIn.color : Palette.flowOut.color
                        context.stroke(motionArc(center: center, radius: radius, start: start,
                                                 sweep: 0.5 + fraction * 4.9),
                                       with: .color(color.opacity(0.42 + fraction * 0.55)),
                                       style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 5]))
                    }
                    context.stroke(motionArc(center: center, radius: r * 0.98, start: -.pi / 2,
                                             sweep: .pi * 2 * motionClamp(usedFraction)),
                                   with: .color(accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    let core = CGRect(x: center.x - r * 0.16, y: center.y - r * 0.16,
                                      width: r * 0.32, height: r * 0.32)
                    context.fill(Path(roundedRect: core, cornerRadius: r * 0.06),
                                 with: .color(accent.opacity(0.72)))
                }
            }
        }
    }
}
