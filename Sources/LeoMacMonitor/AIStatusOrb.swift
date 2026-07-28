import SwiftUI

/// A compact, native status instrument for the AI workload card. The motion is deliberately
/// stateful: idle drifts, active work accelerates along three compute orbits, and constrained work
/// compresses into a scanning cage. It is decorative evidence of liveness; the adjacent text still
/// owns the accessible status.
struct AIStatusOrb: View {
    enum State: Equatable {
        case idle
        case active
        case constrained
    }

    let state: State
    let color: Color
    var size: CGFloat = 27

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var frameInterval: TimeInterval {
        state == .idle ? 1.0 / 8.0 : 1.0 / 18.0
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval,
                                paused: reduceMotion || scenePhase != .active)) { timeline in
            Canvas(rendersAsynchronously: true) { context, canvasSize in
                let now = reduceMotion ? 0.8 : timeline.date.timeIntervalSinceReferenceDate
                draw(in: &context, size: canvasSize, time: now)
            }
        }
        .frame(width: size, height: size)
        .drawingGroup(opaque: false, colorMode: .linear)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private struct Dot {
        let x: CGFloat
        let y: CGFloat
        let depth: CGFloat
        let radius: CGFloat
        let alpha: CGFloat
        let hot: Bool
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = side * 0.39
        let phase = CGFloat(time)
        let speed: CGFloat = switch state {
        case .idle: 0.22
        case .active: 1.08
        case .constrained: 0.58
        }

        // A restrained bloom makes the orb read as a live instrument on both appearances without
        // adding a large coloured surface to the card header.
        let breath = reduceMotion ? 0.55 : 0.52 + 0.18 * sin(phase * 1.7)
        let glowRect = CGRect(x: center.x - radius * 0.72, y: center.y - radius * 0.72,
                              width: radius * 1.44, height: radius * 1.44)
        context.fill(Path(ellipseIn: glowRect), with: .radialGradient(
            Gradient(colors: [color.opacity(0.14 + breath * 0.08), color.opacity(0)]),
            center: center, startRadius: 0, endRadius: radius * 0.78
        ))

        var dots: [Dot] = []
        let ringCount = 3
        let dotsPerRing = state == .idle ? 13 : 16

        for ring in 0..<ringCount {
            let tilt = CGFloat(ring) * (.pi / 3) + 0.34
            let runner = Int((phase * speed * 3.2 + CGFloat(ring * 5)).rounded(.down)) % dotsPerRing
            for index in 0..<dotsPerRing {
                let a = CGFloat(index) / CGFloat(dotsPerRing) * .pi * 2
                    + phase * speed * (ring == 1 ? -0.72 : 1)
                let squash: CGFloat = state == .constrained
                    ? 0.48 + 0.12 * sin(phase * 2.1 + CGFloat(ring))
                    : 0.66

                let localX = cos(a) * radius
                let localY = sin(a) * radius * squash
                let localZ = sin(a) * radius
                let ct = cos(tilt)
                let st = sin(tilt)
                let x = localX * ct - localY * st
                let y = localX * st + localY * ct
                let depth = localZ / max(radius, 1)
                let isRunner = state == .active && circularDistance(index, runner, count: dotsPerRing) <= 1
                let scan = state == .constrained
                    ? max(0, cos(a - phase * 2.4 - CGFloat(ring) * 0.7))
                    : 0
                let dotRadius = side * (0.021 + 0.013 * (depth + 1) / 2)
                    * (isRunner ? 1.85 : 1 + scan * 0.55)
                dots.append(Dot(x: center.x + x, y: center.y + y, depth: depth,
                                radius: dotRadius,
                                alpha: 0.24 + 0.54 * (depth + 1) / 2 + scan * 0.18,
                                hot: isRunner || scan > 0.72))
            }
        }

        // Back-to-front sorting is the small detail that makes the 27 pt mark feel dimensional.
        for dot in dots.sorted(by: { $0.depth < $1.depth }) {
            let rect = CGRect(x: dot.x - dot.radius, y: dot.y - dot.radius,
                              width: dot.radius * 2, height: dot.radius * 2)
            let ink = dot.hot ? color : color.opacity(min(0.9, dot.alpha))
            context.fill(Path(ellipseIn: rect), with: .color(ink))
        }

        if state == .active {
            let coreRadius = side * (reduceMotion ? 0.065 : 0.06 + 0.012 * sin(phase * 3.4))
            let core = CGRect(x: center.x - coreRadius, y: center.y - coreRadius,
                              width: coreRadius * 2, height: coreRadius * 2)
            context.fill(Path(ellipseIn: core), with: .color(color.opacity(0.92)))
        }
    }

    private func circularDistance(_ lhs: Int, _ rhs: Int, count: Int) -> Int {
        let direct = abs(lhs - rhs)
        return min(direct, count - direct)
    }
}
