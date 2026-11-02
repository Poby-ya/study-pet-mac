import AppKit

// Sizes in points: the Windows app's layout at 100 %.
private let scale: CGFloat = 4
private let deskWidth = CGFloat(Sprites.width) * scale
private let boardLine: CGFloat = 20
// Room for the tallest chalkboard; a shorter one leaves the top of the window empty.
private let boardSpace = 48 + CGFloat(Room.boardLines) * boardLine
private let bubbleArea: CGFloat = 92 // a two-line bubble, and a one-line news bubble above it
private let floorY = boardSpace + bubbleArea // top of the desks' grid
let petSize = NSSize(width: 420, height: floorY + CGFloat(Sprites.height) * scale + 10)
private let myX = petSize.width - deskWidth - 14
// The gap keeps two neighbouring bubbles from running into each other.
private let seatX = myX - deskWidth - 22

/// A little classroom, drawn like the Windows app's PetWindow.cs: my desk on the right
/// and the pinned seatmate's on the left, each with a nameplate and a speech bubble, and
/// (unless hidden) a classroom behind them with a chalkboard of who's studying. It floats
/// above every app on every desktop without ever taking focus, and stays out of ⌘-Tab.
/// It starts bottom-right above the Dock; drag it anywhere and it remembers the spot.
final class PetWindow: NSPanel {
    /// Away: my desk is empty, shown only while a friend visits.
    enum Mood { case studying, dozing, leaving, away }

    /// What the seatmate desk shows. Not here: an empty desk with their nameplate.
    struct Seat {
        var name: String
        var look: Look
        var here: Bool
        var dozing: Bool
        var text: String
    }

    static let ink = Sprites.color(0x3A2E39)
    private static let visitYellow = Sprites.color(0xFFF1A8)
    private static let newsMint = Sprites.color(0xDCF5EA)
    private static let wall = Sprites.color(0xF6EEDF)
    private static let wainscot = Sprites.color(0xE8D9C0)
    private static let floorWood = Sprites.color(0xD2A26E)
    private static let wood = Sprites.color(0xA8744A)
    private static let slate = Sprites.color(0x2F5D50)
    private static let chalk = Sprites.color(0xEEF2E6)
    private static let plateFace = Sprites.color(0x4A3326)
    private static let plateTop = Sprites.color(0x7A563E)
    private static let plateText = Sprites.color(0xFFE9B8)

    private static let visitTicks = 24 // six seconds at four frames a second

    private var timer: Timer?
    private var mood = Mood.away
    private var frameCount = 0  // always counts, for animations that don't restart with the mood
    private var tick = 0        // restarts with each mood
    private var fading = false
    private var visitTick = -1  // -1: nobody visiting
    private var visitLook = Look(girl: false, 0, 0, 0, 0, 0, 0)
    private var visitText = ""
    private var visitFromSeat = false // the visitor is my seatmate, so their desk empties meanwhile
    private var dragFrom: NSPoint?
    private var dragOrigin = NSPoint.zero
    private var dragged = false

    /// Read on every frame, so the minutes tick over without anyone pushing updates.
    var bubbleText: () -> String = { "" }
    /// A second bubble above mine for a moment, e.g. "민지가 공부를 시작했어요 !".
    var newsText: () -> String = { "" }
    var myName: () -> String = { "" }
    var seatmate: () -> Seat? = { nil }
    /// The chalkboard; nil hides the whole classroom background.
    var board: () -> (title: String, lines: [String])? = { nil }

    var seatmateClicked: () -> Void = {}
    var awayClicked: () -> Void = {}
    var petClicked: () -> Void = {}
    var contextMenu: NSMenu?

    var look: Look {
        didSet {
            remember("style", look.code)
            remember("look", look.girl ? "girl" : "boy")
            redraw()
        }
    }

    init() {
        // Older settings only knew boy or girl; those get a random look of that gender.
        let saved = Settings.get("style")
        look = saved.isEmpty ? Look.random(girl: Settings.get("look") == "girl") : Look.parse(saved, girl: Settings.get("look") == "girl")
        super.init(contentRect: NSRect(origin: .zero, size: petSize), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        if saved.isEmpty { remember("style", look.code) }
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = Canvas(owner: self)
        setFrameOrigin(savedLocation() ?? defaultLocation())
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func appear(_ newMood: Mood) {
        mood = newMood
        tick = 0
        fading = false
        alphaValue = 0.25
        redraw()
        orderFrontRegardless()
        if timer == nil {
            let t = Timer(timeInterval: 0.25, target: self, selector: #selector(step), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    func setMood(_ newMood: Mood) {
        mood = newMood
        tick = 0
        redraw()
    }

    /// Stand up, wave for about two seconds, fade out, hide.
    func standUpAndLeave() { setMood(.leaving) }

    /// A friend comes round behind my desk and taps my pet on the shoulder, saying `text`.
    /// If my pet isn't out, the friend turns up at my empty desk, waves, and leaves again.
    func visit(_ friend: Look, text: String, fromSeatmate: Bool) {
        visitLook = friend
        visitText = text
        visitFromSeat = fromSeatmate
        visitTick = 0
        if !isVisible || fading || mood == .leaving { appear(.away) }
    }

    /// For the self-test: one moment of the animation, set up without showing the window.
    func preview(_ atMood: Mood, frame atFrame: Int, visitTick atVisitTick: Int = -1,
                 friend: Look = Look(girl: false, 0, 0, 0, 0, 0, 0), friendText: String = "") {
        mood = atMood
        frameCount = atFrame
        tick = atFrame
        visitTick = atVisitTick
        visitLook = friend
        visitText = friendText
        visitFromSeat = true
    }

    @objc private func step() {
        frameCount += 1
        tick += 1
        if visitTick >= 0 {
            visitTick += 1
            if visitTick > PetWindow.visitTicks {
                visitTick = -1
                if mood == .away { fading = true }
            }
        }
        if mood == .leaving && tick > 8 { fading = true }

        if fading {
            if alphaValue <= 0.26 {
                timer?.invalidate()
                timer = nil
                fading = false
                orderOut(nil)
                return
            }
            alphaValue -= 0.25
        } else if alphaValue < 1 {
            alphaValue = min(1, alphaValue + 0.25)
        }
        redraw()
    }

    private func redraw() { contentView?.needsDisplay = true }

    private var myPose: Sprites.Pose {
        switch mood {
        case .studying: return tick % 20 == 19 ? .blink : tick / 2 % 2 == 0 ? .writeA : .writeB
        case .dozing: return tick / 3 % 2 == 0 ? .dozeA : .dozeB
        case .away: return .empty
        case .leaving: return tick < 2 ? .stand : tick / 2 % 2 == 0 ? .waveA : .waveB
        }
    }

    // Offset by a frame, so the two pets don't move in lockstep.
    private func seatPose(_ seat: Seat) -> Sprites.Pose {
        if !seat.here { return .empty }
        if seat.dozing { return (frameCount + 1) / 3 % 2 == 0 ? .dozeA : .dozeB }
        return (frameCount + 1) / 2 % 2 == 0 ? .writeA : .writeB
    }

    /// Draws one frame into the current (flipped) graphics context.
    func paint() {
        if let board = board() { drawClassroom(board.title, board.lines) }

        let seat = seatmate()
        let visiting = visitTick >= 0
        if let seat {
            // A seatmate who has come over to my desk has left theirs empty.
            let gone = visiting && visitFromSeat
            Sprites.draw(gone ? .empty : seatPose(seat), seat.look, left: seatX, top: floorY, scale: scale)
            drawNameplate(seat.name, deskX: seatX)
        }

        // The visitor walks over during the first second (from the seatmate's chair, or in
        // from the left) and stops behind the left end of my desk, which hides their legs.
        let start = visitFromSeat ? seatX : seatX - CGFloat(Int(deskWidth) / 2)
        let arrived = myX - 19 * scale
        let steps = min(max(visitTick, 0), 4)
        let visitorX = start + CGFloat(Int(arrived - start) * steps / 4)
        let walking = steps < 4
        let tapping = visiting && !walking && (mood == .studying || mood == .dozing)
        let tap = tapping && frameCount % 2 == 0 // hand down on the shoulder; up on the other frame
        if visiting {
            let pose: Sprites.Visiting = walking ? .walk : tapping ? .reach : .wave
            let hop = walking && frameCount % 2 == 0 ? scale : 0
            Sprites.draw(layers: Sprites.visitor(visitLook, pose, alt: frameCount % 2 == 0), visitLook,
                         left: visitorX, top: floorY - hop, scale: scale)
        }

        // Each tap makes my pet jump a little, with a "!" over its head.
        Sprites.draw(myPose, look, left: myX, top: floorY, scale: scale, alert: tapping, lift: tap ? 1 : 0)
        drawNameplate(myName(), deskX: myX)
        if tapping { Sprites.draw(layers: Sprites.reachLayers(down: tap), visitLook, left: visitorX, top: floorY, scale: scale) }

        let tip = floorY - 2
        let mid = CGFloat(Sprites.dx + 16) * scale // over the person, not the middle of the desk
        let narrow = deskWidth + 16 // with a neighbour, a bubble stays over its own desk
        if visiting {
            // Only the visitor talks, so its bubble can be wide.
            drawBubble(visitText, cx: visitorX + mid, tipY: tip, maxWidth: petSize.width - 2, fill: PetWindow.visitYellow)
        } else {
            var top = tip
            if mood != .away {
                top = drawBubble(bubbleText(), cx: myX + mid, tipY: tip, maxWidth: seat != nil ? narrow : petSize.width - 2, fill: .white)
            }
            if let seat { drawBubble(seat.text, cx: seatX + mid, tipY: tip, maxWidth: narrow, fill: .white) }
            if mood != .away { drawBubble(newsText(), cx: myX + mid, tipY: top - 2, maxWidth: petSize.width - 2, fill: PetWindow.newsMint) }
        }
    }

    /// Lines (split on "\n") in a rounded box whose tail points down at `cx`. Returns the
    /// box's top, so another bubble can stack above it.
    @discardableResult
    private func drawBubble(_ text: String, cx: CGFloat, tipY: CGFloat, maxWidth: CGFloat, fill: NSColor) -> CGFloat {
        if text.isEmpty { return tipY }
        let lines = text.components(separatedBy: "\n")
        let font = NSFont.boldSystemFont(ofSize: 13)
        let lineHeight: CGFloat = 17
        let w = min(maxWidth, (lines.map { textWidth($0, font) }.max() ?? 0) + 22)
        let h = CGFloat(lines.count) * lineHeight + 10
        let tailHeight: CGFloat = 6
        let left = max(1, min(cx - w / 2, petSize.width - 1 - w))
        let box = NSRect(x: left, y: tipY - tailHeight - h, width: w, height: h)
        let radius = min(h / 2, 12)

        let outline = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
        outline.lineWidth = 1.5
        fill.setFill()
        outline.fill()
        PetWindow.ink.setStroke()
        outline.stroke()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: cx - 6, y: box.maxY - 1))
        tail.line(to: NSPoint(x: cx, y: tipY))
        tail.line(to: NSPoint(x: cx + 6, y: box.maxY - 1))
        tail.lineWidth = 1.5
        tail.fill()
        tail.stroke()

        for (i, line) in lines.enumerated() {
            drawLine(line, font: font, color: PetWindow.ink,
                     in: NSRect(x: box.minX + 2, y: box.minY + 5 + CGFloat(i) * lineHeight, width: box.width - 4, height: lineHeight))
        }
        return box.minY
    }

    /// A wooden nameplate standing on the left end of the desk top, like on a teacher's desk.
    private func drawNameplate(_ name: String, deskX: CGFloat) {
        if name.isEmpty { return }
        let font = NSFont.boldSystemFont(ofSize: 3.4 * scale)
        // Between the desk's left edge and the person's hand (cols 1..16).
        let w = min(15 * scale, max(8 * scale, textWidth(name, font) + 3 * scale))
        let x = deskX + scale + (15 * scale - w) / 2
        let face = NSRect(x: x, y: floorY + 22 * scale, width: w, height: 5 * scale)
        PetWindow.plateTop.setFill()
        NSRect(x: x + scale / 2, y: floorY + 21 * scale, width: w - scale, height: scale + 1).fill()
        PetWindow.plateFace.setFill()
        face.fill()
        PetWindow.ink.setStroke()
        NSBezierPath(rect: face).stroke()
        drawLine(name, font: font, color: PetWindow.plateText, in: face)
    }

    /// The classroom behind the desks: a wall with a chalkboard (one line per person, so it
    /// grows), wainscoting and a wooden floor, all on one rounded card.
    private func drawClassroom(_ title: String, _ lines: [String]) {
        let shownLines = CGFloat(max(1, lines.count))
        let boardBottom = boardSpace - 6
        let boardTop = boardBottom - (30 + shownLines * boardLine + 8)
        let card = NSRect(x: 2, y: boardTop - 14, width: petSize.width - 4, height: petSize.height - 2 - (boardTop - 14))

        let cardPath = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
        PetWindow.wall.setFill()
        cardPath.fill()
        NSGraphicsContext.saveGraphicsState()
        cardPath.addClip()
        PetWindow.wainscot.setFill()
        NSRect(x: card.minX, y: floorY + 20 * scale, width: card.width, height: card.height).fill()
        let floorTop = floorY + 35 * scale
        PetWindow.floorWood.setFill()
        NSRect(x: card.minX, y: floorTop, width: card.width, height: card.maxY - floorTop).fill()
        let seams = NSBezierPath()
        seams.lineWidth = 1
        seams.move(to: NSPoint(x: card.minX, y: floorTop))
        seams.line(to: NSPoint(x: card.maxX, y: floorTop))
        var x = card.minX + 30
        while x < card.maxX {
            seams.move(to: NSPoint(x: x, y: floorTop))
            seams.line(to: NSPoint(x: x - 14, y: card.maxY))
            x += 60
        }
        Sprites.color(0xB88655).setStroke()
        seams.stroke()
        NSGraphicsContext.restoreGraphicsState()
        cardPath.lineWidth = 1
        Sprites.color(0xC9B89A).setStroke()
        cardPath.stroke()

        let frame = NSRect(x: 18, y: boardTop, width: petSize.width - 36, height: boardBottom - boardTop)
        let slate = frame.insetBy(dx: 5, dy: 5)
        PetWindow.wood.setFill()
        NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4).fill()
        PetWindow.slate.setFill()
        slate.fill()
        Sprites.color(0x8B5E3C).setFill()
        NSRect(x: frame.minX + 20, y: frame.maxY - 2, width: frame.width - 40, height: 5).fill()

        let faint = PetWindow.chalk.withAlphaComponent(150.0 / 255)
        let textX = slate.minX + 10
        let textW = slate.width - 20
        drawLine(title, font: .boldSystemFont(ofSize: 12), color: faint,
                 in: NSRect(x: textX, y: slate.minY + 5, width: textW, height: 16), align: .left)
        let shown = lines.isEmpty ? ["아직 아무도 없어요"] : lines
        for (i, line) in shown.enumerated() {
            drawLine(line, font: .systemFont(ofSize: 14), color: lines.isEmpty ? faint : PetWindow.chalk,
                     in: NSRect(x: textX, y: slate.minY + 25 + CGFloat(i) * boardLine, width: textW, height: boardLine), align: .left)
        }
    }

    // ---- Mouse ----------------------------------------------------------------------

    fileprivate func mouseDown(_ event: NSEvent, at p: NSPoint) {
        if event.modifierFlags.contains(.control) {
            showMenu(event)
            return
        }
        if mood == .away {
            awayClicked()
            return
        }
        if seatmate() != nil && p.y >= boardSpace && p.x >= seatX && p.x < seatX + deskWidth {
            seatmateClicked()
            return
        }
        dragFrom = NSEvent.mouseLocation
        dragOrigin = frame.origin
        dragged = false
    }

    fileprivate func mouseDragged() {
        guard let from = dragFrom else { return }
        let now = NSEvent.mouseLocation
        if abs(now.x - from.x) + abs(now.y - from.y) > 3 { dragged = true }
        if dragged { setFrameOrigin(NSPoint(x: dragOrigin.x + now.x - from.x, y: dragOrigin.y + now.y - from.y)) }
    }

    fileprivate func mouseUp(at p: NSPoint) {
        guard dragFrom != nil else { return }
        dragFrom = nil
        if dragged {
            remember("position", "\(Int(frame.origin.x)),\(Int(frame.origin.y))")
            return
        }
        // It didn't move, so it was a click; on my own pet that pauses or resumes.
        if p.y >= boardSpace && p.x >= myX && p.x < myX + deskWidth { petClicked() }
    }

    fileprivate func showMenu(_ event: NSEvent) {
        guard let menu = contextMenu, let view = contentView else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    // ---- Position -------------------------------------------------------------------

    private func savedLocation() -> NSPoint? {
        let xy = Settings.get("position").split(separator: ",")
        guard xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) else { return nil }
        // A spot on a screen that's no longer attached falls back to the default corner.
        let spot = NSRect(x: x, y: y, width: petSize.width, height: petSize.height)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(spot) }) else { return nil }
        // Pulled fully on screen: the window may have grown between versions, or the Dock moved.
        let area = screen.visibleFrame
        return NSPoint(x: max(area.minX, min(x, area.maxX - petSize.width)), y: max(area.minY, min(y, area.maxY - petSize.height)))
    }

    private func defaultLocation() -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
        return NSPoint(x: screen.visibleFrame.maxX - petSize.width - 8, y: screen.visibleFrame.minY)
    }

    private func remember(_ key: String, _ value: String) {
        // A forgotten position or look is harmless; not worth interrupting anyone over.
        try? Settings.set(key, value)
    }
}

/// The pet window's only view: transparent, with the top-left as origin like the Windows app.
private final class Canvas: NSView {
    weak var owner: PetWindow?

    init(owner: PetWindow) {
        self.owner = owner
        super.init(frame: NSRect(origin: .zero, size: petSize))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    // The pet never takes focus, so the first click has to count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)
        owner?.paint()
    }

    override func mouseDown(with event: NSEvent) { owner?.mouseDown(event, at: convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { owner?.mouseDragged() }
    override func mouseUp(with event: NSEvent) { owner?.mouseUp(at: convert(event.locationInWindow, from: nil)) }
    override func rightMouseDown(with event: NSEvent) { owner?.showMenu(event) }
}

func textWidth(_ s: String, _ font: NSFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }

/// One line of text, vertically centred in `rect`, cut with "…" when too long.
func drawLine(_ s: String, font: NSFont, color: NSColor, in rect: NSRect, align: NSTextAlignment = .center, strike: Bool = false) {
    if s.isEmpty { return }
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineBreakMode = .byTruncatingTail
    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
    if strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    let height = ceil((s as NSString).size(withAttributes: attributes).height) + 1
    (s as NSString).draw(in: NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height), withAttributes: attributes)
}
