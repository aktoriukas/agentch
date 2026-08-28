import SwiftUI
import AgentchCore

// MARK: - Shape

/// Flush against the top screen edge, rounded along the bottom — the notch silhouette.
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
    @Bindable var vm: NotchViewModel
    var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(width: vm.currentSize.width, height: vm.currentSize.height)
                .background(NotchShape().fill(.black))
                .clipShape(NotchShape())
                .shadow(color: .black.opacity(vm.stage == .closed ? 0 : 0.45),
                        radius: vm.stage == .closed ? 0 : 18, y: 6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: vm.stage)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.stage {
        case .closed:
            ClosedView(vm: vm, state: state)
        case .peek:
            PeekView(state: state, topInset: vm.closedSize.height)
                .onTapGesture { vm.stage = .open }
        case .open:
            PanelView(state: state, topInset: vm.closedSize.height)
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

// MARK: - Peek

struct PeekView: View {
    var state: AppState
    /// Nothing drawn under the hardware cutout is visible, so content starts below it.
    var topInset: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(state.activeSessions.count) active")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Format.usd(state.todayEstCost)) est.")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }

            ForEach(Provider.allCases) { provider in
                let limits = state.limits(for: provider)
                if !limits.isEmpty {
                    HStack(spacing: 8) {
                        Text(provider.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 44, alignment: .leading)
                        ForEach(limits) { limit in
                            LimitBar(limit: limit)
                        }
                    }
                }
            }

            if state.attentionCount > 0 {
                HStack(spacing: 5) {
                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                    Text(attentionText)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, topInset + 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var attentionText: String {
        let waiting = state.sessions.filter { $0.state == .needsAttention }
        guard let first = waiting.first else { return "" }
        let name = first.projectName ?? first.title
        return waiting.count == 1 ? "\(name) is waiting on you" : "\(waiting.count) sessions waiting on you"
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

// MARK: - Panel

struct PanelView: View {
    var state: AppState
    var topInset: CGFloat = 24
    @State private var filter: Provider?

    private var visibleSessions: [AgentSession] {
        guard let filter else { return state.activeSessions }
        return state.activeSessions.filter { $0.provider == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(alignment: .top, spacing: 18) {
                ForEach(Provider.allCases) { provider in
                    let limits = state.limits(for: provider)
                    if !limits.isEmpty, filter == nil || filter == provider {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(provider.displayName.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                            HStack(spacing: 10) {
                                ForEach(limits) { LimitBar(limit: $0).frame(width: 96) }
                            }
                        }
                    }
                }
            }

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
        .padding(.top, topInset + 8)
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
            Spacer()
            Text("today ≈ \(Format.usd(state.todayEstCost)) est.")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
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
        [session.projectName, session.gitBranch, session.model, session.state.label]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
