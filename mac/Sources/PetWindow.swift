import AppKit

// Sizes in points: the Windows app's layout at 100 %.
private let scale: CGFloat = 4
private let deskWidth = CGFloat(Sprites.width) * scale
private let boardLine: CGFloat = 24
// Room for the tallest chalkboard; a shorter one leaves the top of the window empty.
private let boardSpace = 48 + CGFloat(Room.boardLines) * boardLine
private let bubbleArea: CGFloat = 112 // room for an update reminder above a visitor's bubble
private let floorY = boardSpace + bubbleArea // top of the desks' grid
let petSize = NSSize(width: 3 * deskWidth + 72, height: floorY + CGFloat(Sprites.height) * scale + 10)

/// A little classroom, drawn like the Windows app's PetWindow.cs: my desk in the centre
/// and pinned friends on the left and right, each with a nameplate and a speech bubble, and
/// (unless hidden) a classroom behind them with a chalkboard of who's studying. It floats
/// above every app on every desktop without ever taking focus, and stays out of ⌘-Tab.
/// It starts bottom-right above the Dock; drag it anywhere and it remembers the spot.
final class PetWindow: NSPanel {
    /// Away: my desk is empty, shown only while a friend visits.
    private var textFactor: CGFloat { CGFloat(DisplayPreferences.percent("bubbleTextSize")) / 100 }
    private var boardFactor: CGFloat { CGFloat(DisplayPreferences.percent("boardTextSize")) / 100 }
    private var nameFactor: CGFloat { CGFloat(DisplayPreferences.percent("nameTextSize")) / 100 }
    private var bubbleArea: CGFloat { 142 * max(1, textFactor) }
    private var boardLine: CGFloat { 26 * boardFactor }
    private var boardSpace: CGFloat { 70 + CGFloat(Room.boardLines + 2) * boardLine }
    private var floorY: CGFloat { boardSpace + bubbleArea }
    enum Mood { case studying, dozing, leaving, away, notifying }

    /// What the seatmate desk shows. Not here: an empty desk with their nameplate.
    struct Seat {
        var name: String
        var look: Look
        var here: Bool
        var dozing: Bool
        var text: String
        var drink: Sprites.Drink = .none
        var laptop = false
        var id = ""
    }

    static let ink = Sprites.color(0x3A2E39)
    private static let visitYellow = Sprites.color(0xFFF1A8)
    private static let newsMint = Sprites.color(0xDCF5EA)
    private static let wall = Sprites.color(0xF6EEDF)
    private static let wainscot = Sprites.color(0xE8D9C0)
    private static let wainscotRail = Sprites.color(0xF3E6D0)
    private static let wainscotShade = Sprites.color(0xD6C4A6)
    private static let woodLit = Sprites.color(0xC99668)
    private static let woodDark = Sprites.color(0x8B5E3C)
    private static let floorWood = Sprites.color(0xD2A26E)
    private static let wood = Sprites.color(0xA8744A)
    private static let slate = Sprites.color(0x2F5D50)
    private static let chalk = Sprites.color(0xEEF2E6)
    private static let plateFace = Sprites.color(0x4A3326)
    private static let plateTop = Sprites.color(0x7A563E)
    private static let plateText = Sprites.color(0xFFE9B8)

    private var timer: Timer?
    private var lastStepSeconds = 0.0, animationSeconds = 0.0, moodSeconds = 0.0
    private var windowGlass = NSRect.zero
    private var updateShownAt = 0.0
    private var feedbackText = ""
    private var feedbackUntil = 0.0
    private var transitionFrom = Sprites.Pose.writeA
    private var blends: [Int: PoseBlend] = [:]
    private func blendOf(_ seat: Int) -> PoseBlend { if let blend = blends[seat] { return blend }; let blend = PoseBlend(); blends[seat] = blend; return blend }
    private var roomImage: NSImage?
    private var roomKey = ""
    private var subjectChangedAt = -100.0
    private var updateAvailable = false
    static let updateMessage = "새 버전이 나왔어요\n우클릭 → 업데이트 확인"
    private var mood = Mood.away
    private var frameCount = 0  // always counts, for animations that don't restart with the mood
    private var tick = 0        // restarts with each mood
    private var fading = false
    private var visitTick = -1.0 // four units per second, with fractional travel
    private var visitLook = Look(girl: false, 0, 0, 0, 0, 0, 0)
    private var visitText = ""
    private var visitSide = 0
    private var outgoingTick = -1.0
    private var outgoingSide = 0
    private var outgoingText = ""
    private var shownNews = ""
    private var newsShownAt = 0.0
    private var previousSeats: [Seat?] = [nil, nil]
    private var departingSeats: [Seat?] = [nil,nil]
    private var departureLook: Look?
    private var departureLaptop=false
    private var leavingTicks = [-1.0, -1.0]
    static let displaySizes = Array(stride(from: 50, through: 150, by: 5))
    private(set) var sizePercent = PetWindow.displaySizes.contains(Int(Settings.get("petSize")) ?? 75) ? (Int(Settings.get("petSize")) ?? 75) : 75
    private var dragFrom: NSPoint?
    private var dragOrigin = NSPoint.zero
    private var dragged = false
    private var hasLeft = false, hasRight = false
    private(set) var minimized = false
    var canvasSize: NSSize {
        let count = 1 + (hasLeft ? 1 : 0) + (hasRight ? 1 : 0)
        // 12 on the left, 20 on the right where the last bag hangs past its desk.
        let width = CGFloat(count) * deskWidth + CGFloat(count - 1) * deskGap + 32 * scale
        return NSSize(width: max(width, 330 * max(boardFactor,textFactor)), height: floorY + CGFloat(Sprites.height) * scale + 10)
    }
    private var deskGap: CGFloat { 6 * scale }
    private var deskInset: CGFloat { max(12,(canvasSize.width - CGFloat(1 + (hasLeft ? 1 : 0) + (hasRight ? 1 : 0)) * deskWidth - CGFloat((hasLeft ? 1 : 0) + (hasRight ? 1 : 0)) * deskGap)/2) }
    private var myX: CGFloat { hasLeft ? deskInset + deskWidth + deskGap : deskInset }
    private var seatX: CGFloat { myX - deskWidth - deskGap }
    private var rightX: CGFloat { myX + deskWidth + deskGap }

    /// Read on every frame, so the minutes tick over without anyone pushing updates.
    var bubbleText: () -> String = { "" }
    /// A second bubble above mine for a moment, e.g. "민지가 공부를 시작했어요 !".
    var newsText: () -> String = { "" }
    var myName: () -> String = { "" }
    /// On my desk while I'm at it; an empty desk draws none.
    var drink: Sprites.Drink = .none
    /// A laptop on my desk instead of a book (menu).
    var laptop = false
    /// The time of day for the window's sky and the lamps; the self-test sets it.
    var clock: () -> Date = { Date() }
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
            roomKey = ""
            remember("lookExtras", look.extra)
            if let custom=look.customization {remember("customization",custom.json)}
            remember("style", look.code)
            remember("look", look.girl ? "girl" : "boy")
            redraw()
        }
    }

    init() {
        // Older settings only knew boy or girl; those get a random look of that gender.
        let saved = Settings.get("style")
        var initialLook = saved.isEmpty ? Look.random(girl: Settings.get("look") == "girl") : Look.parse(saved, girl: Settings.get("look") == "girl")
        initialLook = initialLook.withExtras(Settings.get("lookExtras"))
        if !Settings.get("customization").isEmpty {initialLook=initialLook.withCustomization(Customization.parse(Settings.get("customization"),initialLook))}
        if saved.isEmpty { initialLook = initialLook.withAdditions(0) }
        look = initialLook
        super.init(contentRect: NSRect(origin: .zero, size: petSize), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        if saved.isEmpty { remember("style", look.code); remember("lookExtras",look.extra) }
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
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    static func clampDesk(_ desired: NSPoint, area: NSRect, size: NSSize, deskTop: CGFloat) -> NSPoint {
        NSPoint(x: max(area.minX, min(desired.x, max(area.minX, area.maxX - size.width))),
                y: max(area.minY - size.height + 24, min(desired.y, area.maxY - size.height + deskTop)))
    }
    private var displayedDeskTop: CGFloat { (floorY + 27 * scale) * frame.width / canvasSize.width }

    func setDisplaySize(_ percent: Int) {
        guard PetWindow.displaySizes.contains(percent) else { return }
        sizePercent = percent
        redraw()
    }

    private func fitDesks() {
        hasLeft = seatmate() != nil; hasRight = rightSeatmate() != nil
        let area = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: petSize)
        let factor = min(CGFloat(sizePercent) / 100, min(area.width / canvasSize.width, area.height / canvasSize.height))
        let size = NSSize(width: canvasSize.width * factor, height: canvasSize.height * factor)
        if frame.size == size && contentView?.bounds.size == canvasSize { return }
        let old = frame
        let x = old.minX - area.minX < area.maxX - old.maxX ? old.minX : old.maxX - size.width
        if frame.size != size { setContentSize(size) }
        contentView?.frame = NSRect(origin: .zero, size: size)
        contentView?.bounds = NSRect(origin: .zero, size: canvasSize)
        setFrameOrigin(Self.clampDesk(NSPoint(x: x, y: old.minY), area: area, size: size, deskTop: displayedDeskTop))
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
        moodSeconds = 0
        fading = false
        alphaValue = 0.25
        redraw()
        orderFrontRegardless()
        startAnimation()
    }

    private func startAnimation() {
        if timer == nil {
            lastStepSeconds = ProcessInfo.processInfo.systemUptime
            let t = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(step), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    func setMood(_ newMood: Mood) {
        if mood == newMood { redraw(); return }
        transitionFrom = myPose
        mood = newMood
        tick = 0
        moodSeconds = 0
        redraw()
    }

    func setUpdateAvailable(_ available: Bool) {
        if updateAvailable == available { return }
        updateAvailable = available
        updateShownAt = animationSeconds
        if available && !minimized && (!isVisible || mood == .leaving || mood == .away) { appear(.notifying) }
        else if !available && mood == .notifying { timer?.invalidate(); timer = nil; mood = .away; orderOut(nil) }
        else { redraw() }
    }

    func showFeedback(_ text: String) { feedbackText = text; feedbackUntil = animationSeconds + 8; updateShownAt = animationSeconds; if minimized { restoreScene() }; if !isVisible { appear(.notifying) }; redraw() }
    var updateText: String {
        if animationSeconds < feedbackUntil { return feedbackText }
        return updateAvailable && animationSeconds - updateShownAt < 8 && (mood == .studying || mood == .dozing || mood == .notifying) ? Self.updateMessage : ""
    }

    /// Stand up, wave for about two seconds, fade out, hide.
    func standUpAndLeave() {departureLook=look;departureLaptop=laptop; visitTick = -1; outgoingTick = -1; setMood(.leaving) }

    /// A friend comes round behind my desk and taps my pet on the shoulder, saying `text`.
    /// If my pet isn't out, the friend turns up at my empty desk, waves, and leaves again.
    /// `side` is where they come from: -1 the left seat, 1 the right, 0 from outside.
    func visit(_ friend: Look, text: String, side: Int) {
        if minimized { return }
        visitLook = friend
        visitText = text
        visitSide = side
        visitTick = 0
        if !isVisible || fading || mood == .leaving { appear(.away) }
    }

    func goVisit(_ name: String, message: String, side: Int) {
        if minimized { return }
        outgoingTick = 0; outgoingSide = side; outgoingText = name + "에게\n" + message
        if !isVisible { appear(.away) }
    }

    /// For the self-test: one moment of the animation, set up without showing the window.
    func preview(_ atMood: Mood, frame atFrame: Int, visitTick atVisitTick: Double = -1,
                 friend: Look = Look(girl: false, 0, 0, 0, 0, 0, 0), friendText: String = "", outgoingTick atOutgoingTick: Double = -1, outgoingDirection: Int = 0, incomingDirection: Int = -1) {
        mood = atMood
        frameCount = atFrame
        tick = atFrame
        animationSeconds = Double(atFrame) / 4; moodSeconds = animationSeconds
        blends = [:]
        if atMood == .leaving {departureLook=look;departureLaptop=laptop}
        visitTick = atVisitTick
        visitLook = friend
        visitText = friendText
        visitSide = incomingDirection
        outgoingTick = atOutgoingTick; outgoingSide = outgoingDirection; outgoingText = "민지에게\n화이팅 !"
        fitDesks()
    }

    @objc private func step() {
        let now = ProcessInfo.processInfo.systemUptime
        let seconds = now - lastStepSeconds
        lastStepSeconds = now
        advanceAnimation(seconds)
    }

    func advanceAnimation(_ seconds: Double) {
        if minimized { return }
        let beforeFrame = frameCount
        animationSeconds += seconds; moodSeconds += seconds
        frameCount = Int(animationSeconds * 4); tick = Int(moodSeconds * 4)
        for i in 0..<2 { if leavingTicks[i] >= 0 && leavingTicks[i] < 26 { leavingTicks[i] += seconds * 4 } }
        if outgoingTick >= 0 { outgoingTick += seconds * 4; if outgoingTick > Travel.total { outgoingTick = -1; if mood == .away { fading = true } } }
        if visitTick >= 0 {
            visitTick += seconds * 4
            if visitTick > Travel.total {
                visitTick = -1
                if mood == .away { fading = true }
            }
        }
        if mood == .leaving && moodSeconds >= 6.5 || mood == .notifying && animationSeconds - updateShownAt >= 8 { fading = true }

        if fading {
            alphaValue = max(0, alphaValue - seconds * 4 / 3)
            if alphaValue == 0 {
                if updateAvailable && animationSeconds - updateShownAt < 8 { appear(.notifying); return }
                timer?.invalidate()
                timer = nil
                fading = false
                orderOut(nil)
                return
            }
        } else if alphaValue < 1 {
            alphaValue = min(1, alphaValue + seconds * 4)
        }
        // Keep idle pixel poses at 4 fps; interpolate travel, big gestures and fading at about 30 fps.
        func hasEffect(_ moment: Int) -> Bool { moment > 0 && !Routine.effect(moment).isEmpty }
        let seatEffects = [seatmate(), rightSeatmate()].contains { seat in seat.map { hasEffect(seatMoment($0)) } ?? false }
        let clockTicks = animationSeconds * 4
        let moving = (visitTick >= 0 && Travel.walking(visitTick)) || (outgoingTick >= 0 && Travel.walking(outgoingTick)) || blends.values.contains { $0.moving(clockTicks) } || hasEffect(moment) || seatEffects
        if frameCount != beforeFrame || moving || fading || alphaValue < 1 { redraw() }
    }

    func redraw() { fitDesks(); contentView?.needsDisplay = true }

    private var moment: Int { mood == .studying && visitTick < 0 && outgoingTick < 0 ? Routine.studyMoment(tick) : 0 }
    private var momentText: String { Routine.line(moment, Routine.momentFrame(tick), laptop: laptop) }

    func subjectChanged() { subjectChangedAt = animationSeconds; redraw() }
    func nextSeason() {
        let stored = Int(Settings.get("season")) ?? -1
        let season = (0..<4).contains(stored) ? stored : Self.seasonAt(clock())
        remember("season", String((season + 1) % 4)); sceneIndex = (sceneIndex + Int.random(in: 1...5)) % 6; redraw()
    }
    private var myPose: Sprites.Pose {
        switch mood {
        case .studying:
            if visitTick >= 6 && visitTick <= 16 && !visitText.contains("일어나") { return .content }
            if animationSeconds - subjectChangedAt < 1.5 { return .bookmark }
            if visitTick >= 0 && visitTick < Travel.arrive { return visitTick < 1 ? (visitSide == 1 ? .glanceRight : .glanceLeft) : visitSide == 1 ? .lookRight : .lookLeft }
            if moodSeconds < 0.75 && [.dozeA, .dozeB].contains(transitionFrom) { return .recover }
            return Routine.studyPose(tick)
        case .dozing: if moodSeconds < 0.75 { return .foldArms }; return tick / 8 % 2 == 0 ? .dozeA : .dozeB
        case .away: return .empty
        case .leaving: return Departure.pose(moodSeconds * 4)
        case .notifying: return tick < 2 ? .stand : tick / 2 % 2 == 0 ? .waveA : .waveB
        }
    }

    /// A seatmate's own moments, keyed by name so each friend keeps to their own rhythm.
    private static func seatSeed(_ seat: Seat) -> Int { nameSeed(seat.name) }
    /// Also picks a desk's bag and sticker, so a friend's screen shows mine the same.
    private static func nameSeed(_ name: String) -> Int { 1 + name.utf16.reduce(0) { $0 + Int($1) } % 211 }

    private func seatMoment(_ seat: Seat) -> Int { seat.here && !seat.dozing ? Routine.studyMoment(frameCount, seed: Self.seatSeed(seat)) : 0 }

    // Each seatmate works and dozes at their own pace, so no two pets move in lockstep.
    private func seatPose(_ seat: Seat) -> Sprites.Pose {
        if !seat.here { return .empty }
        let seed = Self.seatSeed(seat)
        if seat.dozing { return (frameCount + seed) / 8 % 2 == 0 ? .dozeA : .dozeB }
        return Routine.studyPose(frameCount, seed: seed)
    }

    /// Draws one frame into the current (flipped) graphics context.
    func paint() {
        if let board = board() { drawRoom(board.title, board.lines) } else { windowGlass = .zero }

        let seats = [seatmate(), rightSeatmate()]
        let visiting = visitTick >= 0
        let outgoing = outgoingTick >= 0
        let start = visitSide == 1 ? rightX : visitSide == -1 ? seatX : -deskWidth / 2
        let arrived = myX + (visitSide == 1 ? 25 : -25) * scale
        let visitorX = start + (arrived - start) * CGFloat(Travel.progress(visitTick))
        let walking = Travel.walking(visitTick)
        let cheering = visiting && !visitText.contains("일어나") && !visitText.contains("같이 공부")
        let tapping = visiting && !cheering && !walking && !outgoing && (mood == .studying || mood == .dozing)
        let tap = tapping && frameCount % 2 == 0
        func hop(_ travel: Double, fromSeat: Bool) -> CGFloat { (Travel.walking(travel) ? CGFloat(abs(sin(travel * .pi))) * scale : 0) - (fromSeat ? CGFloat(Travel.seated(travel)) * 4 * scale : 0) }
        if visiting { drawVisitor(visitLook, pose: walking ? .walk : cheering ? .cheer : tapping ? .reach : .wave, x: visitorX,
                                 hop: hop(visitTick, fromSeat: visitSide != 0), mirror: (visitSide == 1) != (visitTick > Travel.leave)) }
        let destination = outgoingSide < 0 ? seatX + 25 * scale : outgoingSide > 0 ? rightX - 25 * scale : canvasSize.width - deskWidth / 2
        let outX = myX + (destination - myX) * CGFloat(Travel.progress(outgoingTick))
        // Wave with the far hand: the near one would be behind the friend I'm visiting.
        if outgoing { drawVisitor(look, pose: Travel.walking(outgoingTick) ? .walk : outgoingText.contains("일어나") || outgoingText.contains("같이 공부") ? .wave : .cheer, x: outX,
                                 hop: hop(outgoingTick, fromSeat: true), mirror: (destination < myX) != (outgoingTick > Travel.leave), leftHand: true) }
        for i in 0..<2 {
            if let departing = seats[i], !departing.here && leavingTicks[i] >= 0 { drawDepartureWalker((departingSeats[i] ?? departing).look, origin: i == 0 ? seatX : rightX, tick: leavingTicks[i]) }
        }
        if mood == .leaving { drawDepartureWalker(departureLook ?? look, origin: myX, tick: moodSeconds * 4) }
        // All desks and seated pets cover the visitors walking behind them.
        var effects: [(x: CGFloat, moment: Int, phase: Double)] = []
        var lamps: [CGFloat] = []
        for i in 0..<2 {
            guard var seat = seats[i] else { previousSeats[i] = nil; leavingTicks[i] = -1; continue }
            if previousSeats[i]?.id != seat.id {leavingTicks[i] = -1;departingSeats[i]=nil}
            if let before = previousSeats[i], before.id == seat.id && before.here && !seat.here { leavingTicks[i] = 0;departingSeats[i]=before }
            if seat.here { leavingTicks[i] = -1 }
            previousSeats[i] = seat
            if leavingTicks[i]>=0,let snapshot=departingSeats[i] {seat=snapshot;seat.here=false}
            let gone = visiting && visitSide == (i == 0 ? -1 : 1)
            let pose: Sprites.Pose = gone ? .empty : leavingTicks[i] >= 0 ? Departure.pose(leavingTicks[i]) : seatPose(seat)
            let x = i == 0 ? seatX : rightX
            let lit = seat.here && !seat.dozing && !gone && (seat.look.customization?.on("lamp") ?? true)
            if !gone && leavingTicks[i]>=12 && leavingTicks[i]<18 {drawAwaySign(x,lift:CGFloat(Departure.signLift(leavingTicks[i])))}
            if lit { Sprites.drawLampGlow(left: x, top: floorY, scale: scale, lamp: seat.look.customization?.value("lamp") ?? 0) }
            let seed = Self.seatSeed(seat)
            let seatBlend = blendOf(i).track(pose, animationSeconds * 4)
            Sprites.draw(pose, seat.look, left: x, top: floorY, scale: scale,
                         decor: Sprites.Decor(drink: seat.drink, laptop: seat.laptop, seed: seed, lit: lit, away: !seat.here, packed: leavingTicks[i] >= 4), from: seatBlend.from, blend: seatBlend.blend, breath: Routine.breathing(frameCount, seed: seed), blink: Routine.blinking(frameCount, seed: seed))
            if !gone && leavingTicks[i] < 0 { effects.append((x, seatMoment(seat), Routine.momentPhase(animationSeconds * 4, seed: seed))) }
            drawNameplate(seat.name, deskX: x)
            if !seat.here && !gone { if leavingTicks[i] >= 0 { drawDepartureProps(seat.look, laptop: seat.laptop, x: x, tick: leavingTicks[i]) } else { drawAwaySign(x) } }
            if lit { lamps.append(x) }
        }
        let myLamp = mood == .studying && !outgoing && (look.customization?.on("lamp") ?? true)
        if myLamp { lamps.append(myX); Sprites.drawLampGlow(left: myX, top: floorY, scale: scale, lamp: look.customization?.value("lamp") ?? 0) }
        if mood == .leaving && moodSeconds*4>=12 && moodSeconds*4<18 {drawAwaySign(myX,lift:CGFloat(Departure.signLift(moodSeconds*4)))}
        let shownPose: Sprites.Pose = outgoing ? .empty : myPose
        let myBlend = blendOf(-1).track(shownPose, animationSeconds * 4)
        Sprites.draw(shownPose, mood == .leaving ? departureLook ?? look : look, left: myX, top: floorY, scale: scale, alert: tapping, lift: tap ? 1 : 0,
                     decor: Sprites.Decor(drink: drink, laptop: mood == .leaving && departureLook != nil ? departureLaptop : laptop, seed: Self.nameSeed(myName()), lit: myLamp, away: mood == .away || mood == .leaving, packed: mood == .leaving && moodSeconds >= 1), from: myBlend.from, blend: myBlend.blend, breath: Routine.breathing(tick), blink: Routine.blinking(tick))
        if cheering && visitTick >= 6 && visitTick <= 16 && mood == .studying && !outgoing && !visitText.contains("업데이트") { Sprites.drawFlameEyes(left: myX, top: floorY, scale: scale, alt: frameCount % 2 == 0) }
        // The tapping arm goes over my pet, or only a stub of it would show.
        if tapping {
            NSGraphicsContext.saveGraphicsState()
            if visitSide == 1 { let t = NSAffineTransform(); t.translateX(by: visitorX + 58 * scale, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat() }
            Sprites.draw(layers: Sprites.reachLayers(visitLook, down: tap), visitLook, left: visitSide == 1 ? 0 : visitorX, top: floorY, scale: scale)
            NSGraphicsContext.restoreGraphicsState()
        }
        drawNameplate(myName(), deskX: myX)
        if mood == .leaving { drawDepartureProps(departureLook ?? look, laptop: departureLook == nil ? laptop : departureLaptop, x: myX, tick: moodSeconds * 4) }
        else if mood == .away && !outgoing { drawAwaySign(myX) }
        // The lamps' light over everything at their desks (but under the speech bubbles).
        for x in lamps { Sprites.drawLampPool(left: x, top: floorY, scale: scale) }
        effects.append((myX, moment, Routine.momentPhase(moodSeconds * 4)))
        let tip = floorY - 2
        let mid = CGFloat(Sprites.dx + 16) * scale
        let narrow = min(canvasSize.width-2,max(deskWidth+16,deskWidth+deskGap-6))
        if visiting || outgoing {
            let top = drawBubble(visiting ? visitText : outgoingText, cx: (visiting ? visitorX : outX) + mid, tipY: tip, maxWidth: canvasSize.width - 2, fill: PetWindow.visitYellow)
            if !updateText.isEmpty { drawBubble(updateText, cx: (outgoing ? outX : myX) + mid, tipY: top - 2, maxWidth: canvasSize.width - 2, fill: PetWindow.newsMint) }
        }
        else {
            var top = tip
            if mood != .away { top = drawBubble(!updateText.isEmpty ? updateText : moment == 0 ? bubbleText() : momentText, cx: myX + mid, tipY: tip, maxWidth: updateText.isEmpty ? narrow : canvasSize.width - 2, fill: .white) }
            for i in 0..<2 {
                if let seat = seats[i], seat.here || (leavingTicks[i] >= 0 && leavingTicks[i] < 18) { drawBubble(leavingTicks[i] >= 0 && leavingTicks[i] < 18 ? "다녀올게요!" : seat.text,
                                                    cx: (i == 0 ? seatX : rightX) + mid, tipY: tip, maxWidth: narrow, fill: .white) }
            }
            let news = mood != .away ? newsText() : ""
            if news != shownNews { shownNews = news; newsShownAt = animationSeconds }
            // Flashes yellow for its first three seconds, so a glance away doesn't miss it.
            let flash = animationSeconds - newsShownAt < 3 && frameCount / 2 % 2 == 0
            drawBubble(news, cx: myX + mid, tipY: top - 2, maxWidth: canvasSize.width - 2, fill: flash ? PetWindow.visitYellow : PetWindow.newsMint)
        }
        // Over the bubbles, so a bubble never hides them.
        for effect in effects where effect.moment > 0 {
            if Routine.effect(effect.moment) == "butterfly" { drawButterfly(effect.x, effect.phase) }
            if Routine.effect(effect.moment) == "hearts" { drawHearts(effect.x, effect.phase) }
        }
    }

    private func drawDepartureWalker(_ actor: Look, origin: CGFloat, tick: Double) {
        guard tick>=18 && tick<26 else {return}
        let x=origin-(origin+deskWidth)*CGFloat(Departure.walk(tick))
        drawVisitor(actor,pose:.carry,x:x,hop:CGFloat(abs(sin(tick * .pi)))*scale,mirror:false)
        Sprites.drawBag(actor,left:x+10*scale,top:floorY+22*scale,scale:scale)
        Sprites.drawPackingReach(actor,left:x,top:floorY,scale:scale,targetX:13,targetY:23,leftHand:true)
    }
    private func drawDepartureProps(_ actor: Look, laptop: Bool, x: CGFloat, tick: Double) {
        if tick>=4 && tick<10 {let p=Departure.item(tick,laptop);NSGraphicsContext.saveGraphicsState();NSRect(x:x,y:0,width:deskWidth,height:floorY+20*scale).clip();Sprites.drawPackingItem(actor,laptop:laptop,left:x+CGFloat(p.0)*scale,top:floorY+CGFloat(p.1)*scale,scale:scale,turn:Departure.ease((tick-4)/3));NSGraphicsContext.restoreGraphicsState()}
        if tick<18 {let bag=Departure.bag(tick);Sprites.drawBag(actor,left:x+CGFloat(bag.0)*scale,top:floorY+CGFloat(bag.1)*scale,scale:scale,open:tick>=5 && tick<10);if tick>=2 {let target=Departure.hand(tick,laptop);Sprites.drawPackingReach(actor,left:x,top:floorY,scale:scale,targetX:Int(target.0.rounded()),targetY:Int(target.1.rounded()),leftHand:target.0<28)}}
        if tick>=12 {if tick>=18 {drawAwaySign(x,lift:CGFloat(Departure.signLift(tick)))};if tick<16 {Sprites.drawPackingReach(actor,left:x,top:floorY,scale:scale,targetX:40,targetY:Int((20-Departure.signLift(tick)).rounded()))}}
    }
    private func drawAwaySign(_ x: CGFloat, lift: Double = 0) {
        let height = 18
        let top = floorY + (CGFloat(27 - height) - CGFloat(lift)) * scale
        let antialias = NSGraphicsContext.current?.shouldAntialias ?? true
        NSGraphicsContext.current?.shouldAntialias = false
        let grid = Array(Sprites.art("AwaySign").suffix(height))
        let left = Sprites.width - 22
        for (y, row) in grid.enumerated() {
            for (col, c) in row.enumerated() where c != "." {
                (c == "k" ? PetWindow.wood : c == "d" ? PetWindow.floorWood : c == "u" ? Sprites.color(0xFFF9E7) : Sprites.color(0xFFF1B8)).setFill()
                NSRect(x: x + CGFloat(left + col) * scale, y: top + CGFloat(y) * scale, width: scale, height: scale).fill()
            }
        }
        NSGraphicsContext.current?.shouldAntialias = antialias
        drawLine("자리 비움", font: .systemFont(ofSize: 3.5 * scale, weight: .bold), color: PetWindow.ink,
                 in: NSRect(x: x + CGFloat(left + 1) * scale, y: top + scale, width: 20 * scale, height: 9 * scale))
    }

    /// Flutters in from the right (phase 0..12 of the moment), rests on the head with its
    /// wings mostly shut, and flies off up and away from phase 20.
    private func drawButterfly(_ deskX: CGFloat, _ phase: Double) {
        let small = scale / 2
        var x = deskX + 26 * scale - 8.5 * small, y = floorY + 7 * scale - 12 * small
        var folded = Int(phase * 2) % 2 == 0
        if phase < 12 {
            let away = CGFloat(1 - phase / 12)
            x += away * 16 * scale
            y -= away * (6 + 2 * CGFloat(sin(phase * 1.6))) * scale
        } else if phase < 20 {
            folded = Int(phase) % 4 != 0
        } else {
            let gone = CGFloat((phase - 20) / 4)
            x += gone * 14 * scale
            y -= gone * 12 * scale
        }
        Sprites.drawButterfly(left: x, top: y, scale: small, folded: folded)
    }

    /// Little hearts rising one after another beside the head.
    private func drawHearts(_ deskX: CGFloat, _ phase: Double) {
        let small = scale / 2
        for i in 0..<4 {
            let t = phase - Double(i * 5)
            if t < 0 || t > 10 { continue }
            Sprites.drawHeart(left: deskX + CGFloat(36 + i % 2 * 3) * scale + CGFloat(sin(t * 1.2)) * small,
                              top: floorY + 20 * scale - CGFloat(t * 1.8) * scale, scale: small)
        }
    }
    private func drawVisitor(_ actor: Look, pose: Sprites.Visiting, x: CGFloat, hop: CGFloat, mirror: Bool, leftHand: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height).clip()
        if mirror { let t = NSAffineTransform(); t.translateX(by: x + 58 * scale, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat() }
        Sprites.draw(layers: Sprites.visitor(actor, pose, alt: frameCount % 2 == 0, leftHand: leftHand), actor, left: mirror ? 0 : x, top: floorY - hop, scale: scale)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Lines (split on "\n") in a rounded box whose tail points down at `cx`. Returns the
    /// box's top, so another bubble can stack above it.
    @discardableResult
    private func drawBubble(_ text: String, cx: CGFloat, tipY: CGFloat, maxWidth: CGFloat, fill: NSColor) -> CGFloat {
        if text.isEmpty { return tipY }
        let lines = text.components(separatedBy: "\n")
        let factor = textFactor
        let font = NSFont.boldSystemFont(ofSize: (text == Self.updateMessage ? 12 : 13) * factor)
        let lineHeight: CGFloat = 18 * factor
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
        let font = NSFont.boldSystemFont(ofSize: 3.4 * scale * nameFactor)
        // Between the desk's left edge and the person's hand (cols 1..16).
        let maxName: CGFloat = min(20,15 * nameFactor)
        let w = min(maxName * scale, max(8 * scale, textWidth(name, font) + 3 * scale))
        let x = deskX + scale + (maxName * scale - w) / 2
        let labelHeight = max(5 * scale, font.ascender - font.descender + 2)
        let face = NSRect(x: x, y: floorY + 27 * scale - labelHeight, width: w, height: labelHeight)
        PetWindow.plateTop.setFill()
        NSRect(x: x + scale / 2, y: face.minY - scale, width: w - scale, height: scale + 1).fill()
        PetWindow.plateFace.setFill()
        face.fill()
        PetWindow.ink.setStroke()
        NSBezierPath(rect: face).stroke()
        drawLine(name, font: font, color: PetWindow.plateText, in: face)
    }

    /// The classroom hardly changes, so it is painted once and reused until something in it does:
    /// the board's text, the sky, the scene, or a cloud moving on (one column every six seconds).
    private func drawRoom(_ title: String, _ lines: [String]) {
        let now = clock()
        let drift = Int(now.timeIntervalSince1970 / 6) % 100000
        let swing = look.customization.map { $0.on("clock") && $0.value("clock") == 1 } ?? false
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let season = seasonNow(now), sky = Self.skyAt(now), scene = windowScene
        let key = "\(canvasSize)|\(title)|\(lines)|\(sky)|\(season)|\(scene)|\(drift)|\(swing ? 0 : minute)|\(boardFactor)"
        if roomImage == nil || key != roomKey {
            roomKey = key
            windowGlass = windowRect() ?? .zero
            let image = NSImage(size: canvasSize, flipped: true) { [weak self] _ in self?.drawClassroom(title, lines, withClock: !swing, sky: sky, season: season, scene: scene, drift: drift); return true }
            image.cacheMode = .always
            roomImage = image
        }
        roomImage?.draw(in: NSRect(origin: .zero, size: canvasSize), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if swing { drawWallClock(now) }
        if windowGlass == .zero { return }
        // Whatever the season blows past the glass, behind the desks and in front of the view.
        NSGraphicsContext.saveGraphicsState()
        windowGlass.insetBy(dx: 2 * scale, dy: 2 * scale).clip()
        Sprites.drawParticles(Int(windowGlass.width / scale), Int(windowGlass.height / scale), sky: sky, season: season, t: animationSeconds, left: windowGlass.minX, top: windowGlass.minY, scale: scale)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawWallClock(_ now: Date) {
        let top = boardSpace + 10 + 12
        if let c = look.customization { c.drawClock(look, 9, top, 2, now) }
        else { let date = Calendar.current.dateComponents([.hour, .minute], from: now); Sprites.drawClock(date.hour ?? 0, date.minute ?? 0, left: 9, top: top, scale: 2) }
    }

    /// The classroom behind the desks: a wall with a chalkboard (one line per person, so it
    /// grows), wainscoting and a wooden floor, all on one rounded card.
    private func drawClassroom(_ title: String, _ lines: [String], withClock: Bool, sky: Int, season: Int, scene: Int, drift: Int) {
        let columns = lines.count >= 4 ? 2 : 1
        let shownLines = CGFloat((lines.count + columns - 1) / columns)
        let boardBottom = boardSpace - 18
        let titleLines = title.components(separatedBy: "\n")
        let boardTop = boardBottom - ((shownLines + CGFloat(titleLines.count)) * boardLine + 32)
        let card = NSRect(x: 2, y: boardTop - 14, width: canvasSize.width - 4, height: canvasSize.height - 2 - (boardTop - 14))

        let cardPath = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
        PetWindow.wall.setFill()
        cardPath.fill()
        NSGraphicsContext.saveGraphicsState()
        cardPath.addClip()
        // Wainscoting under a lit rail, its panels marked off every twelve pixels.
        let railTop = floorY + 20 * scale
        PetWindow.wainscot.setFill()
        NSRect(x: card.minX, y: railTop, width: card.width, height: card.height).fill()
        PetWindow.wainscotRail.setFill()
        NSRect(x: card.minX, y: railTop, width: card.width, height: scale).fill()
        PetWindow.wainscotShade.setFill()
        NSRect(x: card.minX, y: railTop + scale, width: card.width, height: scale).fill()
        var panel = card.minX + 6 * scale
        while panel < card.maxX { NSRect(x: panel, y: railTop + 2 * scale, width: max(1, scale / 2), height: 13 * scale).fill(); panel += 12 * scale }
        let floorTop = floorY + 35 * scale
        Customization.drawFloor(NSRect(x:card.minX,y:floorTop,width:card.width,height:card.maxY-floorTop),scale,look.customization?.on("floor") == true)
        drawWindow(sky: sky, season: season, scene: scene, drift: drift)
        if withClock { drawWallClock(clock()) }
        NSGraphicsContext.restoreGraphicsState()
        cardPath.lineWidth = 1
        Sprites.color(0xC9B89A).setStroke()
        cardPath.stroke()

        let frame = NSRect(x: 18, y: boardTop, width: canvasSize.width - 36, height: boardBottom - boardTop)
        let slate = frame.insetBy(dx: 5, dy: 5)
        // Square wooden corners, lit along the top like everything else in the room.
        PetWindow.ink.setFill()
        frame.insetBy(dx: -max(1, scale / 3), dy: -max(1, scale / 3)).fill()
        PetWindow.wood.setFill()
        frame.fill()
        PetWindow.woodLit.setFill()
        NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(1, scale / 2)).fill()
        PetWindow.slate.setFill()
        slate.fill()
        PetWindow.woodDark.setFill()
        NSRect(x: frame.minX + 20, y: frame.maxY - 2, width: frame.width - 40, height: 5).fill()
        let trayTop = frame.maxY - 2
        PetWindow.chalk.setFill()
        NSRect(x: frame.maxX - 58, y: trayTop - 2, width: 13, height: 2).fill()
        Sprites.color(0xF7D774).setFill()
        NSRect(x: frame.maxX - 40, y: trayTop - 2, width: 9, height: 2).fill()
        Sprites.color(0x4A4F5C).setFill()
        NSRect(x: frame.minX + 30, y: trayTop - 4, width: 18, height: 4).fill()
        Sprites.color(0xC8AD86).setFill()
        NSRect(x: frame.minX + 30, y: trayTop - 4, width: 18, height: 1).fill()

        let faint = PetWindow.chalk.withAlphaComponent(150.0 / 255)
        let textX = slate.minX + 10
        let textW = slate.width - 20
        for (n, header) in titleLines.enumerated() {
            drawLine(header, font: .boldSystemFont(ofSize: (n == 0 && titleLines.count > 1 ? 19 : 14) * boardFactor), color: n == 0 ? PetWindow.chalk : faint,
                     in: NSRect(x: textX, y: slate.minY + 6 + CGFloat(n) * boardLine, width: textW, height: boardLine), align: .center)
        }
        let cellWidth = textW / CGFloat(columns)
        for (i, line) in lines.enumerated() {
            drawLine(line, font: .systemFont(ofSize: 16 * boardFactor), color: PetWindow.chalk,
                     in: NSRect(x: textX + CGFloat(i % columns) * cellWidth, y: slate.minY + CGFloat(titleLines.count) * boardLine + 10 + CGFloat(i / columns) * boardLine, width: cellWidth, height: boardLine), align: .center)
        }
    }

    /// The kind of sky at an hour: 0 night, 1 dawn, 2 day, 3 sunset. Dawn and sunset get an
    /// hour each; the rest of the day is a blue sky, in every season.
    static func skyAt(_ time: Date) -> Int {
        let hour = Calendar.current.component(.hour, from: time)
        return hour < 5 || hour >= 19 ? 0 : hour == 5 ? 1 : hour < 18 ? 2 : 3
    }

    /// The season of a date: 0 spring (Mar–May), 1 summer, 2 autumn, 3 winter (Dec–Feb).
    static func seasonAt(_ time: Date) -> Int {
        let s = Calendar.current.component(.month, from: time) % 12 / 3
        return s == 0 ? 3 : s - 1
    }

    /// The classroom's window, a little narrower than the wall: the hour's sky and the season's tree.
    private func windowRect() -> NSRect? {
        let cardWidth = canvasSize.width - 4
        let wallWidth = cardWidth - 28, wallHeight = floorY + 18 * scale - boardSpace - 10
        let w = Int(wallWidth * 0.72 / scale), h = Int(wallHeight / scale)
        guard w >= 20, h >= 16 else { return nil }
        return NSRect(x: (2 + 14 + (wallWidth - CGFloat(w) * scale) / 2).rounded(.down), y: boardSpace + 10, width: CGFloat(w) * scale, height: CGFloat(h) * scale)
    }
    private func drawWindow(sky: Int, season: Int, scene: Int, drift: Int) {
        guard let glass = windowRect() else { return }
        Sprites.drawWindow(Int(glass.width / scale), Int(glass.height / scale), sky: sky, season: season, left: glass.minX, top: glass.minY, scale: scale, scene: scene, drift: drift)
        if let c = look.customization { c.drawRoom(look, glass, clock(), preview: false) }
    }
    private func seasonNow(_ now: Date) -> Int {
        let stored = Int(Settings.get("season")) ?? -1
        return (0..<4).contains(stored) ? stored : Self.seasonAt(now)
    }

    private var sceneIndex = Int.random(in: 0..<6)
    private var sceneBucket = -1
    private var windowScene: Int {
        let bucket = Int(clock().timeIntervalSince1970 / 1800)
        if sceneBucket != bucket { sceneBucket = bucket; sceneIndex = (sceneIndex + Int.random(in: 1...5)) % 6 }
        return sceneIndex
    }
    func nextWindowScene() { sceneIndex = (sceneIndex + Int.random(in: 1...5)) % 6; redraw() }

    // ---- Mouse ----------------------------------------------------------------------

    fileprivate func mouseDown(_ event: NSEvent, at p: NSPoint) {
        if event.modifierFlags.contains(.control) {
            showMenu(event)
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
        if dragged {
            let area = NSScreen.screens.first(where: { $0.frame.contains(now) })?.visibleFrame ?? NSScreen.main!.visibleFrame
            setFrameOrigin(Self.clampDesk(NSPoint(x: dragOrigin.x + now.x - from.x, y: dragOrigin.y + now.y - from.y), area: area, size: frame.size, deskTop: displayedDeskTop))
        }
    }

    fileprivate func mouseUp(at p: NSPoint) {
        guard dragFrom != nil else { return }
        dragFrom = nil
        if dragged {
            remember("position", "\(Int(frame.origin.x)),\(Int(frame.origin.y))")
            return
        }
        if hitBoard(p) { boardClicked(); return }
        if p.y >= floorY - 8 {
            if let seat = seatmate(), hitSeat(p, x: seatX, actor: seat.look, pose: seatPose(seat), drink: seat.drink, laptop: seat.laptop) { seatmateClicked(); return }
            if let seat = rightSeatmate(), hitSeat(p, x: rightX, actor: seat.look, pose: seatPose(seat), drink: seat.drink, laptop: seat.laptop) { rightSeatmateClicked(); return }
            if hitSeat(p, x: myX, actor: look, pose: myPose, drink: drink, laptop: laptop) { if mood == .away { awayClicked() } else { petClicked() }; return }
        }
        if windowGlass.contains(p) { nextSeason() }
    }

    private func hitSeat(_ p: NSPoint, x: CGFloat, actor: Look, pose: Sprites.Pose, drink: Sprites.Drink, laptop: Bool) -> Bool {
        let px = Int(floor((p.x - x) / scale)), py = Int(floor((p.y - floorY) / scale))
        if px >= 1 && px < 17 && py >= 21 && py < 27 { return true }
        if pose == .empty && px >= 17 && px < 39 && py >= 9 && py < 27 { return true }
        return Sprites.compose(pose, actor, decor: Sprites.Decor(drink: drink, laptop: laptop)).contains { layer in
            let row = py - layer.y, col = px - layer.x
            guard row >= 0 && row < layer.grid.count else { return false }
            let cells = Array(layer.grid[row])
            return col >= 0 && col < cells.count && cells[col] != "."
        }
    }

    func hitBoard(_ p: NSPoint) -> Bool {
        guard let board = board() else { return false }
        let bottom = boardSpace - 18
        let rows = board.lines.count >= 4 ? (board.lines.count + 1) / 2 : board.lines.count
        let top = bottom - (CGFloat(rows + board.title.components(separatedBy: "\n").count) * boardLine + 32)
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
        return Self.clampDesk(NSPoint(x: x, y: y), area: area, size: frame.size, deskTop: displayedDeskTop)
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
