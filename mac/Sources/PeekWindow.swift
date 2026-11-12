import AppKit

/// A friend who called while my desk is closed or minimized peeks up at the bottom-right corner of the
/// screen (over the Dock's line when the Dock is at the bottom): fists hooked on the edge, face only,
/// looking left and right for me (여기 있나~), waving, and after a few seconds ducking down again;
/// clicking them answers. Windows: PeekWindow.cs.
final class PeekWindow: NSPanel {
    static let duration = 8.0
    // The art shown: rows from above the head (hats) down to the edge under the chin, columns round the figure.
    private static let topRow = -4, edge = 18, rows = edge - topRow, column = 11, columns = 40
    private static let scale: CGFloat = 3
    private static let paper = Sprites.color(0xFFF1A8)
    private static let font = NSFont.boldSystemFont(ofSize: 13)
    private weak var pet: NSWindow?
    private var friend: Look?
    private var text = ""
    private var start = Date()
    private var timer: Timer?
    var answered: (() -> Void)?
    var muted: (() -> Void)?

    init(pet: NSWindow) {
        self.pet = pet
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = PeekView(owner: self)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Peeks `delay` seconds from now: after the friend's visit to my desk has played out.
    func peek(_ look: Look, text: String, delay: Double) {
        friend = look
        self.text = text
        start = Date().addingTimeInterval(delay)
        schedule(0.05)
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        orderOut(nil)
    }

    /// A right-click sends them away at once (they may have startled me mid screen share) and offers an hour's quiet.
    fileprivate func rightClicked(_ event: NSEvent, in view: NSView) {
        timer?.invalidate()
        let menu = NSMenu()
        let quiet = NSMenuItem(title: "1시간 동안 알림 끄기", action: #selector(mute), keyEquivalent: "")
        quiet.target = self
        menu.addItem(quiet)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        dismiss()
    }

    @objc private func mute() { muted?() }

    private var seconds: Double { Date().timeIntervalSince(start) }

    private func schedule(_ interval: Double) {
        timer?.invalidate()
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.step() }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func step() {
        let t = seconds
        if t < 0 { schedule(-t); return }
        if t >= Self.duration { dismiss(); return }
        let size = Self.measure(text)
        let area = (pet?.screen ?? NSScreen.main)?.visibleFrame ?? .zero // clear of the Dock, wherever it is
        setFrame(NSRect(x: area.maxX - size.width - 8, y: area.minY, width: size.width, height: size.height), display: false)
        contentView?.needsDisplay = true
        if !isVisible { orderFrontRegardless() }
        schedule(t < 5.8 || t > Self.duration - 0.8 ? 0.05 : 0.2) // holding still before ducking
    }

    fileprivate func paintNow() {
        if let friend { Self.paint(friend, text, t: max(0, seconds), size: Self.measure(text)) }
    }

    private static func lines(_ text: String) -> [String] { [text, "눌러서 답하기"] }
    private static func bubbleSize(_ text: String) -> NSSize {
        NSSize(width: ((lines(text).map { textWidth($0, font) }.max() ?? 0) + 22).rounded(.up), height: CGFloat(lines(text).count) * 18 + 10)
    }

    /// The window for `text`: the bubble over the friend's head.
    static func measure(_ text: String) -> NSSize {
        let bubble = bubbleSize(text)
        return NSSize(width: max(CGFloat(columns) * scale, bubble.width + 2), height: bubble.height + 8 + CGFloat(rows) * scale)
    }

    /// The frame `t` seconds after the friend first pops up, in a flipped box of `size`; the self-test draws these too.
    static func paint(_ look: Look, _ text: String, t: Double, size: NSSize) {
        let s = scale
        let c = t
        // The fists come up onto the edge first and the head after; going, the head ducks first and the fists slip off last.
        func away(_ up: Double, _ down: Double, _ span: Double) -> Double {
            c < up ? 1 - Departure.ease(max(0, c - up + span) / span) : c > down ? Departure.ease(min(1, (c - down) / span)) : 0
        }
        let hands = away(0.3, duration - 0.3, 0.3)
        let head = away(0.8, duration - 0.7, 0.5)
        let eyes = c < 1.8 ? "Left" : c < 2.8 ? "Right" : c < 3.8 ? "Left" : "Open"
        let wave = c >= 3.8 && c < 5.8
        let left = size.width - CGFloat(columns) * s, top = size.height - CGFloat(rows) * s, x = left - CGFloat(column) * s
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: left, y: top, width: CGFloat(columns) * s, height: CGFloat(rows) * s).clip() // the edge hides the rest
        // Searching: leaning the way they look (the eyes alone move one pixel), with a question mark.
        let lean = CGFloat(eyes == "Left" ? -2 : eyes == "Right" ? 2 : 0) * s
        let y = top + CGFloat(-topRow + Int((head * Double(rows)).rounded())) * s
        Sprites.draw(layers: Sprites.visitor(look, wave ? .wave : .stand, alt: Int((c * 4).rounded(.down)) % 2 == 0, eyes: eyes), look, left: x + lean, top: y, scale: s)
        if c >= 0.8 && c < 3.8 { Sprites.drawArt("Question", left: x + lean + CGFloat(Sprites.dx + 28) * s, top: y + s, scale: s) }
        Sprites.draw(layers: Sprites.hookedHands(look, edge: edge, right: !wave), look, left: x, top: top + CGFloat(-topRow + Int((hands * 5).rounded())) * s, scale: s)
        NSGraphicsContext.restoreGraphicsState()
        if head > 0 { return } // the bubble only once they're up

        let bubble = bubbleSize(text)
        let cx = left + CGFloat(31 - column) * s // over the head
        let box = NSRect(x: max(1, min(cx - bubble.width / 2, size.width - 1 - bubble.width)), y: 1, width: bubble.width, height: bubble.height)
        let radius = min(box.height / 2, 12)
        let outline = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
        outline.lineWidth = 1.5
        paper.setFill()
        outline.fill()
        PetWindow.ink.setStroke()
        outline.stroke()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: cx - 6, y: box.maxY - 1))
        tail.line(to: NSPoint(x: cx, y: box.maxY + 6))
        tail.line(to: NSPoint(x: cx + 6, y: box.maxY - 1))
        tail.lineWidth = 1.5
        tail.fill()
        tail.stroke()
        for (i, line) in lines(text).enumerated() {
            drawLine(line, font: font, color: PetWindow.ink, in: NSRect(x: box.minX + 2, y: box.minY + 5 + CGFloat(i) * 18, width: box.width - 4, height: 18))
        }
    }
}

/// Transparent, top-left origin like the Windows app; a click anywhere drawn answers the call.
private final class PeekView: NSView {
    weak var owner: PeekWindow?

    init(owner: PeekWindow) {
        self.owner = owner
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)
        owner?.paintNow()
    }

    override func mouseUp(with event: NSEvent) { owner?.answered?() }
    override func rightMouseDown(with event: NSEvent) { owner?.rightClicked(event, in: self) }
}
