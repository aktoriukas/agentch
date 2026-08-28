import Foundation

/// Assert-based checks for the pure logic in this module. Run with `swift run Agentch --selfcheck`.
/// Stands in for a test target until the machine has a toolchain that ships one.
public enum SelfCheck {
    public static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: Bool, _ label: String) {
            if !condition { failures.append(label) }
        }

        // Token parity: providers bill everything, other tools often show input+output only.
        let t = TokenTotals(input: 100, output: 50, cacheRead: 900, cacheWrite: 200)
        expect(t.all == 1_250, "TokenTotals.all")
        expect(t.conversational == 150, "TokenTotals.conversational")
        expect(TokenParity.all.count(t) == 1_250, "TokenParity.all")
        expect(TokenParity.conversational.count(t) == 150, "TokenParity.conversational")
        var sum = t
        sum += TokenTotals(input: 1, output: 2, cacheRead: 3, cacheWrite: 4)
        expect(sum.all == 1_260, "TokenTotals +=")

        let now = Date()
        expect(Format.countdown(to: now.addingTimeInterval(3_600 * 2 + 840), from: now) == "2h 14m", "countdown h+m")
        expect(Format.countdown(to: now.addingTimeInterval(7_200), from: now) == "2h", "countdown whole hours")
        expect(Format.countdown(to: now.addingTimeInterval(540), from: now) == "9m", "countdown minutes")
        expect(Format.countdown(to: now.addingTimeInterval(30), from: now) == "<1m", "countdown seconds")
        expect(Format.countdown(to: now.addingTimeInterval(-60), from: now) == "now", "countdown elapsed")

        expect(Format.tokens(512) == "512", "tokens units")
        expect(Format.tokens(84_300) == "84.3k", "tokens thousands")
        expect(Format.tokens(1_250_000) == "1.2M", "tokens millions")
        expect(Format.usd(3.4159) == "$3.42", "usd rounding")
        expect(Format.usd(0.004) == "<$0.01", "usd sub-cent")
        expect(Format.usd(0) == "$0.00", "usd zero")
        expect(Format.percent(0.615) == "62%", "percent rounding")

        expect(LimitTier(fractionUsed: 0.59).isOK, "tier ok below 60%")
        expect(LimitTier(fractionUsed: 0.60).isWarn, "tier warn at 60%")
        expect(LimitTier(fractionUsed: 0.84).isWarn, "tier warn below 85%")
        expect(LimitTier(fractionUsed: 0.85).isCritical, "tier critical at 85%")

        // Notch geometry: centred on the screen's top edge, slop never reaching above it.
        let screen = CGRect(x: 0, y: 0, width: 3_440, height: 1_440)
        let rect = NotchGeometry.topCentered(size: CGSize(width: 200, height: 24), in: screen)
        expect(rect.midX == screen.midX, "topCentered midX")
        expect(rect.maxY == screen.maxY, "topCentered flush to top")
        let hover = NotchGeometry.hoverTarget(rect, slop: 4)
        expect(hover.maxY == rect.maxY, "hover slop stays below screen top")
        expect(hover.minY == rect.minY - 4, "hover slop extends downwards")
        expect(hover.width == rect.width + 8, "hover slop widens both sides")

        // Secondary displays sit at an offset in global coordinates.
        let external = CGRect(x: -1_920, y: 300, width: 1_920, height: 1_080)
        let offset = NotchGeometry.topCentered(size: CGSize(width: 190, height: 24), in: external)
        expect(offset.midX == -960, "offset screen midX")
        expect(offset.maxY == 1_380, "offset screen top edge")

        // Codex reports input_tokens inclusive of the cached portion.
        let usage: [String: Any] = ["input_tokens": 55_999_296, "cached_input_tokens": 54_606_976,
                                    "cache_write_input_tokens": 0, "output_tokens": 153_532,
                                    "total_tokens": 56_152_828]
        let parsed = CodexMonitor.tokens(from: usage)
        expect(parsed.input == 1_392_320, "codex input excludes cached")
        expect(parsed.cacheRead == 54_606_976, "codex cache read")
        expect(parsed.output == 153_532, "codex output")
        expect(parsed.all == 56_152_828, "codex totals reconcile")

        // Some sessions zero the breakdown but still report a total.
        let sparse = CodexMonitor.tokens(from: ["input_tokens": 0, "output_tokens": 0, "total_tokens": 3_739])
        expect(sparse.all == 3_739, "codex falls back to total_tokens")

        let limits = CodexMonitor.rateLimits(from: [
            "primary": ["used_percent": 5.0, "window_minutes": 300, "resets_at": 1_787_920_611.0],
            "secondary": ["used_percent": 1.0, "window_minutes": 10_080, "resets_at": 1_788_507_411.0],
            "plan_type": "plus",
        ])
        expect(limits?.primary?.usedPercent == 5.0, "codex primary window")
        expect(limits?.primary?.windowMinutes == 300, "codex 5-hour window length")
        expect(limits?.secondary?.windowMinutes == 10_080, "codex weekly window length")
        expect(limits?.planType == "plus", "codex plan type")
        expect(CodexMonitor.rateLimits(from: ["plan_type": "plus"]) == nil, "codex ignores empty snapshots")

        let windows = CodexMonitor.limitWindows(limits!, fetchedAt: now)
        expect(windows.count == 2, "codex yields both windows")
        expect(windows.first?.fractionUsed == 0.05, "percent converts to fraction")

        expect(CodexMonitor.title(from: "Fix the parser\nand then ship it") == "Fix the parser", "title takes first line")
        expect(CodexMonitor.title(from: String(repeating: "ab ", count: 40))?.hasSuffix("…") == true, "long titles clip")
        expect(CodexMonitor.title(from: "   ") == nil, "blank titles are dropped")

        // Pricing: exact ids win, dated variants fall back to their base id, unknowns stay unpriced.
        let table = PricingTable(models: [
            "openai/gpt-5.6-sol": ModelPrice(input: 4, output: 20, cacheRead: 0.4, cacheWrite: 5),
            "anthropic/claude-opus-5": ModelPrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25),
        ])
        expect(table.price(provider: .codex, model: "gpt-5.6-sol")?.output == 20, "exact price match")
        expect(table.price(provider: .claude, model: "claude-opus-5-20260115")?.input == 5, "dated id falls back")
        expect(table.price(provider: .codex, model: "gpt-9-imaginary") == nil, "unknown model has no price")
        expect(table.price(provider: .claude, model: nil) == nil, "missing model has no price")

        let cost = table.price(provider: .codex, model: "gpt-5.6-sol")!.cost(parsed)
        expect(abs(cost - 30.48) < 0.01, "codex session cost matches hand calculation")

        if failures.isEmpty {
            print("selfcheck: ok")
            return true
        }
        for failure in failures { print("selfcheck FAILED: \(failure)") }
        return false
    }
}

private extension LimitTier {
    var isOK: Bool { if case .ok = self { true } else { false } }
    var isWarn: Bool { if case .warn = self { true } else { false } }
    var isCritical: Bool { if case .critical = self { true } else { false } }
}
