import SwiftUI

/// Eight monochrome dotted instruments inspired by thinking-orbs' distinct motion vocabulary.
/// Each dashboard module owns a stable silhouette; live state only changes its tempo/intensity.
struct AIStatusOrb: View {
    enum State: Equatable { case idle, active, constrained }
    enum Style: Equatable {
        case orbits       // CPU: tilted compute paths
        case globe        // GPU: rotating silicon sphere
        case cube         // Memory: shifting memory lattice
        case wave         // Bandwidth: travelling wavefronts
        case ribbon       // AI: braided inference stream
        case morph        // Sensors: circle/triangle/square envelope
        case helix        // Network: paired send/receive strands
        case radar        // Disk: platter and seek arm
    }

    let state: State
    let style: Style
    let color: Color
    var size: CGFloat = 34

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var frameInterval: TimeInterval { state == .idle ? 1 / 12 : 1 / 24 }
    private var speed: CGFloat {
        switch state { case .idle: 0.52; case .active: 1.15; case .constrained: 0.78 }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval,
                                paused: reduceMotion || scenePhase != .active)) { timeline in
            Canvas(rendersAsynchronously: true) { context, canvasSize in
                let t = reduceMotion ? CGFloat(0.8) : CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                draw(in: &context, size: canvasSize, time: t * speed)
            }
        }
        .frame(width: size, height: size)
        .drawingGroup(opaque: false, colorMode: .linear)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private struct Dot {
        let point: CGPoint
        var depth: CGFloat = 0
        var radius: CGFloat = 0.8
        var alpha: CGFloat = 0.65
        var hot = false
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: CGFloat) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = side * 0.41
        glow(in: &context, center: center, radius: radius, time: time)

        let dots: [Dot] = switch style {
        case .orbits: orbitDots(center, radius, time)
        case .globe: globeDots(center, radius, time)
        case .cube: cubeDots(center, radius, time)
        case .wave: waveDots(center, radius, time)
        case .ribbon: ribbonDots(center, radius, time)
        case .morph: morphDots(center, radius, time)
        case .helix: helixDots(center, radius, time)
        case .radar: radarDots(center, radius, time)
        }
        paint(dots, in: &context)
    }

    private func glow(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: CGFloat) {
        let breath = reduceMotion ? 0.65 : 0.62 + 0.24 * sin(time * 1.45)
        let rect = CGRect(x: center.x - radius * 0.72, y: center.y - radius * 0.72,
                          width: radius * 1.44, height: radius * 1.44)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color.opacity(0.20 + breath * 0.11), color.opacity(0)]),
            center: center, startRadius: 0, endRadius: radius * 0.78))
    }

    private func paint(_ dots: [Dot], in context: inout GraphicsContext) {
        for dot in dots.sorted(by: { $0.depth < $1.depth }) {
            let r = max(0.82, dot.radius * 1.28) * (dot.hot ? 1.52 : 1)
            let rect = CGRect(x: dot.point.x - r, y: dot.point.y - r, width: r * 2, height: r * 2)
            let halo = rect.insetBy(dx: -r * 0.72, dy: -r * 0.72)
            context.fill(Path(ellipseIn: halo),
                         with: .color(color.opacity(dot.hot ? 0.24 : 0.10)))
            context.fill(Path(ellipseIn: rect),
                         with: .color(color.opacity(dot.hot ? 1.0 : max(0.48, dot.alpha))))
        }
    }

    private func orbitDots(_ c: CGPoint, _ r: CGFloat, _ t: CGFloat) -> [Dot] {
        var dots: [Dot] = []
        for ring in 0..<3 {
            let tilt = CGFloat(ring) * .pi / 3 + 0.28
            for i in 0..<14 {
                let a = CGFloat(i) / 14 * .pi * 2 + t * (ring == 1 ? -0.8 : 1)
                let x = cos(a) * r, y = sin(a) * r * 0.62, z = sin(a)
                dots.append(Dot(point: CGPoint(x: c.x + x * cos(tilt) - y * sin(tilt),
                                               y: c.y + x * sin(tilt) + y * cos(tilt)),
                                depth: z, radius: 0.55 + (z + 1) * 0.2,
                                alpha: 0.3 + (z + 1) * 0.26,
                                hot: state == .active && (i + ring * 4) % 13 < 2))
            }
        }
        return dots
    }

    private func globeDots(_ c: CGPoint, _ r: CGFloat, _ t: CGFloat) -> [Dot] {
        var dots: [Dot] = []
        let scan = t.truncatingRemainder(dividingBy: .pi * 2)
        for lat in -3...3 {
            let phi = CGFloat(lat) / 4 * .pi / 2
            for lon in 0..<10 {
                let a = CGFloat(lon) / 10 * .pi * 2 + t * 0.55
                let x = cos(phi) * cos(a), z = cos(phi) * sin(a), y = sin(phi)
                let nearScan = abs(atan2(z, x) - scan).truncatingRemainder(dividingBy: .pi * 2) < 0.35
                dots.append(Dot(point: CGPoint(x: c.x + x * r, y: c.y + y * r), depth: z,
                                radius: 0.5 + (z + 1) * 0.18, alpha: 0.22 + (z + 1) * 0.3,
                                hot: nearScan && state != .idle))
            }
        }
        return dots
    }

    private func cubeDots(_ c: CGPoint, _ r: CGFloat, _ t: CGFloat) -> [Dot] {
        var dots: [Dot] = []
        let angle = t * 0.32
        let shift = state == .active ? sin(t * 2) * r * 0.16 : 0
        for x in -1...1 { for y in -1...1 { for z in -1...1 {
            var px = CGFloat(x) * r * 0.48
            let py = CGFloat(y) * r * 0.48
            let pz = CGFloat(z) * r * 0.48
            if y == 1 { px += shift }
            let rx = px * cos(angle) - pz * sin(angle)
            let rz = px * sin(angle) + pz * cos(angle)
            dots.append(Dot(point: CGPoint(x: c.x + rx, y: c.y + py - rz * 0.28), depth: rz,
                            radius: 0.72, alpha: 0.38 + (rz / r + 1) * 0.25,
                            hot: state == .constrained && y == 1))
        }}}
        return dots
    }

    private func waveDots(_ c: CGPoint, _ r: CGFloat, _ t: CGFloat) -> [Dot] {
        var dots: [Dot] = []
        for lane in -2...2 {
            for i in 0..<9 {
                let x = (CGFloat(i) / 8 * 2 - 1) * r
                let phase = x / r * .pi * 1.4 - t * 2 + CGFloat(lane) * 0.48
                let y = CGFloat(lane) * r * 0.22 + sin(phase) * r * 0.16
                dots.append(Dot(point: CGPoint(x: c.x + x, y: c.y + y), radius: 0.62,
                                alpha: 0.42 + 0.18 * cos(phase), hot: state == .active && i == 7))
            }
        }
        return dots
    }

    private func ribbonDots(_ c: CGPoint, _ r: CGFloat, _ t: CGFloat) -> [Dot] {
        var dots: [Dot] = []
        for lane in -1...1 {
            for i in 0..<16 {
                let u = CGFloat(i) / 15 * 2 - 1
                let bend = sin(u * .pi + t * 1.35)
                let x = u * r * 0.98
                let y = bend * r * 0.34 + CGFloat(lane) * r * 0.18 * cos(u * .pi * 1.5 + t)
                dots.append(Dot(point: CGPoint(x: c.x + x, y: c.y + y), depth: bend,
                                radius: 0.58 + (bend + 1) * 0.12,
                                alpha: 0.38 + (bend + 1) * 0.22,
                                hot: state == .active && i == (Int(t * 5) + lane + 32) % 16))
            }
        }
        return dots
    }

    private func morphDots(_ c: CGPoint, _ r: CGFloat, _ t: CGFloat) -> [Dot] {
        let phase = (sin(t * 0.72) + 1) * 0.5
        let sides = phase < 0.33 ? 3 : (phase < 0.66 ? 4 : 12)
        return (0..<28).map { i in
            let a = CGFloat(i) / 28 * .pi * 2 - .pi / 2
            let sector = .pi * 2 / CGFloat(sides)
            let edge = cos(.pi / CGFloat(sides)) / cos((a + sector / 2).truncatingRemainder(dividingBy: sector) - sector / 2)
            let pulse = state == .constrained ? 0.82 + 0.08 * sin(t * 3) : 0.9
            return Dot(point: CGPoint(x: c.x + cos(a) * r * edge * pulse,
                                      y: c.y + sin(a) * r * edge * pulse),
                       radius: 0.62, alpha: 0.58, hot: state == .active && i % 9 == 0)
        }
    }

    private func helixDots(_ c: CGPoint, _ r: CGFloat, _ t: CGFloat) -> [Dot] {
        var dots: [Dot] = []
        for strand in 0..<2 { for i in 0..<17 {
            let u = CGFloat(i) / 16 * 2 - 1
            let a = u * .pi * 2.2 + t * 1.8 + CGFloat(strand) * .pi
            let z = cos(a)
            dots.append(Dot(point: CGPoint(x: c.x + u * r, y: c.y + sin(a) * r * 0.42),
                            depth: z, radius: 0.54 + (z + 1) * 0.18,
                            alpha: 0.28 + (z + 1) * 0.3,
                            hot: state == .active && i == (Int(t * 5) + strand * 8) % 17))
        }}
        return dots
    }

    private func radarDots(_ c: CGPoint, _ r: CGFloat, _ t: CGFloat) -> [Dot] {
        var dots: [Dot] = []
        let head = t * 2.2
        for ring in 1...3 { for i in 0..<(ring * 10) {
            let a = CGFloat(i) / CGFloat(ring * 10) * .pi * 2
            let delta = abs(atan2(sin(a - head), cos(a - head)))
            dots.append(Dot(point: CGPoint(x: c.x + cos(a) * r * CGFloat(ring) / 3,
                                           y: c.y + sin(a) * r * CGFloat(ring) / 3),
                            radius: 0.58, alpha: 0.3 + CGFloat(ring) * 0.1,
                            hot: state != .idle && delta < 0.28))
        }}
        dots.append(Dot(point: c, radius: 1.05, alpha: 0.9, hot: true))
        return dots
    }
}
