import Foundation
import SQLite3

// MARK: - Models

/// One row of Alma's `usage_records` table (already aggregated per request).
struct AlmaUsageRow {
    let rowid: Int64
    let id: String
    let model: String
    let date: String
    let inputTokens: Int64
    let outputTokens: Int64
    let cachedInputTokens: Int64
    let cacheWriteInputTokens: Int64
    let reasoningTokens: Int64
    let totalTokens: Int64
    let timestamp: String

    /// Failed / empty requests carry no usable tokens and must not be billed.
    var isValid: Bool { outputTokens > 0 || inputTokens > 0 }
}

struct AlmaTotals {
    var input: Int64 = 0
    var output: Int64 = 0
    var cache: Int64 = 0
    var requests: Int = 0
}

/// Live menu-bar state read straight from Alma's authoritative tables.
struct AlmaLiveSample {
    let messageId: String
    let speed: Double
    let outputTokens: Int64
    let model: String
    let isGenerating: Bool
    let timestamp: String
}

// MARK: - Pure helpers (shared with tests; no AppKit dependency)

let almaMaxSpeed: Double = 5_000

/// Alma's `input_tokens` already include cached input, so the cached portion
/// is subtracted to avoid double counting (same convention as Codex/ZCode).
func almaFreshInput(_ row: AlmaUsageRow) -> Int64 {
    max(0, row.inputTokens - row.cachedInputTokens - row.cacheWriteInputTokens)
}

func almaCacheTokens(_ row: AlmaUsageRow) -> Int64 {
    row.cachedInputTokens + row.cacheWriteInputTokens
}

func almaAccumulate(_ rows: [AlmaUsageRow]) -> AlmaTotals {
    var totals = AlmaTotals()
    for row in rows where row.isValid {
        totals.input += almaFreshInput(row)
        totals.output += row.outputTokens
        totals.cache += almaCacheTokens(row)
        totals.requests += 1
    }
    return totals
}

/// Server-reported throughput = real output tokens / real streaming seconds.
func almaSpeed(outputTokens: Int64, streamingDurationMs: Double) -> Double {
    guard streamingDurationMs > 0 else { return 0 }
    let seconds = streamingDurationMs / 1000
    guard seconds > 0 else { return 0 }
    let speed = Double(outputTokens) / seconds
    guard speed.isFinite, speed > 0 else { return 0 }
    return min(speed, almaMaxSpeed)
}

func almaModelDisplayName(for raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    for char in ["`", "\u{27}", "\"", "\\", "\n", "\r", "<", ">"] {
        if let idx = s.firstIndex(of: Character(char)) {
            s = String(s[..<idx])
        }
    }
    while s.hasSuffix(".") || s.hasSuffix(" ") {
        s = String(s.dropLast())
    }
    let tail = s.split(separator: "/").last.map(String.init) ?? s
    let cleaned = tail.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Alma" : cleaned
}

/// Parses `chat_messages.metadata` usage JSON. Falls back to the server's
/// `tokensPerSecond` field if the duration is missing.
func almaParseUsageSpeed(metadata: String) -> (speed: Double, outputTokens: Int64)? {
    guard let data = metadata.data(using: .utf8),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let usage = json["usage"] as? [String: Any] else { return nil }
    let output = (usage["outputTokens"] as? NSNumber)?.int64Value ?? 0
    let durationMs = (usage["streamingDurationMs"] as? NSNumber)?.doubleValue ?? 0
    let tps = (usage["tokensPerSecond"] as? NSNumber)?.doubleValue ?? 0
    var speed = almaSpeed(outputTokens: output, streamingDurationMs: durationMs)
    if speed == 0 && tps > 0 {
        speed = min(tps, almaMaxSpeed)
    }
    guard speed > 0 else { return nil }
    return (speed, output)
}

// MARK: - Read-only SQLite reader

final class AlmaReader {
    static func databaseURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("alma/chat_threads.db", isDirectory: false)
    }

    private var db: OpaquePointer?

    /// Opens the database read-only. `path` is injectable so tests can point at
    /// a synthetic database instead of the real one.
    init(path: String? = nil) {
        let target = path ?? AlmaReader.databaseURL().path
        guard sqlite3_open_v2(target, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let handle = db { sqlite3_close(handle) }
            db = nil
            return
        }
    }

    var isOpen: Bool { db != nil }

    deinit {
        if let handle = db { sqlite3_close(handle) }
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    private func queryInt(_ sql: String) -> Int64? {
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    private func queryRow(_ sql: String) -> [String]? {
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let count = sqlite3_column_count(stmt)
        var row: [String] = []
        for i in 0..<count {
            row.append(columnString(stmt, i))
        }
        return row
    }

    private func queryString(_ sql: String) -> String? {
        queryRow(sql)?.first
    }

    /// Incremental usage scan. rowid is monotonic for insert-only tables, so a
    /// watermark gives exactly-once accounting without byte offsets or mtimes.
    func usageRows(afterRowid watermark: Int64) -> [AlmaUsageRow] {
        guard let db = db else { return [] }
        let sql = """
            SELECT rowid, id, model, date, input_tokens, output_tokens,
                   cached_input_tokens, cache_write_input_tokens,
                   reasoning_tokens, total_tokens, timestamp
            FROM usage_records WHERE rowid > ? ORDER BY rowid ASC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, watermark)
        var rows: [AlmaUsageRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(AlmaUsageRow(
                rowid: sqlite3_column_int64(stmt, 0),
                id: columnString(stmt, 1),
                model: columnString(stmt, 2),
                date: columnString(stmt, 3),
                inputTokens: sqlite3_column_int64(stmt, 4),
                outputTokens: sqlite3_column_int64(stmt, 5),
                cachedInputTokens: sqlite3_column_int64(stmt, 6),
                cacheWriteInputTokens: sqlite3_column_int64(stmt, 7),
                reasoningTokens: sqlite3_column_int64(stmt, 8),
                totalTokens: sqlite3_column_int64(stmt, 9),
                timestamp: columnString(stmt, 10)
            ))
        }
        return rows
    }

    /// Latest completed turn's speed + whether any thread is still generating.
    /// Returns nil when Alma has no threads at all (nothing to show).
    func latestLiveSample() -> AlmaLiveSample? {
        guard db != nil else { return nil }
        guard let threadCount = queryInt("SELECT COUNT(*) FROM chat_threads"),
              threadCount > 0 else { return nil }

        let generating = (queryInt("SELECT COUNT(*) FROM chat_threads WHERE is_generating = 1") ?? 0) > 0

        var model = queryString("SELECT model FROM chat_threads WHERE is_generating = 1 ORDER BY updated_at DESC LIMIT 1") ?? ""
        if model.isEmpty {
            model = queryString("SELECT model FROM chat_threads ORDER BY updated_at DESC LIMIT 1") ?? ""
        }

        var messageId = ""
        var speed: Double = 0
        var outputTokens: Int64 = 0
        var timestamp = ""
        let usageSQL = "SELECT id, metadata, timestamp FROM chat_messages WHERE metadata LIKE '%\"usage\"%' ORDER BY timestamp DESC LIMIT 1"
        if let row = queryRow(usageSQL), row.count >= 3 {
            messageId = row[0]
            if let parsed = almaParseUsageSpeed(metadata: row[1]) {
                speed = parsed.speed
                outputTokens = parsed.outputTokens
            }
            timestamp = row[2]
        }

        return AlmaLiveSample(
            messageId: messageId,
            speed: speed,
            outputTokens: outputTokens,
            model: model,
            isGenerating: generating,
            timestamp: timestamp
        )
    }
}
