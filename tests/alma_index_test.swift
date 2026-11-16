import Foundation

// Verifies the accounting convention momi's UsageIndex applies to Alma rows:
// input_tokens already contains cached tokens, so fresh input = input - cache.
// Synthetic rows only; no real database and no usage.json writes.

func almaIndexRow(
    rowid: Int64, input: Int64, output: Int64,
    cached: Int64 = 0, cacheWrite: Int64 = 0,
    date: String = "2026-11-11"
) -> AlmaUsageRow {
    AlmaUsageRow(
        rowid: rowid, id: "u\(rowid)", model: "prov_demo:acme/demo-model", date: date,
        inputTokens: input, outputTokens: output, cachedInputTokens: cached,
        cacheWriteInputTokens: cacheWrite, reasoningTokens: 0,
        totalTokens: input + output, timestamp: "2026-11-11T07:19:48.436Z"
    )
}

var indexPassed = 0
func indexOK(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() {
        indexPassed += 1
    } else {
        fatalError("FAILED: \(label)")
    }
}

@main
struct AlmaIndexTest {
    static func main() {
        let batch1 = [
            almaIndexRow(rowid: 1, input: 19_036, output: 669, cached: 17_792),
            almaIndexRow(rowid: 2, input: 20_823, output: 120, cached: 20_480),
        ]
        let batch2 = [
            almaIndexRow(rowid: 3, input: 24_812, output: 581, cached: 24_384),
            almaIndexRow(rowid: 4, input: 0, output: 0),                       // failed request
            almaIndexRow(rowid: 5, input: 10_000, output: 500, cached: 2_000, cacheWrite: 1_000),
        ]

        let first = almaAccumulate(batch1)
        indexOK(first.input == 1_587, "cold index fresh input (1244 + 343)")
        indexOK(first.output == 789, "cold index output")
        indexOK(first.cache == 38_272, "cold index cache")
        indexOK(first.requests == 2, "cold index requests")

        let second = almaAccumulate(batch2)
        indexOK(second.input == 7_428, "delta fresh input (428 + 7000, failed row skipped)")
        indexOK(second.output == 1_081, "delta output")
        indexOK(second.cache == 27_384, "delta cache")
        indexOK(second.requests == 2, "failed request not counted")

        var grand = AlmaTotals()
        for t in [first, second] {
            grand.input += t.input
            grand.output += t.output
            grand.cache += t.cache
            grand.requests += t.requests
        }
        indexOK(grand.input == 9_015 && grand.output == 1_870 && grand.requests == 4,
                "grand totals equal sum of deltas")

        // Re-scanning from an advanced watermark must contribute exactly nothing.
        let watermark: Int64 = 5
        let replay = almaAccumulate((batch1 + batch2).filter { $0.rowid > watermark })
        indexOK(replay.requests == 0 && replay.output == 0 && replay.input == 0,
                "watermark replay contributes nothing")

        // A brand-new row beyond the watermark is picked up exactly once.
        let newRow = almaIndexRow(rowid: 6, input: 1_000, output: 42, cached: 900, date: "2026-11-12")
        let delta = almaAccumulate((batch1 + batch2 + [newRow]).filter { $0.rowid > watermark })
        indexOK(delta.requests == 1 && delta.output == 42 && delta.input == 100,
                "new row beyond watermark counted once")
        indexOK(almaModelDisplayName(for: newRow.model) == "demo-model", "indexed model name")
        indexOK(newRow.date == "2026-11-12", "indexed day uses row's own date")

        print("alma index: \(indexPassed)/\(indexPassed) ok")

    }
}
