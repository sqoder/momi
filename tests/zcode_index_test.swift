import Foundation

@main
struct ZCodeIndexTest {
    static func main() {
        let fixture = URL(fileURLWithPath: "tests/fixtures/zcode_rollout.jsonl")
        guard let data = try? Data(contentsOf: fixture),
              let text = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("FAIL: cannot read fixture\n".utf8)); exit(1)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count == 3 else {
            FileHandle.standardError.write(Data("FAIL: expected 3 lines\n".utf8)); exit(1)
        }

        // 1. cold index: 2 success + 1 error row
        let first = zcodeAccumulate(lines: lines)
        guard first.requests == 2 else { failIndex("requests \(first.requests)") }
        // success 1: 42409-64=42345; success 2: 537-410=127
        guard first.input == 42472 else { failIndex("input \(first.input)") }
        guard first.output == 568 else { failIndex("output \(first.output)") }
        guard first.cache == 474 else { failIndex("cache \(first.cache)") }

        // 2. error row alone contributes nothing
        let errorOnly = zcodeAccumulate(lines: [lines[2]])
        guard errorOnly.requests == 0 && errorOnly.output == 0 else { failIndex("error row counted") }

        // 3. offset replay: only bytes after a checkpoint produce no new rows
        let offset = UInt64(lines[0].utf8.count + lines[1].utf8.count + 2)
        let tail = Array(lines[2...])
        let replay = zcodeAccumulate(lines: tail)
        guard replay.requests == 0 else { failIndex("replay counted \(replay.requests)") }
        guard offset > 0 else { failIndex("offset") }

        // 4. day attribution comes from completedAt (local calendar day)
        guard let day = dayKeyForZcode("2026-11-07T15:50:12.732Z"), day == "2026-11-07" else {
            failIndex("dayKey \(dayKeyForZcode("2026-11-07T15:50:12.732Z") ?? "nil")")
        }

        // 5. model display name used for the row
        guard let r = parseZCodeRequest(line: lines[0]),
              zcodeModelDisplayName(for: r.model) == "GLM-5.3-Flash" else {
            failIndex("model display")
        }

        print("zcode index: 5/5 ok")
    }
}

func failIndex(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
    exit(1)
}
