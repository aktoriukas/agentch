import Foundation

/// One Codex rollout file, reduced to what the UI needs.
public struct RolloutSummary: Sendable {
    public var id: String
    public var cwd: String?
    public var model: String?
    public var title: String?
    public var tokens: TokenTotals
    public var contextWindow: Int?
    /// Input tokens on the most recent turn — what Codex itself treats as context in use.
    public var lastTurnInput: Int?
    public var rateLimits: CodexRateLimits?
    public var modifiedAt: Date
}

public struct CodexRateLimits: Sendable, Equatable {
    public struct Window: Sendable, Equatable {
        public var usedPercent: Double
        public var windowMinutes: Int
        public var resetsAt: Date?
    }

    public var primary: Window?
    public var secondary: Window?
    public var planType: String?
}

public struct ProviderScan: Sendable {
    public var sessions: [AgentSession]
    public var limits: [LimitWindow]
    /// Shown when limits are missing, explaining why rather than leaving a blank space.
    public var notice: String?

    public init(sessions: [AgentSession] = [], limits: [LimitWindow] = [], notice: String? = nil) {
        self.sessions = sessions
        self.limits = limits
        self.notice = notice
    }
}

/// Reads `~/.codex/sessions/**/*.jsonl`. Rollouts reach 10 MB+, so each file is sampled at both
/// ends rather than read whole: the head carries session metadata and the opening prompt, the tail
/// carries the latest model, token totals and rate-limit snapshot.
public actor CodexMonitor {
    private struct CacheEntry {
        var size: Int
        var modifiedAt: Date
        var summary: RolloutSummary
    }

    private let home: URL
    private let sessionsDirectory: URL
    private var cache: [URL: CacheEntry] = [:]
    private var catalog = CodexThreadStore.Catalog()
    private var catalogLoadedAt = Date.distantPast
    private static let catalogMaxAge: TimeInterval = 30

    private static let headBytes = 128 * 1024
    private static let tailBytes = 512 * 1024

    /// Sessions touched within this window appear in the feed at all.
    private static let feedWindow: TimeInterval = 24 * 3_600
    /// A rollout written this recently is mid-turn.
    private static let workingWindow: TimeInterval = 60
    /// ponytail: mtime only. Distinguishing "idle but alive" from "exited" needs lsof/pgrep per
    /// poll; add it if stale sessions in the feed become annoying.
    private static let idleWindow: TimeInterval = 2 * 3_600

    public init(home: URL = Paths.codex) {
        self.home = home
        sessionsDirectory = home.appending(path: "sessions")
    }

    public func scan(pricing: PricingTable, limit: Int = 12, now: Date = Date()) -> ProviderScan {
        if now.timeIntervalSince(catalogLoadedAt) > Self.catalogMaxAge {
            catalog = CodexThreadStore.load(home: home)
            catalogLoadedAt = now
        }

        let files = recentFiles(limit: limit, now: now)
        var scan = ProviderScan()

        for file in files {
            guard let summary = summary(for: file) else { continue }
            let age = now.timeIntervalSince(summary.modifiedAt)
            guard age < Self.feedWindow else { continue }

            // Codex names its own threads; that beats the opening prompt as a label.
            let thread = catalog.thread(id: summary.id, rolloutName: file.lastPathComponent)
            let model = summary.model ?? thread?.model
            let cwd = summary.cwd ?? thread?.cwd
            let window = summary.contextWindow ?? pricing.contextWindow(provider: .codex, model: model)
            scan.sessions.append(AgentSession(
                id: summary.id,
                provider: .codex,
                // Threads without a generated name store the whole opening message.
                title: thread?.title.flatMap { Self.title(from: $0) }
                    ?? summary.title
                    ?? cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "Codex session",
                cwd: cwd,
                gitBranch: thread?.gitBranch,
                model: model,
                // Codex opens threads by their catalogue id, not the rollout file name.
                linkID: thread?.id ?? summary.id,
                state: age < Self.workingWindow ? .working : (age < Self.idleWindow ? .idle : .done),
                tokens: summary.tokens,
                estCostUSD: pricing.price(provider: .codex, model: model)?.cost(summary.tokens),
                contextFraction: contextFraction(summary, window: window),
                lastActivity: summary.modifiedAt
            ))
        }

        // The most recently written rollout carries the current limits; older ones are stale.
        if let freshest = files.lazy.compactMap({ self.cache[$0]?.summary }).first(where: { $0.rateLimits != nil }),
           let limits = freshest.rateLimits {
            scan.limits = Self.limitWindows(limits, fetchedAt: freshest.modifiedAt)
        }
        return scan
    }

    private func contextFraction(_ summary: RolloutSummary, window: Int?) -> Double? {
        guard let window, window > 0, let used = summary.lastTurnInput else { return nil }
        return min(Double(used) / Double(window), 1)
    }

    static func limitWindows(_ limits: CodexRateLimits, fetchedAt: Date) -> [LimitWindow] {
        var windows: [LimitWindow] = []
        func append(_ window: CodexRateLimits.Window?, kind: LimitWindow.Kind) {
            guard let window else { return }
            windows.append(LimitWindow(provider: .codex,
                                       kind: kind,
                                       fractionUsed: window.usedPercent / 100,
                                       resetsAt: window.resetsAt,
                                       source: .server,
                                       fetchedAt: fetchedAt))
        }
        append(limits.primary, kind: .session5h)
        append(limits.secondary, kind: .weekly)
        return windows
    }

    /// Newest first.
    private func recentFiles(limit: Int, now: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: sessionsDirectory,
                                                          includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var candidates: [(URL, Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) < Self.feedWindow
            else { continue }
            candidates.append((url, modified))
        }
        return candidates.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private func summary(for url: URL) -> RolloutSummary? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let modified = values.contentModificationDate,
              let size = values.fileSize
        else { return nil }

        if let cached = cache[url], cached.size == size, cached.modifiedAt == modified {
            return cached.summary
        }
        guard var summary = Self.parse(url: url, size: size) else { return nil }
        summary.modifiedAt = modified
        cache[url] = CacheEntry(size: size, modifiedAt: modified, summary: summary)
        return summary
    }

    // MARK: - Parsing

    /// Files big enough to sample can hide their only token event in the middle; when the tail
    /// comes up empty we re-read the whole thing, up to a size worth spending the I/O on.
    private static let fullReadCap = 16 * 1024 * 1024

    static func parse(url: URL, size: Int) -> RolloutSummary? {
        var summary = parse(url: url, size: size, forceFullRead: false)
        if let current = summary, current.tokens.all == 0, size > headBytes + tailBytes, size <= fullReadCap {
            summary = parse(url: url, size: size, forceFullRead: true) ?? current
        }
        return summary
    }

    private static func parse(url: URL, size: Int, forceFullRead: Bool) -> RolloutSummary? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let headObjects: [[String: Any]]
        let tailObjects: [[String: Any]]
        if forceFullRead || size <= headBytes + tailBytes {
            // Small enough to read whole: both ends are the same set of lines.
            let all = jsonLines(in: (try? handle.readToEnd()) ?? Data())
            headObjects = all
            tailObjects = all
        } else {
            let head = (try? handle.read(upToCount: headBytes)) ?? Data()
            try? handle.seek(toOffset: UInt64(size - tailBytes))
            let tail = (try? handle.readToEnd()) ?? Data()
            headObjects = jsonLines(in: head, dropLast: true)
            tailObjects = jsonLines(in: tail, dropFirst: true)
        }

        var summary = RolloutSummary(id: url.deletingPathExtension().lastPathComponent,
                                     tokens: TokenTotals(),
                                     modifiedAt: .distantPast)

        // Head: the opening metadata and prompt.
        for object in headObjects {
            let payload = object["payload"] as? [String: Any] ?? [:]
            switch object["type"] as? String {
            case "session_meta":
                if let id = (payload["id"] ?? payload["session_id"]) as? String { summary.id = id }
                summary.cwd = payload["cwd"] as? String ?? summary.cwd
                summary.contextWindow = payload["context_window"] as? Int ?? summary.contextWindow
            case "event_msg" where payload["type"] as? String == "user_message":
                if summary.title == nil, let message = payload["message"] as? String {
                    summary.title = Self.title(from: message)
                }
            default:
                break
            }
        }

        // Tail: the latest state wins, so later lines overwrite earlier ones.
        for object in tailObjects {
            let payload = object["payload"] as? [String: Any] ?? [:]
            switch object["type"] as? String {
            case "turn_context":
                summary.model = payload["model"] as? String ?? summary.model
            case "event_msg" where payload["type"] as? String == "token_count":
                if let info = payload["info"] as? [String: Any] {
                    if let total = info["total_token_usage"] as? [String: Any] {
                        summary.tokens = Self.tokens(from: total)
                    }
                    if let last = info["last_token_usage"] as? [String: Any] {
                        summary.lastTurnInput = last["input_tokens"] as? Int
                    }
                    summary.contextWindow = info["model_context_window"] as? Int ?? summary.contextWindow
                }
                // Snapshots go missing on some events; the last non-null one still holds.
                if let limits = payload["rate_limits"] as? [String: Any],
                   let parsed = Self.rateLimits(from: limits) {
                    summary.rateLimits = parsed
                }
            default:
                break
            }
        }
        return summary
    }

    /// Codex reports `input_tokens` inclusive of the cached portion; the rest of the app treats
    /// them as separate buckets so cache reads can be priced at their own rate.
    static func tokens(from usage: [String: Any]) -> TokenTotals {
        let input = usage["input_tokens"] as? Int ?? 0
        let cached = usage["cached_input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        // Some sessions report an empty breakdown alongside a real total; counting zero would be a lie.
        if input == 0, output == 0, let total = usage["total_tokens"] as? Int, total > 0 {
            return TokenTotals(input: total)
        }
        return TokenTotals(input: max(input - cached, 0),
                           output: output,
                           cacheRead: cached,
                           cacheWrite: usage["cache_write_input_tokens"] as? Int ?? 0)
    }

    /// JSON numbers arrive as Int or Double depending on how they were written; accept both.
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: double
        case let int as Int: Double(int)
        case let number as NSNumber: number.doubleValue
        default: nil
        }
    }

    static func rateLimits(from raw: [String: Any]) -> CodexRateLimits? {
        func window(_ key: String) -> CodexRateLimits.Window? {
            guard let entry = raw[key] as? [String: Any],
                  let used = number(entry["used_percent"]) else { return nil }
            // Older CLI builds spelled the reset as a relative "resets_in_seconds".
            let resets: Date? = if let epoch = number(entry["resets_at"]) {
                Date(timeIntervalSince1970: epoch)
            } else if let seconds = number(entry["resets_in_seconds"]) {
                Date().addingTimeInterval(seconds)
            } else {
                nil
            }
            return CodexRateLimits.Window(usedPercent: used,
                                          windowMinutes: Int(number(entry["window_minutes"]) ?? 0),
                                          resetsAt: resets)
        }
        let primary = window("primary")
        let secondary = window("secondary")
        guard primary != nil || secondary != nil else { return nil }
        return CodexRateLimits(primary: primary, secondary: secondary, planType: raw["plan_type"] as? String)
    }

    /// First line of the opening prompt, trimmed to something that fits a row.
    static func title(from message: String, limit: Int = 64) -> String? {
        let firstLine = message
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let firstLine, !firstLine.isEmpty else { return nil }
        guard firstLine.count > limit else { return firstLine }
        let clipped = firstLine.prefix(limit)
        let atWord = clipped.lastIndex(of: " ").map { clipped[..<$0] } ?? clipped
        return atWord.trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func jsonLines(in data: Data, dropFirst: Bool = false, dropLast: Bool = false) -> [[String: Any]] {
        guard !data.isEmpty else { return [] }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if dropFirst, !lines.isEmpty { lines.removeFirst() }
        if dropLast, !lines.isEmpty { lines.removeLast() }
        return lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
    }
}
