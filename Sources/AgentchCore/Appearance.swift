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

    /// Assigned to models nobody has picked a colour for. Eight that differ beats ten that collide:
    /// at least 35° apart, none inside the 20–50° wedge the warn/attention accents already own, and
    /// all in one mid-luminance band — a model is identity, never rank, so no swatch may outshine a
    /// row title.
    public static let palette = [
        "#6B8FD6", "#59A8CE", "#4FB09A", "#86AE58",
        "#C77BC0", "#A184D6", "#D66A7E", "#9AA0AC",
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
        // 33 ≡ 1 mod 8, so djb2's low bits are just a byte sum: every "claude-*-5" landed on one
        // colour. Finalise before taking the remainder.
        hash ^= hash >> 33
        hash = hash &* 0xff51_afd7_ed55_8ccd
        hash ^= hash >> 33
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
