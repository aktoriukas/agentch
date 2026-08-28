import SwiftUI
import AgentchCore

// MARK: - Shape

/// Flush against the top screen edge, rounded along the bottom. `bulge` sags the bottom edge
/// mid-transition so the panel appears to pour out of the notch rather than snap open.
struct NotchShape: Shape {
    var cornerRadius: CGFloat = 13
    var bulge: CGFloat = 0

    var animatableData: CGFloat {
        get { bulge }
        set { bulge = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Rounder while it is moving; the corners tighten as the shape settles.
        let r = min(cornerRadius + bulge * 2, rect.height / 2, rect.width / 2)
        let sag = bulge * min(9, rect.height * 0.2)
        // Pinched at the top mid-transition, as though the panel is being drawn out of the notch.
        let pinch = bulge * min(7, rect.width * 0.03)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + pinch, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                          control: CGPoint(x: rect.minX + pinch * 0.25, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        // The sagging middle is what reads as liquid.
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                          control: CGPoint(x: rect.midX, y: rect.maxY + sag))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - pinch, y: rect.minY),
                          control: CGPoint(x: rect.maxX - pinch * 0.25, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Palette

extension LimitTier {
    var color: Color {
        switch self {
        case .ok: .green
        case .warn: .orange
        case .critical: .red
        }
    }
}

extension SessionState {
    var color: Color {
        switch self {
        case .working: .green
        case .needsAttention: .orange
        case .idle: .secondary
        case .done: .secondary.opacity(0.5)
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

extension Provider {
    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - Root

struct NotchRootView: View {
    var vm: NotchViewModel
    var state: AppState

    private var size: CGSize {
        vm.size(for: vm.stage, sessionCount: state.activeSessions.count)
    }

    private var motion: NotchMotion { state.animation.motion }

    var body: some View {
        VStack(spacing: 0) {
            content
                // Content arrives the way the chosen style says it should.
                .opacity(vm.contentVisible ? 1 : motion.hiddenOpacity)
                .blur(radius: vm.contentVisible ? 0 : motion.hiddenBlur)
                .scaleEffect(x: vm.contentVisible ? 1 : motion.hiddenScaleX,
                             y: vm.contentVisible ? 1 : motion.hiddenScaleY,
                             anchor: .top)
                .offset(y: vm.contentVisible ? 0 : motion.hiddenOffsetY)
                .frame(width: size.width, height: size.height)
                .background(NotchShape(bulge: vm.bulge).fill(.black))
                .clipShape(NotchShape(bulge: vm.bulge))
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
                     expand: { vm.setStage(.open, motion: motion) })
        case .open:
            PanelView(state: state, topInset: vm.closedSize.height,
                      collapse: { vm.setStage(.peek, motion: motion) })
        }
    }
}

// MARK: - Closed (ambient)

struct ClosedView: View {
    var vm: NotchViewModel
    var state: AppState

    private var tier: LimitTier { LimitTier(fractionUsed: state.worstLimitFraction) }

    var body: some View {
        if vm.isRealNotch {
            // The hardware cutout hides everything but the bottom sliver, so that is where the signal goes.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    if state.attentionCount > 0 {
                        Circle().fill(Color.orange).frame(width: 3, height: 3)
                    }
                    Capsule()
                        .fill(tier.color.opacity(state.workingCount > 0 ? 0.9 : 0.5))
                        .frame(width: 26, height: 2.5)
                }
                .padding(.bottom, 0.5)
            }
        } else {
            HStack(spacing: 5) {
                Circle()
                    .fill(state.attentionCount > 0 ? Color.orange : tier.color)
                    .frame(width: 5, height: 5)
                Text("\(state.activeSessions.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                Capsule()
                    .fill(tier.color.opacity(0.75))
                    .frame(width: 22, height: 2.5)
            }
            .padding(.horizontal, 10)
        }
    }
}

// MARK: - Peek: the session list

struct PeekView: View {
    var state: AppState
    var topInset: CGFloat = 24
    var expand: () -> Void

    private var sessions: [AgentSession] { state.activeSessions }
    private var shown: [AgentSession] { Array(sessions.prefix(NotchViewModel.peekRowLimit)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if sessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: NotchViewModel.peekRowHeight)
            }
            ForEach(shown) { session in
                CompactSessionRow(session: session, fields: state.hoverFields, parity: state.parity)
                    .frame(height: NotchViewModel.peekRowHeight)
            }
            if sessions.count > NotchViewModel.peekRowLimit {
                Text("+\(sessions.count - NotchViewModel.peekRowLimit) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(height: 16)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, topInset + 4)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: expand)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("\(sessions.count) active")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            if state.attentionCount > 0 {
                Circle().fill(Color.orange).frame(width: 4, height: 4)
                Text("\(state.attentionCount) waiting")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }
            Spacer()
            IconButton(symbol: "gearshape") { state.showMenu?() }
            IconButton(symbol: "chevron.down", action: expand)
        }
        .frame(height: NotchViewModel.peekHeaderHeight)
    }
}

/// One line per session: who it is and what it is doing, plus whichever numbers you asked for.
struct CompactSessionRow: View {
    var session: AgentSession
    var fields: HoverFields
    var parity: TokenParity

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(session.state.color)
                .frame(width: 5, height: 5)
            Image(systemName: session.provider.symbol)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.35))
            Text(session.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            if fields.contains(.project), let project = session.projectName {
                Text(project)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            if fields.contains(.model), let model = session.model {
                Text(model)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if fields.contains(.context), let context = session.contextFraction {
                Text(Format.percent(context))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(LimitTier(fractionUsed: context).color.opacity(0.85))
            }
            if fields.contains(.tokens) {
                Text(Format.tokens(parity.count(session.tokens)))
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.4))
            }
            if fields.contains(.cost) {
                Text(session.estCostUSD.map(Format.usd) ?? "—")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

struct IconButton: View {
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Panel: the breakdown

struct PanelView: View {
    var state: AppState
    var topInset: CGFloat = 24
    var collapse: () -> Void
    @State private var filter: Provider?

    private var visibleSessions: [AgentSession] {
        guard let filter else { return state.activeSessions }
        return state.activeSessions.filter { $0.provider == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            limitsRow
            Divider().overlay(.white.opacity(0.1))
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(visibleSessions) { session in
                        SessionRow(session: session, parity: state.parity)
                        Divider().overlay(.white.opacity(0.06))
                    }
                }
            }
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, topInset + 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            chip(title: "All", active: filter == nil) { filter = nil }
            ForEach(Provider.allCases) { provider in
                chip(title: provider.displayName, active: filter == provider) { filter = provider }
            }
            Spacer()
            if state.attentionCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                    Text("\(state.attentionCount) waiting")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            IconButton(symbol: "gearshape") { state.showMenu?() }
            IconButton(symbol: "chevron.up", action: collapse)
        }
    }

    private var limitsRow: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(Provider.allCases) { provider in
                let limits = state.limits(for: provider)
                if filter == nil || filter == provider, state.hasAnything(provider) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(provider.displayName.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                        if limits.isEmpty {
                            Text(state.notice(for: provider) ?? "No limits reported")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        HStack(spacing: 10) {
                            ForEach(limits) { LimitBar(limit: $0).frame(width: 96) }
                        }
                    }
                }
            }
        }
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(active ? .white.opacity(0.18) : .white.opacity(0.06)))
                .foregroundStyle(.white.opacity(active ? 0.95 : 0.55))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text("\(visibleSessions.count) sessions")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
            if let (limit, eta) = state.urgentProjection {
                Text("· \(limit.provider.displayName) \(limit.kind.label) full in \(Format.countdown(to: eta))")
                    .font(.system(size: 10))
                    .foregroundStyle(LimitTier(fractionUsed: limit.fractionUsed).color.opacity(0.9))
            }
            Spacer()
            Text("today ≈ \(Format.usd(state.todayEstCost)) est.")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

struct LimitBar: View {
    var limit: LimitWindow

    private var tier: LimitTier { LimitTier(fractionUsed: limit.fractionUsed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(limit.kind.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 2)
                Text(Format.percent(limit.fractionUsed))
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tier.color)
                if limit.source == .localEstimate {
                    Text("est.")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(tier.color)
                        .frame(width: max(2, geo.size.width * min(limit.fractionUsed, 1)))
                }
            }
            .frame(height: 3)
            if let reset = limit.resetsAt {
                Text("resets \(Format.countdown(to: reset))")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}

struct SessionRow: View {
    var session: AgentSession
    var parity: TokenParity

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.state.color)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: session.provider.symbol)
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(session.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let context = session.contextFraction {
                VStack(spacing: 2) {
                    Text(Format.percent(context))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(LimitTier(fractionUsed: context).color.opacity(0.9))
                    Text("ctx")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.estCostUSD.map(Format.usd) ?? "—")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                Text(Format.tokens(parity.count(session.tokens)))
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        // What it is doing beats what state it is in, when the session says.
        [session.projectName, session.gitBranch, session.model, session.activity ?? session.state.label]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
