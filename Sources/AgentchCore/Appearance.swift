import Foundation

/// Colours for agents and models, so a session list can be read by colour rather than by reading.
/// Stored as hex strings; turning them into real colours is the app layer's job.
public struct Appearance: Codable, Sendable, Equatable {
    /// Keyed by `Provider.rawValue`.
    public var providers: [String: String]
    /// Keyed by model id.
    public var models: [String: String]

    public init(providers: [String: String] = [:], models: [String: String] = [:]) {
        self.providers = providers
        self.models = models
    }

    public static let defaultProviderColors: [String: String] = [
        Provider.claude.rawValue: "#D97757",
        Provider.codex.rawValue: "#10A37F",
    ]

    /// Assigned to models nobody has picked a colour for. Distinct hues that survive a dark
    /// background.
    public static let palette = [
        "#7AA2F7", "#BB9AF7", "#7DCFFF", "#9ECE6A", "#E0AF68",
        "#F7768E", "#2AC3DE", "#B4F9F8", "#C0CAF5", "#FF9E64",
    ]

    public func color(for provider: Provider) -> String {
        providers[provider.rawValue]
            ?? Self.defaultProviderColors[provider.rawValue]
            ?? Self.palette[0]
    }

    /// A model keeps the same colour between launches without anyone choosing one, because the
    /// fallback is derived from the name rather than from discovery order.
    public func color(forModel model: String) -> String {
        if let chosen = models[model] { return chosen }
        var hash: UInt64 = 5_381
        for byte in model.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Self.palette[Int(hash % UInt64(Self.palette.count))]
    }

    public func isCustom(model: String) -> Bool { models[model] != nil }

    public func isCustom(provider: Provider) -> Bool { providers[provider.rawValue] != nil }

    public mutating func set(_ hex: String?, for provider: Provider) {
        providers[provider.rawValue] = hex
    }

    public mutating func set(_ hex: String?, forModel model: String) {
        models[model] = hex
    }

    private static let defaultsKey = "appearance"

    public static func load(_ defaults: UserDefaults = .standard) -> Appearance {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Appearance.self, from: data)
        else { return Appearance() }
        return decoded
    }

    public func save(_ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Deep links that reopen a session in the app that owns it.
public enum SessionLink {
    /// Claude validates the id against a plain UUID before it will act on the link.
    static func isUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    /// Both apps register a URL scheme; these are the routes their own menus use.
    public static func url(for session: AgentSession) -> URL? {
        guard let id = session.linkID, !id.isEmpty else { return nil }
        switch session.provider {
        case .claude:
            // `resume` imports a CLI session by its transcript UUID. Not `code/continue`, which
            // only accepts "last" or the desktop app's own `local_`-prefixed session ids and
            // silently rejects anything else.
            guard isUUID(id) else { return nil }
            var components = URLComponents(string: "claude://resume")
            components?.queryItems = [URLQueryItem(name: "session", value: id)]
            return components?.url
        case .codex:
            return URL(string: "codex://threads/\(id)")
        }
    }
}
