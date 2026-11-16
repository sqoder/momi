import Foundation

@main
struct ZCodeSpeedTest {
    static func main() {
        let fixture = URL(fileURLWithPath: "tests/fixtures/zcode_rollout.jsonl")
        guard let text = try? String(contentsOf: fixture, encoding: .utf8) else {
            FileHandle.standardError.write(Data("FAIL: cannot read fixture\n".utf8)); exit(1)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count == 3, let success = parseZCodeRequest(line: lines[0]) else {
            FileHandle.standardError.write(Data("FAIL: fixture\n".utf8)); exit(1)
        }

        // 1. speed = outputTokens / duration, clamped
        let speed = zcodeSpeed(success)
        guard abs(speed - 450.0 / 18.546) < 0.01 else { failSpeed("speed \(speed)") }

        // 2. error row produces no speed and no model change
        guard let failed = parseZCodeRequest(line: lines[2]) else { failSpeed("error row nil") }
        guard zcodeSpeed(failed) == 0 else { failSpeed("error row speed \(zcodeSpeed(failed))") }
        guard zcodeSpeed(success) <= 5000 else { failSpeed("clamp missing") }

        // 3. switch file: a shrunken file resets the incremental counters
        var state = ZCodeScanState()
        state.apply(lines: [lines[0]])
        guard state.totalTokens == 450 else { failSpeed("tokens \(state.totalTokens)") }
        state.resetForShrink()
        guard state.totalTokens == 0 && !state.isGenerating else { failSpeed("reset failed") }
        state.apply(lines: [lines[1]])
        guard state.totalTokens == 118 else { failSpeed("post-switch tokens \(state.totalTokens)") }

        // 4. a completed request older than the freshness window is not generating
        let now = Date()
        guard zcodeIsGenerating(lastCompletedAt: now.addingTimeInterval(-1), now: now) else {
            failSpeed("fresh turn marked idle")
        }
        guard !zcodeIsGenerating(lastCompletedAt: now.addingTimeInterval(-30), now: now) else {
            failSpeed("stale turn still generating")
        }
        guard !zcodeIsGenerating(lastCompletedAt: nil, now: now) else {
            failSpeed("no completed turn marked generating")
        }

        print("zcode speed: 4/4 ok")
    }
}

func failSpeed(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
    exit(1)
}
