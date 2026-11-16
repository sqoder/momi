import Foundation

// MARK: - Live Agent Monitor & Session Scanners

final class LiveMonitor {
    private var codexOriginatorCache: [String: String] = [:]
    private var codexLatestCache: [CodexFlavor: (url: URL, modDate: Date)] = [:]
    private var codexDiscoveryAt = Date.distantPast

    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func resetCaches() {
        codexOriginatorCache.removeAll()
        codexLatestCache.removeAll()
        codexDiscoveryAt = .distantPast
    }

    func scan(instances snapshot: [MonitoredInstance], now: Date = Date()) -> (instances: [MonitoredInstance], hasChanges: Bool) {
        var updated = snapshot
        var hasChanges = false

        for i in 0..<updated.count {
            if updated[i].type == .alma {
                updateAlmaSessionState(now: now, instance: &updated[i], hasChanges: &hasChanges)
                continue
            }

            guard let latest = fastFindLatestTranscript(for: updated[i]) else {
                if updated[i].latestURL != nil || updated[i].hasValidSession {
                    updated[i].latestURL = nil
                    updated[i].lastParsedModDate = .distantPast
                    updated[i].latestModDate = .distantPast
                    updated[i].resetSessionState()
                    hasChanges = true
                }
                continue
            }

            if updated[i].latestURL != latest.url {
                updated[i].latestURL = latest.url
                updated[i].lastParsedModDate = .distantPast
                updated[i].resetSessionState()
                hasChanges = true
            }

            updated[i].latestModDate = latest.modDate

            if latest.modDate != updated[i].lastParsedModDate {
                updated[i].lastParsedModDate = latest.modDate
                updateSessionTokens(url: latest.url, modDate: latest.modDate, instance: &updated[i])
                if updated[i].type == .antigravity {
                    updateAntigravitySpeedFromTail(url: latest.url, fileModDate: latest.modDate, now: now, instance: &updated[i])
                }
                hasChanges = true
            }

            if updated[i].type == .antigravity {
                let fresh = now.timeIntervalSince(latest.modDate) < 2.5
                let stale = now.timeIntervalSince(latest.modDate) > 900
                let generating = !stale && (updated[i].antigravityStepInFlight || fresh)
                if generating != updated[i].isGenerating {
                    updated[i].isGenerating = generating
                    hasChanges = true
                }
            }

            let claudeSilence = updated[i].claudeToolInFlight ? 1800.0 : 600.0
            if updated[i].type == .claude,
               updated[i].isGenerating,
               now.timeIntervalSince(latest.modDate) > claudeSilence {
                updated[i].isGenerating = false
                hasChanges = true
            }

            if updated[i].type == .zcode {
                let generating = zcodeIsGenerating(
                    lastCompletedAt: updated[i].zcodeLastCompletedAt,
                    now: now
                )
                if generating != updated[i].isGenerating {
                    updated[i].isGenerating = generating
                    hasChanges = true
                }
            }

            let silentSince = updated[i].type == .deepseek
                ? (updated[i].deepseekLastActivity ?? latest.modDate)
                : latest.modDate
            if [.qoder, .pi, .codex, .deepseek, .zcode].contains(updated[i].type),
               updated[i].isGenerating,
               now.timeIntervalSince(silentSince) > 900 {
                updated[i].isGenerating = false
                hasChanges = true
            }
        }

        return (updated, hasChanges)
    }

    private func parseISODate(_ value: Any?) -> Date? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    // MARK: - Transcript Discovery

    private func fastFindLatestTranscript(for instance: MonitoredInstance) -> (url: URL, modDate: Date)? {
        switch instance.type {
        case .antigravity:
            return fastFindLatestAntigravityTranscript(in: instance.baseDir)
        case .qoder, .pi, .claude:
            return fastFindLatestJSONLInSubdirs(in: instance.baseDir)
        case .deepseek:
            return fastFindLatestFlatFile(in: instance.baseDir) { $0.pathExtension == "json" }
        case .codex:
            return fastFindLatestCodexTranscript(in: instance.baseDir, flavor: instance.codexFlavor)
        case .zcode:
            return fastFindLatestFlatFile(in: instance.baseDir) {
                $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("model-io-")
            }
        case .alma:
            return nil
        }
    }

    private func fastFindLatestAntigravityTranscript(in brainDir: URL) -> (url: URL, modDate: Date)? {
        guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
            at: brainDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return nil }

        var latestFile: URL?
        var latestDate: Date = .distantPast
        for dir in sessionDirs {
            let transcript = dir.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            if let attrs = try? transcript.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
               (attrs.fileSize ?? 0) > 0,
               let date = attrs.contentModificationDate,
               date > latestDate {
                latestDate = date
                latestFile = transcript
            }
        }
        return latestFile.map { ($0, latestDate) }
    }

    private func fastFindLatestJSONLInSubdirs(in parentDir: URL) -> (url: URL, modDate: Date)? {
        guard let subDirs = try? FileManager.default.contentsOfDirectory(
            at: parentDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        var latestFile: URL?
        var latestDate: Date = .distantPast
        for dir in subDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for f in files where f.pathExtension == "jsonl" {
                if let attrs = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                   (attrs.fileSize ?? 0) > 0,
                   let date = attrs.contentModificationDate,
                   date > latestDate {
                    latestDate = date
                    latestFile = f
                }
            }
        }
        return latestFile.map { ($0, latestDate) }
    }

    private func fastFindLatestFlatFile(in dir: URL, matching: (URL) -> Bool) -> (url: URL, modDate: Date)? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        var latestFile: URL?
        var latestDate: Date = .distantPast
        for f in files where matching(f) {
            if let attrs = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
               (attrs.fileSize ?? 0) > 0,
               let date = attrs.contentModificationDate,
               date > latestDate {
                latestDate = date
                latestFile = f
            }
        }
        return latestFile.map { ($0, latestDate) }
    }

    private func fastFindLatestCodexTranscript(in sessionsDir: URL, flavor wanted: CodexFlavor) -> (url: URL, modDate: Date)? {
        let now = Date()
        if now.timeIntervalSince(codexDiscoveryAt) > 5 || codexLatestCache.isEmpty {
            codexDiscoveryAt = now
            codexLatestCache.removeAll()

            var candidates: [(url: URL, modDate: Date)] = []
            if let enumerator = FileManager.default.enumerator(
                at: sessionsDir,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles],
                errorHandler: nil
            ) {
                for case let url as URL in enumerator {
                    guard url.pathExtension == "jsonl",
                          url.lastPathComponent.hasPrefix("rollout-"),
                          let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                          values.isRegularFile == true,
                          (values.fileSize ?? 0) > 0,
                          let modDate = values.contentModificationDate else { continue }
                    candidates.append((url, modDate))
                }
            }

            candidates.sort { $0.modDate > $1.modDate }
            for candidate in candidates {
                let originator = codexSessionOriginator(for: candidate.url)
                let flavor = codexFlavor(forOriginator: originator)
                if codexLatestCache[flavor] == nil {
                    codexLatestCache[flavor] = (candidate.url, candidate.modDate)
                }
                if codexLatestCache.count == 2 { break }
            }
        }

        return codexLatestCache[wanted]
    }

    private func codexSessionOriginator(for url: URL) -> String? {
        if let cached = codexOriginatorCache[url.path] { return cached.isEmpty ? nil : cached }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 65536)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)

        var originator: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("\"session_meta\""),
                  let lineData = String(line).data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                  (json["type"] as? String) == "session_meta",
                  let payload = json["payload"] as? [String: Any] else { continue }
            originator = payload["originator"] as? String
            break
        }
        codexOriginatorCache[url.path] = originator ?? ""
        return originator
    }

    private func readTail(url: URL, maxBytes: UInt64 = 65536) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let fileSize = handle.seekToEndOfFile()
        let offset = fileSize > maxBytes ? fileSize - maxBytes : 0
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private func readNewLines(url: URL, instance: inout MonitoredInstance) -> [Substring]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let fileSize = handle.seekToEndOfFile()

        if fileSize < instance.lastTrackedFileSize {
            instance.resetSessionState()
        }

        handle.seek(toFileOffset: instance.lastTrackedFileSize)
        let newData = handle.readDataToEndOfFile()
        guard !newData.isEmpty, let lastNewline = newData.lastIndex(of: 0x0A) else { return nil }

        let processData = newData.subdata(in: 0..<(lastNewline + 1))
        instance.lastTrackedFileSize += UInt64(processData.count)
        let text = String(decoding: processData, as: UTF8.self)
        guard !text.isEmpty else { return nil }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    // MARK: - Per-Agent Token & Speed Parsers

    private func updateSessionTokens(url: URL, modDate: Date, instance: inout MonitoredInstance) {
        switch instance.type {
        case .antigravity:
            updateAntigravitySessionTokens(url: url, instance: &instance)
        case .qoder:
            updateQoderSessionTokens(url: url, instance: &instance)
        case .deepseek:
            updateDeepseekSessionTokens(url: url, fileModDate: modDate, instance: &instance)
        case .pi:
            updatePiSessionTokens(url: url, instance: &instance)
        case .claude:
            updateClaudeSessionTokens(url: url, instance: &instance)
        case .codex:
            updateCodexSessionTokens(url: url, instance: &instance)
        case .zcode:
            updateZcodeSessionTokens(url: url, instance: &instance)
        case .alma:
            break
        }
    }

    private func updateAntigravitySessionTokens(url: URL, instance: inout MonitoredInstance) {
        guard let lines = readNewLines(url: url, instance: &instance) else { return }
        for line in lines {
            if !line.contains("\"PLANNER_RESPONSE\"")
                && !line.contains("\"USER_INPUT\"")
                && !line.contains("<USER_SETTINGS_CHANGE>") {
                continue
            }
            guard let lineData = String(line).data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] else { continue }

            let source = (json["source"] as? String) ?? ""
            let type = (json["type"] as? String) ?? ""

            if source == "USER_EXPLICIT" {
                instance.hasValidSession = true
                if let userContent = json["content"] as? String,
                   userContent.contains("<USER_SETTINGS_CHANGE>"),
                   let m = extractModelName(from: userContent) {
                    instance.modelName = m
                }
            } else if source == "MODEL" && type == "PLANNER_RESPONSE" {
                instance.hasValidSession = true
                let output = (json["output_tokens"] as? NSNumber)?.intValue ?? 0
                if output > 0 {
                    instance.totalSessionTokens += output
                }
            }
        }
    }

    private func updateQoderSessionTokens(url: URL, instance: inout MonitoredInstance) {
        guard let lines = readNewLines(url: url, instance: &instance) else { return }
        var generatingState: Bool?

        for line in lines {
            guard let d = String(line).data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }

            if (json["isSidechain"] as? Bool) == true { continue }

            let type = (json["type"] as? String) ?? ""
            if type == "runtime-config", let m = json["model"] as? String, !m.isEmpty {
                instance.modelName = qoderModelDisplayName(for: m)
                continue
            }

            if type == "user" {
                instance.hasValidSession = true
                let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]]
                let isToolResult = content?.contains { ($0["type"] as? String) == "tool_result" } ?? false
                if !isToolResult && !instance.isGenerating {
                    instance.currentSpeed = 0
                }
                instance.qoderRequestStartedAt = parseISODate(json["timestamp"]) ?? instance.qoderRequestStartedAt
                generatingState = true
                continue
            }

            if type == "assistant" {
                instance.hasValidSession = true
                let msg = json["message"] as? [String: Any]
                let rawModel = (msg?["model"] as? String) ?? ""
                if !rawModel.isEmpty && rawModel != "<synthetic>" {
                    instance.modelName = qoderModelDisplayName(for: rawModel)
                }

                if rawModel == "<synthetic>" {
                    generatingState = false
                    continue
                }

                let stopReason = msg?["stop_reason"] as? String
                generatingState = (stopReason == nil || stopReason == "tool_use")

                guard let usage = msg?["usage"] as? [String: Any] else { continue }
                let realOutput = (usage["output_tokens"] as? NSNumber)?.intValue ?? 0
                if realOutput > 0 {
                    instance.totalSessionTokens += realOutput
                    if let started = instance.qoderRequestStartedAt,
                       let ended = parseISODate(json["timestamp"]) {
                        let duration = ended.timeIntervalSince(started)
                        if duration >= 0.2 {
                            instance.currentSpeed = clampSpeed(Double(realOutput) / duration)
                        }
                    }
                } else {
                    instance.currentSpeed = 0
                }
            }
        }

        if let generating = generatingState {
            instance.isGenerating = generating
        }
    }

    private func updateDeepseekSessionTokens(url: URL, fileModDate: Date, instance: inout MonitoredInstance) {
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let record = root["record"] as? [String: Any],
              let rows = record["rows"] as? [String: Any] else { return }

        func row(_ key: String) -> [String: Any]? {
            guard let entry = rows[key] as? [String: Any],
                  let value = entry["val"] as? [String: Any] else { return nil }
            return value
        }

        if let selection = row("modelSelection"),
           let lastUsed = selection["lastUsed"] as? [String: Any],
           let model = lastUsed["model"] as? String, !model.isEmpty {
            instance.modelName = deepseekModelDisplayName(for: model)
        }

        var running = false
        var stats: [String: Any]?
        var realActivity: Date?
        if let sessionStats = row("sessionStats") {
            stats = sessionStats
            if let openStep = sessionStats["openStep"] as? [String: Any] {
                running = true
                if let ms = (openStep["startTime"] as? NSNumber)?.doubleValue, ms > 0 {
                    realActivity = Date(timeIntervalSince1970: ms / 1000)
                }
            }
        }
        if let boundary = row("turnBoundary"),
           (boundary["openTurnStartSeq"] as? NSNumber) != nil {
            running = true
        }
        if let ms = (row("timeContext")?["lastMessageTime"] as? NSNumber)?.doubleValue, ms > 0 {
            let messageTime = Date(timeIntervalSince1970: ms / 1000)
            realActivity = max(realActivity ?? .distantPast, messageTime)
        }
        instance.deepseekLastActivity = realActivity ?? fileModDate
        instance.isGenerating = running

        let totals = row("tokenUsage")?["totals"] as? [String: Any]
        let output = (totals?["outputTokens"] as? NSNumber)?.intValue ?? 0
        let steps = (stats?["steps"] as? NSNumber)?.intValue ?? 0
        instance.hasValidSession = running || output > 0 || steps > 0
        instance.totalSessionTokens = output

        if running {
            if let lastTurn = stats?["lastTurn"] as? [String: Any],
               let tTok = (lastTurn["decodeTokens"] as? NSNumber)?.doubleValue,
               let tMs = (lastTurn["decodeMs"] as? NSNumber)?.doubleValue,
               tTok > 0, tMs > 0 {
                instance.currentSpeed = clampSpeed(tTok / (tMs / 1000))
            } else {
                let decodeTokens = (stats?["decodeTokens"] as? NSNumber)?.doubleValue ?? 0
                let decodeMs = (stats?["decodeMs"] as? NSNumber)?.doubleValue ?? 0
                if decodeTokens > 0, decodeMs > 0 {
                    instance.currentSpeed = clampSpeed(decodeTokens / (decodeMs / 1000))
                }
            }
        } else {
            instance.currentSpeed = 0
        }
    }

    private func updatePiSessionTokens(url: URL, instance: inout MonitoredInstance) {
        guard let lines = readNewLines(url: url, instance: &instance) else { return }

        var lastRole: String?
        var lastStopReason: String?
        for line in lines {
            guard let d = String(line).data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }

            let type = (json["type"] as? String) ?? ""
            if type == "model_change" {
                if let modelId = json["modelId"] as? String, !modelId.isEmpty {
                    instance.modelName = piModelDisplayName(for: modelId)
                }
                continue
            }

            guard type == "message",
                  let msg = json["message"] as? [String: Any] else { continue }

            let role = (msg["role"] as? String) ?? ""
            if role == "user" || role == "assistant" || role == "toolResult" {
                instance.hasValidSession = true
                if role == "user" && !instance.isGenerating {
                    instance.currentSpeed = 0
                }
                lastRole = role
                lastStopReason = (msg["stopReason"] as? String) ?? (json["stopReason"] as? String)
            }

            guard role == "assistant" else { continue }

            if let model = msg["model"] as? String, !model.isEmpty {
                instance.modelName = piModelDisplayName(for: model)
            }

            let output = (msg["usage"] as? [String: Any]).flatMap { ($0["output"] as? NSNumber)?.intValue } ?? 0
            let durationMs = (msg["durationMs"] as? NSNumber)?.doubleValue ?? 0
            instance.totalSessionTokens += output
            if output > 0 && durationMs >= 50 {
                instance.currentSpeed = clampSpeed(Double(output) / (durationMs / 1000.0))
            }
        }

        if let lastRole = lastRole {
            if lastRole == "user" || lastRole == "toolResult" {
                instance.isGenerating = true
            } else if lastRole == "assistant" {
                instance.isGenerating = (lastStopReason == "toolUse")
            } else {
                instance.isGenerating = false
            }
        }
    }

    private func updateClaudeSessionTokens(url: URL, instance: inout MonitoredInstance) {
        guard let lines = readNewLines(url: url, instance: &instance) else { return }

        for line in lines {
            guard let d = String(line).data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }

            if (json["isSidechain"] as? Bool) == true { continue }

            let type = (json["type"] as? String) ?? ""
            if type == "api-request" {
                instance.hasValidSession = true
                if !instance.isGenerating {
                    instance.currentSpeed = 0
                }
                if let ts = parseISODate(json["timestamp"]) {
                    instance.claudeRequestStartedAt = ts
                }
                if let params = json["params"] as? [String: Any],
                   let model = params["model"] as? String,
                   !model.isEmpty, model != "<synthetic>" {
                    instance.modelName = claudeModelDisplayName(for: model)
                }
                instance.isGenerating = true
            } else if type == "user" {
                if (json["isMeta"] as? Bool) == true { continue }
                let msgContent = (json["message"] as? [String: Any])?["content"]
                if let content = msgContent as? String,
                   content.hasPrefix("<command-") || content.hasPrefix("<local-command-") {
                    continue
                }
                instance.hasValidSession = true
                let isToolResult = (msgContent as? [[String: Any]])?.contains { ($0["type"] as? String) == "tool_result" } ?? false
                if !isToolResult && !instance.isGenerating {
                    instance.currentSpeed = 0
                }
                instance.claudeToolInFlight = false
                instance.claudeRequestStartedAt = parseISODate(json["timestamp"]) ?? instance.claudeRequestStartedAt
                instance.isGenerating = true
            } else if type == "assistant" {
                instance.hasValidSession = true
                let msg = json["message"] as? [String: Any]
                if let model = msg?["model"] as? String, !model.isEmpty, model != "<synthetic>" {
                    instance.modelName = claudeModelDisplayName(for: model)
                }

                if let messageId = msg?["id"] as? String, !messageId.isEmpty,
                   let usage = msg?["usage"] as? [String: Any],
                   let output = (usage["output_tokens"] as? NSNumber)?.intValue,
                   output > 0 {
                    let seen = instance.claudeMessageLedger[messageId] ?? 0
                    if output > seen {
                        instance.claudeMessageLedger[messageId] = output
                        instance.totalSessionTokens += (output - seen)
                    }
                    if let started = instance.claudeRequestStartedAt,
                       let ended = parseISODate(json["timestamp"]) {
                        let duration = ended.timeIntervalSince(started)
                        if duration >= 0.2 {
                            instance.currentSpeed = clampSpeed(Double(output) / duration)
                        }
                    }
                }

                let stopReason = msg?["stop_reason"] as? String
                instance.claudeToolInFlight = (stopReason == "tool_use")
                instance.isGenerating = (stopReason == nil || stopReason == "tool_use")
            }
        }
    }

    private func updateCodexSessionTokens(url: URL, instance: inout MonitoredInstance) {
        guard let lines = readNewLines(url: url, instance: &instance) else { return }

        for line in lines {
            guard let d = String(line).data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }

            let type = (json["type"] as? String) ?? ""
            let payload = json["payload"] as? [String: Any]

            if type == "turn_context" {
                if let model = payload?["model"] as? String, !model.isEmpty {
                    instance.modelName = codexModelDisplayName(for: model)
                }
                continue
            }

            if type == "response_item" {
                instance.hasValidSession = true
                let itemType = (payload?["type"] as? String) ?? ""
                if itemType.hasSuffix("_output"), let ts = parseISODate(json["timestamp"]) {
                    instance.codexStepStartedAt = ts
                    instance.codexStepMeasuredByRecord = false
                }
                continue
            }

            if type == "token_usage_record" {
                instance.hasValidSession = true
                let stepOut = ((payload?["usage"] as? [String: Any])?["output_tokens"] as? NSNumber)?.intValue ?? 0
                if stepOut > 0,
                   let started = instance.codexStepStartedAt,
                   let ended = parseISODate(json["timestamp"]) {
                    let duration = ended.timeIntervalSince(started)
                    if duration >= 0.2 {
                        instance.currentSpeed = clampSpeed(Double(stepOut) / duration)
                        instance.codexStepMeasuredByRecord = true
                    }
                }
                continue
            }

            guard type == "event_msg", let payload = payload else { continue }
            let event = (payload["type"] as? String) ?? ""

            if event == "thread_settings_applied" {
                if let settings = payload["thread_settings"] as? [String: Any],
                   let model = settings["model"] as? String, !model.isEmpty {
                    instance.modelName = codexModelDisplayName(for: model)
                }
                continue
            }

            if event == "task_started" {
                instance.hasValidSession = true
                if !instance.isGenerating {
                    instance.currentSpeed = 0
                }
                instance.isGenerating = true
                instance.codexStepStartedAt = parseISODate(json["timestamp"])
                instance.codexStepMeasuredByRecord = false
                continue
            }

            if event == "task_complete" || event == "turn_aborted" {
                instance.isGenerating = false
                instance.codexStepStartedAt = nil
                instance.codexStepMeasuredByRecord = false
                continue
            }

            guard event == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let totals = info["total_token_usage"] as? [String: Any] else { continue }

            let output = Int((totals["output_tokens"] as? NSNumber)?.int64Value ?? 0)
            let previousTotal = instance.totalSessionTokens
            instance.totalSessionTokens = output
            if output > 0 {
                instance.hasValidSession = true
            }

            if let ended = parseISODate(json["timestamp"]) {
                if !instance.codexStepMeasuredByRecord {
                    let lastOut = ((info["last_token_usage"] as? [String: Any])?["output_tokens"] as? NSNumber)?.intValue ?? 0
                    let stepTokens = lastOut > 0 ? lastOut : max(0, output - previousTotal)
                    if stepTokens > 0, let started = instance.codexStepStartedAt {
                        let duration = ended.timeIntervalSince(started)
                        if duration >= 0.2 {
                            instance.currentSpeed = clampSpeed(Double(stepTokens) / duration)
                        }
                    }
                }
                instance.codexStepStartedAt = ended
                instance.codexStepMeasuredByRecord = false
            }
        }
    }

    private func updateZcodeSessionTokens(url: URL, instance: inout MonitoredInstance) {
        guard let lines = readNewLines(url: url, instance: &instance) else { return }

        var state = ZCodeScanState(
            totalTokens: instance.totalSessionTokens,
            currentSpeed: instance.currentSpeed,
            isGenerating: instance.isGenerating,
            modelName: instance.modelName
        )
        state.apply(lines: lines)
        instance.totalSessionTokens = state.totalTokens
        instance.currentSpeed = clampSpeed(state.currentSpeed)
        instance.isGenerating = state.isGenerating
        instance.modelName = state.modelName
        if state.totalTokens > 0 || state.isGenerating {
            instance.hasValidSession = true
        }

        for line in lines {
            guard let request = parseZCodeRequest(line: line), request.isSuccess,
                  let raw = request.completedAtRaw,
                  let date = zcodeDate(raw) else { continue }
            instance.zcodeLastCompletedAt = date
        }
    }

    private func updateAlmaSessionState(now: Date, instance: inout MonitoredInstance, hasChanges: inout Bool) {
        let reader = AlmaReader()
        guard reader.isOpen, let sample = reader.latestLiveSample() else {
            if instance.latestURL != nil || instance.hasValidSession {
                instance.latestURL = nil
                instance.resetSessionState()
                hasChanges = true
            }
            return
        }

        let dbURL = AlmaReader.databaseURL()
        if instance.latestURL != dbURL {
            instance.latestURL = dbURL
            instance.resetSessionState()
            hasChanges = true
        }

        let valid = sample.isGenerating || sample.outputTokens > 0 || !sample.messageId.isEmpty
        if valid != instance.hasValidSession {
            instance.hasValidSession = valid
            hasChanges = true
        }

        if sample.messageId != instance.almaLastMessageId, !sample.messageId.isEmpty {
            instance.almaLastMessageId = sample.messageId
            instance.totalSessionTokens += Int(sample.outputTokens)
            hasChanges = true
        }

        let rawSpeed: Double
        if sample.isGenerating {
            if let msgDate = parseISODate(sample.timestamp),
               now.timeIntervalSince(msgDate) >= -5,
               now.timeIntervalSince(msgDate) <= 60 {
                rawSpeed = sample.speed
            } else {
                rawSpeed = 0
            }
        } else {
            rawSpeed = 0
        }
        let speed = clampSpeed(rawSpeed)
        if speed != instance.currentSpeed {
            instance.currentSpeed = speed
            hasChanges = true
        }

        let model = almaModelDisplayName(for: sample.model)
        if model != instance.modelName {
            instance.modelName = model
            hasChanges = true
        }

        if sample.isGenerating != instance.isGenerating {
            instance.isGenerating = sample.isGenerating
            hasChanges = true
        }
    }

    private func updateAntigravitySpeedFromTail(url: URL, fileModDate: Date, now: Date, instance: inout MonitoredInstance) {
        guard let content = readTail(url: url) else {
            instance.antigravityStepInFlight = false
            return
        }

        let rawLines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let lines: [String] = (rawLines.count > 1 && !rawLines[0].hasPrefix("{"))
            ? Array(rawLines.dropFirst())
            : rawLines

        var steps: [[String: Any]] = []
        for line in lines {
            if let data = line.data(using: .utf8),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                steps.append(json)
            }
        }

        if !steps.isEmpty {
            instance.hasValidSession = true
        }

        for i in 0..<steps.count {
            let step = steps[i]
            guard (step["source"] as? String) == "MODEL",
                  (step["type"] as? String) == "PLANNER_RESPONSE" else { continue }

            let outTokens = (step["output_tokens"] as? NSNumber)?.intValue ?? 0
            guard outTokens > 0,
                  let tStart = parseISODate(step["created_at"]) else { continue }
            let stepIdx = (step["step_index"] as? NSNumber)?.intValue ?? i

            if i + 1 < steps.count {
                let nextStep = steps[i + 1]
                let nextType = (nextStep["type"] as? String) ?? ""
                if ["GENERIC", "MODEL", "TOOL", "CHECKPOINT", "ERROR_MESSAGE"].contains(nextType),
                   let tEnd = parseISODate(nextStep["created_at"]),
                   tEnd >= tStart {
                    let dur = max(0.5, tEnd.timeIntervalSince(tStart))
                    if stepIdx >= instance.antigravityLastStepIndex {
                        instance.antigravityLastStepIndex = stepIdx
                        instance.currentSpeed = clampSpeed(Double(outTokens) / dur)
                    }
                }
            } else if fileModDate >= tStart,
                      now.timeIntervalSince(fileModDate) <= 15,
                      stepIdx >= instance.antigravityLastStepIndex {
                let dur = max(0.5, fileModDate.timeIntervalSince(tStart))
                instance.antigravityLastStepIndex = stepIdx
                instance.currentSpeed = clampSpeed(Double(outTokens) / dur)
            }
        }

        let lastStep = steps.last
        let lastType = (lastStep?["type"] as? String) ?? ""
        let lastStatus = (lastStep?["status"] as? String) ?? ""
        instance.antigravityStepInFlight = lastStatus == "RUNNING"
            || lastType == "GENERIC"
            || lastType == "USER_INPUT"
        if lastType == "USER_INPUT" {
            instance.currentSpeed = 0
        }
    }
}
