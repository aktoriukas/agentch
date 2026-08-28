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
