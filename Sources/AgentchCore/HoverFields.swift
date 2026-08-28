import Foundation

/// Which per-session details the hover view shows. The hover is the view people actually live
/// with, so what appears there is theirs to choose.
public struct HoverFields: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let project = HoverFields(rawValue: 1 << 0)
    public static let model = HoverFields(rawValue: 1 << 1)
    public static let context = HoverFields(rawValue: 1 << 2)
    public static let tokens = HoverFields(rawValue: 1 << 3)
    public static let cost = HoverFields(rawValue: 1 << 4)

    public static let standard: HoverFields = [.project, .context, .cost]

    /// Menu order, with the labels used in settings.
    public static let choices: [(field: HoverFields, label: String)] = [
        (.project, "Project"),
        (.model, "Model"),
        (.context, "Context used"),
        (.tokens, "Tokens"),
        (.cost, "Estimated cost"),
    ]

    private static let defaultsKey = "hoverFields"

    /// Persisted choice, falling back to the standard set when nothing has been chosen yet.
    public static func load(_ defaults: UserDefaults = .standard) -> HoverFields {
        guard defaults.object(forKey: defaultsKey) != nil else { return .standard }
        return HoverFields(rawValue: defaults.integer(forKey: defaultsKey))
    }

    public func save(_ defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
