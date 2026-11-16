import Foundation

enum UsagePeriod: Int, CaseIterable, Hashable {
    case all = 0
    case week = 1
    case today = 2
}

struct TokenUsage: Codable {
    var input: Int64 = 0
    var output: Int64 = 0
    var cache: Int64 = 0
    var requests: Int = 0
    var credits: Double = 0
    var contextPeak: Double = 0

    /// True when the harness billed the run in credits but never reported tokens.
    var hasTokens: Bool { input > 0 || output > 0 || cache > 0 }
    var isCreditsOnly: Bool { !hasTokens && credits > 0 }

    var total: Int64 { input + output }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case input, output, cache, requests, credits, contextPeak
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decodeIfPresent(Int64.self, forKey: .input) ?? 0
        output = try c.decodeIfPresent(Int64.self, forKey: .output) ?? 0
        cache = try c.decodeIfPresent(Int64.self, forKey: .cache) ?? 0
        requests = try c.decodeIfPresent(Int.self, forKey: .requests) ?? 0
        credits = try c.decodeIfPresent(Double.self, forKey: .credits) ?? 0
        contextPeak = try c.decodeIfPresent(Double.self, forKey: .contextPeak) ?? 0
    }

    mutating func add(input: Int64, output: Int64, cache: Int64, requests: Int, credits: Double, contextPeak: Double) {
        self.input += input
        self.output += output
        self.cache += cache
        self.requests += requests
        self.credits += credits
        self.contextPeak = max(self.contextPeak, contextPeak)
    }

    mutating func add(_ other: TokenUsage) {
        input += other.input
        output += other.output
        cache += other.cache
        requests += other.requests
        credits += other.credits
        contextPeak = max(contextPeak, other.contextPeak)
    }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        var result = lhs
        result.add(rhs)
        return result
    }
}

struct UsageRow {
    let name: String
    let usage: TokenUsage
    let iconName: String?
}

struct UsageDayPoint {
    let dateKey: String
    let label: String
    let usage: TokenUsage
    let isToday: Bool
}

struct UsagePeriodSnapshot {
    let total: TokenUsage
    let modelRows: [UsageRow]
    let agentRows: [UsageRow]
    let dailySeries: [UsageDayPoint]
}

struct UsageSnapshotBundle {
    let periods: [UsagePeriod: UsagePeriodSnapshot]
    let indexedAt: Date?
    let isIndexing: Bool
    let progress: Double
    let fileCount: Int
}

struct UsageFileCheckpoint: Codable {
    var size: UInt64 = 0
    var mtime: Double = 0
    var offset: UInt64 = 0
    var antigravityModel: String?
    var antigravityLastStep: Int?
    var claudeMessageId: String?
    var claudeInput: Int64 = 0
    var claudeOutput: Int64 = 0
    var claudeCache: Int64 = 0
    var qoderMessageId: String?
    var codexAgent: String?
    var codexModel: String?
    var codexInput: Int64 = 0
    var codexOutput: Int64 = 0
    var codexCache: Int64 = 0
    var deepseekInput: Int64 = 0
    var deepseekOutput: Int64 = 0
    var deepseekCache: Int64 = 0
    var deepseekSteps: Int64 = 0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case size, mtime, offset, antigravityModel, antigravityLastStep
        case claudeMessageId, claudeInput, claudeOutput, claudeCache, qoderMessageId
        case codexAgent, codexModel, codexInput, codexOutput, codexCache
        case deepseekInput, deepseekOutput, deepseekCache, deepseekSteps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(UInt64.self, forKey: .size) ?? 0
        mtime = try c.decodeIfPresent(Double.self, forKey: .mtime) ?? 0
        offset = try c.decodeIfPresent(UInt64.self, forKey: .offset) ?? 0
        antigravityModel = try c.decodeIfPresent(String.self, forKey: .antigravityModel)
        antigravityLastStep = try c.decodeIfPresent(Int.self, forKey: .antigravityLastStep)
        claudeMessageId = try c.decodeIfPresent(String.self, forKey: .claudeMessageId)
        claudeInput = try c.decodeIfPresent(Int64.self, forKey: .claudeInput) ?? 0
        claudeOutput = try c.decodeIfPresent(Int64.self, forKey: .claudeOutput) ?? 0
        claudeCache = try c.decodeIfPresent(Int64.self, forKey: .claudeCache) ?? 0
        qoderMessageId = try c.decodeIfPresent(String.self, forKey: .qoderMessageId)
        codexAgent = try c.decodeIfPresent(String.self, forKey: .codexAgent)
        codexModel = try c.decodeIfPresent(String.self, forKey: .codexModel)
        codexInput = try c.decodeIfPresent(Int64.self, forKey: .codexInput) ?? 0
        codexOutput = try c.decodeIfPresent(Int64.self, forKey: .codexOutput) ?? 0
        codexCache = try c.decodeIfPresent(Int64.self, forKey: .codexCache) ?? 0
        deepseekInput = try c.decodeIfPresent(Int64.self, forKey: .deepseekInput) ?? 0
        deepseekOutput = try c.decodeIfPresent(Int64.self, forKey: .deepseekOutput) ?? 0
        deepseekCache = try c.decodeIfPresent(Int64.self, forKey: .deepseekCache) ?? 0
        deepseekSteps = try c.decodeIfPresent(Int64.self, forKey: .deepseekSteps) ?? 0
    }
}

struct UsageStore: Codable {
    static let currentVersion = 3

    var version: Int = UsageStore.currentVersion
    var total = TokenUsage()
    var daily: [String: TokenUsage] = [:]
    var modelTotal: [String: TokenUsage] = [:]
    var modelDaily: [String: [String: TokenUsage]] = [:]
    var agentDaily: [String: [String: TokenUsage]] = [:]
    var files: [String: UsageFileCheckpoint] = [:]
    var indexedAt: Double = 0
    /// Highest `usage_records.rowid` already folded into the stats (Alma only).
    var almaWatermark: Int64 = 0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, total, daily, modelTotal, modelDaily, agentDaily, files, indexedAt, almaWatermark
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        total = try c.decodeIfPresent(TokenUsage.self, forKey: .total) ?? TokenUsage()
        daily = try c.decodeIfPresent([String: TokenUsage].self, forKey: .daily) ?? [:]
        modelTotal = try c.decodeIfPresent([String: TokenUsage].self, forKey: .modelTotal) ?? [:]
        modelDaily = try c.decodeIfPresent([String: [String: TokenUsage]].self, forKey: .modelDaily) ?? [:]
        agentDaily = try c.decodeIfPresent([String: [String: TokenUsage]].self, forKey: .agentDaily) ?? [:]
        files = try c.decodeIfPresent([String: UsageFileCheckpoint].self, forKey: .files) ?? [:]
        indexedAt = try c.decodeIfPresent(Double.self, forKey: .indexedAt) ?? 0
        almaWatermark = try c.decodeIfPresent(Int64.self, forKey: .almaWatermark) ?? 0
    }
}
