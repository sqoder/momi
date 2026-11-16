import Foundation
import SQLite3

// Synthetic on-disk SQLite database that mirrors Alma's real schema. Tests never
// touch ~/Library/Application Support/alma/chat_threads.db.
final class AlmaTestDatabase {
    let path: String
    private var db: OpaquePointer?

    init() {
        path = NSTemporaryDirectory() + "momi_alma_test_\(UUID().uuidString).db"
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        exec("""
            CREATE TABLE usage_records (
                id TEXT PRIMARY KEY, message_id TEXT, thread_id TEXT, model TEXT,
                provider_id TEXT, date TEXT, input_tokens INTEGER, output_tokens INTEGER,
                cached_input_tokens INTEGER, cache_write_input_tokens INTEGER,
                reasoning_tokens INTEGER, total_tokens INTEGER, timestamp TEXT, created_at TEXT
            );
            CREATE TABLE chat_threads (
                id TEXT PRIMARY KEY, title TEXT, model TEXT, is_generating BOOLEAN,
                created_at TEXT, updated_at TEXT
            );
            CREATE TABLE chat_messages (
                id TEXT PRIMARY KEY, thread_id TEXT, message TEXT, timestamp TEXT, metadata TEXT
            );
            """)
    }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let err = err {
            fatalError("sqlite exec failed: \(String(cString: err))")
        }
    }

    func insertUsage(
        id: String, model: String = "prov_demo:acme/demo-model",
        date: String = "2026-11-11", input: Int64, output: Int64,
        cached: Int64 = 0, cacheWrite: Int64 = 0, reasoning: Int64 = 0,
        timestamp: String = "2026-11-11T07:19:48.436Z"
    ) {
        let esc = { (v: String) in v.replacingOccurrences(of: "'", with: "''") }
        exec("""
            INSERT INTO usage_records VALUES
            ('\(esc(id))','msg_\(esc(id))','thread_1','\(esc(model))','prov_1','\(esc(date))',
             \(input),\(output),\(cached),\(cacheWrite),\(reasoning),\(input + output),
             '\(esc(timestamp))','\(esc(timestamp))');
            """)
    }

    func insertThread(id: String, model: String, generating: Bool, updatedAt: String) {
        exec("INSERT INTO chat_threads VALUES ('\(id)','t','\(model)',\(generating ? 1 : 0),'\(updatedAt)','\(updatedAt)');")
    }

    func insertMessage(id: String, timestamp: String, metadata: String) {
        let esc = { (v: String) in v.replacingOccurrences(of: "'", with: "''") }
        exec("INSERT INTO chat_messages VALUES ('\(esc(id))','thread_1','','\(esc(timestamp))','\(esc(metadata))');")
    }

    func close() {
        if let db = db { sqlite3_close(db) }
        db = nil
        try? FileManager.default.removeItem(atPath: path)
    }
}

var passed = 0
func ok(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() {
        passed += 1
    } else {
        fatalError("FAILED: \(label)")
    }
}

@main
struct AlmaReaderTest {
    static func main() {
        // --- Pure helper assertions ---


        let sampleRow = AlmaUsageRow(
            rowid: 1, id: "u1", model: "prov_demo:acme/demo-model", date: "2026-11-11",
            inputTokens: 19_036, outputTokens: 669, cachedInputTokens: 17_792,
            cacheWriteInputTokens: 0, reasoningTokens: 543, totalTokens: 19_705,
            timestamp: "2026-11-11T07:19:48.436Z"
        )
        ok(almaFreshInput(sampleRow) == 1_244, "fresh input subtracts cached tokens")
        ok(almaCacheTokens(sampleRow) == 17_792, "cache = cached + cache write")

        let writeRow = AlmaUsageRow(
            rowid: 2, id: "u2", model: "prov_demo:acme/demo-model", date: "2026-11-11",
            inputTokens: 10_000, outputTokens: 500, cachedInputTokens: 2_000,
            cacheWriteInputTokens: 1_000, reasoningTokens: 50, totalTokens: 10_500,
            timestamp: "2026-11-11T07:20:00.000Z"
        )
        ok(almaFreshInput(writeRow) == 7_000, "fresh input subtracts cache write too")
        ok(almaCacheTokens(writeRow) == 3_000, "cache includes cache write")

        let emptyRow = AlmaUsageRow(
            rowid: 3, id: "u3", model: "", date: "2026-11-11",
            inputTokens: 0, outputTokens: 0, cachedInputTokens: 0,
            cacheWriteInputTokens: 0, reasoningTokens: 0, totalTokens: 0,
            timestamp: "2026-11-11T07:21:00.000Z"
        )
        ok(!emptyRow.isValid, "empty/failed row is skipped")

        let totals = almaAccumulate([sampleRow, writeRow, emptyRow])
        ok(totals.input == 8_244, "accumulated fresh input")
        ok(totals.output == 1_169, "accumulated output")
        ok(totals.cache == 20_792, "accumulated cache")
        ok(totals.requests == 2, "requests counts only valid rows")

        ok(almaSpeed(outputTokens: 581, streamingDurationMs: 59_377) > 9.7 &&
           almaSpeed(outputTokens: 581, streamingDurationMs: 59_377) < 9.9, "speed = output / seconds")
        ok(almaSpeed(outputTokens: 1_031, streamingDurationMs: 1_074) > 950, "short burst speed")
        ok(almaSpeed(outputTokens: 100, streamingDurationMs: 0) == 0, "zero duration gives no speed")
        ok(almaSpeed(outputTokens: 100_000, streamingDurationMs: 1) == almaMaxSpeed, "speed is clamped")

        ok(almaModelDisplayName(for: "prov_demo:acme/demo-model") == "demo-model", "model tail")
        ok(almaModelDisplayName(for: "") == "Alma", "empty model falls back to Alma")
        ok(almaModelDisplayName(for: "  plain-name  ") == "plain-name", "plain model name")

        let metadataOK = #"{"reasoningDuration":41.563,"usage":{"inputTokens":24812,"outputTokens":581,"totalTokens":25393,"reasoningTokens":482,"cachedInputTokens":24384,"timeToFirstTokenMs":13758,"streamingDurationMs":59377,"tokensPerSecond":9.78}}"#
        if let parsed = almaParseUsageSpeed(metadata: metadataOK) {
            ok(parsed.outputTokens == 581, "parsed output tokens")
            ok(parsed.speed > 9.7 && parsed.speed < 9.9, "parsed speed matches server value")
        } else {
            fatalError("FAILED: parse usage metadata")
        }
        ok(almaParseUsageSpeed(metadata: #"{"reasoningDuration":13.842}"#) == nil, "generating turn has no speed")
        ok(almaParseUsageSpeed(metadata: "not json") == nil, "bad metadata gives nil")

        let tpsFallback = #"{"usage":{"outputTokens":300,"tokensPerSecond":42.5}}"#
        if let parsed = almaParseUsageSpeed(metadata: tpsFallback) {
            ok(parsed.speed == 42.5, "fallback to server tokensPerSecond")
        } else {
            fatalError("FAILED: tps fallback")
        }

        // --- Reader assertions against synthetic DB ---

        let testDB = AlmaTestDatabase()
        testDB.insertUsage(id: "u1", input: 19_036, output: 669, cached: 17_792, reasoning: 543)
        testDB.insertUsage(id: "u2", input: 10_000, output: 500, cached: 2_000, cacheWrite: 1_000)
        testDB.insertUsage(id: "u3", input: 0, output: 0)   // failed request
        testDB.insertThread(id: "thread_1", model: "prov_demo:acme/demo-model", generating: true, updatedAt: "2026-11-11T07:19:36.861Z")
        testDB.insertMessage(id: "m_done", timestamp: "2026-11-11T07:19:48.436Z", metadata: metadataOK)
        testDB.insertMessage(id: "m_running", timestamp: "2026-11-11T07:20:00.000Z", metadata: #"{"reasoningDuration":13.842}"#)

        let reader = AlmaReader(path: testDB.path)
        ok(reader.isOpen, "reader opens synthetic db")

        let all = reader.usageRows(afterRowid: 0)
        ok(all.count == 3, "reads all usage rows")
        ok(all[0].model == "prov_demo:acme/demo-model", "model column")
        ok(all[0].date == "2026-11-11", "date column")
        ok(all[0].outputTokens == 669, "output column")
        ok(all[0].cachedInputTokens == 17_792, "cached column")

        let afterFirst = reader.usageRows(afterRowid: all[0].rowid)
        ok(afterFirst.count == 2, "watermark excludes already-seen rows")
        ok(reader.usageRows(afterRowid: all[2].rowid).isEmpty, "replay at max watermark adds nothing")

        let replay = almaAccumulate(reader.usageRows(afterRowid: all[2].rowid))
        ok(replay.requests == 0 && replay.output == 0, "incremental replay does not double count")

        if let live = reader.latestLiveSample() {
            ok(live.isGenerating == true, "is_generating read from chat_threads")
            ok(live.model == "prov_demo:acme/demo-model", "live model")
            ok(live.messageId == "m_done", "picks latest completed (usage-bearing) message")
            ok(live.speed > 9.7 && live.speed < 9.9, "live speed")
        } else {
            fatalError("FAILED: latestLiveSample returned nil")
        }

        testDB.close()

        let emptyDB = AlmaTestDatabase()
        let emptyReader = AlmaReader(path: emptyDB.path)
        ok(emptyReader.latestLiveSample() == nil, "no threads -> no live sample (row stays hidden)")
        emptyDB.close()

        let missingReader = AlmaReader(path: "/tmp/momi_alma_definitely_missing_\(UUID().uuidString).db")
        ok(!missingReader.isOpen, "missing db fails open gracefully")
        ok(missingReader.usageRows(afterRowid: 0).isEmpty, "missing db returns no rows")
        ok(missingReader.latestLiveSample() == nil, "missing db returns nil live sample")

        print("alma reader: \(passed)/\(passed) ok")

    }
}
