import Foundation

/// Tracks how fast a limit window is filling, so the UI can answer "will I run out before it
/// resets?" rather than only "how full is it now".
public struct BurnTracker: Sendable {
    public struct Sample: Sendable {
        public var at: Date
        public var fraction: Double
    }

    /// Samples per window id, oldest first.
    private var history: [String: [Sample]] = [:]

    /// Ignore samples closer together than this; consecutive polls are mostly noise.
    static let minimumSpacing: TimeInterval = 30
    /// A rate computed over less than this is too jumpy to project from.
    static let minimumSpan: TimeInterval = 5 * 60
    static let window: TimeInterval = 60 * 60

    public init() {}

    public mutating func record(_ limits: [LimitWindow], now: Date = Date()) {
        for limit in limits {
            var samples = history[limit.id] ?? []
            if let last = samples.last {
                // A window that reset went backwards; the old samples describe a different period.
                if limit.fractionUsed < last.fraction - 0.001 {
                    samples = []
                } else if now.timeIntervalSince(last.at) < Self.minimumSpacing {
                    continue
                }
            }
            samples.append(Sample(at: now, fraction: limit.fractionUsed))
            history[limit.id] = samples.filter { now.timeIntervalSince($0.at) <= Self.window }
        }
    }

    /// Fraction of the window consumed per hour, or nil while there is too little history.
    public func ratePerHour(for limit: LimitWindow, now: Date = Date()) -> Double? {
        guard let samples = history[limit.id], let first = samples.first, let last = samples.last else { return nil }
        let span = last.at.timeIntervalSince(first.at)
        guard span >= Self.minimumSpan else { return nil }
        let rate = (last.fraction - first.fraction) / (span / 3_600)
        return rate > 0 ? rate : nil
    }

    /// When the window would reach 100% at the current rate. nil when it will not get there
    /// before it resets anyway, which is the answer people actually want.
    public func projectedExhaustion(for limit: LimitWindow, now: Date = Date()) -> Date? {
        guard limit.fractionUsed < 1, let rate = ratePerHour(for: limit, now: now) else { return nil }
        let hoursLeft = (1 - limit.fractionUsed) / rate
        let eta = now.addingTimeInterval(hoursLeft * 3_600)
        if let reset = limit.resetsAt, eta >= reset { return nil }
        return eta
    }

    /// The window most at risk: soonest projected exhaustion.
    public func mostUrgent(among limits: [LimitWindow], now: Date = Date()) -> (LimitWindow, Date)? {
        limits.compactMap { limit in
            projectedExhaustion(for: limit, now: now).map { (limit, $0) }
        }
        .min { $0.1 < $1.1 }
    }
}
