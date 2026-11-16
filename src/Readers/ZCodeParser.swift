import Foundation

struct ZCodeRequest {
    let model: String
    let outputTokens: Int64
    let inputTokens: Int64
    let cacheTokens: Int64
    let duration: TimeInterval
    let completedAtRaw: String?
    let isSuccess: Bool
}

private let zcodeFractionalFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let zcodePlainFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func zcodeDate(_ raw: String?) -> Date? {
    guard let raw = raw else { return nil }
    return zcodeFractionalFormatter.date(from: raw) ?? zcodePlainFormatter.date(from: raw)
}

func parseZCodeRequest(line: Substring) -> ZCodeRequest? {
    guard let data = String(line).data(using: .utf8),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          (json["type"] as? String) == "model_io",
          let response = json["response"] as? [String: Any] else { return nil }

    let modelDict = json["model"] as? [String: Any]
    let model = (modelDict?["modelId"] as? String) ?? ""
    let usage = response["usage"] as? [String: Any] ?? [:]
    let output = (usage["outputTokens"] as? NSNumber)?.int64Value ?? 0
    let input = (usage["inputTokens"] as? NSNumber)?.int64Value ?? 0
    let cache = ((usage["cacheReadTokens"] as? NSNumber)?.int64Value ?? 0)
        + ((usage["cacheWriteTokens"] as? NSNumber)?.int64Value ?? 0)

    let startedAtRaw = json["startedAt"] as? String
    let completedAtRaw = json["completedAt"] as? String
    let duration: TimeInterval
    if let ms = (json["durationMs"] as? NSNumber)?.doubleValue, ms > 0 {
        duration = ms / 1000
    } else if let start = zcodeDate(startedAtRaw), let end = zcodeDate(completedAtRaw) {
        duration = max(0, end.timeIntervalSince(start))
    } else {
        duration = 0
    }

    return ZCodeRequest(
        model: model,
        outputTokens: output,
        inputTokens: input,
        cacheTokens: cache,
        duration: duration,
        completedAtRaw: completedAtRaw,
        isSuccess: json["error"] == nil && output > 0
    )
}

func zcodeFreshInput(_ request: ZCodeRequest) -> Int64 {
    max(0, request.inputTokens - request.cacheTokens)
}

let zcodeMaxSpeed: Double = 5_000
let zcodeFreshnessWindow: TimeInterval = 5

/// Rollout rows are written on completion, so only a just-finished request counts as running.
func zcodeIsGenerating(lastCompletedAt: Date?, now: Date) -> Bool {
    guard let completed = lastCompletedAt else { return false }
    let age = now.timeIntervalSince(completed)
    return age >= 0 && age <= zcodeFreshnessWindow
}

func zcodeSpeed(_ request: ZCodeRequest) -> Double {
    guard request.isSuccess, request.duration > 0 else { return 0 }
    let speed = Double(request.outputTokens) / request.duration
    guard speed.isFinite, speed > 0 else { return 0 }
    return min(speed, zcodeMaxSpeed)
}

/// Speed/token state for one monitored ZCode session file.
struct ZCodeScanState {
    var totalTokens: Int = 0
    var currentSpeed: Double = 0
    var isGenerating: Bool = false
    var modelName: String = "ZCode"

    mutating func apply(lines: [Substring]) {
        for line in lines {
            guard let request = parseZCodeRequest(line: line), request.isSuccess else { continue }
            totalTokens += Int(request.outputTokens)
            modelName = zcodeModelDisplayName(for: request.model)
            isGenerating = true
            let speed = zcodeSpeed(request)
            if speed > 0 { currentSpeed = speed }
        }
    }

    mutating func resetForShrink() {
        totalTokens = 0
        currentSpeed = 0
        isGenerating = false
        modelName = "ZCode"
    }
}

struct ZCodeTotals {
    var input: Int64 = 0
    var output: Int64 = 0
    var cache: Int64 = 0
    var requests: Int = 0
}

/// Accumulates successful requests only; UsageIndex calls this per new byte range.
func zcodeAccumulate(lines: [Substring]) -> ZCodeTotals {
    var totals = ZCodeTotals()
    for line in lines {
        guard let request = parseZCodeRequest(line: line), request.isSuccess else { continue }
        totals.input += zcodeFreshInput(request)
        totals.output += request.outputTokens
        totals.cache += request.cacheTokens
        totals.requests += 1
    }
    return totals
}

func dayKeyForZcode(_ raw: String?) -> String? {
    guard let date = zcodeDate(raw) else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    return formatter.string(from: date)
}

func zcodeModelDisplayName(for raw: String) -> String {
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
    return cleaned.isEmpty ? "ZCode" : cleaned
}
