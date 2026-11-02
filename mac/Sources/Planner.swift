import AppKit

private let plannerWidth: CGFloat = 600
private let lineHeight: CGFloat = 52
private let margin: CGFloat = 46                 // x of the red margin line
private let firstLine: CGFloat = 66 + lineHeight // y of the line a new subject is written on

/// A page of a study planner that pops up beside the pet, like SubjectPicker.cs: today's
/// date at the top, a ruled line to write a new subject on, and below it the subjects
/// ranked by this month's study time ("TOP 1.  영어    4h 30m (5d 3h)"). Click one to
/// start; ✕ crosses one off the list, asking whether its records go too. Clicking
/// elsewhere or Esc closes it.
final class Planner: NSPanel {
    static let paper = Sprites.color(0xFFFDF4)
    static let ink = Sprites.color(0x3A2E39)
    static let pencil = Sprites.color(0x8A8088)
    static let stamp = Sprites.color(0xE2574C)
    static let highlight = Sprites.color(0xFFF1A8)

    var picked: ((String) -> Void)?
    /// The subject, and whether its study records should go too.
    var removed: ((String, Bool) -> Void)?

    private let input = NSTextField()
    private var asking = false
    private var closing = false

    init(ranking: [Records.Rank], anchor: NSRect) {
        let area = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame ?? anchor
        let width = min(plannerWidth, area.width - 16)
        let height = min(max(300, firstLine + CGFloat(max(1, ranking.count)) * lineHeight + 16), area.height - 16)
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless],
                   backing: .buffered, defer: false)
        level = .floating
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        backgroundColor = Planner.paper

        let paper = PaperView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        paper.empty = ranking.isEmpty
        contentView = paper
        let right = width - 14

        let start = PaperButton(frame: NSRect(x: right - 92, y: firstLine - 40 - 4, width: 92, height: 40))
        start.hoverColor = Sprites.color(0xFFE8E5)
        start.paint = { b in
            Planner.stamp.setStroke()
            let border = NSBezierPath(rect: b.bounds.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
            drawLine("시작!", font: .boldSystemFont(ofSize: 15), color: Planner.stamp, in: b.bounds)
        }
        start.onClick = { [weak self] in self?.pick(self?.input.stringValue ?? "") }
        paper.addSubview(start)

        input.isBordered = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.font = .systemFont(ofSize: 18)
        input.textColor = Planner.ink
        input.placeholderString = "새 과목 적기"
        input.cell?.sendsActionOnEndEditing = false // only Return starts; clicking away must not
        input.target = self
        input.action = #selector(enter)
        input.frame = NSRect(x: margin + 10, y: firstLine - 26 - 3, width: start.frame.minX - margin - 22, height: 26)
        paper.addSubview(input)

        let scroll = NSScrollView(frame: NSRect(x: 1, y: firstLine + 1, width: width - 2, height: height - firstLine - 9))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let rows = PaperRows(frame: NSRect(x: 0, y: 0, width: width - 18, height: max(scroll.bounds.height, CGFloat(max(1, ranking.count)) * lineHeight)))
        rows.empty = ranking.isEmpty
        scroll.documentView = rows
        paper.addSubview(scroll)
        let rankFont = NSFont.boldSystemFont(ofSize: 14.5)
        let timeFont = NSFont.systemFont(ofSize: 13)
        let subjectFont = NSFont.systemFont(ofSize: 16)
        for (i, item) in ranking.enumerated() {
            let rank = "TOP \(i + 1)."
            let time = "\(Records.short(item.month)) (\(Records.short(item.total)))"
            let rowTop = CGFloat(i) * lineHeight + 4
            let row = PaperButton(frame: NSRect(x: margin + 4, y: rowTop, width: right - margin - lineHeight - 24, height: lineHeight - 6))
            row.setAccessibilityLabel("\(rank) \(item.subject), 이번 달 \(Records.duration(item.month)), 전체 \(Records.duration(item.total))")
            row.onClick = { [weak self] in self?.pick(item.subject) }
            row.paint = { b in
                // Rank on the left in red, the times on the right, the subject in between.
                let area = b.bounds.insetBy(dx: 8, dy: 0)
                let struck = !b.isEnabled
                let rankWidth = textWidth(rank, rankFont)
                let timeWidth = textWidth(time, timeFont)
                drawLine(rank, font: rankFont, color: struck ? Planner.pencil : Planner.stamp, in: area, align: .left)
                drawLine(time, font: timeFont, color: Planner.pencil, in: area, align: .right)
                drawLine(item.subject, font: subjectFont, color: struck ? Planner.pencil : Planner.ink,
                         in: NSRect(x: area.minX + rankWidth + 10, y: area.minY, width: area.width - rankWidth - timeWidth - 20, height: area.height),
                         align: .left, strike: struck)
            }

            let remove = PaperButton(frame: NSRect(x: right - lineHeight - 12, y: rowTop, width: lineHeight - 4, height: lineHeight - 6))
            remove.setAccessibilityLabel(item.subject + " 목록에서 지우기")
            remove.paint = { b in drawLine("✕", font: timeFont, color: Planner.pencil, in: b.bounds) }
            remove.onClick = { [weak self, weak row, weak remove] in
                guard let self else { return }
                var alsoRecords = false
                if item.total >= 1 {
                    switch self.askRemove(item) {
                    case nil: return
                    case let answer?: alsoRecords = answer
                    }
                }
                self.removed?(item.subject, alsoRecords)
                // Crossed off, like in a real planner; it comes back next time it's studied.
                row?.isEnabled = false
                remove?.isHidden = true
            }
            row.toolTip = "\(item.subject) · 이번 달 \(Records.duration(item.month)) · 전체 \(Records.duration(item.total))"
            rows.addSubview(row)
            rows.addSubview(remove)
        }

        // Bottom-right corner on the pet's, kept inside the screen.
        setFrameOrigin(NSPoint(x: max(area.minX, min(anchor.maxX - width, area.maxX - width)),
                               y: max(area.minY, min(anchor.minY, area.maxY - height))))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { true }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(input)
    }

    /// true: the records go too, false: off the list only, nil: never mind.
    private func askRemove(_ item: Records.Rank) -> Bool? {
        asking = true // the question box takes focus; that mustn't close the page
        defer {
            asking = false
            makeKeyAndOrderFront(nil)
        }
        let alert = NSAlert()
        alert.messageText = "‘\(item.subject)’ 과목을 목록에서 뺄게요."
        alert.informativeText = "지금까지 공부한 기록(\(Records.duration(item.total)))도 지울까요?\n지운 기록은 통계에서도 사라져요."
        alert.addButton(withTitle: "목록에서만 빼기")
        alert.addButton(withTitle: "기록까지 지우기")
        alert.addButton(withTitle: "취소").keyEquivalent = "\u{1b}"
        alert.window.level = .modalPanel
        switch alert.runModal() {
        case .alertFirstButtonReturn: return false
        case .alertSecondButtonReturn: return true
        default: return nil
        }
    }

    @objc private func enter() { pick(input.stringValue) }

    private func pick(_ raw: String) {
        let subject = Records.cleanSubject(raw)
        if subject.isEmpty {
            makeFirstResponder(input)
            return
        }
        close()
        picked?(subject)
    }

    override func cancelOperation(_ sender: Any?) { close() }

    override func resignKey() {
        super.resignKey()
        if !closing && !asking { close() }
    }

    override func close() {
        closing = true
        super.close()
    }
}

/// The page itself: ruled lines, the red margin, a spiral binding and today's date.
private final class PaperView: NSView {
    var empty = false

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Planner.paper.setFill()
        bounds.fill()

        let rules = NSBezierPath()
        rules.lineWidth = 1
        var y = firstLine
        while y < bounds.height - 6 {
            rules.move(to: NSPoint(x: 0, y: y + 0.5))
            rules.line(to: NSPoint(x: bounds.width, y: y + 0.5))
            y += lineHeight
        }
        Sprites.color(0xD5E3F3).setStroke()
        rules.stroke()
        let red = NSBezierPath()
        red.move(to: NSPoint(x: margin + 0.5, y: 24))
        red.line(to: NSPoint(x: margin + 0.5, y: bounds.height))
        Sprites.color(0xF0A3A3).setStroke()
        red.stroke()

        // Spiral binding along the top edge.
        var x: CGFloat = 20
        while x < bounds.width - 10 {
            Sprites.color(0x5C5560).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - 3, y: 11, width: 7, height: 7)).fill()
            let wire = NSBezierPath()
            wire.lineWidth = 2
            for step in 0...14 {
                let t = (200 + CGFloat(step) * 10) * .pi / 180
                let p = NSPoint(x: x + 0.5 + 4.5 * cos(t), y: 9 + 8 * sin(t))
                if step == 0 { wire.move(to: p) } else { wire.line(to: p) }
            }
            Sprites.color(0xA9A4AD).setStroke()
            wire.stroke()
            x += 24
        }

        let date = DateFormatter()
        date.locale = Locale(identifier: "ko_KR")
        date.dateFormat = "M월 d일 EEEE"
        drawLine(date.string(from: Date()), font: .boldSystemFont(ofSize: 17), color: Planner.ink,
                 in: NSRect(x: margin + 8, y: 28, width: 260, height: 26), align: .left)
        drawLine("공부 플래너", font: .systemFont(ofSize: 12), color: Planner.pencil,
                 in: NSRect(x: 0, y: 35, width: bounds.width - 14, height: 18), align: .right)


        Sprites.color(0xC9C2B0).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

/// A flat button on the paper that turns highlighter yellow under the mouse; `paint`
/// draws its face.
private final class PaperRows: NSView {
    var empty = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Planner.paper.setFill(); bounds.fill()
        let rules = NSBezierPath()
        var y = lineHeight - 0.5
        while y < bounds.height { rules.move(to: NSPoint(x: 0, y: y)); rules.line(to: NSPoint(x: bounds.width, y: y)); y += lineHeight }
        Sprites.color(0xD5E3F3).setStroke(); rules.stroke()
        let red = NSBezierPath(); red.move(to: NSPoint(x: margin - 0.5, y: 0)); red.line(to: NSPoint(x: margin - 0.5, y: bounds.height))
        Sprites.color(0xF0A3A3).setStroke(); red.stroke()
        if empty { drawLine("아직 공부한 과목이 없어요. 위에 적어 보세요!", font: .systemFont(ofSize: 12), color: Planner.pencil,
                            in: NSRect(x: margin + 12, y: 8, width: bounds.width - margin - 24, height: 24), align: .left) }
    }
}

private final class PaperButton: NSView {
    override var acceptsFirstResponder: Bool { isEnabled }
    override func keyDown(with event: NSEvent) {
        if isEnabled && [" ", "\r"].contains(event.characters ?? "") { onClick() } else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { if !isEnabled { return false }; onClick(); return true }
    var onClick: () -> Void = {}
    var paint: (PaperButton) -> Void = { _ in }
    var hoverColor = Planner.highlight
    var isEnabled = true {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    private var hover = false

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hover = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {} // keeps the mouse-up coming here

    override func mouseUp(with event: NSEvent) {
        if isEnabled && bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func draw(_ dirtyRect: NSRect) {
        if hover && isEnabled {
            hoverColor.setFill()
            bounds.fill()
        }
        paint(self)
    }
}
