import Foundation
import Darwin

/// An entry in `~/.claude/sessions`, one file per running CLI process.
struct ClaudeRegistryEntry: Sendable {
    var pid: Int32
    var sessionId: String
    var cwd: String?
    var name: String?
    var entrypoint: String?
}

/// Reads `~/.claude`. Unlike Codex, Claude publishes a registry of live processes, so "running"
/// is a fact here rather than an inference from file timestamps.
public actor ClaudeMonitor {
    /// Accumulated state for one transcript. Transcripts only ever grow, so each byte is parsed once.
    private struct Cursor {
        var offset: UInt64 = 0
        /// One API response is written across several lines as it streams, keyed by message and
        /// request id. Later lines supersede earlier ones, so usage is stored per message and
        /// folded on read rather than accumulated.
        var messages: [String: (model: String, tokens: TokenTotals)] = [:]
        var contextTokens: Int?

        var tokensByModel: [String: TokenTotals] {
            var totals: [String: TokenTotals] = [:]
            for (_, entry) in messages {
                totals[entry.model, default: TokenTotals()] += entry.tokens
            }
            return totals
        }

        var model: String?
        var title: String?
        var lastPrompt: String?
        var cwd: String?
        var gitBranch: String?
    }

    private let home: URL
    private var cursors: [URL: Cursor] = [:]
    /// Version of the Claude Code build on this machine, for the usage endpoint's user agent.
    public private(set) var clientVersion: String?
    /// Sessions that raised a hook notification and have not finished a turn since.
    private var awaitingUser: Set<String> = []

    private static let feedWindow: TimeInterval = 24 * 3_600
    private static let workingWindow: TimeInterval = 60

    public init(home: URL = Paths.claude) {
        self.home = home
    }

    public func scan(pricing: PricingTable, now: Date = Date()) -> ProviderScan {
        // Hook events are consumed once, so the flag is kept here rather than re-derived.
        for event in ClaudeHooks.drain() {
            if event.name == ClaudeHooks.raiseEvent {
                awaitingUser.insert(event.sessionId)
            } else {
                awaitingUser.remove(event.sessionId)
            }
        }

        let registry = liveRegistry()
        var subagentTokens: [String: [String: TokenTotals]] = [:]
        var mainFiles: [(url: URL, sessionId: String, modified: Date)] = []

        for file in transcripts(now: now) {
            let cursor = advance(file.url)
            if let parent = file.parentSessionID {
                // Subagent spend belongs to the session that spawned it.
                for (model, tokens) in cursor.tokensByModel {
                    subagentTokens[parent, default: [:]][model, default: TokenTotals()] += tokens
                }
            } else {
                mainFiles.append((file.url, file.sessionId, file.modified))
            }
        }

        var scan = ProviderScan()
        for file in mainFiles {
            guard let cursor = cursors[file.url] else { continue }

            var tokensByModel = cursor.tokensByModel
            for (model, tokens) in subagentTokens[file.sessionId] ?? [:] {
                tokensByModel[model, default: TokenTotals()] += tokens
            }

            var total = TokenTotals()
            var cost: Double?
            for (model, tokens) in tokensByModel {
                total += tokens
                if let price = pricing.price(provider: .claude, model: model) {
                    cost = (cost ?? 0) + price.cost(tokens)
                }
            }

            let live = registry[file.sessionId]
            let age = now.timeIntervalSince(file.modified)
            let window = pricing.contextWindow(provider: .claude, model: cursor.model)

            let state: SessionState = if live == nil {
                .done
            } else if awaitingUser.contains(file.sessionId) {
                .needsAttention
            } else if age < Self.workingWindow {
                .working
            } else {
                .idle
            }
            if live == nil { awaitingUser.remove(file.sessionId) }

            scan.sessions.append(AgentSession(
                id: file.sessionId,
                provider: .claude,
                title: cursor.title
                    ?? live?.name
                    ?? cursor.lastPrompt
                    ?? cursor.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "Claude session",
                cwd: cursor.cwd ?? live?.cwd,
                gitBranch: cursor.gitBranch == "HEAD" ? nil : cursor.gitBranch,
                model: cursor.model,
                linkID: file.sessionId,
                // The registry is the authority on whether the session still exists.
                state: state,
                activity: live == nil ? nil : currentTask(sessionId: file.sessionId),
                tokens: total,
                estCostUSD: cost,
                contextFraction: contextFraction(cursor, window: window),
                lastActivity: file.modified
            ))
        }
        return scan
    }

    private func contextFraction(_ cursor: Cursor, window: Int?) -> Double? {
        guard let window, window > 0, let used = cursor.contextTokens else { return nil }
        return min(Double(used) / Double(window), 1)
    }

    /// The in-progress entry from the session's task list, phrased as an activity by Claude Code
    /// itself ("Writing the parser").
    private func currentTask(sessionId: String) -> String? {
        let directory = home.appending(path: "tasks/\(sessionId)")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        for name in names.sorted() where name.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: directory.appending(path: name)),
                  let task = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  task["status"] as? String == "in_progress"
            else { continue }
            if let form = task["activeForm"] as? String ?? task["subject"] as? String {
                return Self.firstLine(form)
            }
        }
        return nil
    }

    /// Sessions whose process is still alive, keyed by session id.
    private func liveRegistry() -> [String: ClaudeRegistryEntry] {
        let directory = home.appending(path: "sessions")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [:] }

        var live: [String: ClaudeRegistryEntry] = [:]
        for name in names where name.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: directory.appending(path: name)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = object["pid"] as? Int32 ?? (object["pid"] as? Int).map(Int32.init),
                  let sessionId = object["sessionId"] as? String
            else { continue }
            // Registry files outlive their process; kill(0) is the cheap liveness probe.
            guard kill(pid, 0) == 0 || errno == EPERM else { continue }
            clientVersion = object["version"] as? String ?? clientVersion
            live[sessionId] = ClaudeRegistryEntry(pid: pid,
                                                  sessionId: sessionId,
                                                  cwd: object["cwd"] as? String,
                                                  name: object["name"] as? String,
                                                  entrypoint: object["entrypoint"] as? String)
        }
        return live
    }

    private struct TranscriptFile {
        var url: URL
        var sessionId: String
        var modified: Date
        /// Set when this is a subagent transcript, naming the session that spawned it.
        var parentSessionID: String?
    }

    private func transcripts(now: Date) -> [TranscriptFile] {
        let projects = home.appending(path: "projects")
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: projects,
                                                          includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return [] }

        var found: [TranscriptFile] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) < Self.feedWindow
            else { continue }

            // projects/<slug>/<sessionId>/subagents/agent-*.jsonl
            let isSubagent = url.deletingLastPathComponent().lastPathComponent == "subagents"
            let parent = isSubagent
                ? url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                : nil
            found.append(TranscriptFile(url: url,
                                        sessionId: parent ?? url.deletingPathExtension().lastPathComponent,
                                        modified: modified,
                                        parentSessionID: parent))
        }
        return found.sorted { $0.modified > $1.modified }
    }

    /// Reads whatever has been appended since the last pass and folds it into the cursor.
    @discardableResult
    private func advance(_ url: URL) -> Cursor {
        var cursor = cursors[url] ?? Cursor()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return cursor }
        defer { try? handle.close() }

        try? handle.seek(toOffset: cursor.offset)
        guard let fresh = try? handle.readToEnd(), !fresh.isEmpty else { return cursor }

        // A trailing partial line is left for the next pass.
        let newline = UInt8(ascii: "\n")
        guard let lastNewline = fresh.lastIndex(of: newline) else { return cursor }
        let complete = fresh[fresh.startIndex...lastNewline]
        cursor.offset += UInt64(complete.count)

        for line in complete.split(separator: newline, omittingEmptySubsequences: true) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            apply(object, to: &cursor)
        }
        cursors[url] = cursor
        return cursor
    }

    private func apply(_ object: [String: Any], to cursor: inout Cursor) {
        cursor.cwd = object["cwd"] as? String ?? cursor.cwd
        cursor.gitBranch = object["gitBranch"] as? String ?? cursor.gitBranch

        switch object["type"] as? String {
        case "custom-title":
            cursor.title = object["customTitle"] as? String ?? cursor.title
        case "ai-title":
            cursor.title = object["aiTitle"] as? String ?? cursor.title
        case "last-prompt":
            if let prompt = object["lastPrompt"] as? String {
                cursor.lastPrompt = Self.firstLine(prompt)
            }
        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return }
            let model = message["model"] as? String ?? "unknown"
            // Placeholder rows for errors and no-ops carry no real spend.
            guard model != "<synthetic>" else { return }

            let id = (message["id"] as? String ?? "") + "|" + (object["requestId"] as? String ?? "")
            guard id != "|" else { return }

            cursor.model = model
            let tokens = Self.tokens(from: usage)
            // Last write wins: the closing line for a message carries its complete usage.
            cursor.messages[id] = (model, tokens)
            // What the next request will carry: everything the model just read back.
            cursor.contextTokens = tokens.input + tokens.cacheRead + tokens.cacheWrite + tokens.cacheWrite1h
        default:
            return
        }
    }

    static func tokens(from usage: [String: Any]) -> TokenTotals {
        let creation = usage["cache_creation"] as? [String: Any]
        let oneHour = creation?["ephemeral_1h_input_tokens"] as? Int
        let fiveMinute = creation?["ephemeral_5m_input_tokens"] as? Int
        let totalCreation = usage["cache_creation_input_tokens"] as? Int ?? 0

        return TokenTotals(
            input: usage["input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0,
            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
            // Without the breakdown, assume the cheaper 5-minute lifetime.
            cacheWrite: fiveMinute ?? (oneHour == nil ? totalCreation : 0),
            cacheWrite1h: oneHour ?? 0)
    }

    static func firstLine(_ text: String, limit: Int = 64) -> String? {
        let line = text.split(separator: "\n", omittingEmptySubsequences: true).first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let line, !line.isEmpty else { return nil }
        guard line.count > limit else { return line }
        let clipped = line.prefix(limit)
        let atWord = clipped.lastIndex(of: " ").map { clipped[..<$0] } ?? clipped
        return atWord.trimmingCharacters(in: .whitespaces) + "…"
    }
}
