import Foundation

/// USD per million tokens, as published by models.dev.
public struct ModelPrice: Sendable, Codable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite: Double
    public var context: Int?

    public init(input: Double, output: Double, cacheRead: Double = 0, cacheWrite: Double = 0, context: Int? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.context = context
    }

    /// Subscription plans do not bill per token; this is what the same usage would cost at list price.
    public func cost(_ tokens: TokenTotals) -> Double {
        (Double(tokens.input) * input
            + Double(tokens.output) * output
            + Double(tokens.cacheRead) * cacheRead
            + Double(tokens.cacheWrite) * cacheWrite
            // A 1-hour cache write bills at twice the input rate.
            + Double(tokens.cacheWrite1h) * input * 2) / 1_000_000
    }
}

/// Prices for the first-party providers only. A model we cannot price shows no dollar figure
/// rather than a wrong one.
public struct PricingTable: Sendable, Codable {
    /// Keyed "openai/gpt-5.6-sol", "anthropic/claude-opus-5".
    public var models: [String: ModelPrice]
    public var fetchedAt: Date

    public init(models: [String: ModelPrice] = [:], fetchedAt: Date = .distantPast) {
        self.models = models
        self.fetchedAt = fetchedAt
    }

    public func price(provider: Provider, model: String?) -> ModelPrice? {
        guard let model, !model.isEmpty else { return nil }
        let vendor = provider == .claude ? "anthropic" : "openai"
        if let exact = models["\(vendor)/\(model)"] { return exact }
        // Dated or suffixed ids ("claude-opus-5-20260115") fall back to the longest matching base id.
        let prefix = "\(vendor)/"
        let candidate = models.keys
            .filter { $0.hasPrefix(prefix) && model.hasPrefix(String($0.dropFirst(prefix.count))) }
            .max(by: { $0.count < $1.count })
        return candidate.flatMap { models[$0] }
    }

    public func contextWindow(provider: Provider, model: String?) -> Int? {
        price(provider: provider, model: model)?.context
    }
}

public enum PricingLoader {
    static let catalogURL = URL(string: "https://models.dev/api.json")!
    static let maxAge: TimeInterval = 24 * 3_600

    public static var cacheURL: URL {
        Paths.support.appendingPathComponent("pricing.json")
    }

    /// Cached table, refreshed from models.dev at most once a day. Never throws: a stale or empty
    /// table just means costs render as "—".
    public static func load() async -> PricingTable {
        let cached = readCache()
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < maxAge { return cached }
        guard let fetched = await fetch() else { return cached ?? PricingTable() }
        writeCache(fetched)
        return fetched
    }

    private static func readCache() -> PricingTable? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(PricingTable.self, from: data)
    }

    private static func writeCache(_ table: PricingTable) {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(table) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// models.dev ships every reseller of every model; we keep only the two first-party vendors.
    private static func fetch() async -> PricingTable? {
        var request = URLRequest(url: catalogURL)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var models: [String: ModelPrice] = [:]
        for vendor in ["openai", "anthropic"] {
            guard let vendorEntry = root[vendor] as? [String: Any],
                  let vendorModels = vendorEntry["models"] as? [String: Any] else { continue }
            for (id, raw) in vendorModels {
                guard let entry = raw as? [String: Any],
                      let cost = entry["cost"] as? [String: Any],
                      let input = cost["input"] as? Double,
                      let output = cost["output"] as? Double
                else { continue }
                // ponytail: base tier only — OpenAI charges double above a 272k context. Add the
                // tier lookup if long-context turns start showing up meaningfully under-priced.
                models["\(vendor)/\(id)"] = ModelPrice(
                    input: input,
                    output: output,
                    cacheRead: cost["cache_read"] as? Double ?? 0,
                    cacheWrite: cost["cache_write"] as? Double ?? 0,
                    context: (entry["limit"] as? [String: Any])?["context"] as? Int
                )
            }
        }
        guard !models.isEmpty else { return nil }
        return PricingTable(models: models, fetchedAt: Date())
    }
}

public enum Paths {
    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }

    public static var support: URL {
        home.appending(path: "Library/Application Support/agentch")
    }

    public static var codex: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return home.appending(path: ".codex")
    }

    public static var claude: URL {
        home.appending(path: ".claude")
    }
}
