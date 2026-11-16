import Foundation

// MARK: - Model Name & Agent Metadata Helpers

let maxPlausibleSpeed: Double = 5_000
let refreshIntervalDefaultsKey = "momi.refreshInterval"
let refreshIntervalOptions: [Double] = [1.5, 3.0, 5.0, 10.0]

let usageAgentOrder = [
    "antigravity-desktop",
    "antigravity-cli",
    "qoder",
    "deepseek",
    "pi",
    "claude",
    "codex-desktop",
    "codex-cli",
    "zcode",
    "alma"
]

func clampSpeed(_ speed: Double) -> Double {
    guard speed.isFinite, speed > 0 else { return 0 }
    return min(speed, maxPlausibleSpeed)
}

func currentStoredRefreshInterval() -> TimeInterval {
    let stored = UserDefaults.standard.double(forKey: refreshIntervalDefaultsKey)
    return stored >= 1 ? min(stored, 60) : 1.5
}

func sanitizeModelName(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    for char in ["`", "\u{27}", "\"", "\\", "\n", "\r", "<", ">"] {
        if let idx = s.firstIndex(of: Character(char)) {
            s = String(s[..<idx])
        }
    }
    while s.hasSuffix(".") || s.hasSuffix(" ") {
        s = String(s.dropLast())
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

func extractModelName(from content: String) -> String? {
    guard content.contains("Model Selection") else { return nil }
    let pattern = #"(?:setting\s+)?[`\x27]?Model Selection[`\x27]?\s+from\s+([^\n\r]+?)\s+to\s+([^\n\r]*?)(?:\.\s+(?:No need|If reporting)|</USER_SETTINGS_CHANGE>|\.\s*\n|\.\s*$|\n|$)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    let matches = regex.matches(in: content, options: [], range: range)
    for match in matches.reversed() {
        guard let modelRange = Range(match.range(at: 2), in: content) else { continue }
        let rawModel = String(content[modelRange])
        let cleaned = sanitizeModelName(rawModel)
        let lower = cleaned.lowercased()
        if !cleaned.isEmpty,
           !["none", "default", "null"].contains(lower),
           !lower.contains("no need to comment"),
           !lower.contains("if reporting"),
           !cleaned.contains("{"),
           !cleaned.contains("let ") {
            return cleaned
        }
    }
    return nil
}

func piModelDisplayName(for raw: String) -> String {
    let tail = raw.split(separator: "/").last.map(String.init) ?? raw
    let candidates = tail == raw ? [raw] : [raw, tail]
    let modelsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".pi/agent/models.json")

    if let data = try? Data(contentsOf: modelsURL),
       let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
       let providers = json["providers"] as? [String: Any] {
        for value in providers.values {
            guard let provider = value as? [String: Any],
                  let models = provider["models"] as? [[String: Any]] else { continue }
            for model in models {
                guard let modelID = model["id"] as? String, candidates.contains(modelID) else { continue }
                if let name = model["name"] as? String, !name.isEmpty {
                    let shortName = name.components(separatedBy: " · ").first ?? name
                    return sanitizeModelName(shortName)
                }
            }
        }
    }

    let clean = sanitizeModelName(tail)
    return clean.isEmpty ? "Pi" : qoderModelDisplayName(for: clean)
}

func claudeModelDisplayName(for raw: String) -> String {
    let clean = sanitizeModelName(raw)
    guard !clean.isEmpty else { return "Claude" }
    let lower = clean.lowercased()
    guard lower.contains("claude") else { return qoderModelDisplayName(for: clean) }

    var tokens = lower.split(separator: "-").map(String.init)
    tokens.removeAll { token in
        token == "claude" || (token.count == 8 && Int(token) != nil)
    }

    guard let familyIndex = tokens.firstIndex(where: { ["opus", "sonnet", "haiku"].contains($0) }) else {
        return clean
    }
    let family = tokens[familyIndex].capitalized
    let numbers = tokens.enumerated()
        .filter { $0.offset != familyIndex && Int($0.element) != nil }
        .map { $0.element }
    return numbers.isEmpty ? "Claude \(family)" : "Claude \(family) \(numbers.joined(separator: "."))"
}

func qoderModelDisplayName(for raw: String) -> String {
    let clean = sanitizeModelName(raw)
    guard !clean.isEmpty else { return "未知模型" }

    let tail = clean.split(separator: "/").last.map(String.init) ?? clean
    let candidates = tail == clean ? [clean] : [clean, tail]
    let dynamicTextsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".qoder/.auth/dynamic-texts.json")

    if let data = try? Data(contentsOf: dynamicTextsURL),
       let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
       let locales = json["locales"] as? [String: Any] {
        let localeDict = (locales["zh"] as? [String: Any]) ?? (locales["en"] as? [String: Any]) ?? [:]
        for candidate in candidates {
            if let name = localeDict["modelSelector.item.\(candidate)"] as? String, !name.isEmpty {
                return sanitizeModelName(name)
            }
        }
    }

    let formatted = sanitizeModelName(tail)
    return formatted.isEmpty ? "未知模型" : formatted
}

func codexModelDisplayName(for raw: String) -> String {
    let clean = sanitizeModelName(raw)
    guard !clean.isEmpty else { return "Codex" }
    let id = clean.split(separator: "/").last.map(String.init) ?? clean
    guard id.lowercased().hasPrefix("gpt-") else { return id }

    let tail = id.dropFirst(4).split(separator: "-").map { part -> String in
        if part.first?.isNumber == true { return String(part) }
        return part.prefix(1).uppercased() + part.dropFirst()
    }.joined(separator: "-")
    return "GPT-" + tail
}

func deepseekModelDisplayName(for raw: String) -> String {
    let clean = sanitizeModelName(raw)
    guard !clean.isEmpty else { return "DeepSeek" }
    let id = clean.split(separator: "/").last.map(String.init) ?? clean
    var parts = id.split(separator: "-").map { part -> String in
        guard let first = part.first else { return "" }
        return first.uppercased() + part.dropFirst()
    }
    if let first = parts.first, first.lowercased() == "deepseek" {
        parts[0] = "DeepSeek"
    }
    return parts.joined(separator: "-")
}

enum CodexFlavor: String {
    case desktop
    case cli

    var agentKey: String { self == .desktop ? "codex-desktop" : "codex-cli" }
}

func codexFlavor(forOriginator raw: String?) -> CodexFlavor {
    let value = (raw ?? "").lowercased()
    return value.contains("desktop") || value.contains("vscode") || value.contains("atlas") ? .desktop : .cli
}

func agentDisplayName(for key: String) -> String {
    switch key {
    case "antigravity-desktop": return "Antigravity Desktop"
    case "antigravity-cli": return "Antigravity CLI"
    case "qoder": return "Qoder"
    case "deepseek": return "DeepSeek Harness"
    case "pi": return "Pi"
    case "claude": return "Claude Code"
    case "codex-desktop": return "Codex App"
    case "codex-cli": return "Codex CLI"
    case "zcode": return "ZCode"
    case "alma": return "Alma"
    default: return key
    }
}

func agentIconName(for key: String) -> String? {
    switch key {
    case "antigravity-desktop": return "agent_antigravity"
    case "antigravity-cli": return "agent_antigravity_cli"
    case "qoder": return "agent_qoder"
    case "deepseek": return "agent_deepseek"
    case "pi": return "agent_pi"
    case "claude": return "agent_claude"
    case "codex-desktop": return "agent_codex"
    case "codex-cli": return "agent_codex_cli"
    case "zcode": return "agent_zcode"
    case "alma": return "agent_alma"
    default: return nil
    }
}
