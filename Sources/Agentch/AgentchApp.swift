import AppKit
import SwiftUI
import AgentchCore

@MainActor
@Observable
final class AppState {
    /// One scan per provider, replaced wholesale on each refresh.
    var scans: [Provider: ProviderScan] = [:]
    var parity: TokenParity = .all

    var sessions: [AgentSession] { Provider.allCases.flatMap { scans[$0]?.sessions ?? [] } }
    var limits: [LimitWindow] { Provider.allCases.flatMap { scans[$0]?.limits ?? [] } }

    var activeSessions: [AgentSession] {
        sessions.filter { $0.state != .done }.sorted { $0.lastActivity > $1.lastActivity }
    }

    var attentionCount: Int { sessions.filter { $0.state == .needsAttention }.count }
    var workingCount: Int { sessions.filter { $0.state == .working }.count }

    /// Drives the ambient tint: the closest any window is to its limit.
    var worstLimitFraction: Double { limits.map(\.fractionUsed).max() ?? 0 }

    func limits(for provider: Provider) -> [LimitWindow] {
        scans[provider]?.limits ?? []
    }

    func notice(for provider: Provider) -> String? {
        scans[provider]?.notice
    }

    /// A provider with neither limits nor sessions has nothing to say yet.
    func hasAnything(_ provider: Provider) -> Bool {
        !(scans[provider]?.limits.isEmpty ?? true) || !(scans[provider]?.sessions.isEmpty ?? true)
    }

    /// Sum across sessions still in the feed — not a true daily total until M2 adds day bucketing.
    var todayEstCost: Double { activeSessions.compactMap(\.estCostUSD).reduce(0, +) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var controllers: [NotchController] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let codex = CodexMonitor()
    private let claude = ClaudeMonitor()
    private let claudeUsage = ClaudeUsageClient()
    private var pricing = PricingTable()
    private var refreshTimer: Timer?
    /// A refresh can block on a Keychain prompt; without this, ticks pile up behind it.
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuildControllers()
        startRefreshing()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { _ in
            MainActor.assumeIsolated { AppDelegate.currentPointer(self) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            MainActor.assumeIsolated { AppDelegate.currentPointer(self) }
            return event
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.rebuildControllers() }
        }
    }

    /// ponytail: a 5s poll, cheap because rollout summaries are cached on (size, mtime) — most
    /// ticks are a handful of stat calls. Swap in FSEvents if the latency ever matters.
    private func startRefreshing() {
        Task { @MainActor in
            pricing = await PricingLoader.load()
            await refresh()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in await self.refresh() }
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let pricing = pricing
        // Independent readers; neither should wait on the other's file I/O.
        async let codexScan = codex.scan(pricing: pricing)
        async let claudeScan = claude.scan(pricing: pricing)
        state.scans[.codex] = await codexScan

        var scan = await claudeScan
        await claudeUsage.setClientVersion(await claude.clientVersion)
        // Unlike Codex, Claude publishes no limits locally; they come from its usage endpoint,
        // which self-throttles to one call per five minutes.
        switch await claudeUsage.limits() {
        case .limits(let windows):
            scan.limits = windows
        case .noWindows:
            scan.notice = "This account publishes no usage windows"
        case .needsAuth:
            scan.notice = "Sign in with Claude Code to show limits"
        case .unavailable:
            scan.notice = "Limits unavailable"
        }
        state.scans[.claude] = scan
    }

    private static func currentPointer(_ delegate: AppDelegate) {
        let point = NSEvent.mouseLocation
        for controller in delegate.controllers { controller.pointerMoved(to: point) }
    }

    /// Default: the main display plus a notched built-in, so the notch and pill paths both show up.
    /// ponytail: settings UI to pick displays lands in M5; override meanwhile with
    /// `defaults write com.agentch.app enabledDisplays -array-add <displayID>`.
    private func enabledScreens() -> [NSScreen] {
        let stored = UserDefaults.standard.array(forKey: "enabledDisplays") as? [NSNumber]
        if let stored, !stored.isEmpty {
            let wanted = Set(stored.map { CGDirectDisplayID($0.uint32Value) })
            let matches = NSScreen.screens.filter { wanted.contains($0.displayID) }
            if !matches.isEmpty { return matches }
        }
        var screens: [NSScreen] = []
        if let main = NSScreen.main { screens.append(main) }
        for screen in NSScreen.screens where screen.hasNotch && !screens.contains(screen) {
            screens.append(screen)
        }
        return screens
    }

    private func rebuildControllers() {
        controllers.forEach { $0.close() }
        controllers = enabledScreens().map { NotchController(screen: $0, state: state) }
    }
}

/// Fixed data for `--render`, so the stage PNGs stay comparable between runs.
extension AppState {
    func loadStubData() {
        let now = Date()
        let sessions: [AgentSession] = [
            AgentSession(id: "c1", provider: .claude, title: "Wire up the notch window",
                         cwd: "/Users/huy/Projects/personal/agentch", gitBranch: "main",
                         model: "claude-opus-5", state: .working,
                         tokens: TokenTotals(input: 4_200, output: 18_400, cacheRead: 812_000, cacheWrite: 96_000),
                         estCostUSD: 3.42, contextFraction: 0.38, lastActivity: now),
            AgentSession(id: "c2", provider: .claude, title: "Migrate billing tests",
                         cwd: "/Users/huy/Projects/work/folio", gitBranch: "fix/billing",
                         model: "claude-sonnet-5", state: .needsAttention,
                         tokens: TokenTotals(input: 1_100, output: 6_200, cacheRead: 240_000, cacheWrite: 31_000),
                         estCostUSD: 0.86, contextFraction: 0.71,
                         lastActivity: now.addingTimeInterval(-240)),
            AgentSession(id: "x1", provider: .codex, title: "Plan autonomous outreach",
                         cwd: "/Users/huy/Projects/personal/outreach", gitBranch: "main",
                         model: "gpt-5.6-sol", state: .working,
                         tokens: TokenTotals(input: 156_070, output: 341, cacheRead: 155_776),
                         estCostUSD: 1.27, contextFraction: 0.22,
                         lastActivity: now.addingTimeInterval(-45)),
            AgentSession(id: "c3", provider: .claude, title: "Draft release notes",
                         cwd: "/Users/huy/Projects/work/alchemy", gitBranch: "main",
                         model: "claude-sonnet-5", state: .idle,
                         tokens: TokenTotals(input: 800, output: 2_400, cacheRead: 44_000),
                         estCostUSD: 0.11, contextFraction: 0.09,
                         lastActivity: now.addingTimeInterval(-1_900)),
        ]
        let limits: [LimitWindow] = [
            LimitWindow(provider: .claude, kind: .session5h, fractionUsed: 0.62,
                        resetsAt: now.addingTimeInterval(3_600 * 2 + 840), source: .server, fetchedAt: now),
            LimitWindow(provider: .claude, kind: .weekly, fractionUsed: 0.41,
                        resetsAt: now.addingTimeInterval(3_600 * 52), source: .server, fetchedAt: now),
            LimitWindow(provider: .codex, kind: .session5h, fractionUsed: 0.05,
                        resetsAt: now.addingTimeInterval(3_600 * 4), source: .server, fetchedAt: now),
            LimitWindow(provider: .codex, kind: .weekly, fractionUsed: 0.01,
                        resetsAt: now.addingTimeInterval(3_600 * 120), source: .server, fetchedAt: now),
        ]
        for provider in Provider.allCases {
            scans[provider] = ProviderScan(sessions: sessions.filter { $0.provider == provider },
                                           limits: limits.filter { $0.provider == provider })
        }
    }
}

@main
@MainActor
struct AgentchMain {
    static func main() {
        if CommandLine.arguments.contains("--selfcheck") {
            exit(SelfCheck.run() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--render") {
            DevRender.writeStagePNGs()
            exit(0)
        }
        if CommandLine.arguments.contains("--dump") {
            let semaphore = DispatchSemaphore(value: 0)
            // Detached: a plain Task would inherit MainActor and deadlock against the wait below.
            Task.detached {
                await DevRender.dumpScan()
                semaphore.signal()
            }
            semaphore.wait()
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Agent app: no Dock icon, no menu bar of its own.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
