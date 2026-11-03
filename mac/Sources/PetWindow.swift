import AppKit

// Sizes in points: the Windows app's layout at 100 %.
private let scale: CGFloat = 4
private let deskWidth = CGFloat(Sprites.width) * scale
private let boardLine: CGFloat = 20
// Room for the tallest chalkboard; a shorter one leaves the top of the window empty.
private let boardSpace = 48 + CGFloat(Room.boardLines) * boardLine
private let bubbleArea: CGFloat = 92 // a two-line bubble, and a one-line news bubble above it
private let floorY = boardSpace + bubbleArea // top of the desks' grid
let petSize = NSSize(width: 3 * deskWidth + 72, height: floorY + CGFloat(Sprites.height) * scale + 10)

/// A little classroom, drawn like the Windows app's PetWindow.cs: my desk in the centre
/// and pinned friends on the left and right, each with a nameplate and a speech bubble, and
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
    private var visitSide = 0
    private var outgoingTick = -1
    private var outgoingSide = 0
    private var outgoingText = ""
    private var previousSeats: [Seat?] = [nil, nil]
    private var leavingTicks = [-1, -1]
    private(set) var sizePercent = [50, 75, 100, 125, 150].contains(Int(Settings.get("petSize")) ?? 75) ? (Int(Settings.get("petSize")) ?? 75) : 75
    private var dragFrom: NSPoint?
    private var dragOrigin = NSPoint.zero
    private var dragged = false
    private var hasLeft = false, hasRight = false
    private(set) var minimized = false
    var canvasSize: NSSize {
        let count = 1 + (hasLeft ? 1 : 0) + (hasRight ? 1 : 0)
        return NSSize(width: CGFloat(count) * deskWidth + CGFloat(count - 1) * 22 + 24, height: petSize.height)
    }
    private var myX: CGFloat { hasLeft ? 12 + deskWidth + 22 : 12 }
    private var seatX: CGFloat { myX - deskWidth - 22 }
    private var rightX: CGFloat { myX + deskWidth + 22 }

    /// Read on every frame, so the minutes tick over without anyone pushing updates.
    var bubbleText: () -> String = { "" }
    /// A second bubble above mine for a moment, e.g. "민지가 공부를 시작했어요 !".
    var newsText: () -> String = { "" }
    var myName: () -> String = { "" }
    var seatmate: () -> Seat? = { nil }
    var rightSeatmate: () -> Seat? = { nil }
    /// The chalkboard; nil hides the whole classroom background.
    var board: () -> (title: String, lines: [String])? = { nil }

    var seatmateClicked: () -> Void = {}
    var rightSeatmateClicked: () -> Void = {}
    var awayClicked: () -> Void = {}
    var petClicked: () -> Void = {}
    var boardClicked: () -> Void = {}
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
        setDisplaySize(sizePercent)
        setFrameOrigin(savedLocation() ?? defaultLocation())
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setDisplaySize(_ percent: Int) {
        guard [50, 75, 100, 125, 150].contains(percent) else { return }
        sizePercent = percent
        redraw()
    }

    private func fitDesks() {
        hasLeft = seatmate() != nil; hasRight = rightSeatmate() != nil
        let area = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: petSize)
        let factor = min(CGFloat(sizePercent) / 100, min(area.width / canvasSize.width, area.height / canvasSize.height))
        let size = NSSize(width: canvasSize.width * factor, height: canvasSize.height * factor)
        let old = frame
        let x = old.minX - area.minX < area.maxX - old.maxX ? old.minX : old.maxX - size.width
        if frame.size != size { setContentSize(size) }
        contentView?.frame = NSRect(origin: .zero, size: size)
        contentView?.bounds = NSRect(origin: .zero, size: canvasSize)
        setFrameOrigin(NSPoint(x: max(area.minX, min(x, area.maxX - size.width)), y: max(area.minY, min(old.minY, area.maxY - size.height))))
    }

    func minimizeScene() {
        minimized = true
        timer?.invalidate(); timer = nil
        visitTick = -1; outgoingTick = -1
        orderOut(nil)
    }

    func restoreScene() {
        guard minimized else { return }
        minimized = false
        guard mood != .leaving && mood != .away else { return }
        fading = false; alphaValue = 1
        redraw(); orderFrontRegardless(); startAnimation()
    }

    func appear(_ newMood: Mood) {
        mood = newMood
        minimized = false
        tick = 0
        fading = false
        alphaValue = 0.25
        redraw()
        orderFrontRegardless()
        startAnimation()
    }

    private func startAnimation() {
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
    func standUpAndLeave() { visitTick = -1; outgoingTick = -1; setMood(.leaving) }

    /// A friend comes round behind my desk and taps my pet on the shoulder, saying `text`.
    /// If my pet isn't out, the friend turns up at my empty desk, waves, and leaves again.
    func visit(_ friend: Look, text: String, fromSeatmate: Bool) {
        if minimized { return }
        visitLook = friend
        visitText = text
        visitSide = fromSeatmate ? -1 : 0
        visitTick = 0
        if !isVisible || fading || mood == .leaving { appear(.away) }
    }

    func visit(_ friend: Look, text: String, side: Int) {
        visit(friend, text: text, fromSeatmate: side != 0)
        visitSide = side
    }

    func goVisit(_ name: String, message: String, side: Int) {
        if minimized { return }
        outgoingTick = 0; outgoingSide = side; outgoingText = name + "에게\n" + message
        if !isVisible { appear(.away) }
    }

    /// For the self-test: one moment of the animation, set up without showing the window.
    func preview(_ atMood: Mood, frame atFrame: Int, visitTick atVisitTick: Int = -1,
                 friend: Look = Look(girl: false, 0, 0, 0, 0, 0, 0), friendText: String = "", outgoingTick atOutgoingTick: Int = -1, outgoingDirection: Int = 0) {
        mood = atMood
        frameCount = atFrame
        tick = atFrame
        visitTick = atVisitTick
        visitLook = friend
        visitText = friendText
        visitSide = -1
        outgoingTick = atOutgoingTick; outgoingSide = outgoingDirection; outgoingText = "민지에게\n화이팅 !"
        fitDesks()
    }

    @objc private func step() {
        frameCount += 1
        tick += 1
        for i in 0..<2 { if leavingTicks[i] >= 0 && leavingTicks[i] < 10 { leavingTicks[i] += 1 } }
        if outgoingTick >= 0 { outgoingTick += 1; if outgoingTick > PetWindow.visitTicks { outgoingTick = -1; if mood == .away { fading = true } } }
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

    private func redraw() { fitDesks(); contentView?.needsDisplay = true }

    static func studyMoment(_ ticks: Int) -> Int { ticks % 360 >= 336 ? ticks / 360 % 6 + 1 : 0 }
    private var moment: Int { mood == .studying && visitTick < 0 && outgoingTick < 0 ? Self.studyMoment(tick) : 0 }
    private var momentFrame: Int { tick % 360 - 336 }
    private var momentText: String {
        switch moment {
        case 1: return "으쌰, 기지개!"
        case 2: return momentFrame < 16 ? "앗, 내 연필!" : "찾았다! 다시 집중 ♪"
        case 3: return "나비도 응원하러 왔나 봐 ♪"
        case 4: return "호록, 따뜻해…"
        case 5: return "한 장 더 넘겼다!"
        case 6: return "오늘도 잘하고 있어 ♡"
        default: return ""
        }
    }

    private var myPose: Sprites.Pose {
        switch mood {
        case .studying:
            if moment == 1 { return momentFrame % 4 < 2 ? .stretchA : .stretchB }
            if moment == 2 && momentFrame < 16 { return .pickUp }
            if moment == 4 { return momentFrame / 4 % 2 == 0 ? .teaA : .teaB }
            if moment == 5 && momentFrame % 4 < 2 { return .turnPage }
            return tick % 20 == 19 ? .blink : tick / 2 % 2 == 0 ? .writeA : .writeB
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

        let seats = [seatmate(), rightSeatmate()]
        let visiting = visitTick >= 0
        let outgoing = outgoingTick >= 0
        for i in 0..<2 {
            guard let seat = seats[i] else { previousSeats[i] = nil; leavingTicks[i] = -1; continue }
            if let before = previousSeats[i], before.name == seat.name && before.here && !seat.here { leavingTicks[i] = 0 }
            if seat.here { leavingTicks[i] = -1 }
            previousSeats[i] = seat
            let gone = visiting && visitSide == (i == 0 ? -1 : 1)
            let pose: Sprites.Pose = gone ? .empty : leavingTicks[i] >= 0 && leavingTicks[i] < 10
                ? (leavingTicks[i] < 2 ? .stand : leavingTicks[i] % 2 == 0 ? .waveA : .waveB) : seatPose(seat)
            let x = i == 0 ? seatX : rightX
            Sprites.draw(pose, seat.look, left: x, top: floorY, scale: scale)
            drawNameplate(seat.name, deskX: x)
            if !seat.here && !(leavingTicks[i] >= 0 && leavingTicks[i] < 10) && !gone { drawAwaySign(x) }
        }
        let start = visitSide == 1 ? rightX : visitSide == -1 ? seatX : -deskWidth / 2
        let arrived = myX + (visitSide == 1 ? 19 : -19) * scale
        let steps = Self.travelStep(visitTick)
        let visitorX = start + (arrived - start) * CGFloat(steps) / 4
        let walking = visitTick < 4 || visitTick > 18
        let tapping = visiting && !walking && !outgoing && (mood == .studying || mood == .dozing)
        let tap = tapping && frameCount % 2 == 0
        if visiting { drawVisitor(visitLook, pose: walking ? .walk : tapping ? .reach : .wave, x: visitorX,
                                 hop: walking && frameCount % 2 == 0 ? scale : 0, mirror: (visitSide == 1) != (visitTick > 18)) }
        Sprites.draw(outgoing ? .empty : myPose, look, left: myX, top: floorY, scale: scale, alert: tapping, lift: tap ? 1 : 0)
        drawNameplate(myName(), deskX: myX)
        if mood == .away && !outgoing { drawAwaySign(myX) }
        if moment == 3 { drawButterfly() }
        if moment == 6 { drawHearts() }
        if tapping {
            NSGraphicsContext.saveGraphicsState()
            if visitSide == 1 { let t = NSAffineTransform(); t.translateX(by: visitorX + deskWidth, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat() }
            Sprites.draw(layers: Sprites.reachLayers(down: tap), visitLook, left: visitSide == 1 ? 0 : visitorX, top: floorY, scale: scale)
            NSGraphicsContext.restoreGraphicsState()
        }
        let destination = outgoingSide < 0 ? seatX + deskWidth / 2 : outgoingSide > 0 ? rightX - deskWidth / 2 : canvasSize.width - deskWidth / 2
        let outX = myX + (destination - myX) * CGFloat(Self.travelStep(outgoingTick)) / 4
        if outgoing { drawVisitor(look, pose: outgoingTick < 4 || outgoingTick > 18 ? .walk : .wave, x: outX,
                                 hop: frameCount % 2 == 0 ? scale : 0, mirror: (destination < myX) != (outgoingTick > 18)) }
        let tip = floorY - 2
        let mid = CGFloat(Sprites.dx + 16) * scale
        let narrow = deskWidth + 16
        if visiting { drawBubble(visitText, cx: visitorX + mid, tipY: tip, maxWidth: canvasSize.width - 2, fill: PetWindow.visitYellow) }
        else if outgoing { drawBubble(outgoingText, cx: outX + mid, tipY: tip, maxWidth: canvasSize.width - 2, fill: PetWindow.visitYellow) }
        else {
            var top = tip
            if mood != .away { top = drawBubble(moment == 0 ? bubbleText() : momentText, cx: myX + mid, tipY: tip, maxWidth: narrow, fill: .white) }
            for i in 0..<2 {
                if let seat = seats[i], seat.here || (leavingTicks[i] >= 0 && leavingTicks[i] < 10) { drawBubble(leavingTicks[i] >= 0 && leavingTicks[i] < 10 ? "다녀올게요!" : seat.text,
                                                    cx: (i == 0 ? seatX : rightX) + mid, tipY: tip, maxWidth: narrow, fill: .white) }
            }
            if mood != .away { drawBubble(newsText(), cx: myX + mid, tipY: top - 2, maxWidth: canvasSize.width - 2, fill: PetWindow.newsMint) }
        }
    }

    static func travelStep(_ tick: Int) -> Int { tick < 0 ? 0 : tick < 4 ? tick : tick <= 18 ? 4 : max(0, (24 - tick) * 4 / 6) }

    private func drawAwaySign(_ x: CGFloat) {
        let face = NSRect(x: x + 12 * scale, y: floorY + 16 * scale, width: 25 * scale, height: 10 * scale)
        Sprites.color(0xFFF1B8).setFill(); face.fill()
        PetWindow.wood.setStroke()
        let edge = NSBezierPath(rect: face); edge.lineWidth = scale / 2; edge.stroke()
        let base = NSBezierPath(); base.move(to: NSPoint(x: face.minX - scale, y: face.maxY)); base.line(to: NSPoint(x: face.maxX + scale, y: face.maxY)); base.lineWidth = scale / 2; base.stroke()
        drawLine("자리 비움", font: .boldSystemFont(ofSize: 3.3 * scale), color: PetWindow.ink, in: face)
    }

    private func drawButterfly() {
        let small = scale / 2
        let x = myX + deskWidth - 4 - 17 * small - (CGFloat(sin(Double(momentFrame) / 4)) + 1) * 6
        let y = floorY - 16 + CGFloat(cos(Double(momentFrame) / 3)) * 5
        Sprites.drawButterfly(left: x, top: y, scale: small, folded: frameCount % 4 >= 2)
    }

    private func drawHearts() {
        let small = scale / 2
        for i in 0..<2 {
            let t = momentFrame - i * 8
            if t < 0 || t > 16 { continue }
            Sprites.drawHeart(left: myX + deskWidth - 32 + CGFloat(i) * 12, top: floorY - 6 - CGFloat(t) * small, scale: small)
        }
    }
    private func drawVisitor(_ actor: Look, pose: Sprites.Visiting, x: CGFloat, hop: CGFloat, mirror: Bool) {
        NSGraphicsContext.saveGraphicsState()
        if mirror { let t = NSAffineTransform(); t.translateX(by: x + deskWidth, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat() }
        Sprites.draw(layers: Sprites.visitor(actor, pose, alt: frameCount % 2 == 0), actor, left: mirror ? 0 : x, top: floorY - hop, scale: scale)
        NSGraphicsContext.restoreGraphicsState()
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
        let left = max(1, min(cx - w / 2, canvasSize.width - 1 - w))
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
        let card = NSRect(x: 2, y: boardTop - 14, width: canvasSize.width - 4, height: canvasSize.height - 2 - (boardTop - 14))

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

        let frame = NSRect(x: 18, y: boardTop, width: canvasSize.width - 36, height: boardBottom - boardTop)
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
        if p.y >= boardSpace {
            if seatmate() != nil && p.x >= seatX && p.x < seatX + deskWidth { seatmateClicked(); return }
            if rightSeatmate() != nil && p.x >= rightX && p.x < rightX + deskWidth { rightSeatmateClicked(); return }
            if mood == .away && p.x >= myX && p.x < myX + deskWidth { awayClicked(); return }
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
        if hitBoard(p) { boardClicked(); return }
        if p.y >= boardSpace && p.x >= myX && p.x < myX + deskWidth { petClicked() }
    }

    func hitBoard(_ p: NSPoint) -> Bool {
        guard let board = board() else { return false }
        let bottom = boardSpace - 6
        let top = bottom - (30 + CGFloat(max(1, board.lines.count)) * boardLine + 8)
        return NSRect(x: 18, y: top, width: canvasSize.width - 36, height: bottom - top).contains(p)
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
        let spot = NSRect(x: x, y: y, width: frame.width, height: frame.height)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(spot) }) else { return nil }
        // Pulled fully on screen: the window may have grown between versions, or the Dock moved.
        let area = screen.visibleFrame
        return NSPoint(x: max(area.minX, min(x, area.maxX - frame.width)), y: max(area.minY, min(y, area.maxY - frame.height)))
    }

    private func defaultLocation() -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
        return NSPoint(x: screen.visibleFrame.maxX - frame.width - 8, y: screen.visibleFrame.minY)
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
