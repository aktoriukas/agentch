import Foundation

public enum Provider: String, Codable, Sendable, CaseIterable, Identifiable {
    case claude, codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

public enum SessionState: String, Codable, Sendable {
    /// Model is streaming right now.
    case working
    /// Alive but waiting on the human.
    case idle
    /// Blocked on a permission prompt or an explicit question.
    case needsAttention
    /// Process gone; kept briefly for context.
    case done
}

public struct TokenTotals: Codable, Sendable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    /// Cache writes with the default 5-minute lifetime.
    public var cacheWrite: Int
    /// Cache writes with a 1-hour lifetime, which bill at twice the input rate rather than the
    /// usual cache-write rate. Claude Code subscriptions use these heavily.
    public var cacheWrite1h: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0,
                cacheWrite: Int = 0, cacheWrite1h: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.cacheWrite1h = cacheWrite1h
    }

    /// Everything the provider billed for — matches ccusage totals.
    public var all: Int { input + output + cacheRead + cacheWrite + cacheWrite1h }

    /// Input + output only — matches what the web UIs report.
    public var conversational: Int { input + output }

    public static func + (a: TokenTotals, b: TokenTotals) -> TokenTotals {
        TokenTotals(input: a.input + b.input,
                    output: a.output + b.output,
                    cacheRead: a.cacheRead + b.cacheRead,
                    cacheWrite: a.cacheWrite + b.cacheWrite,
                    cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h)
    }

    public static func += (a: inout TokenTotals, b: TokenTotals) { a = a + b }
}

/// How token counts are presented. Providers bill on `.all`; other tools often show `.conversational`.
public enum TokenParity: String, Sendable, CaseIterable {
    case all, conversational

    public func count(_ t: TokenTotals) -> Int {
        switch self {
        case .all: t.all
        case .conversational: t.conversational
        }
    }
}

public struct AgentSession: Identifiable, Sendable, Equatable {
    public let id: String
    public let provider: Provider
    public var title: String
    public var cwd: String?
    public var gitBranch: String?
    public var model: String?
    public var state: SessionState
    /// What the agent is doing right now, when it publishes a task list ("Writing the parser").
    public var activity: String?
    public var tokens: TokenTotals
    /// nil when the model has no published price — better a dash than a wrong number.
    public var estCostUSD: Double?
    /// Fraction of the model's context window in use, 0...1.
    public var contextFraction: Double?
    public var lastActivity: Date

    public init(id: String, provider: Provider, title: String, cwd: String? = nil,
                gitBranch: String? = nil, model: String? = nil, state: SessionState,
                activity: String? = nil, tokens: TokenTotals = .init(), estCostUSD: Double? = nil,
                contextFraction: Double? = nil, lastActivity: Date) {
        self.id = id
        self.provider = provider
        self.title = title
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.model = model
        self.state = state
        self.activity = activity
        self.tokens = tokens
        self.estCostUSD = estCostUSD
        self.contextFraction = contextFraction
        self.lastActivity = lastActivity
    }

    /// Last path component of `cwd`, which is what people actually recognise.
    public var projectName: String? {
        cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
    }
}

public struct LimitWindow: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case session5h
        case weekly
        case modelScoped(String)

        public var label: String {
            switch self {
            case .session5h: "5-hour"
            case .weekly: "Weekly"
            case .modelScoped(let name): name
            }
        }
    }

    /// Server truth beats anything we derive locally, and the UI says which it is.
    public enum Source: String, Sendable {
        case server, localEstimate
    }

    public let provider: Provider
    public let kind: Kind
    /// 0...1.
    public var fractionUsed: Double
    public var resetsAt: Date?
    public var source: Source
    public var fetchedAt: Date

    public init(provider: Provider, kind: Kind, fractionUsed: Double,
                resetsAt: Date? = nil, source: Source, fetchedAt: Date) {
        self.provider = provider
        self.kind = kind
        self.fractionUsed = fractionUsed
        self.resetsAt = resetsAt
        self.source = source
        self.fetchedAt = fetchedAt
    }

    public var id: String { "\(provider.rawValue)-\(kind.label)" }
}

/// Ambient severity — drives the notch tint.
public enum LimitTier: Sendable {
    case ok, warn, critical

    public init(fractionUsed: Double) {
        switch fractionUsed {
        case ..<0.6: self = .ok
        case ..<0.85: self = .warn
        default: self = .critical
        }
    }
}
