import AppKit

// MARK: - Compact & Exact Token Formatting

private enum UsageNumberFormat {
    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let creditsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func compact(_ value: Int64) -> String {
        let absVal = abs(value)
        if absVal >= 1_000_000_000 {
            return String(format: "%.2fB", Double(value) / 1_000_000_000)
        }
        if absVal >= 100_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if absVal >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if absVal >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    static func exact(_ value: Int64) -> String {
        intFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func exactInt(_ value: Int) -> String {
        intFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func credits(_ value: Double) -> String {
        creditsFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

// MARK: - Solid Native Palette (No Translucent Washes)

private enum UsagePalette {
    static let seriesColors: [NSColor] = [
        NSColor.systemBlue,
        NSColor.systemTeal,
        NSColor.systemOrange,
        NSColor.systemIndigo,
        NSColor.systemGreen
    ]

    static func color(forRank rank: Int?) -> NSColor {
        guard let rank = rank, rank >= 0, rank < seriesColors.count else {
            return NSColor.systemGray
        }
        return seriesColors[rank]
    }

    static func inputBarColor(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.28, green: 0.31, blue: 0.36, alpha: 1.0)
            : NSColor(srgbRed: 0.80, green: 0.83, blue: 0.87, alpha: 1.0)
    }

    static func outputBarColor() -> NSColor {
        NSColor.controlAccentColor
    }

    static func trackColor(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.19, green: 0.20, blue: 0.23, alpha: 1.0)
            : NSColor(srgbRed: 0.92, green: 0.93, blue: 0.95, alpha: 1.0)
    }

    static func cardBackground(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.14, green: 0.15, blue: 0.17, alpha: 1.0)
            : NSColor(srgbRed: 0.99, green: 0.99, blue: 0.995, alpha: 1.0)
    }

    static func hoverRowBackground(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.20, green: 0.21, blue: 0.24, alpha: 1.0)
            : NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1.0)
    }
}

// MARK: - Sorting & Column Layout

private enum UsageSortColumn: Int {
    case name
    case input
    case output
    case total
    case cache
    case share
}

private struct UsageColumnLayout {
    static let rowHeight: CGFloat = 32
    static let headerHeight: CGFloat = 26

    let name: NSRect
    let input: NSRect
    let output: NSRect
    let total: NSRect
    let cache: NSRect
    let share: NSRect

    static func make(width: CGFloat, height: CGFloat) -> UsageColumnLayout {
        let gap: CGFloat = 14
        let nameGap: CGFloat = 18
        var x = width

        func take(_ colWidth: CGFloat) -> NSRect {
            x -= colWidth
            let rect = NSRect(x: x, y: 0, width: colWidth, height: height)
            x -= gap
            return rect
        }

        let share = take(64)
        let cache = take(76)
        let total = take(80)
        let output = take(72)
        let input = take(72)
        let name = NSRect(x: 0, y: 0, width: max(0, input.minX - nameGap), height: height)

        return UsageColumnLayout(
            name: name,
            input: input,
            output: output,
            total: total,
            cache: cache,
            share: share
        )
    }

    func columns() -> [(UsageSortColumn, NSRect)] {
        [
            (.name, name),
            (.input, input),
            (.output, output),
            (.total, total),
            (.cache, cache),
            (.share, share)
        ]
    }
}

private func usageFontHeight(_ font: NSFont) -> CGFloat {
    ceil(font.ascender - font.descender)
}

private func drawUsageString(
    _ string: String,
    in rect: NSRect,
    alignment: NSTextAlignment,
    font: NSFont,
    color: NSColor
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    let height = usageFontHeight(font)
    let y = floor(rect.midY - height / 2)
    (string as NSString).draw(
        in: NSRect(x: rect.minX, y: y, width: rect.width, height: height + 2),
        withAttributes: attributes
    )
}

private func drawUsageAttributedString(
    _ string: NSAttributedString,
    in rect: NSRect,
    alignment: NSTextAlignment,
    font: NSFont
) {
    let mutable = NSMutableAttributedString(attributedString: string)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    mutable.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutable.length))
    let height = usageFontHeight(font)
    let y = floor(rect.midY - height / 2)
    mutable.draw(in: NSRect(x: rect.minX, y: y, width: rect.width, height: height + 2))
}

// MARK: - Hairline Divider

private final class UsageHairlineView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let scale = max(1, window?.backingScaleFactor ?? 2)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1 / scale).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Responsive Padded Text Button

private final class ActionPillButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updateHighlight() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 5
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 14, height: max(base.height + 8, 24))
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.5
            if !isEnabled { isHovered = false }
            window?.invalidateCursorRects(for: self)
        }
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
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if isEnabled { isHovered = true }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHighlight()
    }

    private func updateHighlight() {
        layer?.backgroundColor = (isHovered && isEnabled)
            ? UsagePalette.hoverRowBackground(for: effectiveAppearance).cgColor
            : NSColor.clear.cgColor
    }
}

// MARK: - Solid Daily Trend + Storage-Style Breakdown Panel

private struct BreakdownSegment {
    let name: String
    let value: Int64
    let share: Double
    let color: NSColor
}

private final class UsageChartsPanelView: NSView {
    var total = TokenUsage() {
        didSet { needsDisplay = true }
    }

    var series: [UsageDayPoint] = [] {
        didSet {
            hoveredIndex = nil
            needsDisplay = true
        }
    }

    var segments: [BreakdownSegment] = [] {
        didSet { needsDisplay = true }
    }

    var period: UsagePeriod = .all {
        didSet { needsDisplay = true }
    }

    var onHoverDay: ((UsageDayPoint?) -> Void)?

    private var hoveredIndex: Int?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = effectiveAppearance
        let cardRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 8, yRadius: 8)
        UsagePalette.cardBackground(for: appearance).setFill()
        cardPath.fill()
        NSColor.separatorColor.setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        drawSummaryBar(appearance: appearance)
        drawDailyChart(appearance: appearance)
        drawBreakdownBar(appearance: appearance)
    }

    private func drawSummaryBar(appearance: NSAppearance) {
        let stripH: CGFloat = 32
        let padX: CGFloat = 14
        let scale = max(1, window?.backingScaleFactor ?? 2)

        NSColor.separatorColor.setFill()
        NSRect(x: 1, y: stripH, width: max(0, bounds.width - 2), height: 1 / scale).fill()

        let labelFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let subFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        var x = padX

        func drawMetric(swatch: NSColor?, title: String, value: String, suffix: String) {
            if let swatch = swatch {
                let rect = NSRect(x: x, y: 12, width: 8, height: 8)
                swatch.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
                x += 13
            }
            let attr = NSMutableAttributedString()
            attr.append(NSAttributedString(string: title + " ", attributes: [
                .font: labelFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
            attr.append(NSAttributedString(string: value, attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.labelColor
            ]))
            if !suffix.isEmpty {
                attr.append(NSAttributedString(string: " " + suffix, attributes: [
                    .font: subFont,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]))
            }
            let w = ceil(attr.size().width) + 2
            drawUsageAttributedString(attr, in: NSRect(x: x, y: 0, width: w, height: stripH), alignment: .left, font: valueFont)
            x += w + 16
        }

        let denom = max(1, total.total)
        let inPct = total.total > 0 ? Double(total.input) / Double(denom) * 100 : 0
        let outPct = total.total > 0 ? Double(total.output) / Double(denom) * 100 : 0

        drawMetric(
            swatch: UsagePalette.inputBarColor(for: appearance),
            title: "输入",
            value: UsageNumberFormat.compact(total.input),
            suffix: total.total > 0 ? String(format: "%.1f%%", inPct) : ""
        )
        drawMetric(
            swatch: UsagePalette.outputBarColor(),
            title: "输出",
            value: UsageNumberFormat.compact(total.output),
            suffix: total.total > 0 ? String(format: "%.1f%%", outPct) : ""
        )

        let right = NSMutableAttributedString()
        right.append(NSAttributedString(string: "缓存 ", attributes: [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        right.append(NSAttributedString(string: UsageNumberFormat.compact(total.cache), attributes: [
            .font: valueFont,
            .foregroundColor: NSColor.labelColor
        ]))
        let promptTotal = total.cache + total.input
        if total.cache > 0 && promptTotal > 0 {
            let hitRate = Double(total.cache) / Double(promptTotal) * 100
            right.append(NSAttributedString(string: String(format: " (命中 %.1f%%)", hitRate), attributes: [
                .font: subFont,
                .foregroundColor: NSColor.tertiaryLabelColor
            ]))
        }
        if total.credits > 0 {
            right.append(NSAttributedString(string: "   额度 ", attributes: [
                .font: labelFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
            right.append(NSAttributedString(string: UsageNumberFormat.credits(total.credits), attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.labelColor
            ]))
        } else if total.requests > 0 {
            right.append(NSAttributedString(string: "   请求 ", attributes: [
                .font: labelFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
            right.append(NSAttributedString(string: "\(UsageNumberFormat.exactInt(total.requests)) 次", attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.labelColor
            ]))
        }

        let rightW = max(0, bounds.width - padX - x)
        if rightW > 60 {
            drawUsageAttributedString(right, in: NSRect(x: x, y: 0, width: rightW, height: stripH), alignment: .right, font: valueFont)
        }
    }

    private func chartGeometry() -> (plotRect: NSRect, slots: [NSRect], barCols: [NSRect]) {
        let leftAxisW: CGFloat = 46
        let padRight: CGFloat = 14
        let topY: CGFloat = 44
        let plotH: CGFloat = 68
        let plotX = 14 + leftAxisW
        let plotW = max(0, bounds.width - plotX - padRight)
        let plotRect = NSRect(x: plotX, y: topY, width: plotW, height: plotH)
        guard !series.isEmpty, plotW > 0 else { return (plotRect, [], []) }

        let count = series.count
        let gap: CGFloat = count <= 7 ? 14 : 4
        let totalGap = gap * CGFloat(max(0, count - 1))
        let barW = max(4, floor((plotW - totalGap) / CGFloat(count)))
        let usedW = barW * CGFloat(count) + totalGap
        let startX = plotX + floor((plotW - usedW) / 2)

        var slots: [NSRect] = []
        var bars: [NSRect] = []
        for idx in 0..<count {
            let x = startX + CGFloat(idx) * (barW + gap)
            slots.append(NSRect(x: x - floor(gap / 2), y: topY - 4, width: barW + gap, height: plotH + 22))
            bars.append(NSRect(x: x, y: topY, width: barW, height: plotH))
        }
        return (plotRect, slots, bars)
    }

    private func drawDailyChart(appearance: NSAppearance) {
        let (plotRect, slots, barCols) = chartGeometry()
        guard !series.isEmpty, !barCols.isEmpty else {
            drawUsageString(
                "暂无按日趋势数据",
                in: NSRect(x: 0, y: 64, width: bounds.width, height: 22),
                alignment: .center,
                font: .systemFont(ofSize: 11, weight: .regular),
                color: .tertiaryLabelColor
            )
            return
        }

        let maxDay = series.map { $0.usage.total }.max() ?? 0
        let scale = max(1, window?.backingScaleFactor ?? 2)
        let axisFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

        // Y-axis gridlines & crisp labels
        let gridColor = NSColor.separatorColor
        gridColor.setFill()
        NSRect(x: plotRect.minX, y: plotRect.minY, width: plotRect.width, height: 1 / scale).fill()
        NSRect(x: plotRect.minX, y: plotRect.midY, width: plotRect.width, height: 1 / scale).fill()
        NSRect(x: plotRect.minX, y: plotRect.maxY, width: plotRect.width, height: 1 / scale).fill()

        if maxDay > 0 {
            drawUsageString(
                UsageNumberFormat.compact(maxDay),
                in: NSRect(x: 10, y: plotRect.minY - 7, width: 44, height: 14),
                alignment: .right,
                font: axisFont,
                color: .tertiaryLabelColor
            )
            drawUsageString(
                UsageNumberFormat.compact(maxDay / 2),
                in: NSRect(x: 10, y: plotRect.midY - 7, width: 44, height: 14),
                alignment: .right,
                font: axisFont,
                color: .tertiaryLabelColor
            )
        }
        drawUsageString(
            "0",
            in: NSRect(x: 10, y: plotRect.maxY - 7, width: 44, height: 14),
            alignment: .right,
            font: axisFont,
            color: .tertiaryLabelColor
        )

        let inColor = UsagePalette.inputBarColor(for: appearance)
        let outColor = UsagePalette.outputBarColor()
        let dimColor = UsagePalette.trackColor(for: appearance)

        for (idx, point) in series.enumerated() {
            let col = barCols[idx]
            let isHovered = (hoveredIndex == idx)
            let isDimmed = (period == .today && !point.isToday && !isHovered)

            if isHovered {
                let hl = slots[idx].insetBy(dx: 1, dy: 0)
                UsagePalette.hoverRowBackground(for: appearance).setFill()
                NSBezierPath(roundedRect: hl, xRadius: 4, yRadius: 4).fill()
            }

            let dayTotal = point.usage.total
            if dayTotal > 0 && maxDay > 0 {
                let rawH = Double(dayTotal) / Double(maxDay) * Double(col.height)
                let barH = max(3, CGFloat(Int(rawH.rounded())))
                let barRect = NSRect(x: col.minX, y: col.maxY - barH, width: col.width, height: barH)

                let outRatio = Double(point.usage.output) / Double(dayTotal)
                let outH: CGFloat = point.usage.output > 0
                    ? min(barH, max(2, CGFloat(Int((Double(barH) * outRatio).rounded()))))
                    : 0

                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2).addClip()

                if isDimmed {
                    dimColor.setFill()
                    barRect.fill()
                } else {
                    if outH > 0 {
                        outColor.setFill()
                        NSRect(x: barRect.minX, y: barRect.minY, width: barRect.width, height: outH).fill()
                    }
                    if barH > outH {
                        inColor.setFill()
                        NSRect(x: barRect.minX, y: barRect.minY + outH, width: barRect.width, height: barH - outH).fill()
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
            } else {
                dimColor.setFill()
                NSRect(x: col.minX, y: col.maxY - 2, width: col.width, height: 2).fill()
            }
        }

        // X-axis ticks
        let count = series.count
        let tickIndices: Set<Int> = count <= 7
            ? Set(0..<count)
            : [0, count / 4, count / 2, (count * 3) / 4, count - 1]
        let activeFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let labelY = plotRect.maxY + 4

        for idx in tickIndices.sorted() where series.indices.contains(idx) {
            let point = series[idx]
            let col = barCols[idx]
            let active = (hoveredIndex == idx) || (period == .today && point.isToday)
            let labelW: CGFloat = 46
            let labelX: CGFloat
            let align: NSTextAlignment
            if idx == 0 && count > 7 {
                labelX = col.minX
                align = .left
            } else if idx == count - 1 && count > 7 {
                labelX = col.maxX - labelW
                align = .right
            } else {
                labelX = floor(col.midX - labelW / 2)
                align = .center
            }
            drawUsageString(
                point.label,
                in: NSRect(x: labelX, y: labelY, width: labelW, height: 15),
                alignment: align,
                font: active ? activeFont : axisFont,
                color: active ? .labelColor : .tertiaryLabelColor
            )
        }
    }

    private func drawBreakdownBar(appearance: NSAppearance) {
        let padX: CGFloat = 14
        let sepY: CGFloat = 136
        let scale = max(1, window?.backingScaleFactor ?? 2)

        NSColor.separatorColor.setFill()
        NSRect(x: 1, y: sepY, width: max(0, bounds.width - 2), height: 1 / scale).fill()

        let barRect = NSRect(x: padX, y: 147, width: max(0, bounds.width - padX * 2), height: 10)
        UsagePalette.trackColor(for: appearance).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 4, yRadius: 4).fill()

        guard !segments.isEmpty else { return }

        let totalVal = segments.reduce(Int64(0)) { $0 + $1.value }
        if totalVal > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: barRect, xRadius: 4, yRadius: 4).addClip()
            var cursorX = barRect.minX
            for (idx, seg) in segments.enumerated() where seg.value > 0 {
                let w: CGFloat
                if idx == segments.count - 1 {
                    w = max(0, barRect.maxX - cursorX)
                } else {
                    w = max(2, floor(barRect.width * CGFloat(Double(seg.value) / Double(totalVal))))
                }
                seg.color.setFill()
                NSRect(x: cursorX, y: barRect.minY, width: w, height: barRect.height).fill()
                if idx < segments.count - 1 && w > 2 {
                    UsagePalette.cardBackground(for: appearance).setFill()
                    NSRect(x: cursorX + w - 1, y: barRect.minY, width: 1, height: barRect.height).fill()
                }
                cursorX += w
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        // Legend row below the segmented bar
        let legendY: CGFloat = 162
        let legendH: CGFloat = 18
        let nameFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let pctFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        var lx = padX
        let maxX = bounds.width - padX

        for seg in segments {
            let pctText = seg.share < 0.1 ? "<0.1%" : String(format: "%.1f%%", seg.share)
            let item = NSMutableAttributedString()
            item.append(NSAttributedString(string: seg.name + " ", attributes: [
                .font: nameFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
            item.append(NSAttributedString(string: pctText, attributes: [
                .font: pctFont,
                .foregroundColor: NSColor.tertiaryLabelColor
            ]))
            let itemW = min(132, ceil(item.size().width) + 2)
            if lx + 12 + itemW > maxX { break }

            seg.color.setFill()
            NSBezierPath(roundedRect: NSRect(x: lx, y: legendY + 5, width: 8, height: 8), xRadius: 2, yRadius: 2).fill()
            drawUsageAttributedString(
                item,
                in: NSRect(x: lx + 12, y: legendY, width: itemW, height: legendH),
                alignment: .left,
                font: nameFont
            )
            lx += 12 + itemW + 14
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let (_, slots, _) = chartGeometry()
        let next = slots.firstIndex(where: { $0.contains(point) })
        if next != hoveredIndex {
            hoveredIndex = next
            needsDisplay = true
            if let idx = next, series.indices.contains(idx) {
                onHoverDay?(series[idx])
            } else {
                onHoverDay?(nil)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredIndex != nil {
            hoveredIndex = nil
            needsDisplay = true
            onHoverDay?(nil)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Sortable Table Header View

private final class UsageStatsHeaderView: NSView {
    var groupByAgent = false {
        didSet { needsDisplay = true }
    }

    var activeSortColumn: UsageSortColumn? {
        didSet { needsDisplay = true }
    }

    var sortAscending = false {
        didSet { needsDisplay = true }
    }

    var onSelectSort: ((UsageSortColumn) -> Void)?

    private var hoveredColumn: UsageSortColumn?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let layout = UsageColumnLayout.make(width: bounds.width, height: bounds.height)
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let activeFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

        func title(_ col: UsageSortColumn, base: String) -> String {
            guard activeSortColumn == col else { return base }
            return base + (sortAscending ? " ↑" : " ↓")
        }

        func color(for col: UsageSortColumn) -> NSColor {
            if activeSortColumn == col { return .labelColor }
            if hoveredColumn == col { return .secondaryLabelColor }
            return .tertiaryLabelColor
        }

        func labelFont(for col: UsageSortColumn) -> NSFont {
            activeSortColumn == col ? activeFont : font
        }

        drawUsageString(title(.name, base: groupByAgent ? "Agent" : "模型"), in: layout.name, alignment: .left, font: labelFont(for: .name), color: color(for: .name))
        drawUsageString(title(.input, base: "输入"), in: layout.input, alignment: .right, font: labelFont(for: .input), color: color(for: .input))
        drawUsageString(title(.output, base: "输出"), in: layout.output, alignment: .right, font: labelFont(for: .output), color: color(for: .output))
        drawUsageString(title(.total, base: "合计"), in: layout.total, alignment: .right, font: labelFont(for: .total), color: color(for: .total))
        drawUsageString(title(.cache, base: "缓存"), in: layout.cache, alignment: .right, font: labelFont(for: .cache), color: color(for: .cache))
        drawUsageString(title(.share, base: "占比"), in: layout.share, alignment: .right, font: labelFont(for: .share), color: color(for: .share))

        let scale = max(1, window?.backingScaleFactor ?? 2)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1 / scale, width: bounds.width, height: 1 / scale).fill()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let layout = UsageColumnLayout.make(width: bounds.width, height: bounds.height)
        for (col, rect) in layout.columns() where rect.contains(point) {
            onSelectSort?(col)
            return
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let layout = UsageColumnLayout.make(width: bounds.width, height: bounds.height)
        for (_, rect) in layout.columns() {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let layout = UsageColumnLayout.make(width: bounds.width, height: bounds.height)
        let next = layout.columns().first(where: { $0.1.contains(point) })?.0
        if next != hoveredColumn {
            hoveredColumn = next
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredColumn != nil {
            hoveredColumn = nil
            needsDisplay = true
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Clean Ranked Rows Table

private final class UsageStatsRowsView: NSView, NSViewToolTipOwner {
    var rows: [UsageRow] = [] {
        didSet {
            refreshToolTips()
            needsDisplay = true
        }
    }

    var rankByName: [String: Int] = [:] {
        didSet { needsDisplay = true }
    }

    var groupByAgent = false {
        didSet { needsDisplay = true }
    }

    var periodTotal: Int64 = 0 {
        didSet { needsDisplay = true }
    }

    var emptyText = "" {
        didSet { needsDisplay = true }
    }

    private var tintedIcons: [String: NSImage] = [:]
    private var hoveredRow: Int?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty else {
            drawUsageString(
                emptyText.isEmpty ? "暂无用量记录" : emptyText,
                in: NSRect(x: 0, y: 48, width: bounds.width, height: 22),
                alignment: .center,
                font: .systemFont(ofSize: 12, weight: .regular),
                color: .tertiaryLabelColor
            )
            return
        }

        let appearance = effectiveAppearance
        let layout = UsageColumnLayout.make(width: bounds.width, height: UsageColumnLayout.rowHeight)
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let totalFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let shareFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        let nameFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let scale = max(1, window?.backingScaleFactor ?? 2)

        for (index, item) in rows.enumerated() {
            let rowRect = NSRect(
                x: 0,
                y: CGFloat(index) * UsageColumnLayout.rowHeight,
                width: bounds.width,
                height: UsageColumnLayout.rowHeight
            )

            if hoveredRow == index {
                let highlight = NSBezierPath(
                    roundedRect: rowRect.insetBy(dx: 0, dy: 2),
                    xRadius: 5,
                    yRadius: 5
                )
                UsagePalette.hoverRowBackground(for: appearance).setFill()
                highlight.fill()
            }

            var nameX = layout.name.minX
            if let iconName = item.iconName, let icon = tintedIcon(named: iconName) {
                icon.draw(
                    in: NSRect(x: nameX, y: rowRect.minY + 8, width: 16, height: 16),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
                nameX += 24
            } else {
                let dotColor = UsagePalette.color(forRank: rankByName[item.name])
                dotColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: nameX + 1, y: rowRect.minY + 12, width: 8, height: 8)).fill()
                nameX += 16
            }

            let nameRect = NSRect(
                x: nameX,
                y: rowRect.minY,
                width: max(0, layout.name.maxX - nameX),
                height: rowRect.height
            )
            let nameAttr = NSMutableAttributedString(
                string: item.name,
                attributes: [
                    .font: nameFont,
                    .foregroundColor: NSColor.labelColor
                ]
            )
            if item.usage.credits > 0 {
                nameAttr.append(NSAttributedString(
                    string: "  额度 \(UsageNumberFormat.credits(item.usage.credits))",
                    attributes: [
                        .font: badgeFont,
                        .foregroundColor: NSColor.tertiaryLabelColor
                    ]
                ))
            } else if groupByAgent && item.usage.requests > 0 {
                nameAttr.append(NSAttributedString(
                    string: "  \(UsageNumberFormat.exactInt(item.usage.requests)) 次",
                    attributes: [
                        .font: badgeFont,
                        .foregroundColor: NSColor.tertiaryLabelColor
                    ]
                ))
            }
            drawUsageAttributedString(nameAttr, in: nameRect, alignment: .left, font: nameFont)

            func cellRect(_ rect: NSRect) -> NSRect {
                NSRect(x: rect.minX, y: rowRect.minY, width: rect.width, height: rowRect.height)
            }

            func drawTokenCell(_ rect: NSRect, _ value: Int64, isTotal: Bool = false) {
                if item.usage.isCreditsOnly {
                    drawUsageString("—", in: cellRect(rect), alignment: .right, font: numberFont, color: .tertiaryLabelColor)
                } else {
                    drawUsageString(
                        UsageNumberFormat.compact(value),
                        in: cellRect(rect),
                        alignment: .right,
                        font: isTotal ? totalFont : numberFont,
                        color: isTotal ? .labelColor : .secondaryLabelColor
                    )
                }
            }

            drawTokenCell(layout.input, item.usage.input)
            drawTokenCell(layout.output, item.usage.output)
            drawTokenCell(layout.total, item.usage.total, isTotal: true)
            drawTokenCell(layout.cache, item.usage.cache)

            let shareText: String
            if item.usage.isCreditsOnly {
                shareText = "按额度"
            } else if periodTotal > 0 {
                let percent = Double(item.usage.total) / Double(periodTotal) * 100
                shareText = (percent > 0 && percent < 0.1) ? "<0.1%" : String(format: "%.1f%%", percent)
            } else {
                shareText = "—"
            }
            drawUsageString(
                shareText,
                in: cellRect(layout.share),
                alignment: .right,
                font: shareFont,
                color: item.usage.isCreditsOnly ? .tertiaryLabelColor : .secondaryLabelColor
            )

            if index < rows.count - 1 {
                NSColor.separatorColor.withAlphaComponent(0.45).setFill()
                NSRect(x: 0, y: rowRect.maxY - 1 / scale, width: bounds.width, height: 1 / scale).fill()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = Int(point.y / UsageColumnLayout.rowHeight)
        let next = rows.indices.contains(index) ? index : nil
        if next != hoveredRow {
            hoveredRow = next
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredRow != nil {
            hoveredRow = nil
            needsDisplay = true
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshToolTips()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        tintedIcons.removeAll()
        needsDisplay = true
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        let index = Int(point.y / UsageColumnLayout.rowHeight)
        guard rows.indices.contains(index) else { return "" }
        let item = rows[index]

        if item.usage.isCreditsOnly {
            let percent = item.usage.contextPeak * 100
            let peakSuffix = percent > 0 ? String(format: " · 上下文峰值 %.1f%%", percent) : ""
            return "\(item.name)\nQoder 按服务端额度计量：\(UsageNumberFormat.credits(item.usage.credits)) · 请求 \(UsageNumberFormat.exactInt(item.usage.requests)) 次\(peakSuffix)"
        }

        var lines = [
            "\(item.name) · 请求 \(UsageNumberFormat.exactInt(item.usage.requests)) 次",
            "合计：\(UsageNumberFormat.exact(item.usage.total))（输入 \(UsageNumberFormat.exact(item.usage.input)) / 输出 \(UsageNumberFormat.exact(item.usage.output))）",
            "缓存读取：\(UsageNumberFormat.exact(item.usage.cache))（单独统计，不计入合计）"
        ]
        if item.usage.credits > 0 {
            lines.append("计费额度：\(UsageNumberFormat.credits(item.usage.credits))")
        }
        return lines.joined(separator: "\n")
    }

    private func refreshToolTips() {
        removeAllToolTips()
        guard !rows.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        addToolTip(bounds, owner: self, userData: nil)
    }

    private func tintedIcon(named name: String) -> NSImage? {
        if let cached = tintedIcons[name] { return cached }
        guard let base = NSImage(named: name) else { return nil }
        if name == "agent_alma" {
            base.isTemplate = false
            tintedIcons[name] = base
            return base
        }
        base.isTemplate = true
        let size = NSSize(width: 16, height: 16)
        let tinted = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.secondaryLabelColor.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        tintedIcons[name] = tinted
        return tinted
    }
}

// MARK: - Scroll View

private final class UsageScrollView: NSScrollView {
    var contentHeight: CGFloat = 0

    override func layout() {
        super.layout()
        guard let documentView = documentView else { return }
        let viewport = contentView.bounds.size
        let height = max(contentHeight, viewport.height)
        if abs(documentView.frame.width - viewport.width) > 0.5
            || abs(documentView.frame.height - height) > 0.5 {
            documentView.frame = NSRect(x: 0, y: 0, width: viewport.width, height: height)
        }
    }
}

// MARK: - Usage Stats Window Controller

final class UsageStatsWindowController: NSWindowController {
    private var bundle: UsageSnapshotBundle?
    private var period: UsagePeriod = .all
    private var groupByAgent = false
    private var sortColumn: UsageSortColumn?
    private var sortAscending = false
    private var rows: [UsageRow] = []
    private var hoveredDay: UsageDayPoint?

    private let captionLabel = NSTextField(labelWithString: "累计 Token 消耗")
    private let totalLabel = NSTextField(labelWithString: "—")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let periodControl = NSSegmentedControl(labels: ["全部", "近 7 天", "今天"], trackingMode: .selectOne, target: nil, action: nil)
    private let groupControl = NSSegmentedControl(labels: ["模型", "Agent"], trackingMode: .selectOne, target: nil, action: nil)
    private let chartsPanel = UsageChartsPanelView()
    private let headerView = UsageStatsHeaderView()
    private let rowsView = UsageStatsRowsView()
    private let scrollView = UsageScrollView()
    private let footerSeparator = UsageHairlineView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let rebuildButton = ActionPillButton(frame: .zero)
    private let refreshButton = ActionPillButton(frame: .zero)

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var onRefreshIntervalChange: ((Double) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "用量统计"
        window.minSize = NSSize(width: 720, height: 500)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        captionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(captionLabel)

        totalLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        totalLabel.textColor = .labelColor
        totalLabel.toolTip = "输入 + 输出，不含缓存读取"
        totalLabel.setContentHuggingPriority(.required, for: .horizontal)
        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(totalLabel)

        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(subtitleLabel)

        periodControl.controlSize = .regular
        periodControl.selectedSegment = UsagePeriod.all.rawValue
        periodControl.target = self
        periodControl.action = #selector(periodChanged(_:))
        periodControl.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(periodControl)

        groupControl.controlSize = .regular
        groupControl.selectedSegment = 0
        groupControl.target = self
        groupControl.action = #selector(groupChanged(_:))
        groupControl.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(groupControl)

        chartsPanel.onHoverDay = { [weak self] day in
            guard let self = self else { return }
            self.hoveredDay = day
            self.updateSubtitleReadout()
        }
        chartsPanel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(chartsPanel)

        headerView.groupByAgent = groupByAgent
        headerView.onSelectSort = { [weak self] column in
            self?.toggleSort(column: column)
        }
        headerView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(headerView)

        rowsView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.documentView = rowsView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentHeight = 160
        content.addSubview(scrollView)

        footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footerSeparator)

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        rebuildButton.target = self
        rebuildButton.action = #selector(rebuildAction)
        rebuildButton.setContentHuggingPriority(.required, for: .horizontal)
        rebuildButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rebuildButton)
        updateRebuildButton(isIndexing: false)

        refreshButton.imagePosition = .imageTrailing
        refreshButton.imageHugsTitle = true
        refreshButton.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        refreshButton.contentTintColor = .tertiaryLabelColor
        refreshButton.toolTip = "刷新间隔"
        refreshButton.target = self
        refreshButton.action = #selector(showRefreshMenu)
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(refreshButton)
        syncRefreshIntervalDisplay()

        NSLayoutConstraint.activate([
            captionLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            captionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),

            totalLabel.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 2),
            totalLabel.leadingAnchor.constraint(equalTo: captionLabel.leadingAnchor),

            subtitleLabel.firstBaselineAnchor.constraint(equalTo: totalLabel.firstBaselineAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: totalLabel.trailingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: periodControl.leadingAnchor, constant: -16),

            groupControl.centerYAnchor.constraint(equalTo: totalLabel.centerYAnchor),
            groupControl.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            periodControl.centerYAnchor.constraint(equalTo: groupControl.centerYAnchor),
            periodControl.trailingAnchor.constraint(equalTo: groupControl.leadingAnchor, constant: -10),

            chartsPanel.topAnchor.constraint(equalTo: totalLabel.bottomAnchor, constant: 12),
            chartsPanel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            chartsPanel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            chartsPanel.heightAnchor.constraint(equalToConstant: 186),

            headerView.topAnchor.constraint(equalTo: chartsPanel.bottomAnchor, constant: 12),
            headerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: UsageColumnLayout.headerHeight),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 2),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: footerSeparator.topAnchor, constant: -2),

            footerSeparator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            footerSeparator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            footerSeparator.heightAnchor.constraint(equalToConstant: 1),
            footerSeparator.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -42),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            statusLabel.centerYAnchor.constraint(equalTo: footerSeparator.bottomAnchor, constant: 21),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: rebuildButton.leadingAnchor, constant: -12),

            rebuildButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            rebuildButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -8),

            refreshButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18)
        ])

        updateDisplay()
    }

    func apply(_ bundle: UsageSnapshotBundle) {
        self.bundle = bundle
        updateDisplay()
        if !bundle.isIndexing {
            fitWindowHeightToRows()
        }
    }

    func syncRefreshIntervalDisplay() {
        let interval = currentStoredRefreshInterval()
        let title = interval == floor(interval)
            ? String(format: "%.0fs", interval)
            : String(format: "%.1fs", interval)
        refreshButton.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        fitWindowHeightToRows()
    }

    @objc private func periodChanged(_ sender: NSSegmentedControl) {
        guard let next = UsagePeriod(rawValue: sender.selectedSegment) else { return }
        period = next
        hoveredDay = nil
        updateDisplay()
        scrollToTop()
        fitWindowHeightToRows()
    }

    @objc private func groupChanged(_ sender: NSSegmentedControl) {
        groupByAgent = sender.selectedSegment == 1
        sortColumn = nil
        sortAscending = false
        updateDisplay()
        scrollToTop()
        fitWindowHeightToRows()
    }

    private func toggleSort(column: UsageSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = (column == .name)
        }
        updateDisplay()
    }

    private func sorted(_ source: [UsageRow]) -> [UsageRow] {
        guard let column = sortColumn else { return source }
        let asc = sortAscending
        return source.sorted { lhs, rhs in
            if column == .name {
                let cmp = lhs.name.localizedStandardCompare(rhs.name)
                return asc ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
            let lVal: Double
            let rVal: Double
            switch column {
            case .name:
                lVal = 0; rVal = 0
            case .input:
                lVal = Double(lhs.usage.input); rVal = Double(rhs.usage.input)
            case .output:
                lVal = Double(lhs.usage.output); rVal = Double(rhs.usage.output)
            case .total, .share:
                lVal = Double(lhs.usage.total); rVal = Double(rhs.usage.total)
            case .cache:
                lVal = Double(lhs.usage.cache); rVal = Double(rhs.usage.cache)
            }
            if lVal != rVal {
                return asc ? (lVal < rVal) : (lVal > rVal)
            }
            if lhs.usage.credits != rhs.usage.credits {
                return asc ? (lhs.usage.credits < rhs.usage.credits) : (lhs.usage.credits > rhs.usage.credits)
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func buildBreakdown(from sourceRows: [UsageRow], totalTokens: Int64) -> ([BreakdownSegment], [String: Int]) {
        guard totalTokens > 0 else { return ([], [:]) }
        let ranked = sourceRows
            .filter { $0.usage.total > 0 }
            .sorted { $0.usage.total > $1.usage.total }
        guard !ranked.isEmpty else { return ([], [:]) }

        var rankMap: [String: Int] = [:]
        var segments: [BreakdownSegment] = []
        let topLimit = 5
        for (idx, row) in ranked.prefix(topLimit).enumerated() {
            rankMap[row.name] = idx
            let share = Double(row.usage.total) / Double(totalTokens) * 100
            segments.append(BreakdownSegment(
                name: row.name,
                value: row.usage.total,
                share: share,
                color: UsagePalette.color(forRank: idx)
            ))
        }
        if ranked.count > topLimit {
            let rest = ranked.dropFirst(topLimit).reduce(Int64(0)) { $0 + $1.usage.total }
            if rest > 0 {
                let share = Double(rest) / Double(totalTokens) * 100
                segments.append(BreakdownSegment(
                    name: "其他",
                    value: rest,
                    share: share,
                    color: UsagePalette.color(forRank: nil)
                ))
            }
        }
        return (segments, rankMap)
    }

    private func fitWindowHeightToRows() {
        guard let window = window, window.isVisible, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let rowsHeight = rows.isEmpty
            ? 160
            : CGFloat(rows.count) * UsageColumnLayout.rowHeight + 8
        let topInset = content.bounds.height - scrollView.frame.maxY
        let desiredContent = topInset + max(rowsHeight, 160) + 46
        let clamped = min(max(desiredContent, 500), 760)
        guard abs(content.bounds.height - clamped) > 1 else { return }

        var frame = window.frame
        let top = frame.maxY
        frame.size.height = window.frameRect(
            forContentRect: NSRect(x: 0, y: 0, width: frame.width, height: clamped)
        ).height
        frame.origin.y = top - frame.size.height
        if let screen = window.screen {
            frame = window.constrainFrameRect(frame, to: screen)
        }
        window.setFrame(frame, display: true)
    }

    private var periodName: String {
        switch period {
        case .all: return "全部历史"
        case .week: return "近 7 天"
        case .today: return "今天"
        }
    }

    private var periodCaption: String {
        switch period {
        case .all: return "累计 Token 消耗"
        case .week: return "近 7 天 Token 消耗"
        case .today: return "今日 Token 消耗"
        }
    }

    private func updateRebuildButton(isIndexing: Bool) {
        rebuildButton.isEnabled = !isIndexing
        rebuildButton.attributedTitle = NSAttributedString(
            string: isIndexing ? "索引中…" : "重建索引",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: isIndexing ? NSColor.tertiaryLabelColor : NSColor.secondaryLabelColor
            ]
        )
    }

    private func updateSubtitleReadout() {
        if let day = hoveredDay {
            if day.usage.total > 0 {
                let reqPart = day.usage.requests > 0 ? " · \(UsageNumberFormat.exactInt(day.usage.requests)) 次请求" : ""
                subtitleLabel.stringValue = "\(day.dateKey) · 合计 \(UsageNumberFormat.compact(day.usage.total))（输入 \(UsageNumberFormat.compact(day.usage.input)) / 输出 \(UsageNumberFormat.compact(day.usage.output))\(reqPart)）"
            } else if day.usage.credits > 0 {
                subtitleLabel.stringValue = "\(day.dateKey) · 额度 \(UsageNumberFormat.credits(day.usage.credits))"
            } else {
                subtitleLabel.stringValue = "\(day.dateKey) · 当日无用量记录"
            }
            subtitleLabel.textColor = .secondaryLabelColor
            return
        }

        let total = bundle?.periods[period]?.total ?? TokenUsage()
        if total.total > 0 {
            subtitleLabel.stringValue = "\(UsageNumberFormat.exact(total.total)) tokens"
        } else if total.credits > 0 {
            subtitleLabel.stringValue = "按服务端额度计量"
        } else {
            subtitleLabel.stringValue = ""
        }
        subtitleLabel.textColor = .tertiaryLabelColor
    }

    private func updateDisplay() {
        periodControl.selectedSegment = period.rawValue
        groupControl.selectedSegment = groupByAgent ? 1 : 0
        headerView.groupByAgent = groupByAgent
        headerView.activeSortColumn = sortColumn ?? (groupByAgent ? nil : .total)
        headerView.sortAscending = sortColumn == nil ? false : sortAscending
        captionLabel.stringValue = periodCaption

        guard let bundle = bundle else {
            updateRebuildButton(isIndexing: false)
            totalLabel.stringValue = "—"
            subtitleLabel.stringValue = ""
            chartsPanel.total = TokenUsage()
            chartsPanel.series = []
            chartsPanel.segments = []
            chartsPanel.period = period
            rows = []
            rowsView.rankByName = [:]
            rowsView.rows = []
            rowsView.emptyText = "正在载入用量数据…"
            scrollView.contentHeight = 160
            scrollView.needsLayout = true
            statusLabel.stringValue = ""
            return
        }

        updateRebuildButton(isIndexing: bundle.isIndexing)

        let snapshot = bundle.periods[period]
        let total = snapshot?.total ?? TokenUsage()
        if total.total == 0 && bundle.isIndexing {
            totalLabel.stringValue = "—"
        } else {
            totalLabel.stringValue = UsageNumberFormat.compact(total.total)
            totalLabel.toolTip = "精确合计：\(UsageNumberFormat.exact(total.total)) tokens（输入 + 输出，不含缓存读取）"
        }

        let baseRows = snapshot.map { groupByAgent ? $0.agentRows : $0.modelRows } ?? []
        let (segments, rankMap) = buildBreakdown(from: baseRows, totalTokens: total.total)

        chartsPanel.period = period
        chartsPanel.total = total
        chartsPanel.series = snapshot?.dailySeries ?? []
        chartsPanel.segments = segments
        updateSubtitleReadout()

        rows = sorted(baseRows)
        rowsView.rankByName = rankMap
        rowsView.groupByAgent = groupByAgent
        rowsView.periodTotal = total.total
        rowsView.emptyText = bundle.isIndexing
            ? "正在读取历史日志…"
            : (bundle.indexedAt == nil ? "尚未建立索引" : "当前筛选下没有用量记录")
        rowsView.rows = rows

        let rowHeight = CGFloat(rows.count) * UsageColumnLayout.rowHeight + 8
        scrollView.contentHeight = max(rowHeight, 160)
        scrollView.needsLayout = true

        var parts: [String] = []
        if bundle.isIndexing {
            let percent = Int((bundle.progress * 100).rounded())
            parts.append("正在建立历史索引 \(percent)%")
            parts.append(periodName)
            if bundle.fileCount > 0 {
                parts.append("\(bundle.fileCount) 个日志")
            }
        } else if let indexedAt = bundle.indexedAt {
            parts.append(periodName)
            parts.append("\(rows.count) 个\(groupByAgent ? " Agent" : "模型")")
            parts.append("\(bundle.fileCount) 个日志")
            parts.append("更新于 \(timeFormatter.string(from: indexedAt))")
        } else {
            parts.append(periodName)
            parts.append("尚未建立索引")
        }
        statusLabel.stringValue = parts.joined(separator: " · ")
    }

    private func scrollToTop() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc private func showRefreshMenu() {
        let current = currentStoredRefreshInterval()
        let menu = NSMenu()
        var selectedItem: NSMenuItem?
        for interval in refreshIntervalOptions {
            let title = interval == floor(interval)
                ? String(format: "%.0f 秒", interval)
                : String(format: "%.1f 秒", interval)
            let item = NSMenuItem(title: title, action: #selector(selectRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = interval
            let isSelected = abs(current - interval) < 0.01
            item.state = isSelected ? .on : .off
            if isSelected { selectedItem = item }
            menu.addItem(item)
        }
        menu.popUp(
            positioning: selectedItem,
            at: NSPoint(x: 0, y: 0),
            in: refreshButton
        )
    }

    @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? Double else { return }
        UserDefaults.standard.set(interval, forKey: refreshIntervalDefaultsKey)
        syncRefreshIntervalDisplay()
        onRefreshIntervalChange?(interval)
    }

    @objc private func rebuildAction() {
        let alert = NSAlert()
        alert.messageText = "重建用量索引？"
        alert.informativeText = "将重新扫描全部 Agent 的历史会话日志。首次全量扫描可能需要几秒到几十秒。"
        alert.addButton(withTitle: "重建")
        alert.addButton(withTitle: "取消")
        if let window = window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    UsageIndex.shared.rebuild()
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            UsageIndex.shared.rebuild()
        }
    }
}
