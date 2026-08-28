import SwiftUI
import AgentchCore

// MARK: - Shape

/// Flush against the top screen edge, rounded along the bottom.
struct NotchShape: Shape {
    var cornerRadius: CGFloat = 13

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Palette

/// Four foreground tiers, a handful of neutral surfaces, three accents. Everything composites over
/// pure black, so opacities are literal: white 0.05 is #0D0D0D. Anything not in here is a mistake.
enum UI {
    static let fg1 = Color.white.opacity(0.92)
    static let fg2 = Color.white.opacity(0.60)
    static let fg3 = Color.white.opacity(0.38)
    static let fg4 = Color.white.opacity(0.24)

    static let surface = Color.white.opacity(0.05)
    static let track = Color.white.opacity(0.10)
    /// The closed bar is 2.5pt on black inside a black bezel, with no card behind it: it needs the
    /// hairline's alpha, not a card meter's, or there is nothing to read the fill against.
    static let barTrack = Color.white.opacity(0.16)
    static let hoverPeek = Color.white.opacity(0.06)
    static let hoverPanel = Color.white.opacity(0.07)
    static let active = Color.white.opacity(0.12)

    /// Only on the closed pulse, the waiting dot and the "N waiting" run. Not .orange, which is a
    /// light-mode system colour and blooms on black.
    static let attention = Color(hex: "#E8913A")
    static let warn = Color(hex: "#D29922")
    static let critical = Color(hex: "#F85149")

    static let numPct: CGFloat = 30
    static let numCost: CGFloat = 44
    static let numTokens: CGFloat = 46

    /// Context pressure is not quota: 71% of a context window is an ordinary working state and
    /// nothing resets when it fills. Its own ramp, far later than LimitTier's.
    static func context(_ fraction: Double) -> Color {
        fraction >= 0.90 ? critical : fraction >= 0.78 ? warn : fg2
    }
}

extension LimitTier {
    /// Healthy is neutral: colour means "look here", not "all good".
    var color: Color {
        switch self {
        case .ok: UI.fg2
        case .warn: UI.warn
        case .critical: UI.critical
        }
    }
}

extension SessionState {
    /// The dot carries the state on its own — opacity for alive-vs-parked, hue only for blocked.
    var color: Color {
        switch self {
        case .working: UI.fg1
        case .needsAttention: UI.attention
        case .idle: UI.fg4
        case .done: UI.fg4
        }
    }

    var label: String {
        switch self {
        case .working: "working"
        case .needsAttention: "needs you"
        case .idle: "idle"
        case .done: "done"
        }
    }
}

/// The Claude burst. Eight spokes, not the mark's twelve: at 10pt twelve spokes are 2.6pt apart
/// and the strokes close up into a blob.
struct ClaudeBurst: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.3
        var path = Path()
        for spoke in 0..<8 {
            let angle = Double(spoke) / 8 * 2 * .pi
            path.move(to: CGPoint(x: centre.x + cos(angle) * inner, y: centre.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: centre.x + cos(angle) * outer, y: centre.y + sin(angle) * outer))
        }
        return path
    }
}

/// The provider's mark at any size. Fixed 13pt box everywhere it sits in a text run, so a variable
/// glyph never steps the title column in and out row by row.
struct ProviderGlyph: View {
    var provider: Provider
    var size: CGFloat

    var body: some View {
        switch provider {
        case .claude:
            ClaudeBurst()
                .stroke(style: StrokeStyle(lineWidth: max(0.9, size * 0.1), lineCap: .round))
                .frame(width: size, height: size)
        case .codex:
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: size * 0.78, weight: .semibold))
        }
    }
}

/// A provider's nearest limit as one puck: the mark inside a ring that fills as the window burns.
/// Reads at a glance where a 3pt linear meter needs a label to be legible at all.
struct ProviderRing: View {
    var provider: Provider
    var fractionUsed: Double
    var color: Color
    var diameter: CGFloat = 24
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().stroke(UI.track, lineWidth: lineWidth)
            if fractionUsed >= 0.01 {
                Circle()
                    // A round cap on a hairline arc is already ~2% of the circumference, so the
                    // floor keeps 1% from drawing the same length as 4%.
                    .trim(from: 0, to: min(max(fractionUsed, 0.02), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            ProviderGlyph(provider: provider, size: diameter * 0.44)
                .foregroundStyle(UI.fg2)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Root

struct NotchRootView: View {
    var vm: NotchViewModel
    var state: AppState

    private var size: CGSize {
        vm.size(for: vm.stage, sessionCount: state.activeSessions.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(width: size.width, height: size.height)
                .background(NotchShape().fill(.black))
                .clipShape(NotchShape())
                .shadow(color: .black.opacity(vm.stage == .closed ? 0 : 0.5),
                        radius: vm.stage == .closed ? 0 : 20, y: 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.stage {
        case .closed:
            ClosedView(vm: vm, state: state)
        case .peek:
            PeekView(state: state, topInset: vm.closedSize.height,
                     notchWidth: vm.closedSize.width,
                     expand: { vm.setStage(.open) })
        case .open:
            PanelView(state: state, topInset: vm.closedSize.height,
                      notchWidth: vm.closedSize.width,
                      collapse: { vm.setStage(.peek) })
        }
    }
}

// MARK: - Closed (ambient)

struct ClosedView: View {
    var vm: NotchViewModel
    var state: AppState
    @State private var lit = false

    private var attention: Bool { state.attentionCount > 0 }

    var body: some View {
        content
            .background {
                // Only on the pill, where there is room above the bar to carry it. On real hardware
                // the cutout leaves just the bar visible, and a wash there would paint over the one
                // element that carries data — so on a notch the pulse lives in the bar's own track.
                if attention && !vm.isRealNotch {
                    LinearGradient(colors: [UI.attention.opacity(0), UI.attention.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                        .opacity(lit ? 0.4 : 0.10)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
            .animation(attention ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : nil,
                       value: lit)
            .onAppear { lit = attention }
            .onChange(of: attention) { _, on in lit = on }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isRealNotch {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RemainingBar(state: state, alert: attention ? (lit ? 0.55 : 0.18) : 0)
                    // 10, not 6: the 13pt bottom corner arc is inset 8.4pt at the bar's baseline
                    // and would slice the end segments diagonally.
                    .padding(.horizontal, 10)
                    .padding(.bottom, 0.5)
            }
        } else {
            VStack(spacing: 2) {
                Text("\(state.activeSessions.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(UI.fg1)
                RemainingBar(state: state)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
    }
}

/// One segment per provider, across the full width: filled is what is left of its nearest limit.
/// At 2.5pt tall a capsule is all end cap, so the segments are square-ish rounded rectangles.
struct RemainingBar: View {
    var state: AppState
    /// Alpha for the alert in the bar's own track, on hardware where the bar is all that shows.
    var alert: Double = 0

    /// How much of the nearest limit each provider still has. Providers reporting nothing are
    /// left out rather than shown as full.
    private var segments: [(provider: Provider, remaining: Double)] {
        Provider.allCases.compactMap { provider in
            guard let worst = state.limits(for: provider).map(\.fractionUsed).max() else { return nil }
            return (provider, max(0, 1 - worst))
        }
    }

    private var trackColor: Color { alert > 0 ? UI.attention.opacity(alert) : UI.barTrack }

    var body: some View {
        HStack(spacing: 2) {
            if segments.isEmpty {
                RoundedRectangle(cornerRadius: 1).fill(trackColor)
            }
            ForEach(segments, id: \.provider) { segment in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(trackColor)
                        // Nothing at all below 1%: exhausted and nearly-exhausted have to differ.
                        if segment.remaining >= 0.01 {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color(hex: state.appearance.color(for: segment.provider)))
                                .frame(width: max(2, geo.size.width * segment.remaining))
                        }
                    }
                }
            }
        }
        .frame(height: 2.5)
    }
}

// MARK: - Peek: the session list

struct PeekView: View {
    var state: AppState
    var topInset: CGFloat = 24
    var notchWidth: CGFloat = 190
    var expand: () -> Void

    private var sessions: [AgentSession] { state.activeSessions }
    private var shown: [AgentSession] { Array(sessions.prefix(NotchViewModel.peekRowLimit)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NotchFlank(limits: state.limits, notchWidth: notchWidth, height: topInset)
            Spacer(minLength: 0).frame(height: 6)
            if sessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 10))
                    .foregroundStyle(UI.fg3)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: NotchViewModel.peekRowHeight)
            }
            ForEach(shown) { session in
                CompactSessionRow(session: session, fields: state.hoverFields,
                                  parity: state.parity, appearance: state.appearance)
                    .frame(height: NotchViewModel.peekRowHeight)
            }
            if sessions.count > NotchViewModel.peekRowLimit {
                Text("+\(sessions.count - NotchViewModel.peekRowLimit) more")
                    .font(.system(size: 9))
                    .tracking(0.1)
                    .foregroundStyle(UI.fg3)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                // Left-aligned text abutting a centred chevron reads as one broken control.
                Spacer(minLength: 0).frame(height: 2)
            }
            BottomBar(symbol: "chevron.down",
                      height: NotchViewModel.peekBarHeight,
                      action: expand,
                      showSettings: state.showSettings) {
                Text("\(sessions.count) active")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(-0.1)
                    .monospacedDigit()
                    .foregroundStyle(UI.fg2)
                if state.attentionCount > 0 {
                    Text("\(state.attentionCount) waiting")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(-0.1)
                        .monospacedDigit()
                        .foregroundStyle(UI.attention)
                }
            }
        }
        // The container hugs the window edge; every band re-inserts 6pt of its own, so a hover fill
        // sits 4pt off the edge while the text lines up at 10pt.
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}

/// One line per session: who it is and what it is doing, plus whichever numbers you asked for.
/// Clicking it reopens the session in the app that owns it.
struct CompactSessionRow: View {
    var session: AgentSession
    var fields: HoverFields
    var parity: TokenParity
    var appearance: Appearance
    @State private var hovering = false

    private var canOpen: Bool { SessionLink.url(for: session) != nil }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.state.color)
                .frame(width: 4, height: 4)
                .padding(.trailing, -4)
                .accessibilityLabel(session.state.label)
            // The glyph shape already separates the two providers; the hue would be a third carrier.
            // Fixed width: sparkle measures ~7.5pt and the codex chevrons ~13, and a variable glyph
            // would step the title column in and out row by row.
            ProviderGlyph(provider: session.provider, size: 10)
                .frame(width: 13, alignment: .center)
                .foregroundStyle(UI.fg3)
            Text(session.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(UI.fg1)
                .lineLimit(1)
                .truncationMode(.tail)

            metadata

            Spacer(minLength: 6)

            if fields.contains(.context), let context = session.contextFraction {
                Text(Format.percent(context))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .frame(width: UI.numPct, alignment: .trailing)
                    .foregroundStyle(UI.context(context))
            }
            if fields.contains(.tokens) {
                Text(Format.tokens(parity.count(session.tokens)))
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .frame(width: UI.numTokens, alignment: .trailing)
                    .foregroundStyle(UI.fg3)
            }
            if fields.contains(.cost) {
                Text(session.estCostUSD.map(Format.usd) ?? "—")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .frame(width: UI.numCost, alignment: .trailing)
                    .foregroundStyle(UI.fg2)
            }
        }
        .padding(.horizontal, 6)
        // Fill the row slot the list assigns: otherwise the hit area is only as tall as the text
        // and the pointer keeps falling into dead space between rows.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(hovering && canOpen ? UI.hoverPeek : .clear)
                .padding(.vertical, 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { session.open() }
    }

    /// Model and project are the same size, weight and tier, so without the separator a tier below
    /// them they read as one string.
    @ViewBuilder
    private var metadata: some View {
        let model = fields.contains(.model) ? session.model : nil
        let project = fields.contains(.project) ? session.projectName : nil
        HStack(spacing: 0) {
            if let model { ModelTag(model: model, appearance: appearance) }
            if let project {
                if model != nil {
                    Text(" · ").font(.system(size: 9)).foregroundStyle(UI.fg4)
                }
                Text(project)
                    .font(.system(size: 9))
                    .tracking(0.1)
                    .foregroundStyle(UI.fg3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

/// The model is identity, not rank: a 4pt swatch carries the hue so the name can stay tertiary.
struct ModelTag: View {
    var model: String
    var appearance: Appearance

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(hex: appearance.color(forModel: model)))
                .frame(width: 4, height: 4)
            Text(model)
                .font(.system(size: 9))
                .tracking(0.1)
                .foregroundStyle(UI.fg3)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

extension AgentSession {
    /// Hands the session back to the app that owns it.
    func open() {
        guard let url = SessionLink.url(for: self) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct IconButton: View {
    var symbol: String
    var size: CGFloat = 9
    var target: CGFloat = 18
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                // Resting at the icon tier: a gear you never came for must not outweigh the numbers.
                .foregroundStyle(hovering ? UI.fg2 : UI.fg4)
                .frame(width: target, height: target)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? UI.hoverPeek : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The five-hour window per provider, parked in the dead space either side of the hardware
/// cutout. Same position in both stages, so the number does not move when the panel opens.
struct NotchFlank: View {
    var limits: [LimitWindow]
    var notchWidth: CGFloat
    var height: CGFloat

    /// The screen edge is the panel's top edge, so the cell needs a gap or its rounded corners
    /// run off it. Only where the band is tall enough to spare it.
    private var inset: CGFloat { height > 30 ? 4 : 0 }

    /// Fixed provider order, so the two sides do not swap between refreshes.
    private var fiveHour: [LimitWindow] {
        Provider.allCases.compactMap { provider in
            limits.first { $0.provider == provider && $0.kind == .session5h }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            side(fiveHour.first)
            // The cutout itself. Anything drawn here is behind the hardware.
            Color.clear.frame(width: notchWidth)
            side(fiveHour.dropFirst().first)
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func side(_ limit: LimitWindow?) -> some View {
        if let limit {
            RingCell(limit: limit, diameter: min(24, max(14, height - inset - 10)))
                .frame(maxWidth: .infinity)
                .padding(.top, inset)
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }
}

/// One provider cell: ring on the left, name over number on the right.
struct RingCell: View {
    var limit: LimitWindow
    var diameter: CGFloat = 24

    private var tier: LimitTier { LimitTier(fractionUsed: limit.fractionUsed) }

    var body: some View {
        HStack(spacing: 8) {
            ProviderRing(provider: limit.provider,
                         fractionUsed: limit.fractionUsed,
                         color: tier.color,
                         diameter: diameter,
                         lineWidth: max(1.5, diameter * 0.083))
            VStack(alignment: .leading, spacing: 1) {
                Text(limit.provider.displayName.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(UI.fg2)
                HStack(spacing: 4) {
                    Text(Format.percent(limit.fractionUsed))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(tier.color)
                    if let reset = limit.resetsAt {
                        Text(Format.countdown(to: reset))
                            .font(.system(size: 9))
                            .tracking(0.1)
                            .monospacedDigit()
                            .foregroundStyle(UI.fg3)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 7).fill(UI.surface))
    }
}

/// Everything that is not data lives here: the stage chevron dead centre, whatever the stage
/// wants on the left, the gear on the right. The panel grows and shrinks downwards out from
/// under it rather than jumping the pointer.
struct BottomBar<Leading: View>: View {
    var symbol: String
    var height: CGFloat
    var action: () -> Void
    var showSettings: (() -> Void)?
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
            IconButton(symbol: "gearshape") { showSettings?() }
        }
        .padding(.horizontal, 6)
        .frame(height: height)
        .overlay { StageButton(symbol: symbol, action: action) }
    }
}

struct StageButton: View {
    var symbol: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hovering ? UI.fg2 : UI.fg3)
                // The hit area is the whole width; the highlight belongs to the chevron.
                .frame(width: 44, height: NotchViewModel.peekExpandHeight)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? UI.hoverPeek : .clear))
                // Shaped before it is centred: it sits over the bar's other controls.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Panel: the breakdown

struct PanelView: View {
    var state: AppState
    var topInset: CGFloat = 24
    var notchWidth: CGFloat = 190
    var collapse: () -> Void
    @State private var filter: Provider?

    private var visibleSessions: [AgentSession] {
        guard let filter else { return state.activeSessions }
        return state.activeSessions.filter { $0.provider == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NotchFlank(limits: state.limits, notchWidth: notchWidth, height: topInset)
            Spacer(minLength: 0).frame(height: 12)
            limitsBand
            Spacer(minLength: 0).frame(height: 16)
            list
            Spacer(minLength: 0).frame(height: 8)
            footer
            BottomBar(symbol: "chevron.up",
                      height: NotchViewModel.panelBarHeight,
                      action: collapse,
                      showSettings: state.showSettings) {
                segmented
                if state.attentionCount > 0 {
                    Text("\(state.attentionCount) waiting")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(-0.1)
                        .monospacedDigit()
                        .foregroundStyle(UI.attention)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A toggle group, not a row of pills: one track, square-ish items, no accent on the active one.
    private var segmented: some View {
        HStack(spacing: 0) {
            chip(title: "All", count: state.activeSessions.count, active: filter == nil) { filter = nil }
            ForEach(Provider.allCases) { provider in
                chip(title: provider.displayName,
                     count: state.activeSessions.filter { $0.provider == provider }.count,
                     active: filter == provider) { filter = provider }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(UI.surface))
    }

    private func chip(title: String, count: Int, active: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            (Text(title) + Text(count > 0 ? "  \(count)" : "").foregroundStyle(UI.fg3))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(active ? UI.fg1 : UI.fg3)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(active ? UI.active : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var limitsBand: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Provider.allCases) { provider in
                let limits = state.limits(for: provider)
                if filter == nil || filter == provider, state.hasAnything(provider) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(provider.displayName.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(UI.fg2)
                        if limits.isEmpty {
                            Text(state.notice(for: provider) ?? "No limits reported")
                                .font(.system(size: 9))
                                .tracking(0.1)
                                .foregroundStyle(UI.fg3)
                        }
                        // Stacked, not raced: side by side the gap inside a window was wider than
                        // the gap between windows, so the line read as one run of numbers.
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(limits) { limit in
                                LimitBar(limit: limit)
                            }
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(UI.surface))
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                if visibleSessions.isEmpty {
                    Text("No active sessions")
                        .font(.system(size: 10))
                        .foregroundStyle(UI.fg3)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: NotchViewModel.panelRowHeight)
                }
                ForEach(visibleSessions) { session in
                    SessionRow(session: session, parity: state.parity, appearance: state.appearance)
                }
            }
        }
        .scrollIndicators(.never)
        // Fade into the footer rather than stopping at a rule.
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 12)
            }
        )
    }

    private var footer: some View {
        HStack(spacing: 6) {
            // The count is already in the "All 4" chip; twice on one screen is once too many.
            if let (limit, eta) = state.urgentProjection {
                Text("\(limit.provider.displayName) \(limit.kind.label) full in \(Format.countdown(to: eta))")
                    .font(.system(size: 10))
                    .foregroundStyle(LimitTier(fractionUsed: limit.fractionUsed).color)
            }
            Spacer()
            // The only aggregate on the panel: the amount carries the row, "est." matches LimitBar.
            (Text("today ").font(.system(size: 10)).foregroundStyle(UI.fg3)
             + Text(Format.usd(state.todayEstCost))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(UI.fg2)
             + Text(" est.").font(.system(size: 8)).tracking(0.2).foregroundStyle(UI.fg4))
        }
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(height: 18)
    }
}

/// A window's label, its percentage and a 3pt meter. "resets" only shows when it is worth knowing.
struct LimitBar: View {
    var limit: LimitWindow
    /// Overrides the window label; the peek folds the provider name into it.
    var title: Text? = nil
    var uppercase = false

    private var tier: LimitTier { LimitTier(fractionUsed: limit.fractionUsed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                (title ?? Text(limit.kind.label).foregroundStyle(UI.fg3))
                    .font(.system(size: 9, weight: uppercase ? .semibold : .regular))
                    .tracking(uppercase ? 0.5 : 0.1)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if limit.source == .localEstimate {
                    Text("est.")
                        .font(.system(size: 8))
                        .tracking(0.2)
                        .foregroundStyle(UI.fg4)
                }
                if tier != .ok, let reset = limit.resetsAt {
                    Text("resets \(Format.countdown(to: reset))")
                        .font(.system(size: 8))
                        .tracking(0.2)
                        .foregroundStyle(UI.fg3)
                        .lineLimit(1)
                }
                Text(Format.percent(limit.fractionUsed))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .frame(width: UI.numPct, alignment: .trailing)
                    .foregroundStyle(tier.color)
            }
            Meter(fraction: limit.fractionUsed, color: tier.color)
        }
    }
}

/// 3pt of capsule. Below 1% nothing is drawn at all, because the cap radius would make an empty
/// window look 5% used.
struct Meter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(UI.track)
                if fraction >= 0.01 {
                    // 6, not 3: at 3pt tall a 3pt floor is a perfect circle and reads as dust.
                    Capsule().fill(color.opacity(0.9))
                        .frame(width: max(6, geo.size.width * min(fraction, 1)))
                }
            }
        }
        .frame(height: 3)
    }
}

struct SessionRow: View {
    var session: AgentSession
    var parity: TokenParity
    var appearance: Appearance
    @State private var hovering = false

    private var canOpen: Bool { SessionLink.url(for: session) != nil }

    var body: some View {
        // The numbers hang off the title line, not the middle of the two-line stack.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // On the title line, not centred on the row: it belongs to the glyph beside it.
                    Circle()
                        .fill(session.state.color)
                        .frame(width: 5, height: 5)
                        .padding(.trailing, -3)
                        .accessibilityLabel(session.state.label)
                    ProviderGlyph(provider: session.provider, size: 10)
                        .frame(width: 13, alignment: .center)
                        .foregroundStyle(UI.fg3)
                    Text(session.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(UI.fg1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // 0, not 6: `metadata` brings its own leading separator, so the line is punctuated
                // the same way the peek punctuates it.
                HStack(spacing: 0) {
                    if let model = session.model {
                        ModelTag(model: model, appearance: appearance)
                    }
                    metadata
                        .font(.system(size: 9))
                        .tracking(0.1)
                        .foregroundStyle(UI.fg3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            // No unit label: the column identifies the field, as it already does in the peek.
            if let context = session.contextFraction {
                Text(Format.percent(context))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .frame(width: UI.numPct, alignment: .trailing)
                    .foregroundStyle(UI.context(context))
            }

            Text(Format.tokens(parity.count(session.tokens)))
                .font(.system(size: 9))
                .monospacedDigit()
                .frame(width: UI.numTokens, alignment: .trailing)
                .foregroundStyle(UI.fg3)

            Text(session.estCostUSD.map(Format.usd) ?? "—")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .frame(width: UI.numCost, alignment: .trailing)
                .foregroundStyle(UI.fg2)
        }
        .padding(.horizontal, 6)
        .frame(height: NotchViewModel.panelRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(hovering && canOpen ? UI.hoverPanel : .clear)
                .padding(.vertical, 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { session.open() }
    }

    /// The separators sit a tier below the words they divide; that alone stops the line reading as
    /// one joined string.
    private var metadata: Text {
        // The model has its own swatch and the state is already the dot — neither belongs here.
        let parts = [session.projectName, session.gitBranch, session.activity].compactMap { $0 }
        let lead = session.model != nil && !parts.isEmpty
            ? Text(" · ").foregroundStyle(UI.fg4) : Text("")
        return parts.dropFirst().reduce(lead + Text(parts.first ?? "")) { line, part in
            line + Text(" · ").foregroundStyle(UI.fg4) + Text(part)
        }
    }
}
