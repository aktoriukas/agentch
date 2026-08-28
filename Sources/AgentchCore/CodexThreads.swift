import Foundation
import SQLite3

/// A row from Codex's thread catalogue. Rollout files carry the raw events; this carries the
/// human-readable name Codex generated for the thread, which is what the UI wants to show.
public struct CodexThread: Sendable {
    public var id: String
    public var rolloutPath: String?
    public var title: String?
    public var gitBranch: String?
    public var model: String?
    public var cwd: String?
    public var tokensUsed: Int
}

/// Reads `state_5.sqlite`. Codex keeps it in WAL mode and holds it open, so it is copied aside
/// before reading — opening the live file read-only fails, and writing to it is out of the question.
public enum CodexThreadStore {
    /// Keyed by thread id, plus an index by rollout filename for exact matching.
    public struct Catalog: Sendable {
        public var byID: [String: CodexThread] = [:]
        public var byRolloutName: [String: CodexThread] = [:]

        public func thread(id: String, rolloutName: String) -> CodexThread? {
            byRolloutName[rolloutName] ?? byID[id]
        }
    }

    static let databaseNames = ["state_5.sqlite", "state_4.sqlite", "state.sqlite"]

    public static func load(home: URL = Paths.codex) -> Catalog {
        guard let source = databaseNames
            .map({ home.appending(path: $0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else { return Catalog() }

        guard let scratch = copyAside(source) else { return Catalog() }
        defer { try? FileManager.default.removeItem(at: scratch) }
        return read(scratch.appending(path: source.lastPathComponent))
    }

    /// The -wal and -shm siblings must travel with the database or recent writes are invisible.
    private static func copyAside(_ source: URL) -> URL? {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "agentch-codex-\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil
        else { return nil }
        for suffix in ["", "-wal", "-shm"] {
            let sibling = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(atPath: sibling.path) else { continue }
            try? FileManager.default.copyItem(
                at: sibling,
                to: scratch.appending(path: source.lastPathComponent + suffix))
        }
        return scratch
    }

    private static func read(_ url: URL) -> Catalog {
        // Read-write on purpose: this is our own throwaway copy, and a WAL database needs to write
        // its -shm sidecar before it can be queried at all. The real database is never opened.
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return Catalog()
        }
        defer { sqlite3_close(db) }

        // Column set has drifted between CLI versions; ask for only what we use.
        let sql = """
            SELECT id, rollout_path, title, git_branch, model, cwd, tokens_used
            FROM threads ORDER BY recency_at_ms DESC LIMIT 200
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return Catalog() }
        defer { sqlite3_finalize(statement) }

        func text(_ index: Int32) -> String? {
            guard let raw = sqlite3_column_text(statement, index) else { return nil }
            let value = String(cString: raw)
            return value.isEmpty ? nil : value
        }

        var catalog = Catalog()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(0) else { continue }
            let thread = CodexThread(id: id,
                                     rolloutPath: text(1),
                                     title: text(2),
                                     gitBranch: text(3),
                                     model: text(4),
                                     cwd: text(5),
                                     tokensUsed: Int(sqlite3_column_int64(statement, 6)))
            catalog.byID[id] = thread
            if let path = thread.rolloutPath {
                catalog.byRolloutName[URL(fileURLWithPath: path).lastPathComponent] = thread
            }
        }
        return catalog
    }
}
