import SwiftUI

enum DashboardFaceMode: String, CaseIterable {
    static let storageKey = "dashboard.faceMode"

    case data
    case motion
    case mixed

    var label: String {
        switch self {
        case .data: return "数据"
        case .motion: return "动效"
        case .mixed: return "混合"
        }
    }

    var symbol: String {
        switch self {
        case .data: return "list.bullet.rectangle"
        case .motion: return "sparkles.rectangle.stack"
        case .mixed: return "rectangle.split.2x1"
        }
    }
}

private struct MetricMotionActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var metricMotionActive: Bool {
        get { self[MetricMotionActiveKey.self] }
        set { self[MetricMotionActiveKey.self] = newValue }
    }
}

struct DashboardFaceModeControl: View {
    @Binding var selection: DashboardFaceMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardFaceMode.allCases, id: \.rawValue) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 25, height: 21)
                        .foregroundStyle(selection == mode ? Color.white : Theme.dim)
                        .background(selection == mode ? Theme.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("\(mode.label)模式")
                .accessibilityLabel("\(mode.label)模式")
            }
        }
        .padding(3)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
        .animation(reduceMotion ? nil : Motion.state, value: selection)
    }
}

/// One fixed-size dashboard card with a detailed data face and an ambient motion face.
/// The two faces never participate in layout independently, so flipping cannot disturb the 4×2 grid.
struct FlippableMetricCard<Front: View, Back: View>: View {
    let id: String
    @ViewBuilder let front: Front
    @ViewBuilder let back: Back

    @AppStorage(DashboardFaceMode.storageKey) private var dashboardMode: DashboardFaceMode = .data
    @AppStorage private var mixedShowsMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    init(id: String, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.id = id
        self.front = front()
        self.back = back()
        _mixedShowsMotion = AppStorage(wrappedValue: false, "dashboard.card.\(id).motion")
    }

    private var showsMotion: Bool {
        switch dashboardMode {
        case .data: return false
        case .motion: return true
        case .mixed: return mixedShowsMotion
        }
    }

    var body: some View {
        ZStack {
            front
                .opacity(showsMotion ? 0 : 1)
                .rotation3DEffect(.degrees(showsMotion ? 180 : 0),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                .allowsHitTesting(!showsMotion)

            back
                .environment(\.metricMotionActive, showsMotion)
                .opacity(showsMotion ? 1 : 0)
                .rotation3DEffect(.degrees(showsMotion ? 0 : -180),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                .allowsHitTesting(showsMotion)
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: toggle) {
                Image(systemName: showsMotion ? "list.bullet.rectangle" : "sparkles.rectangle.stack")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Theme.accent : Theme.faint)
                    .frame(width: 23, height: 20)
                    .background(Theme.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .padding(7)
            .help(showsMotion ? "翻到数据面" : "翻到动效面")
            .accessibilityLabel(showsMotion ? "翻到数据面" : "翻到动效面")
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .onTapGesture(count: 2, perform: toggle)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.12)
                                : .spring(response: 0.48, dampingFraction: 0.86),
                   value: showsMotion)
    }

    private func toggle() {
        mixedShowsMotion = !showsMotion
        if dashboardMode != .mixed { dashboardMode = .mixed }
    }
}

/// Shared chrome for all eight motion faces. The graphics differ; typography and state hierarchy do not.
struct MotionCardFace<Visual: View>: View {
    let title: String
    let primary: String
    let primaryValue: Double
    let status: String
    let accent: Color
    @ViewBuilder let visual: Visual

    init(title: String, primary: String, primaryValue: Double, status: String, accent: Color,
         @ViewBuilder visual: () -> Visual) {
        self.title = title
        self.primary = primary
        self.primaryValue = primaryValue
        self.status = status
        self.accent = accent
        self.visual = visual()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(title))
                    .textCase(.uppercase)
                    .font(Theme.font(.sectionMajor))
                    .tracking(Theme.tracking(.sectionMajor))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1).minimumScaleFactor(0.58)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Text(LocalizedStringKey(status))
                    .font(Theme.font(.caption, .strong))
                    .foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(accent.opacity(0.11), in: Capsule())
                    .overlay(Capsule().strokeBorder(accent.opacity(0.22), lineWidth: 1))
            }

            visual
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(primary)
                .font(.system(size: min(UIScale.scaled(22), 28), weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1).minimumScaleFactor(0.5)
                // The persistent flip affordance occupies the lower-right corner. Reserve its
                // footprint so long MHz/rpm/rate strings scale down instead of sitting beneath it.
                .padding(.trailing, 28)
                .metricValueTransition(primaryValue)
        }
        .padding(.horizontal, Space.card)
        .padding(.vertical, Space.tight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                Theme.panel
                RadialGradient(colors: [accent.opacity(0.13), Color.clear],
                               center: .center, startRadius: 0, endRadius: 180)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .strokeBorder(accent.opacity(0.26), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

/// A single implementation of lifecycle-aware Canvas scheduling for all motion faces.
struct ActiveMetricCanvas<Symbols: View>: View {
    let minimumInterval: TimeInterval
    @ViewBuilder let symbols: (Date) -> Symbols

    @Environment(\.metricMotionActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(fps: Double = 24, @ViewBuilder symbols: @escaping (Date) -> Symbols) {
        self.minimumInterval = 1 / max(1, fps)
        self.symbols = symbols
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: minimumInterval,
                                paused: !active || reduceMotion || scenePhase != .active)) { timeline in
            symbols(timeline.date)
        }
    }
}
