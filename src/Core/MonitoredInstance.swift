import Foundation

enum InstanceType {
    case antigravity
    case qoder
    case deepseek
    case pi
    case claude
    case codex
    case zcode
    case alma
}

struct MonitoredInstance {
    let name: String
    let shortTag: String
    let type: InstanceType
    let baseDir: URL
    var latestURL: URL?
    var latestModDate: Date = .distantPast
    var lastParsedModDate: Date = .distantPast
    var hasValidSession: Bool = false
    var isGenerating: Bool = false
    var currentSpeed: Double = 0.0
    var totalSessionTokens: Int = 0
    var lastTrackedFileSize: UInt64 = 0
    var modelName: String = "Antigravity"
    var antigravityLastStepIndex: Int = -1
    var claudeMessageLedger: [String: Int] = [:]
    var claudeRequestStartedAt: Date?
    var claudeToolInFlight: Bool = false
    var antigravityStepInFlight: Bool = false
    var codexFlavor: CodexFlavor = .cli
    var codexStepStartedAt: Date?
    var codexStepMeasuredByRecord: Bool = false
    var qoderRequestStartedAt: Date?
    var deepseekLastActivity: Date?
    var zcodeLastCompletedAt: Date?
    var almaLastMessageId: String?

    var defaultModelName: String {
        switch type {
        case .antigravity: return "Antigravity"
        case .qoder: return "Qoder"
        case .deepseek: return "DeepSeek Harness"
        case .pi: return "Pi"
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .zcode: return "ZCode"
        case .alma: return "Alma"
        }
    }

    var iconResourceName: String {
        switch type {
        case .qoder:
            return "agent_qoder"
        case .deepseek:
            return "agent_deepseek"
        case .pi:
            return "agent_pi"
        case .claude:
            return "agent_claude"
        case .codex:
            return codexFlavor == .desktop ? "agent_codex" : "agent_codex_cli"
        case .zcode:
            return "agent_zcode"
        case .alma:
            return "agent_alma"
        case .antigravity:
            return shortTag == "CLI" ? "agent_antigravity_cli" : "agent_antigravity"
        }
    }

    mutating func resetSessionState() {
        hasValidSession = false
        totalSessionTokens = 0
        lastTrackedFileSize = 0
        isGenerating = false
        currentSpeed = 0
        modelName = defaultModelName
        antigravityLastStepIndex = -1
        antigravityStepInFlight = false
        claudeMessageLedger.removeAll()
        claudeRequestStartedAt = nil
        claudeToolInFlight = false
        codexStepStartedAt = nil
        codexStepMeasuredByRecord = false
        qoderRequestStartedAt = nil
        deepseekLastActivity = nil
        zcodeLastCompletedAt = nil
        almaLastMessageId = nil
    }

    static func defaultInstances(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [MonitoredInstance] {
        [
            MonitoredInstance(
                name: "Antigravity Desktop",
                shortTag: "Desktop",
                type: .antigravity,
                baseDir: home.appendingPathComponent(".gemini/antigravity/brain")
            ),
            MonitoredInstance(
                name: "Antigravity CLI",
                shortTag: "CLI",
                type: .antigravity,
                baseDir: home.appendingPathComponent(".gemini/antigravity-cli/brain")
            ),
            MonitoredInstance(
                name: "Qoder",
                shortTag: "Qoder",
                type: .qoder,
                baseDir: home.appendingPathComponent(".qoder/projects"),
                modelName: "Qoder"
            ),
            MonitoredInstance(
                name: "DeepSeek Harness",
                shortTag: "DeepSeek",
                type: .deepseek,
                baseDir: home.appendingPathComponent(".dsh/storages/session_projcache/sessions"),
                modelName: "DeepSeek Harness"
            ),
            MonitoredInstance(
                name: "Pi",
                shortTag: "Pi",
                type: .pi,
                baseDir: home.appendingPathComponent(".pi/agent/sessions"),
                modelName: "Pi"
            ),
            MonitoredInstance(
                name: "Claude Code",
                shortTag: "Claude",
                type: .claude,
                baseDir: home.appendingPathComponent(".claude/projects"),
                modelName: "Claude"
            ),
            MonitoredInstance(
                name: "Codex App",
                shortTag: "App",
                type: .codex,
                baseDir: home.appendingPathComponent(".codex/sessions"),
                modelName: "Codex",
                codexFlavor: .desktop
            ),
            MonitoredInstance(
                name: "Codex CLI",
                shortTag: "CLI",
                type: .codex,
                baseDir: home.appendingPathComponent(".codex/sessions"),
                modelName: "Codex",
                codexFlavor: .cli
            ),
            MonitoredInstance(
                name: "ZCode",
                shortTag: "ZCode",
                type: .zcode,
                baseDir: home.appendingPathComponent(".zcode/cli/rollout"),
                modelName: "ZCode"
            ),
            MonitoredInstance(
                name: "Alma",
                shortTag: "Alma",
                type: .alma,
                baseDir: home.appendingPathComponent("Library/Application Support/alma"),
                modelName: "Alma"
            )
        ]
    }
}
