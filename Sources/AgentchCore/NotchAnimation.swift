import Foundation

/// How the panel behaves when it opens and closes. The curves themselves live in the app layer;
/// this is just the choice and where it is remembered.
public enum NotchAnimation: String, CaseIterable, Sendable {
    /// Pinches at the top and sags along the bottom, content pouring in behind it.
    case liquid
    /// Quick and crisp, content straight away.
    case snap
    /// Unrolls downwards like a drawer.
    case unfold
    /// Overshoots and settles.
    case bounce
    /// Instant, no motion at all.
    case none

    public var label: String {
        switch self {
        case .liquid: "Liquid"
        case .snap: "Snap"
        case .unfold: "Unfold"
        case .bounce: "Bounce"
        case .none: "No animation"
        }
    }

    private static let defaultsKey = "notchAnimation"

    public static func load(_ defaults: UserDefaults = .standard) -> NotchAnimation {
        guard let raw = defaults.string(forKey: defaultsKey) else { return .liquid }
        return NotchAnimation(rawValue: raw) ?? .liquid
    }

    public func save(_ defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
