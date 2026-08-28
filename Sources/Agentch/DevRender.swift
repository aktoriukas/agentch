import AppKit
import SwiftUI
import AgentchCore

/// Renders each stage offscreen to a PNG so the UI can be reviewed without Xcode previews
/// (and without granting screen-recording access just to look at a window).
/// Usage: `swift run Agentch --render` → /tmp/agentch-{closed-pill,closed-notch,peek,panel}.png
@MainActor
enum DevRender {
    static func writeStagePNGs() {
        let state = AppState()
        state.loadStubData()

        let pill = NotchViewModel(closedSize: CGSize(width: 190, height: 24), isRealNotch: false)
        let notch = NotchViewModel(closedSize: CGSize(width: 220, height: 41), isRealNotch: true)

        write(ClosedView(vm: pill, state: state), size: pill.closedSize, name: "closed-pill")
        write(ClosedView(vm: notch, state: state), size: notch.closedSize, name: "closed-notch")
        let count = state.activeSessions.count
        write(PeekView(state: state, topInset: pill.closedSize.height, expand: {}),
              size: pill.peekSize(sessionCount: count), name: "peek")
        // Worst case for the top inset: content must clear the 38pt hardware cutout.
        write(PeekView(state: state, topInset: notch.closedSize.height, expand: {}),
              size: notch.peekSize(sessionCount: count), name: "peek-notch")
        write(PanelView(state: state, collapse: {}), size: pill.openSize, name: "panel")

        // ScrollView renders blank under ImageRenderer, so check the rows on their own.
        let rows = VStack(spacing: 0) {
            ForEach(state.activeSessions) { session in
                SessionRow(session: session, parity: state.parity)
                Divider().overlay(.white.opacity(0.06))
            }
        }
        .padding(.horizontal, 16)
        write(rows, size: CGSize(width: 680, height: 220), name: "rows")

        // Each style caught mid-transition, since motion cannot be previewed any other way here.
        for style in NotchAnimation.allCases {
            writeRaw(midTransition(style, state: state, vm: pill), name: "style-\(style.rawValue)")
        }
    }

    /// The frame partway through opening. Only the frame differs per style now — the content
    /// reveal is shared — so that is all this compares.
    private static func midTransition(_ style: NotchAnimation, state: AppState, vm: NotchViewModel) -> some View {
        let bulge = style.motion.bulgeAmount * 0.7
        return PeekView(state: state, topInset: vm.closedSize.height, animates: false, expand: {})
            .frame(width: 470, height: vm.peekSize(sessionCount: state.activeSessions.count).height)
            .background(NotchShape(bulge: bulge).fill(.black))
            .clipShape(NotchShape(bulge: bulge))
            .padding(16)
            .background(Color(white: 0.28))
            .overlay(alignment: .bottom) {
                Text(style.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 2)
            }
    }

    private static func writeRaw(_ view: some View, name: String) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: "/tmp/agentch-\(name).png"))
    }

    /// Prints what the providers actually return, for checking against each vendor's own UI.
    nonisolated static func dumpScan() async {
        let pricing = await PricingLoader.load()
        print("pricing: \(pricing.models.count) models, fetched \(pricing.fetchedAt)")

        let catalog = CodexThreadStore.load()
        print("codex thread catalog: \(catalog.byRolloutName.count) rows")

        let codex = await CodexMonitor().scan(pricing: pricing, limit: 12)
        report("codex", codex)
        let monitor = ClaudeMonitor()
        var claude = await monitor.scan(pricing: pricing)
        let usage = ClaudeUsageClient()
        await usage.setClientVersion(await monitor.clientVersion)
        switch await usage.limits(force: true) {
        case .limits(let windows): claude.limits = windows
        case .noWindows: claude.notice = "account publishes no usage windows"
        case .needsAuth: claude.notice = "needs sign-in"
        case .unavailable: claude.notice = "unavailable"
        }
        report("claude", claude)
    }

    private nonisolated static func report(_ label: String, _ scan: ProviderScan) {
        print("\n== \(label) limits ==")
        if scan.limits.isEmpty { print("  (none) \(scan.notice.map { "— \($0)" } ?? "")") }
        for limit in scan.limits {
            let reset = limit.resetsAt.map { Format.countdown(to: $0) } ?? "?"
            print("  \(limit.kind.label): \(Format.percent(limit.fractionUsed)) used, resets in \(reset) [\(limit.source)]")
        }
        print("\n== \(label) sessions (\(scan.sessions.count)) ==")
        for session in scan.sessions.sorted(by: { $0.lastActivity > $1.lastActivity }) {
            let context = session.contextFraction.map { Format.percent($0) } ?? "—"
            print("  [\(session.state)] \(session.title)")
            print("      \(session.projectName ?? "?") · \(session.model ?? "?") · ctx \(context) · "
                  + "\(Format.tokens(session.tokens.all)) tok · \(session.estCostUSD.map(Format.usd) ?? "—") est")
            let t = session.tokens
            print("      raw: in=\(t.input) out=\(t.output) cacheRead=\(t.cacheRead) "
                  + "cacheWrite5m=\(t.cacheWrite) cacheWrite1h=\(t.cacheWrite1h) total=\(t.all)")
        }
    }

    private static func write(_ view: some View, size: CGSize, name: String) {
        let framed = view
            .frame(width: size.width, height: size.height)
            .background(NotchShape().fill(.black))
            .clipShape(NotchShape())
            // The notch is black-on-black; a grey mat shows where its edges actually fall.
            .padding(12)
            .background(Color(white: 0.28))
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            print("render failed: \(name)")
            return
        }
        let url = URL(fileURLWithPath: "/tmp/agentch-\(name).png")
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}
