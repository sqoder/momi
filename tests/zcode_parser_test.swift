import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
    exit(1)
}

func approx(_ a: Double, _ b: Double, _ epsilon: Double = 0.001) -> Bool {
    abs(a - b) < epsilon
}

@main
struct ZCodeParserTest {
    static func main() {
        let fixture = URL(fileURLWithPath: "tests/fixtures/zcode_rollout.jsonl")
        guard let text = try? String(contentsOf: fixture, encoding: .utf8) else {
            fail("cannot read fixture")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count == 3 else { fail("expected 3 fixture lines, got \(lines.count)") }

        // 1. success row parses every real-token field
        guard let success = parseZCodeRequest(line: lines[0]) else { fail("success row returned nil") }
        guard success.model == "GLM-5.3-Flash" else { fail("model: \(success.model)") }
        guard success.outputTokens == 450 else { fail("outputTokens: \(success.outputTokens)") }
        guard success.inputTokens == 42409 else { fail("inputTokens: \(success.inputTokens)") }
        guard success.cacheTokens == 64 else { fail("cacheTokens: \(success.cacheTokens)") }
        guard approx(success.duration, 18.546) else { fail("duration: \(success.duration)") }
        guard success.isSuccess else { fail("isSuccess false on success row") }
        guard success.completedAtRaw == "2026-11-07T15:50:12.732Z" else { fail("completedAtRaw: \(success.completedAtRaw ?? "nil")") }

        // 2. error row contributes nothing
        guard let failed = parseZCodeRequest(line: lines[2]) else { fail("error row returned nil") }
        guard !failed.isSuccess else { fail("error row marked success") }
        guard failed.outputTokens == 0 else { fail("error row outputTokens: \(failed.outputTokens)") }

        // 3. garbage line is rejected
        guard parseZCodeRequest(line: "not json"[...]) == nil else { fail("garbage row parsed") }

        // 4. inputTokens includes cache; fresh input must subtract it
        guard zcodeFreshInput(success) == 42345 else { fail("freshInput: \(zcodeFreshInput(success))") }

        // 5. missing durationMs falls back to completedAt - startedAt
        guard let noDuration = parseZCodeRequest(line: lines[1]) else { fail("no-duration row returned nil") }
        guard approx(noDuration.duration, 6.852) else { fail("fallback duration: \(noDuration.duration)") }

        // 6. model display name cleans the id
        guard zcodeModelDisplayName(for: "account:plan/GLM-5.3-Flash") == "GLM-5.3-Flash" else {
            fail("displayName: \(zcodeModelDisplayName(for: "account:plan/GLM-5.3-Flash"))")
        }

        print("zcode parser: 5/5 ok")
    }
}
