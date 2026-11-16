import Foundation

// MARK: - Historical Token Usage Index

final class UsageIndex {
    static let shared = UsageIndex()

    private struct SourceFile {
        let url: URL
        let path: String
        let agent: String
        let kind: InstanceType
        let size: UInt64
        let mtime: Date
    }

    private struct SourceSpec {
        let root: URL
        let agent: String
        let kind: InstanceType
        let matches: (URL) -> Bool
    }

    private let queue = DispatchQueue(label: "com.sqoder.momi.usage", qos: .utility)
    private var store = UsageStore()
    private var scanInFlight = false
    private var pendingRescan = false
    private var pendingRebuild = false
    private var isIndexing = false
    private var progress: Double = 1
    private var activeFileCount: Int = 0
    private var lastSnapshotPost = Date.distantPast
    private var modelLookup: [String: String] = [:]
    private var piNameCache: [String: String] = [:]
    private var timer: DispatchSourceTimer?

    var onUpdate: ((UsageSnapshotBundle) -> Void)?

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

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private lazy var storeURL: URL = {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("momi", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage.json")
    }()

    private init() {}

    func start() {
        queue.async {
            self.loadStore()
            self.postSnapshot(force: true)
            self.scanAll(rebuild: false)
            self.startAutoScan()
        }
    }

    func scanNow() {
        queue.async { self.scanAll(rebuild: false) }
    }

    func rebuild() {
        queue.async {
            self.isIndexing = true
            self.progress = 0
            self.postSnapshot(force: true)
            self.scanAll(rebuild: true)
        }
    }

    private func startAutoScan() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(5))
        t.setEventHandler { [weak self] in self?.scanAll(rebuild: false) }
        t.resume()
        timer = t
    }

    private func loadStore() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(UsageStore.self, from: data),
              decoded.version == UsageStore.currentVersion else {
            store = UsageStore()
            activeFileCount = 0
            modelLookup.removeAll()
            return
        }
        store = decoded
        activeFileCount = decoded.files.count
        modelLookup.removeAll()
        for key in store.modelTotal.keys {
            modelLookup[key.lowercased()] = key
        }
    }

    private func saveStore() {
        store.indexedAt = Date().timeIntervalSince1970
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func collectSourceFiles() -> [SourceFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let specs: [SourceSpec] = [
            SourceSpec(
                root: home.appendingPathComponent(".gemini/antigravity/brain"),
                agent: "antigravity-desktop",
                kind: .antigravity,
                matches: { $0.lastPathComponent == "transcript.jsonl" }
            ),
            SourceSpec(
                root: home.appendingPathComponent(".gemini/antigravity-cli/brain"),
                agent: "antigravity-cli",
                kind: .antigravity,
                matches: { $0.lastPathComponent == "transcript.jsonl" }
            ),
            SourceSpec(
                root: home.appendingPathComponent(".qoder/projects"),
                agent: "qoder",
                kind: .qoder,
                matches: { $0.pathExtension == "jsonl" }
            ),
            SourceSpec(
                root: home.appendingPathComponent(".dsh/storages/session_projcache/sessions"),
                agent: "deepseek",
                kind: .deepseek,
                matches: { $0.pathExtension == "json" }
            ),
            SourceSpec(
                root: home.appendingPathComponent(".pi/agent/sessions"),
                agent: "pi",
                kind: .pi,
                matches: { $0.pathExtension == "jsonl" }
            ),
            SourceSpec(
                root: home.appendingPathComponent(".claude/projects"),
                agent: "claude",
                kind: .claude,
                matches: { $0.pathExtension == "jsonl" }
            ),
            SourceSpec(
                root: home.appendingPathComponent(".codex/sessions"),
                agent: "codex-cli",
                kind: .codex,
                matches: {
                    $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-")
                }
            ),
            SourceSpec(
                root: home.appendingPathComponent(".zcode/cli/rollout"),
                agent: "zcode",
                kind: .zcode,
                matches: {
                    $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("model-io-")
                }
            )
        ]

        var result: [SourceFile] = []
        for spec in specs {
            guard let enumerator = FileManager.default.enumerator(
                at: spec.root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [],
                errorHandler: nil
            ) else { continue }

            for case let url as URL in enumerator {
                guard spec.matches(url),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true,
                      let size = values.fileSize,
                      let mtime = values.contentModificationDate else { continue }
                result.append(SourceFile(
                    url: url,
                    path: url.path,
                    agent: spec.agent,
                    kind: spec.kind,
                    size: UInt64(size),
                    mtime: mtime
                ))
            }
        }
        result.sort { $0.path < $1.path }
        return result
    }

    private func scanAll(rebuild: Bool) {
        if scanInFlight {
            pendingRescan = true
            if rebuild { pendingRebuild = true }
            return
        }
        scanInFlight = true

        var rebuildNeeded = rebuild
        if rebuildNeeded {
            store = UsageStore()
            modelLookup.removeAll()
        }

        let files = collectSourceFiles()
        if !rebuildNeeded {
            for file in files {
                // Projection caches are rewritten wholesale and may legitimately
                // shrink; only append-only transcripts signal a rebuild this way.
                if file.kind == .deepseek { continue }
                if let checkpoint = store.files[file.path], checkpoint.offset > 0, file.size < checkpoint.offset {
                    rebuildNeeded = true
                    break
                }
            }
        }
        if rebuildNeeded {
            store = UsageStore()
            modelLookup.removeAll()
        }

        var pending: [(SourceFile, UInt64)] = []
        for file in files {
            let checkpoint = store.files[file.path]
            if file.kind == .deepseek {
                let changed = checkpoint.map {
                    $0.size != file.size
                        || abs($0.mtime - file.mtime.timeIntervalSince1970) >= 0.001
                } ?? true
                if changed {
                    pending.append((file, file.size))
                }
                continue
            }
            let offset = checkpoint?.offset ?? 0
            if let checkpoint = checkpoint,
               checkpoint.size == file.size,
               abs(checkpoint.mtime - file.mtime.timeIntervalSince1970) < 0.001,
               checkpoint.offset >= file.size {
                continue
            }
            if offset < file.size {
                pending.append((file, file.size - offset))
            }
        }

        let almaReader = AlmaReader()
        activeFileCount = files.count + (almaReader.isOpen ? 1 : 0)

        let bytesToScan = pending.reduce(UInt64(0)) { $0 + $1.1 }
        if rebuildNeeded || bytesToScan > 1_000_000 {
            isIndexing = true
            progress = 0
            postSnapshot(force: true)
        } else {
            progress = 1
        }

        var processed: UInt64 = 0
        var lastSave = Date()
        var needsRebuild = false

        for (file, fileBytes) in pending {
            if !scanFile(file) {
                needsRebuild = true
                break
            }
            processed += fileBytes
            progress = bytesToScan > 0 ? min(0.99, Double(processed) / Double(bytesToScan)) : 1
            postSnapshot()
            if Date().timeIntervalSince(lastSave) > 2.0 {
                saveStore()
                lastSave = Date()
            }
        }

        if needsRebuild {
            scanInFlight = false
            scanAll(rebuild: true)
            return
        }

        scanAlmaUsage(reader: almaReader)
        saveStore()
        scanInFlight = false

        if pendingRescan {
            let nextRebuild = pendingRebuild
            pendingRescan = false
            pendingRebuild = false
            scanAll(rebuild: nextRebuild)
            return
        }

        isIndexing = false
        progress = 1
        postSnapshot(force: true)
    }

    /// Returns false when the file shrank after enumeration and a full rebuild is required.
    private func scanFile(_ file: SourceFile) -> Bool {
        var checkpoint = store.files[file.path] ?? UsageFileCheckpoint()
        if file.kind == .deepseek {
            let ok = scanDeepseekProjection(file, checkpoint: &checkpoint)
            store.files[file.path] = checkpoint
            return ok
        }
        guard let handle = try? FileHandle(forReadingFrom: file.url) else { return true }
        defer { try? handle.close() }

        let actualSize = handle.seekToEndOfFile()
        if actualSize < checkpoint.offset {
            return false
        }
        handle.seek(toFileOffset: checkpoint.offset)
        let newData = handle.readDataToEndOfFile()

        guard !newData.isEmpty, let lastNewline = newData.lastIndex(of: 0x0A) else {
            checkpoint.size = actualSize
            checkpoint.mtime = file.mtime.timeIntervalSince1970
            store.files[file.path] = checkpoint
            return true
        }

        let processData = newData.subdata(in: 0..<(lastNewline + 1))
        let text = String(decoding: processData, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)

        switch file.kind {
        case .antigravity:
            scanAntigravity(lines: lines, file: file, checkpoint: &checkpoint)
        case .qoder:
            scanQoder(lines: lines, file: file, checkpoint: &checkpoint)
        case .deepseek:
            break
        case .pi:
            scanPi(lines: lines, file: file, checkpoint: &checkpoint)
        case .claude:
            scanClaude(lines: lines, file: file, checkpoint: &checkpoint)
        case .codex:
            scanCodex(lines: lines, file: file, checkpoint: &checkpoint)
        case .zcode:
            scanZcode(lines: lines, file: file, checkpoint: &checkpoint)
        case .alma:
            break
        }

        checkpoint.offset += UInt64(processData.count)
        checkpoint.size = actualSize
        checkpoint.mtime = file.mtime.timeIntervalSince1970
        store.files[file.path] = checkpoint
        return true
    }

    private func scanDeepseekProjection(_ file: SourceFile, checkpoint: inout UsageFileCheckpoint) -> Bool {
        guard let data = try? Data(contentsOf: file.url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let recordObject = root["record"] as? [String: Any],
              let rows = recordObject["rows"] as? [String: Any] else { return true }

        func row(_ key: String) -> [String: Any]? {
            guard let entry = rows[key] as? [String: Any],
                  let value = entry["val"] as? [String: Any] else { return nil }
            return value
        }

        checkpoint.offset = UInt64(data.count)
        checkpoint.size = UInt64(data.count)
        checkpoint.mtime = file.mtime.timeIntervalSince1970

        guard let usage = row("tokenUsage"),
              let totals = usage["totals"] as? [String: Any] else { return true }

        let input = Int64((totals["uncachedInputTokens"] as? NSNumber)?.int64Value ?? 0)
        let output = Int64((totals["outputTokens"] as? NSNumber)?.int64Value ?? 0)
        let cache = Int64((totals["cacheReadTokens"] as? NSNumber)?.int64Value ?? 0)
            + Int64((totals["cacheWriteTokens"] as? NSNumber)?.int64Value ?? 0)
        let steps = Int64((row("sessionStats")?["steps"] as? NSNumber)?.int64Value ?? 0)
        let isColdSight = checkpoint.deepseekInput == 0 && checkpoint.deepseekOutput == 0
            && checkpoint.deepseekCache == 0 && checkpoint.deepseekSteps == 0

        if input < checkpoint.deepseekInput
            || output < checkpoint.deepseekOutput
            || cache < checkpoint.deepseekCache
            || steps < checkpoint.deepseekSteps {
            checkpoint.deepseekInput = input
            checkpoint.deepseekOutput = output
            checkpoint.deepseekCache = cache
            checkpoint.deepseekSteps = steps
            return true
        }

        let deltaInput = input - checkpoint.deepseekInput
        let deltaOutput = output - checkpoint.deepseekOutput
        let deltaCache = cache - checkpoint.deepseekCache
        let deltaSteps = max(0, steps - checkpoint.deepseekSteps)
        checkpoint.deepseekInput = input
        checkpoint.deepseekOutput = output
        checkpoint.deepseekCache = cache
        checkpoint.deepseekSteps = steps

        guard deltaInput > 0 || deltaOutput > 0 || deltaCache > 0 else { return true }

        var rawModel = "DeepSeek"
        if let selection = row("modelSelection"),
           let lastUsed = selection["lastUsed"] as? [String: Any],
           let model = lastUsed["model"] as? String, !model.isEmpty {
            rawModel = model
        }

        let day: String
        if isColdSight,
           let ms = (row("sessionListMetadata")?["lastPromptAt"] as? NSNumber)?.doubleValue, ms > 0 {
            day = dayKey(for: Date(timeIntervalSince1970: ms / 1000))
        } else {
            day = dayKey(for: file.mtime)
        }

        record(
            agent: file.agent,
            model: deepseekModelDisplayName(for: rawModel),
            day: day,
            input: deltaInput,
            output: deltaOutput,
            cache: deltaCache,
            requests: Int(deltaSteps)
        )
        return true
    }

    private func scanAntigravity(lines: [Substring], file: SourceFile, checkpoint: inout UsageFileCheckpoint) {
        for line in lines {
            if !line.contains("\"output_tokens\"") && !line.contains("<USER_SETTINGS_CHANGE>") { continue }
            autoreleasepool {
                guard let data = line.data(using: .utf8),
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

                if (json["source"] as? String) == "USER_EXPLICIT",
                   let content = json["content"] as? String,
                   content.contains("<USER_SETTINGS_CHANGE>"),
                   let model = extractModelName(from: content) {
                    checkpoint.antigravityModel = model
                }

                guard (json["source"] as? String) == "MODEL",
                      (json["type"] as? String) == "PLANNER_RESPONSE" else { return }

                let step = (json["step_index"] as? NSNumber)?.intValue
                if let step = step, let last = checkpoint.antigravityLastStep, step <= last {
                    return
                }

                let input = (json["input_tokens"] as? NSNumber)?.int64Value ?? 0
                let output = (json["output_tokens"] as? NSNumber)?.int64Value ?? 0
                let cache = (json["cache_read_tokens"] as? NSNumber)?.int64Value ?? 0
                if let step = step {
                    checkpoint.antigravityLastStep = step
                }
                guard input > 0 || output > 0 || cache > 0 else { return }

                let model = checkpoint.antigravityModel ?? "Gemini (未标注)"
                let day = dayKey(fromISO: json["created_at"] as? String) ?? dayKey(for: file.mtime)
                record(agent: file.agent, model: model, day: day, input: input, output: output, cache: cache, requests: 1)
            }
        }
    }

    private func scanQoder(lines: [Substring], file: SourceFile, checkpoint: inout UsageFileCheckpoint) {
        for line in lines {
            if !line.contains("\"usage\"") { continue }
            autoreleasepool {
                guard let data = line.data(using: .utf8),
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      (json["type"] as? String) == "assistant",
                      (json["isSidechain"] as? Bool) != true,
                      let message = json["message"] as? [String: Any],
                      let messageId = message["id"] as? String, !messageId.isEmpty,
                      let usage = message["usage"] as? [String: Any] else { return }

                let rawModel = (message["model"] as? String) ?? ""
                if rawModel == "<synthetic>" { return }
                if messageId == checkpoint.qoderMessageId { return }
                checkpoint.qoderMessageId = messageId

                let input = (usage["input_tokens"] as? NSNumber)?.int64Value ?? 0
                let output = (usage["output_tokens"] as? NSNumber)?.int64Value ?? 0
                let cache = ((usage["cache_read_input_tokens"] as? NSNumber)?.int64Value ?? 0)
                    + ((usage["cache_creation_input_tokens"] as? NSNumber)?.int64Value ?? 0)
                let credits = (usage["credits"] as? NSNumber)?.doubleValue ?? 0
                let contextRatio = (usage["context_usage_ratio"] as? NSNumber)?.doubleValue ?? 0

                let day = dayKey(fromISO: json["timestamp"] as? String) ?? dayKey(for: file.mtime)
                record(
                    agent: file.agent,
                    model: qoderModelDisplayName(for: rawModel),
                    day: day,
                    input: input,
                    output: output,
                    cache: cache,
                    requests: 1,
                    credits: credits,
                    contextPeak: contextRatio
                )
            }
        }
    }

    private func scanPi(lines: [Substring], file: SourceFile, checkpoint: inout UsageFileCheckpoint) {
        for line in lines {
            if !line.contains("\"usage\"") { continue }
            autoreleasepool {
                guard let data = line.data(using: .utf8),
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      (json["type"] as? String) == "message",
                      let message = json["message"] as? [String: Any],
                      (message["role"] as? String) == "assistant",
                      let usage = message["usage"] as? [String: Any] else { return }

                let input = (usage["input"] as? NSNumber)?.int64Value ?? 0
                let output = (usage["output"] as? NSNumber)?.int64Value ?? 0
                let cache = ((usage["cacheRead"] as? NSNumber)?.int64Value ?? 0)
                    + ((usage["cacheWrite"] as? NSNumber)?.int64Value ?? 0)
                guard input > 0 || output > 0 || cache > 0 else { return }

                let rawModel = (message["model"] as? String) ?? ""
                let day = dayKey(fromISO: json["timestamp"] as? String) ?? dayKey(for: file.mtime)
                record(
                    agent: file.agent,
                    model: piDisplayName(rawModel),
                    day: day,
                    input: input,
                    output: output,
                    cache: cache,
                    requests: 1
                )
            }
        }
    }

    private func scanClaude(lines: [Substring], file: SourceFile, checkpoint: inout UsageFileCheckpoint) {
        for line in lines {
            if !line.contains("\"usage\"") { continue }
            autoreleasepool {
                guard let data = line.data(using: .utf8),
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      (json["type"] as? String) == "assistant",
                      (json["isSidechain"] as? Bool) != true,
                      let message = json["message"] as? [String: Any],
                      let messageId = message["id"] as? String, !messageId.isEmpty,
                      let usage = message["usage"] as? [String: Any] else { return }

                let rawModel = (message["model"] as? String) ?? ""
                if rawModel == "<synthetic>" { return }

                let input = (usage["input_tokens"] as? NSNumber)?.int64Value ?? 0
                let output = (usage["output_tokens"] as? NSNumber)?.int64Value ?? 0
                let cache = ((usage["cache_read_input_tokens"] as? NSNumber)?.int64Value ?? 0)
                    + ((usage["cache_creation_input_tokens"] as? NSNumber)?.int64Value ?? 0)
                let day = dayKey(fromISO: json["timestamp"] as? String) ?? dayKey(for: file.mtime)
                let model = claudeModelDisplayName(for: rawModel)

                if messageId == checkpoint.claudeMessageId {
                    let deltaInput = max(0, input - checkpoint.claudeInput)
                    let deltaOutput = max(0, output - checkpoint.claudeOutput)
                    let deltaCache = max(0, cache - checkpoint.claudeCache)
                    checkpoint.claudeInput = max(checkpoint.claudeInput, input)
                    checkpoint.claudeOutput = max(checkpoint.claudeOutput, output)
                    checkpoint.claudeCache = max(checkpoint.claudeCache, cache)
                    if deltaInput > 0 || deltaOutput > 0 || deltaCache > 0 {
                        record(agent: file.agent, model: model, day: day, input: deltaInput, output: deltaOutput, cache: deltaCache, requests: 0)
                    }
                } else {
                    checkpoint.claudeMessageId = messageId
                    checkpoint.claudeInput = input
                    checkpoint.claudeOutput = output
                    checkpoint.claudeCache = cache
                    guard input > 0 || output > 0 || cache > 0 else { return }
                    record(agent: file.agent, model: model, day: day, input: input, output: output, cache: cache, requests: 1)
                }
            }
        }
    }

    private func scanCodex(lines: [Substring], file: SourceFile, checkpoint: inout UsageFileCheckpoint) {
        for line in lines {
            if !line.contains("\"token_count\"")
                && !line.contains("\"session_meta\"")
                && !line.contains("\"turn_context\"")
                && !line.contains("\"thread_settings_applied\"") { continue }
            autoreleasepool {
                guard let data = line.data(using: .utf8),
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let payload = json["payload"] as? [String: Any] else { return }

                let type = (json["type"] as? String) ?? ""
                if type == "session_meta" {
                    checkpoint.codexAgent = codexFlavor(forOriginator: payload["originator"] as? String).agentKey
                    checkpoint.codexModel = nil
                    checkpoint.codexInput = 0
                    checkpoint.codexOutput = 0
                    checkpoint.codexCache = 0
                    return
                }

                if type == "turn_context" {
                    if let model = payload["model"] as? String, !model.isEmpty {
                        checkpoint.codexModel = model
                    }
                    return
                }

                guard type == "event_msg" else { return }
                let event = (payload["type"] as? String) ?? ""

                if event == "thread_settings_applied" {
                    if let settings = payload["thread_settings"] as? [String: Any],
                       let model = settings["model"] as? String, !model.isEmpty {
                        checkpoint.codexModel = model
                    }
                    return
                }

                guard event == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let totals = info["total_token_usage"] as? [String: Any] else { return }

                let input = (totals["input_tokens"] as? NSNumber)?.int64Value ?? 0
                let output = (totals["output_tokens"] as? NSNumber)?.int64Value ?? 0
                let cache = ((totals["cached_input_tokens"] as? NSNumber)?.int64Value ?? 0)
                    + ((totals["cache_write_input_tokens"] as? NSNumber)?.int64Value ?? 0)

                if input < checkpoint.codexInput || output < checkpoint.codexOutput || cache < checkpoint.codexCache {
                    checkpoint.codexInput = input
                    checkpoint.codexOutput = output
                    checkpoint.codexCache = cache
                    return
                }

                let deltaInput = input - checkpoint.codexInput
                let deltaOutput = output - checkpoint.codexOutput
                let deltaCache = cache - checkpoint.codexCache
                checkpoint.codexInput = input
                checkpoint.codexOutput = output
                checkpoint.codexCache = cache

                let freshInput = max(0, deltaInput - deltaCache)
                guard freshInput > 0 || deltaOutput > 0 || deltaCache > 0 else { return }

                let day = dayKey(fromISO: json["timestamp"] as? String) ?? dayKey(for: file.mtime)
                let model = codexModelDisplayName(for: checkpoint.codexModel ?? "Codex")
                record(
                    agent: checkpoint.codexAgent ?? CodexFlavor.cli.agentKey,
                    model: model,
                    day: day,
                    input: freshInput,
                    output: deltaOutput,
                    cache: deltaCache,
                    requests: 1
                )
            }
        }
    }

    private func scanZcode(lines: [Substring], file: SourceFile, checkpoint: inout UsageFileCheckpoint) {
        for line in lines {
            autoreleasepool {
                guard let request = parseZCodeRequest(line: line), request.isSuccess else { return }
                let day = dayKeyForZcode(request.completedAtRaw) ?? dayKey(for: file.mtime)
                record(
                    agent: file.agent,
                    model: zcodeModelDisplayName(for: request.model),
                    day: day,
                    input: zcodeFreshInput(request),
                    output: request.outputTokens,
                    cache: request.cacheTokens,
                    requests: 1
                )
            }
        }
    }

    private func scanAlmaUsage(reader: AlmaReader) {
        guard reader.isOpen else { return }
        let rows = reader.usageRows(afterRowid: store.almaWatermark)
        guard !rows.isEmpty else { return }
        var maxRowid = store.almaWatermark
        for row in rows {
            maxRowid = max(maxRowid, row.rowid)
            guard row.isValid else { continue }
            let day = row.date.isEmpty
                ? (dayKey(fromISO: row.timestamp) ?? dayKey(for: Date()))
                : row.date
            record(
                agent: "alma",
                model: almaModelDisplayName(for: row.model),
                day: day,
                input: almaFreshInput(row),
                output: row.outputTokens,
                cache: almaCacheTokens(row),
                requests: 1
            )
        }
        store.almaWatermark = maxRowid
    }

    private func record(
        agent: String,
        model rawModel: String,
        day: String,
        input: Int64,
        output: Int64,
        cache: Int64,
        requests: Int,
        credits: Double = 0,
        contextPeak: Double = 0
    ) {
        let model = canonicalModel(rawModel)
        var usage = TokenUsage()
        usage.add(input: input, output: output, cache: cache, requests: requests, credits: credits, contextPeak: contextPeak)

        store.total.add(usage)
        store.daily[day, default: TokenUsage()].add(usage)

        store.modelTotal[model, default: TokenUsage()].add(usage)
        var modelDays = store.modelDaily[model] ?? [:]
        modelDays[day, default: TokenUsage()].add(usage)
        store.modelDaily[model] = modelDays

        var agentDays = store.agentDaily[agent] ?? [:]
        agentDays[day, default: TokenUsage()].add(usage)
        store.agentDaily[agent] = agentDays
    }

    private func canonicalModel(_ rawModel: String) -> String {
        let cleaned = sanitizeModelName(rawModel)
        let name = cleaned.isEmpty ? "未知模型" : cleaned
        let key = name.lowercased()
        if let existing = modelLookup[key] { return existing }
        modelLookup[key] = name
        return name
    }

    private func piDisplayName(_ rawModel: String) -> String {
        if let cached = piNameCache[rawModel] { return cached }
        let name = piModelDisplayName(for: rawModel)
        piNameCache[rawModel] = name
        return name
    }

    private func dayKey(fromISO raw: String?) -> String? {
        guard let raw = raw else { return nil }
        guard let date = isoFractional.date(from: raw) ?? isoPlain.date(from: raw) else { return nil }
        return dayFormatter.string(from: date)
    }

    private func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func makeSnapshot() -> UsageSnapshotBundle {
        let now = Date()
        let calendar = Calendar.current
        let todayKey = dayFormatter.string(from: now)
        let weekKeys = Set((0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: now)
        }.map { dayFormatter.string(from: $0) })

        func sum(_ days: [String: TokenUsage], period: UsagePeriod) -> TokenUsage {
            switch period {
            case .all:
                var bucket = TokenUsage()
                for value in days.values { bucket.add(value) }
                return bucket
            case .today:
                return days[todayKey] ?? TokenUsage()
            case .week:
                var bucket = TokenUsage()
                for (key, value) in days where weekKeys.contains(key) { bucket.add(value) }
                return bucket
            }
        }

        func buildSeries(daysCount: Int, anchor: Date) -> [UsageDayPoint] {
            (0..<daysCount).reversed().compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: anchor) else { return nil }
                let key = dayFormatter.string(from: date)
                let short = key.count >= 10 ? String(key.suffix(5)) : key
                let isToday = (key == todayKey)
                return UsageDayPoint(
                    dateKey: key,
                    label: isToday ? "今天" : short,
                    usage: store.daily[key] ?? TokenUsage(),
                    isToday: isToday
                )
            }
        }

        var allAnchor = now
        let recent28HasData = (0..<28).contains { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return false }
            let key = dayFormatter.string(from: date)
            if let u = store.daily[key] { return u.hasTokens || u.credits > 0 }
            return false
        }
        if !recent28HasData,
           let latestKey = store.daily.keys.max(),
           let latestDate = dayFormatter.date(from: latestKey) {
            allAnchor = latestDate
        }
        let allSeries = buildSeries(daysCount: 28, anchor: allAnchor)
        let weekSeries = buildSeries(daysCount: 7, anchor: now)

        var periods: [UsagePeriod: UsagePeriodSnapshot] = [:]
        for period in UsagePeriod.allCases {
            let total = period == .all ? store.total : sum(store.daily, period: period)

            var modelRows: [UsageRow] = []
            for (name, days) in store.modelDaily {
                let usage = sum(days, period: period)
                guard usage.hasTokens || usage.credits > 0 else { continue }
                modelRows.append(UsageRow(name: name, usage: usage, iconName: nil))
            }
            modelRows.sort { lhs, rhs in
                if lhs.usage.total != rhs.usage.total { return lhs.usage.total > rhs.usage.total }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            var agentRows: [UsageRow] = []
            for key in usageAgentOrder {
                guard let days = store.agentDaily[key] else { continue }
                let usage = sum(days, period: period)
                guard usage.hasTokens || usage.credits > 0 else { continue }
                agentRows.append(UsageRow(
                    name: agentDisplayName(for: key),
                    usage: usage,
                    iconName: agentIconName(for: key)
                ))
            }

            let series = (period == .all) ? allSeries : weekSeries
            periods[period] = UsagePeriodSnapshot(
                total: total,
                modelRows: modelRows,
                agentRows: agentRows,
                dailySeries: series
            )
        }

        return UsageSnapshotBundle(
            periods: periods,
            indexedAt: store.indexedAt > 0 ? Date(timeIntervalSince1970: store.indexedAt) : nil,
            isIndexing: isIndexing,
            progress: progress,
            fileCount: activeFileCount
        )
    }

    private func postSnapshot(force: Bool = false) {
        let now = Date()
        if !force && now.timeIntervalSince(lastSnapshotPost) < 0.4 { return }
        lastSnapshotPost = now
        let bundle = makeSnapshot()
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(bundle)
        }
    }
}
