import AppKit

// MARK: - Menu Bar Agent Row

final class AgentTableRowView: NSView {
    private let iconView = NSImageView()
    private let modelLabel = NSTextField(labelWithString: "--")
    private let speedLabel = NSTextField(labelWithString: "--")

    private var currentInstance: MonitoredInstance?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updateHighlight() }
    }

    var onSelect: ((MonitoredInstance) -> Void)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        modelLabel.font = .systemFont(ofSize: 11, weight: .medium)
        modelLabel.textColor = .labelColor
        modelLabel.lineBreakMode = .byTruncatingTail
        modelLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(modelLabel)

        speedLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        speedLabel.textColor = .secondaryLabelColor
        speedLabel.alignment = .right
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(speedLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            modelLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 50),
            modelLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            modelLabel.trailingAnchor.constraint(lessThanOrEqualTo: speedLabel.leadingAnchor, constant: -10),

            speedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            speedLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            speedLabel.widthAnchor.constraint(equalToConstant: 72),
        ])
    }

    func update(instance: MonitoredInstance, icon: NSImage?) {
        currentInstance = instance
        iconView.image = icon
        iconView.toolTip = instance.name
        modelLabel.stringValue = instance.modelName
        modelLabel.toolTip = instance.modelName
        toolTip = instance.latestURL != nil
            ? "\(instance.name) · \(instance.modelName)\n点击在访达中定位会话文件"
            : "\(instance.name) · \(instance.modelName)"

        let speed = clampSpeed(instance.currentSpeed)
        if instance.isGenerating {
            if speed > 0 {
                speedLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
                speedLabel.stringValue = String(format: "%.1f t/s", speed)
            } else {
                speedLabel.font = .systemFont(ofSize: 11, weight: .medium)
                speedLabel.stringValue = "运行中"
            }
            speedLabel.textColor = .systemOrange
        } else {
            speedLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
            speedLabel.stringValue = "—"
            speedLabel.textColor = .tertiaryLabelColor
        }
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if currentInstance?.latestURL != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if currentInstance?.latestURL != nil {
            isHovered = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point),
              let instance = currentInstance,
              instance.latestURL != nil else { return }
        isHovered = false
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [onSelect] in
            onSelect?(instance)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHighlight()
    }

    private func updateHighlight() {
        layer?.backgroundColor = isHovered
            ? NSColor.labelColor.withAlphaComponent(0.06).cgColor
            : NSColor.clear.cgColor
    }
}

// MARK: - Interactive Footer Row

private final class DashboardFooterView: NSView {
    let captionLabel = NSTextField(labelWithString: "累计使用 Token")
    let valueLabel = NSTextField(labelWithString: "--")

    var onClick: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updateHighlight() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 5

        captionLabel.font = .systemFont(ofSize: 10, weight: .regular)
        captionLabel.textColor = .tertiaryLabelColor
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captionLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        toolTip = "输入 + 输出，不含缓存读取 · 点击打开用量统计"

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),

            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            captionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: captionLabel.trailingAnchor, constant: 12),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        isHovered = false
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [onClick] in
            onClick?()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHighlight()
    }

    private func updateHighlight() {
        layer?.backgroundColor = isHovered
            ? NSColor.labelColor.withAlphaComponent(0.06).cgColor
            : NSColor.clear.cgColor
    }
}

// MARK: - Empty Row Placeholder

private final class DashboardEmptyRowView: NSView {
    private let label = NSTextField(labelWithString: "暂无活跃会话 · 等待 Agent 启动")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Dashboard View

final class MomiDashboardView: NSView {
    private let headerAgent = NSTextField(labelWithString: "Agent")
    private let headerModel = NSTextField(labelWithString: "模型")
    private let headerSpeed = NSTextField(labelWithString: "速度")

    private let rowsStack = NSStackView()
    private var rowViews: [AgentTableRowView] = []
    private var emptyRowView: DashboardEmptyRowView?

    private let separator = NSBox()
    private let footerView = DashboardFooterView()

    var onSelectInstance: ((MonitoredInstance) -> Void)?
    var onOpenStats: (() -> Void)? {
        get { footerView.onClick }
        set { footerView.onClick = newValue }
    }

    private let totalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 86))
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true

        for label in [headerAgent, headerModel, headerSpeed] {
            label.font = .systemFont(ofSize: 9.5, weight: .semibold)
            label.textColor = .tertiaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        headerSpeed.alignment = .right

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 0
        rowsStack.distribution = .fill
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        addSubview(footerView)

        NSLayoutConstraint.activate([
            headerAgent.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            headerAgent.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerAgent.heightAnchor.constraint(equalToConstant: 14),

            headerModel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 50),
            headerModel.centerYAnchor.constraint(equalTo: headerAgent.centerYAnchor),

            headerSpeed.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            headerSpeed.centerYAnchor.constraint(equalTo: headerAgent.centerYAnchor),
            headerSpeed.widthAnchor.constraint(equalToConstant: 72),

            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: headerAgent.bottomAnchor, constant: 2),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            separator.topAnchor.constraint(equalTo: rowsStack.bottomAnchor, constant: 4),
            separator.heightAnchor.constraint(equalToConstant: 1),

            footerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            footerView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 2),
            footerView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2),
        ])
    }

    func configure(with instances: [MonitoredInstance]) {
        if instances.isEmpty {
            if emptyRowView != nil && rowViews.isEmpty { return }
            clearRows()
            let placeholder = DashboardEmptyRowView()
            rowsStack.addArrangedSubview(placeholder)
            placeholder.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            emptyRowView = placeholder
            setFrameSize(NSSize(width: 280, height: 86))
            return
        }

        if emptyRowView != nil {
            clearRows()
        }

        guard rowViews.count != instances.count else { return }

        clearRows()
        rowViews = instances.map { _ in
            let row = AgentTableRowView()
            row.onSelect = { [weak self] selected in
                self?.onSelectInstance?(selected)
            }
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            return row
        }

        setFrameSize(NSSize(width: 280, height: 56 + CGFloat(instances.count) * 30))
    }

    private func clearRows() {
        for row in rowViews {
            rowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rowViews.removeAll()
        if let empty = emptyRowView {
            rowsStack.removeArrangedSubview(empty)
            empty.removeFromSuperview()
            emptyRowView = nil
        }
    }

    func update(with instances: [MonitoredInstance]) {
        configure(with: instances)

        for (row, instance) in zip(rowViews, instances) {
            row.update(instance: instance, icon: icon(for: instance))
        }
    }

    func updateTotal(_ total: Int64, indexing: Bool) {
        if total > 0 {
            footerView.valueLabel.stringValue = totalFormatter.string(from: NSNumber(value: total)) ?? "\(total)"
            footerView.valueLabel.textColor = .labelColor
            footerView.toolTip = indexing
                ? "输入 + 输出，正在更新索引… · 点击打开用量统计"
                : "输入 + 输出，不含缓存读取 · 点击打开用量统计"
        } else {
            footerView.valueLabel.stringValue = indexing ? "索引中…" : "--"
            footerView.valueLabel.textColor = indexing ? .tertiaryLabelColor : .labelColor
            footerView.toolTip = "点击打开用量统计"
        }
    }

    private func icon(for instance: MonitoredInstance) -> NSImage? {
        guard let image = NSImage(named: instance.iconResourceName) else { return nil }
        image.isTemplate = true
        return image
    }
}
