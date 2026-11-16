import Foundation

var corePassed = 0
func coreOK(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() {
        corePassed += 1
    } else {
        fatalError("FAILED: \(label)")
    }
}

@main
struct MomiCoreTest {
    static func main() {
        // 1. Speed clamping rejects NaN/Inf/negative and caps bursts
        coreOK(clampSpeed(Double.nan) == 0, "NaN clamps to 0")
        coreOK(clampSpeed(Double.infinity) == 0, "Inf clamps to 0")
        coreOK(clampSpeed(-12.5) == 0, "negative clamps to 0")
        coreOK(clampSpeed(88.4) == 88.4, "normal speed unchanged")
        coreOK(clampSpeed(9_999) == maxPlausibleSpeed, "burst clamped to maxPlausibleSpeed")

        // 2. extractModelName rejects USER_SETTINGS_CHANGE prose leakage
        let emptyChange = "<USER_SETTINGS_CHANGE> The user changed setting `Model Selection` from Gemini 3 to . No need to comment on this change. </USER_SETTINGS_CHANGE>"
        coreOK(extractModelName(from: emptyChange) == nil, "empty Model Selection ignores prose")

        let validChange = "<USER_SETTINGS_CHANGE> The user changed setting `Model Selection` from Argon to Gemini 4 Hydrogen (XHigh). No need to comment on this change. </USER_SETTINGS_CHANGE>"
        coreOK(extractModelName(from: validChange) == "Gemini 4 Hydrogen (XHigh)", "valid Model Selection extracts clean name")

        // 3. Gateway prefixes are stripped consistently
        coreOK(claudeModelDisplayName(for: "gateway-provider/custom-model") == "custom-model", "claude gateway prefix stripped")
        coreOK(claudeModelDisplayName(for: "claude-sonnet-4-6-20260101") == "Claude Sonnet 4.6", "claude family parsed")
        coreOK(codexModelDisplayName(for: "openai/gpt-5.4-codex") == "GPT-5.4-Codex", "codex model formatted")
        coreOK(deepseekModelDisplayName(for: "deepseek-reasoner") == "DeepSeek-Reasoner", "deepseek model formatted")

        // 4. Codex originator flavor routing
        coreOK(codexFlavor(forOriginator: "codex-desktop") == .desktop, "desktop originator")
        coreOK(codexFlavor(forOriginator: "codex-vscode") == .desktop, "vscode originator")
        coreOK(codexFlavor(forOriginator: "codex-tui") == .cli, "cli originator")
        coreOK(codexFlavor(forOriginator: nil) == .cli, "nil originator falls back to cli")

        print("momi core: \(corePassed)/\(corePassed) ok")
    }
}
