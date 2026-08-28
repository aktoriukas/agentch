import Foundation

/// Opt-in integration with Claude Code's hook system, so agentch can tell a session that is
/// waiting on you from one that is simply idle. Installing edits `~/.claude/settings.json`;
/// uninstalling removes exactly what was added.
public enum ClaudeHooks {
    public struct Event: Sendable {
        public var sessionId: String
        public var name: String
        public var message: String?
    }

    public static var eventsURL: URL { Paths.support.appending(path: "claude-events.jsonl") }

    static var settingsURL: URL { Paths.claude.appending(path: "settings.json") }

    /// Events we care about: one raises the flag, the other lowers it.
    static let raiseEvent = "Notification"
    static let clearEvent = "Stop"

    /// Strips newlines so each event lands on one line — JSON escapes real newlines inside
    /// strings, so only formatting whitespace is removed.
    static var command: String {
        "{ tr -d '\\n'; echo; } >> \"$HOME/Library/Application Support/agentch/claude-events.jsonl\""
    }

    /// How our entries are recognised for removal.
    static let marker = "claude-events.jsonl"

    public static func isInstalled() -> Bool {
        guard let hooks = readSettings()?["hooks"] as? [String: Any] else { return false }
        return [raiseEvent, clearEvent].allSatisfy { event in
            guard let groups = hooks[event] as? [[String: Any]] else { return false }
            return groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains {
                    ($0["command"] as? String)?.contains(marker) == true
                }
            }
        }
    }

    public static func install() throws {
        var settings = readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in [raiseEvent, clearEvent] {
            var groups = hooks[event] as? [[String: Any]] ?? []
            // Never add ours twice.
            groups.removeAll { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains {
                    ($0["command"] as? String)?.contains(marker) == true
                }
            }
            groups.append([
                "matcher": "",
                "hooks": [["type": "command", "command": command]],
            ])
            hooks[event] = groups
        }
        settings["hooks"] = hooks

        try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try write(settings)
    }

    public static func uninstall() throws {
        guard var settings = readSettings(),
              var hooks = settings["hooks"] as? [String: Any] else { return }

        for event in [raiseEvent, clearEvent] {
            guard var groups = hooks[event] as? [[String: Any]] else { continue }
            groups = groups.compactMap { group in
                var group = group
                let remaining = (group["hooks"] as? [[String: Any]] ?? []).filter {
                    ($0["command"] as? String)?.contains(marker) != true
                }
                // Drop groups that existed only for us; keep any the user added alongside.
                if remaining.isEmpty { return nil }
                group["hooks"] = remaining
                return group
            }
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        try write(settings)
    }

    /// Reads and clears the event log. Events are consumed once; callers keep the derived state.
    public static func drain() -> [Event] {
        guard let data = try? Data(contentsOf: eventsURL), !data.isEmpty else { return [] }
        try? Data().write(to: eventsURL, options: .atomic)

        return data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let sessionId = object["session_id"] as? String,
                  let name = object["hook_event_name"] as? String
            else { return nil }
            return Event(sessionId: sessionId, name: name, message: object["message"] as? String)
        }
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Backs the file up before every write, because this is the user's live configuration.
    private static func write(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        if let existing = try? Data(contentsOf: settingsURL) {
            try? existing.write(to: settingsURL.appendingPathExtension("agentch-backup"), options: .atomic)
        }
        try data.write(to: settingsURL, options: .atomic)
    }
}
