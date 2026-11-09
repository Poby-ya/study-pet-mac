import AppKit

private let plannerWidth: CGFloat = 420
private let boardHeight: CGFloat = 92, railHeight: CGFloat = 8
private let pad: CGFloat = 16
private let boxTop = boardHeight + railHeight + pad, boxHeight: CGFloat = 46
private let captionTop = boxTop + boxHeight + 14
private let listTop = captionTop + 24
private let rowHeight: CGFloat = 54, rowStep = rowHeight + 6
private let edgeGap: CGFloat = 12

/// The study planner that pops up in the corner of the screen, like SubjectPicker.cs: a small
/// chalkboard with today's date, a box to write a new subject in, and this month's subjects as
/// cards, most studied first. Click a card to start; ✕ takes one off the list, asking whether its
/// records go too. Clicking elsewhere or Esc closes it.
final class Planner: NSPanel {
    static let paper = Sprites.color(0xFFFBF2)
    static let cardEdge = Sprites.color(0xEADFCB)
    static let track = Sprites.color(0xF1EADC)
    static let ink = Sprites.color(0x3A2E39)
    static let pencil = Sprites.color(0x8A8088)
    static let stamp = Sprites.color(0xE2574C)
    static let stampHot = Sprites.color(0xCC473D)
    static let highlight = Sprites.color(0xFFF4BF)
    static let spines = [0x7AA7F5, 0x6BB596, 0xF5A9C0, 0xF2B23A, 0xB9A7E8, 0xF08A6C, 0x9DB36B, 0x65ABC4].map { Sprites.color($0) }

    var picked: ((String) -> Void)?
    /// The subject, and whether its study records should go too.
    var removed: ((String, Bool) -> Void)?

    private let input = NSTextField()
    private var asking = false
    private var closing = false

    init(ranking: [Records.Rank], anchor: NSRect) {
        let area = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame ?? anchor
        let width = min(plannerWidth, area.width - 16)
        let height = min(max(300, listTop + CGFloat(max(1, ranking.count)) * rowStep + 10), area.height - 16)
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        let page = PageView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        page.wantsLayer = true
        page.layer?.cornerRadius = 16
        page.layer?.masksToBounds = true
        contentView = page

        let start = PaperButton(frame: NSRect(x: width - pad - 76, y: boxTop, width: 76, height: boxHeight))
        start.paint = { b in
            (b.hover ? Planner.stampHot : Planner.stamp).setFill()
            NSBezierPath(roundedRect: b.bounds, xRadius: 12, yRadius: 12).fill()
            drawLine("시작!", font: .boldSystemFont(ofSize: 15), color: .white, in: b.bounds)
        }
        start.setAccessibilityLabel("시작")
        start.onClick = { [weak self] in self?.pick(self?.input.stringValue ?? "") }
        page.addSubview(start)

        page.inputBox = NSRect(x: pad, y: boxTop, width: start.frame.minX - 8 - pad, height: boxHeight)
        input.isBordered = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.font = .systemFont(ofSize: 16)
        input.textColor = Planner.ink
        input.placeholderString = "새 과목 적기"
        input.cell?.sendsActionOnEndEditing = false // only Return starts; clicking away must not
        input.target = self
        input.action = #selector(enter)
        input.frame = page.inputBox.insetBy(dx: 14, dy: (boxHeight - 24) / 2)
        page.addSubview(input)

        let scroll = NSScrollView(frame: NSRect(x: pad, y: listTop, width: width - 2 * pad, height: height - listTop - 10))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let rows = PaperRows(frame: NSRect(x: 0, y: 0, width: scroll.bounds.width, height: max(scroll.bounds.height, CGFloat(max(1, ranking.count)) * rowStep)))
        rows.empty = ranking.isEmpty
        scroll.documentView = rows
        page.addSubview(scroll)

        let nameFont = NSFont.boldSystemFont(ofSize: 15)
        let timeFont = NSFont.boldSystemFont(ofSize: 13)
        let smallFont = NSFont.systemFont(ofSize: 12)
        let most = max(1, ranking.map(\.month).max() ?? 1)
        for (i, item) in ranking.enumerated() {
            let spine = Planner.spines[i % Planner.spines.count]
            let monthText = Records.duration(item.month), totalText = "전체 " + Records.duration(item.total)
            let top = CGFloat(i) * rowStep
            let card = PaperButton(frame: NSRect(x: 0, y: top, width: rows.bounds.width - 34, height: rowHeight))
            card.setAccessibilityLabel("\(i + 1)위 \(item.subject), 이번 달 \(Records.duration(item.month)), 전체 \(Records.duration(item.total))")
            card.onClick = { [weak self] in self?.pick(item.subject) }
            card.paint = { b in
                let struck = !b.isEnabled
                let shape = NSBezierPath(roundedRect: b.bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
                (!struck && b.hover ? Planner.highlight : NSColor.white).setFill()
                shape.fill()
                NSGraphicsContext.saveGraphicsState()
                shape.addClip()
                (struck ? Planner.cardEdge : spine).setFill()
                NSRect(x: 0, y: 0, width: 6, height: b.bounds.height).fill()
                NSGraphicsContext.restoreGraphicsState()
                Planner.cardEdge.setStroke()
                shape.stroke()

                let left: CGFloat = 18
                let timeWidth = ceil(max(textWidth(monthText, timeFont), textWidth(totalText, smallFont)))
                let timeLeft = b.bounds.width - timeWidth - 12
                let nameWidth = max(1, timeLeft - left - 10)
                drawLine(item.subject, font: nameFont, color: struck ? Planner.pencil : Planner.ink, in: NSRect(x: left, y: 8, width: nameWidth, height: 20), align: .left, strike: struck)
                drawLine(monthText, font: timeFont, color: struck ? Planner.pencil : Planner.ink, in: NSRect(x: timeLeft, y: 8, width: timeWidth, height: 20), align: .right)
                drawLine(totalText, font: smallFont, color: Planner.pencil, in: NSRect(x: timeLeft, y: b.bounds.height - 25, width: timeWidth, height: 18), align: .right)
                if struck { return }
                let barTop = b.bounds.height - 14
                Planner.track.setFill()
                NSBezierPath(roundedRect: NSRect(x: left, y: barTop, width: nameWidth, height: 5), xRadius: 2.5, yRadius: 2.5).fill()
                let filled = nameWidth * CGFloat(item.month / most)
                if filled < 1 { return }
                spine.setFill()
                NSBezierPath(roundedRect: NSRect(x: left, y: barTop, width: max(filled, 5), height: 5), xRadius: 2.5, yRadius: 2.5).fill()
            }

            let remove = PaperButton(frame: NSRect(x: rows.bounds.width - 30, y: top, width: 30, height: rowHeight))
            remove.hoverColor = Sprites.color(0xFFE8E5)
            remove.setAccessibilityLabel(item.subject + " 목록에서 지우기")
            remove.paint = { b in
                if b.hover { b.hoverColor.setFill(); b.bounds.fill() }
                drawLine("✕", font: smallFont, color: Planner.pencil, in: b.bounds)
            }
            remove.onClick = { [weak self, weak card, weak remove] in
                guard let self else { return }
                var alsoRecords = false
                if item.total >= 1 {
                    switch self.askRemove(item) {
                    case nil: return
                    case let answer?: alsoRecords = answer
                    }
                }
                self.removed?(item.subject, alsoRecords)
                // Crossed off; it comes back next time it's studied.
                card?.isEnabled = false
                remove?.isHidden = true
            }
            card.toolTip = "\(item.subject) · 이번 달 \(Records.duration(item.month)) · 전체 \(Records.duration(item.total))"
            rows.addSubview(card)
            rows.addSubview(remove)
        }

        // Just inside the bottom-right corner of this monitor, above the Dock.
        setFrameOrigin(NSPoint(x: area.maxX - width - edgeGap, y: area.minY + edgeGap))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { true }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(input)
        invalidateShadow() // follows the rounded corners
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

/// The page itself: the chalkboard on its wooden rail, like the one in the classroom, and the input box.
private final class PageView: NSView {
    var inputBox = NSRect.zero

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Planner.paper.setFill()
        bounds.fill()
        func fill(_ color: Int, _ rect: NSRect) { Sprites.color(color).setFill(); rect.fill() }
        fill(0x2F5D50, NSRect(x: 0, y: 0, width: bounds.width, height: boardHeight))
        fill(0xA8744A, NSRect(x: 0, y: boardHeight, width: bounds.width, height: railHeight))
        fill(0xC99668, NSRect(x: 0, y: boardHeight, width: bounds.width, height: 2))
        fill(0x8B5E3C, NSRect(x: 0, y: boardHeight + railHeight - 1, width: bounds.width, height: 1))
        fill(0xEEF2E6, NSRect(x: bounds.width - 64, y: boardHeight - 3, width: 16, height: 3))
        fill(0xF7D774, NSRect(x: bounds.width - 42, y: boardHeight - 3, width: 11, height: 3))

        let date = DateFormatter()
        date.locale = Locale(identifier: "ko_KR")
        date.dateFormat = "M월 d일 EEEE"
        drawLine(date.string(from: Date()), font: .systemFont(ofSize: 13), color: Sprites.color(0xB9CDBF), in: NSRect(x: 18, y: 16, width: bounds.width - 36, height: 20), align: .left)
        drawLine("오늘은 뭘 공부할까요?", font: .boldSystemFont(ofSize: 21), color: Sprites.color(0xEEF2E6), in: NSRect(x: 18, y: 40, width: bounds.width - 36, height: 32), align: .left)

        let box = NSBezierPath(roundedRect: inputBox.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor.white.setFill()
        box.fill()
        Planner.cardEdge.setStroke()
        box.stroke()
        drawLine("이번 달에 많이 공부한 순서예요", font: .systemFont(ofSize: 12), color: Planner.pencil, in: NSRect(x: pad, y: captionTop, width: bounds.width - 2 * pad, height: 18), align: .left)
    }
}

private final class PaperRows: NSView {
    var empty = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Planner.paper.setFill(); bounds.fill()
        if empty { drawLine("아직 공부한 과목이 없어요. 위에 적어 보세요!", font: .systemFont(ofSize: 12), color: Planner.pencil,
                            in: NSRect(x: 4, y: 8, width: bounds.width - 8, height: 24), align: .left) }
    }
}

/// A flat button that knows when the mouse is over it; `paint` draws its face.
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
    private(set) var hover = false

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

    override func draw(_ dirtyRect: NSRect) { paint(self) }
}
