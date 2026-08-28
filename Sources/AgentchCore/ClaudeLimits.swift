import Foundation
import Security

/// Read-only access to Claude Code's OAuth token. agentch never writes it and never refreshes it:
/// refresh tokens are single-use, so redeeming one would sign the real CLI out.
enum ClaudeCredentials {
    /// The Keychain item Claude Code stores its OAuth token in.
    static let service = "Claude Code-credentials"

    struct Token {
        var accessToken: String
        var expiresAt: Date?
        var subscriptionType: String?
    }

    enum Failure: Error {
        /// No credentials anywhere — Claude Code has probably never signed in on this machine.
        case missing
        /// The item exists but this process may not read it (denied, or the ACL was rotated).
        case denied
        /// Present but holding something other than a Claude OAuth token.
        case unusable
    }

    static func load() -> Result<Token, Failure> {
        if let token = fromFile() { return .success(token) }
        return fromKeychain()
    }

    /// Linux-style credentials file; still present on some macOS installs.
    private static func fromFile() -> Token? {
        let url = Paths.claude.appending(path: ".credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    private static func fromKeychain() -> Result<Token, Failure> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data, let token = decode(data) else { return .failure(.unusable) }
            return .success(token)
        case errSecItemNotFound:
            return .failure(.missing)
        default:
            // Includes the user declining the access prompt.
            return .failure(.denied)
        }
    }

    private static func decode(_ data: Data) -> Token? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Claude Code 2.1.x sometimes stores only an unrelated `mcpOAuth` blob here.
        guard let oauth = root["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty
        else { return nil }
        let expiry = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1_000) }
        return Token(accessToken: accessToken,
                     expiresAt: expiry,
                     subscriptionType: oauth["subscriptionType"] as? String)
    }
}

/// Fetches subscription limits from the endpoint Claude Code itself uses. Undocumented and
/// unversioned, so every field is optional and every failure degrades to "no server limits".
public actor ClaudeUsageClient {
    public enum Outcome: Sendable, Equatable {
        case limits([LimitWindow])
        /// Reached the endpoint, but this account exposes no windows (enterprise seats do this).
        case noWindows
        case needsAuth
        case unavailable
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let beta = "oauth-2025-04-20"
    /// Anthropic rate-limits this endpoint hard; poll no faster than this.
    static let minimumInterval: TimeInterval = 300

    private var lastFetch = Date.distantPast
    private var blockedUntil = Date.distantPast
    private var cached: Outcome = .unavailable
    private var clientVersion = "2.1.0"

    public init() {}

    /// Reports the client version Claude Code is running, used for the request's user agent.
    public func setClientVersion(_ version: String?) {
        if let version, !version.isEmpty { clientVersion = version }
    }

    /// Returns cached limits unless the poll interval has elapsed. `force` bypasses the interval
    /// (for a manual refresh) but never a 429 backoff.
    public func limits(force: Bool = false, now: Date = Date()) async -> Outcome {
        guard now >= blockedUntil else { return cached }
        guard force || now.timeIntervalSince(lastFetch) >= Self.minimumInterval else { return cached }

        switch ClaudeCredentials.load() {
        case .failure(.missing), .failure(.unusable):
            cached = .needsAuth
            lastFetch = now
            return cached
        case .failure(.denied):
            cached = .unavailable
            lastFetch = now
            return cached
        case .success(let token):
            lastFetch = now
            cached = await fetch(token: token, now: now)
            return cached
        }
    }

    private func fetch(token: ClaudeCredentials.Token, now: Date) async -> Outcome {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.beta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/\(clientVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .unavailable }

        switch http.statusCode {
        case 200:
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unavailable
            }
            // The payload is unversioned and has changed shape before; this prints the raw
            // structure (usage numbers only, no credentials) when diagnosing drift.
            if ProcessInfo.processInfo.environment["AGENTCH_DEBUG_USAGE"] == "1" {
                print(String(data: data, encoding: .utf8) ?? "<undecodable>")
            }
            let windows = Self.parse(root, fetchedAt: now)
            return windows.isEmpty ? .noWindows : .limits(windows)
        case 401, 403:
            return .needsAuth
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init) ?? 300
            blockedUntil = now.addingTimeInterval(retryAfter)
            return cached
        default:
            return .unavailable
        }
    }

    /// Handles both shapes: the newer `limits` array with per-model scopes, and the older flat
    /// `five_hour`/`seven_day*` objects. Responses carry both and repeat the same windows, so the
    /// array wins when present. A null window means "not applicable", not zero.
    static func parse(_ root: [String: Any], fetchedAt: Date) -> [LimitWindow] {
        var windows: [LimitWindow] = []

        func add(_ kind: LimitWindow.Kind, _ entry: [String: Any]) {
            guard let utilization = CodexMonitor.number(entry["utilization"] ?? entry["percent"]) else { return }
            windows.append(LimitWindow(provider: .claude,
                                       kind: kind,
                                       // Reported as a percentage in both shapes.
                                       fractionUsed: utilization / 100,
                                       resetsAt: date(entry["resets_at"]),
                                       source: .server,
                                       fetchedAt: fetchedAt))
        }

        if let list = root["limits"] as? [[String: Any]], !list.isEmpty {
            for entry in list {
                // The newer payload calls the five-hour window a "session".
                let kind: LimitWindow.Kind = switch entry["kind"] as? String {
                case "session", "five_hour": .session5h
                case "weekly_all", "seven_day": .weekly
                default: .modelScoped(scopeLabel(entry) ?? "Weekly")
                }
                add(kind, entry)
            }
            return windows
        }

        if let five = root["five_hour"] as? [String: Any] { add(.session5h, five) }
        if let week = root["seven_day"] as? [String: Any] { add(.weekly, week) }
        for (key, label) in [("seven_day_opus", "Opus weekly"), ("seven_day_sonnet", "Sonnet weekly")] {
            if let entry = root[key] as? [String: Any] { add(.modelScoped(label), entry) }
        }
        return windows
    }

    private static func scopeLabel(_ entry: [String: Any]) -> String? {
        guard let scope = entry["scope"] as? [String: Any],
              let model = scope["model"] as? [String: Any],
              let name = model["display_name"] as? String else { return nil }
        return "\(name) weekly"
    }

    static func date(_ value: Any?) -> Date? {
        if let epoch = CodexMonitor.number(value) { return Date(timeIntervalSince1970: epoch) }
        guard let text = value as? String else { return nil }

        // Built per call: formatters are not Sendable, and this runs a handful of times per poll.
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainISO = ISO8601DateFormatter()

        if let parsed = fractionalISO.date(from: text) ?? plainISO.date(from: text) { return parsed }
        // Timestamps arrive with microsecond precision, which Foundation will not accept; keep
        // milliseconds and retry.
        guard let dot = text.firstIndex(of: "."),
              let fractionEnd = text[dot...].firstIndex(where: { $0 == "+" || $0 == "Z" || $0 == "-" })
        else { return nil }
        let trimmed = text[..<dot] + text[dot...][..<fractionEnd].prefix(4) + text[fractionEnd...]
        return fractionalISO.date(from: String(trimmed)) ?? plainISO.date(from: String(trimmed))
    }
}
