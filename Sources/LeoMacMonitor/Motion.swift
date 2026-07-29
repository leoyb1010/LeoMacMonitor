import SwiftUI

/// Product-wide motion language. Live samples may arrive as often as every 300 ms, so frequent
/// transitions are deliberately shorter than the sampling interval and never overshoot measured
/// values. Continuous motion is reserved for a real continuous state (fans / connecting / record).
enum Motion {
    static let data = Animation.easeOut(duration: 0.42)
    static let interaction = Animation.easeOut(duration: 0.12)
    static let state = Animation.easeInOut(duration: 0.24)
    static let disclosure = Animation.spring(response: 0.30, dampingFraction: 0.90)
    static let event = Animation.spring(response: 0.38, dampingFraction: 0.86)
}

private struct MetricValueTransition: ViewModifier {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(reduceMotion ? .opacity : .numericText(value: value))
            .animation(reduceMotion ? nil : Motion.data, value: value)
    }
}

extension View {
    /// Smooths live numeric replacement without moving surrounding layout.
    func metricValueTransition(_ value: Double) -> some View {
        modifier(MetricValueTransition(value: value))
    }

    /// For formatted readings whose underlying number is no longer available at the text site.
    func liveTextTransition(_ token: String) -> some View {
        modifier(LiveTextTransition(token: token))
    }
}

private struct LiveTextTransition: ViewModifier {
    let token: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(reduceMotion ? nil : Motion.data, value: token)
    }
}

/// Compact state transition used outside dashboard cards (Fleet, save/copy and connection state).
struct MotionStatusPill: View {
    let label: String
    let systemImage: String
    let color: Color
    var busy = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            if busy {
                ProgressView().controlSize(.mini).tint(color)
            } else {
                Image(systemName: systemImage)
                    .contentTransition(.symbolEffect(.replace))
            }
            Text(LocalizedStringKey(label)).lineLimit(1)
        }
        .font(Theme.font(.caption, .strong))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
        .animation(reduceMotion ? nil : Motion.state, value: label)
    }
}
