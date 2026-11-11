import AppKit
import CoreText

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
    /// My desk prop's life: minutes on the timer, a plant's growth (0..2), today's book stack (1..5); -1 its usual look.
    var studyMinutes = -1
    var propGrowth = -1
    var propBooks = -1
        var id = ""
        /// A note from a friend waits on this empty desk (anyone in the room can see it there).
        var note = false
        /// Their minutes of study as the room shows them, for the timer on their desk; -1 unknown.
        var minutes = -1
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
    private var animating = true
    private var updateAvailable = false
    static let updateMessage = "새 버전이 나왔어요\n우클릭 → 업데이트 확인"
    private var mood = Mood.away
    private var frameCount = 0  // always counts, for animations that don't restart with the mood
    private var tick = 0        // restarts with each mood
    // My own rhythm for this stretch of study, so no two sessions open with the same moments.
    private var routineSeed = 0
    private var fading = false
    private var visitTick = -1.0 // four units per second, with fractional travel
    private var visitLook = Look(girl: false, 0, 0, 0, 0, 0, 0)
    private var visitText = ""
    private var onArrival: (() -> Void)? // what happens once the visitor reaches the desk
    private var visitRetort = "", outgoingRetort = "" // the answer to a cheer from someone not studying
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
    // Walking in to study (Departure.arrival), mine and each seatmate's; -1 when not.
    private var arrivalTick = -1.0
    private var arrivingTicks = [-1.0, -1.0]
    // When I first saw each seatmate resting, by my clock: how deeply they sleep.
    private var restSince = [-1.0, -1.0]
    // A moment played on cue (a snack eaten, a yawn caught from a seatmate): which, from when (moodSeconds × 4), and what it says.
    private var forcedMoment = 0
    private var forcedAt = 0.0
    private var forcedLine = ""
    private var seatForced: [(moment: Int, at: Double)] = [(0, 0), (0, 0)] // at in animationSeconds × 4
    private var lastSeatMoment = [0, 0]
    private var mimicked = 0 // catchable moments seen; every other one is copied
    private var lookSide = 0 // a glance at a seatmate until lookUntil (moodSeconds × 4)
    private var lookUntil = -1.0
    private var celebratedAt = [-100.0, -100.0]
    private var worried = [false, false]
    private var visitorHit = NSRect.zero, newsHit = NSRect.zero, noteHit = NSRect.zero
    // A friend's note stuck up above my desk until it's clicked off.
    private var note: (to: String, body: String, from: String)?
    // The handwriting on it (나눔손글씨 연지체, in Resources as note-font.ttf), registered for this app only.
    private static let noteFontName: String? = {
        guard let url = Bundle.main.url(forResource: "note-font", withExtension: "ttf"),
              let first = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
    }()
    static func noteFont(_ size: CGFloat) -> NSFont { noteFontName.flatMap { NSFont(name: $0, size: size) } ?? .systemFont(ofSize: size) }
    private var lastBubble = NSRect.zero
    // A borrowed eraser comes back twenty seconds after the visit: when, and who brings it (my pet, or them).
    private var returnAt = -1.0
    private var returnIncoming = false
    private var returnLook = Look(girl: false, 0, 0, 0, 0, 0, 0)
    private var returnName = ""
    private var returnSide = 0
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
    /// My desk prop's life: minutes on the timer, a plant's growth (0..2), today's book stack (1..5); -1 its usual look.
    var studyMinutes = -1
    var propGrowth = -1
    var propBooks = -1
    /// The time of day for the window's sky and the lamps; the self-test sets it.
    var clock: () -> Date = { Date() }
    /// Only quiet work and no bubbles, for when the pets would distract. A friend's visit still comes through.
    var focus = false
    func setFocus(_ on: Bool) { focus = on; wake(); redraw() }
    private var night: Bool { Self.skyAt(clock()) == 0 }
    var seatmate: () -> Seat? = { nil }
    var rightSeatmate: () -> Seat? = { nil }
    /// The chalkboard; nil hides the whole classroom background.
    var board: () -> (title: String, lines: [String])? = { nil }

    var seatmateClicked: () -> Void = {}
    var rightSeatmateClicked: () -> Void = {}
    var awayClicked: () -> Void = {}
    var petClicked: () -> Void = {}
    var boardClicked: () -> Void = {}
    /// The visiting friend or their bubble was clicked; the news bubble over my desk.
    var visitorClicked: () -> Void = {}
    var newsClicked: () -> Void = {}
    /// A seatmate has been resting ten minutes: their name and how long.
    var worriedAbout: (String, Int) -> Void = { _, _ in }
    /// The menu for a seatmate's desk (-1 left, 1 right), or nil for the usual one.
    var seatMenu: (Int) -> NSMenu? = { _ in nil }
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
        returnAt = -1
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

    /// `arrive`: walk in with the bag and unpack, for a study session just started here.
    func appear(_ newMood: Mood, arrive: Bool = false) {
        arrivalTick = arrive && newMood == .studying && !minimized && !focus ? 0 : -1
        forcedMoment = 0; lookUntil = -1
        mood = newMood
        routineSeed = Int.random(in: 1...211)
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
            t.tolerance = 0.01
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    func setMood(_ newMood: Mood) {
        if mood == newMood { redraw(); return }
        transitionFrom = myPose
        arrivalTick = -1
        forcedMoment = 0; lookUntil = -1 // timed from the mood's own clock
        mood = newMood
        routineSeed = Int.random(in: 1...211)
        tick = 0
        moodSeconds = 0
        wake()
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
    func visit(_ friend: Look, text: String, side: Int, arrived: (() -> Void)? = nil, retort: String = "") {
        returnAt = -1 // a new visit comes first
        if minimized { arrived?(); return }
        if FriendInteractions.isBorrow(text) { (returnAt, returnIncoming, returnLook, returnName, returnSide) = (animationSeconds + 26, true, friend, text.components(separatedBy: " : ")[0], side) }
        onArrival = arrived
        arrivalTick = -1 // a visit comes first
        visitLook = friend
        visitText = text
        visitRetort = retort
        visitSide = side
        visitTick = 0
        wake()
        if !isVisible || fading || mood == .leaving { appear(.away) }
    }

    /// A note from `from` to `to`, stuck up over my desk until clicked; it keeps an empty desk's window open.
    func showNote(to: String, body: String, from: String) {
        note = (to.isEmpty ? "나" : to, body, from)
        if minimized { return }
        if !isVisible || fading { appear(.away) }
        wake(); redraw()
    }

    /// Play moment `id` (a name from the routines, e.g. "munch") after `delay` ticks, saying `line`
    /// instead of its own caption. Only while studying; a new mood ends it.
    func play(_ id: String, delay: Double = 0, line: String = "") {
        let moment = Routine.momentIndex(id)
        guard moment > 0 && mood == .studying else { return }
        forcedMoment = moment; forcedAt = moodSeconds * 4 + delay; forcedLine = line
        wake()
    }
    private var forced: Int { forcedMoment > 0 && moodSeconds * 4 >= forcedAt && moodSeconds * 4 < forcedAt + 24 ? Int(moodSeconds * 4 - forcedAt) : -1 }
    private func seatForcedFrame(_ i: Int) -> Int { let f = animationSeconds * 4 - seatForced[i].at; return seatForced[i].moment > 0 && f >= 0 && f < 24 ? Int(f) : -1 }

    /// A seatmate (-1 left, 1 right) has just passed another hour: a sparkle over their desk and a hand in the air.
    func celebrate(_ side: Int) {
        if focus || side == 0 { return }
        celebratedAt[side < 0 ? 0 : 1] = animationSeconds
        wake()
    }

    /// Twenty seconds on, the eraser goes back: quietly dropped if anything else is going on.
    private func bringBack() {
        returnAt = -1
        if visitTick >= 0 || outgoingTick >= 0 || minimized || mood == .away || mood == .leaving || mood == .notifying { return }
        if returnIncoming { visit(returnLook, text: returnName + " : " + FriendInteractions.giveBack, side: returnSide) }
        else { goVisit(returnName, message: FriendInteractions.giveBack, side: returnSide) }
    }

    /// A visitor has reached my desk: a snack gets eaten.
    private func visitorArrived() { if FriendInteractions.isSnack(visitText) && mood == .studying { play("munch") } }
    /// My pet has reached a seatmate's desk with a snack: they eat it.
    private func arrivedAtFriend() {
        guard outgoingSide != 0 else { return }
        let i = outgoingSide < 0 ? 0 : 1
        if let seat = i == 0 ? seatmate() : rightSeatmate(), seat.here && !seat.dozing && FriendInteractions.isSnack(outgoingText) { seatForced[i] = (Routine.momentIndex("munch"), animationSeconds * 4) }
    }

    /// A seatmate's yawn is catching and a stretch is better together; a dropped pencil gets a look.
    /// Every other time, and never over anything else my pet is doing.
    func mimic(_ i: Int, _ id: String) {
        guard ["yawn", "stretch", "drop"].contains(id) else { return }
        mimicked += 1
        if mimicked % 2 == 0 || focus || mood != .studying || visitTick >= 0 || outgoingTick >= 0 || arrivalTick >= 0 || sendOffSide != 0 || forcedMoment > 0 || moment > 0 || moodSeconds * 4 < lookUntil { return }
        if id == "drop" { lookSide = i == 0 ? -1 : 1; lookUntil = moodSeconds * 4 + 10 }
        else { play(id, delay: id == "yawn" ? 6 : 3, line: id == "yawn" ? "하품이 옮았다…" : "같이 으쌰 !") }
    }

    func goVisit(_ name: String, message: String, side: Int, retort: String = "") {
        returnAt = -1
        if minimized { return }
        if FriendInteractions.isBorrow(message) { (returnAt, returnIncoming, returnName, returnSide) = (animationSeconds + 26, false, name, side) }
        arrivalTick = -1
        outgoingTick = 0; outgoingSide = side; outgoingText = name + "에게\n" + message; outgoingRetort = side == 0 && !retort.isEmpty ? name + " : " + retort : retort // no desk on screen to say it from
        wake()
        if !isVisible { appear(.away) }
    }

    /// For the self-test: one moment of the animation, set up without showing the window.
    func preview(_ atMood: Mood, frame atFrame: Int, visitTick atVisitTick: Double = -1,
                 friend: Look = Look(girl: false, 0, 0, 0, 0, 0, 0), friendText: String = "", outgoingTick atOutgoingTick: Double = -1, outgoingDirection: Int = 0, incomingDirection: Int = -1, arrivalTick atArrivalTick: Double = -1) {
        mood = atMood
        arrivalTick = atArrivalTick
        routineSeed = 0
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
        timer?.fireDate = Date(timeIntervalSinceNow: nextStep)
    }

    /// Nobody can see the window: covered, on another Space, or the display is asleep.
    private var unseen: Bool { isVisible && !occlusionState.contains(.visible) }
    /// Seconds to the next step: about 30 fps while something moves, otherwise asleep until the next pose is due.
    var nextStep: TimeInterval {
        if minimized || unseen { return 1 }
        return animating ? 1.0 / 30 : max(0.001, Double(frameCount + 1) / 4 - animationSeconds)
    }
    private func wake() { animating = true; timer?.fireDate = Date() }

    func advanceAnimation(_ seconds: Double) {
        if minimized { return }
        let beforeFrame = frameCount
        let visitWas = visitTick, outWas = outgoingTick
        animationSeconds += seconds; moodSeconds += seconds
        frameCount = Int(animationSeconds * 4); tick = Int(moodSeconds * 4)
        for i in 0..<2 { if leavingTicks[i] >= 0 && leavingTicks[i] < 26 { leavingTicks[i] += seconds * 4 } }
        for i in 0..<2 where arrivingTicks[i] >= 0 { arrivingTicks[i] += seconds * 4; if arrivingTicks[i] >= Departure.arrivalTicks { arrivingTicks[i] = -1 } }
        if arrivalTick >= 0 { arrivalTick += seconds * 4; if arrivalTick >= Departure.arrivalTicks { arrivalTick = -1 } }
        if outgoingTick >= 0 { outgoingTick += seconds * 4; if outgoingTick > Travel.total { outgoingTick = -1; if mood == .away && note == nil { fading = true } } }
        if visitTick >= Travel.arrive, let arrive = onArrival { onArrival = nil; arrive() }
        if visitTick >= 0 {
            visitTick += seconds * 4
            if visitTick > Travel.total {
                visitTick = -1
                if mood == .away && note == nil { fading = true }
            }
        }
        if visitWas >= 0 && visitWas < Travel.arrive && visitTick >= Travel.arrive { visitorArrived() }
        if outWas >= 0 && outWas < Travel.arrive && outgoingTick >= Travel.arrive { arrivedAtFriend() }
        if forcedMoment > 0 && moodSeconds * 4 >= forcedAt + 24 { forcedMoment = 0 }
        // Back at their desk with a borrowed eraser: they rub something out.
        if outWas >= 0 && outgoingTick < 0 && FriendInteractions.isBorrow(outgoingText) { play("erase", delay: 4) }
        if visitWas >= 0 && visitTick < 0 && visitSide != 0 && FriendInteractions.isBorrow(visitText) { seatForced[visitSide < 0 ? 0 : 1] = (Routine.momentIndex("erase"), animationSeconds * 4 + 4) }
        if returnAt >= 0 && animationSeconds >= returnAt { bringBack() }
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
        let moving = (visitTick >= 0 && Travel.walking(visitTick)) || (outgoingTick >= 0 && Travel.walking(outgoingTick)) || arrivalTick >= 0 || arrivingTicks.contains { $0 >= 0 } || celebratedAt.contains { animationSeconds - $0 < 3 } || blends.values.contains { $0.moving(clockTicks) } || hasEffect(moment) || seatEffects
        animating = moving || fading || alphaValue < 1
        if (frameCount != beforeFrame || animating) && !unseen { redraw() }
    }

    func redraw() { fitDesks(); contentView?.needsDisplay = true }

    /// Today's weather in the window (by the season it shows; none over the Christmas view) and what is
    /// passing by right now, the same on every screen.
    private func skyNow(_ now: Date) -> (weather: Int, kind: Int, phase: Double) {
        let sky = Self.skyAt(now), day = Sprites.dayIndex(now)
        let weather = windowScene == Sprites.christmasScene ? 0 : Sprites.weather(day, season: seasonNow(now), sky: sky)
        let event = Sprites.skyEvent(now.timeIntervalSince1970, sky: sky, rainDay: weather == 1)
        return (weather, event.kind, event.phase)
    }
    static let wishes = ["합격하게 해 주세요 !", "오늘 목표 다 하게 해 주세요 !", "시험 잘 보게 해 주세요 !", "내일도 같이 공부하게 해 주세요 !"]

    /// "11/10 화" and, when one is set, "기말 D-12" (D-day on the day, D+3 after).
    static func boardCorner(_ now: Date, _ dday: String) -> [String] {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.month, .day, .weekday], from: now)
        let date = "\(parts.month!)/\(parts.day!) " + String(Array("일월화수목금토")[parts.weekday! - 1])
        let fields = dday.components(separatedBy: "|")
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard fields.count == 2, let target = f.date(from: fields[1]) else { return [date] }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
        return [date, fields[0] + " " + (days == 0 ? "D-day" : days > 0 ? "D-\(days)" : "D+\(-days)")]
    }

    /// "기말 12/23", "수능 2026-11-19" or a bare date into "name|yyyy-MM-dd"; "" clears it, nil if unreadable.
    /// A month and day without a year mean the next time it comes round.
    static func parseDday(_ raw: String, today: Date) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return "" }
        guard let m = try? NSRegularExpression(pattern: "^(.*?)\\s*(?:(\\d{4})[-./])?(\\d{1,2})[-./](\\d{1,2})\\s*$").firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { String(text[$0]) } }
        let calendar = Calendar.current
        let thisYear = calendar.component(.year, from: today)
        guard let month = Int(group(3) ?? ""), let day = Int(group(4) ?? ""), (1...12).contains(month) else { return nil }
        var year = group(2).flatMap(Int.init) ?? thisYear
        guard let days = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month))!), days.contains(day) else { return nil }
        if group(2) == nil, calendar.date(from: DateComponents(year: year, month: month, day: day))! < calendar.startOfDay(for: today) { year += 1 }
        var name = (group(1) ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "|", with: " ")
        if name.isEmpty { name = "D-day" } else if name.count > 8 { name = String(name.prefix(8)) }
        return name + "|" + String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Whose eyes light up as my pet cheers them on: -1 the left seat, 1 the right, 0 nobody.
    static func cheeredSide(_ tick: Double, _ side: Int, _ text: String) -> Int { tick >= 6 && tick <= 16 && !text.contains("일어나") && !text.contains("같이 공부") && !text.contains("업데이트") ? side : 0 }

    /// Seatmate `side` (-1 left, 1 right) packing up and setting off: my pet waves them off from its chair.
    /// A visit or my own arrival comes first; focus mode has no departures to wave at.
    private var sendOffSide: Int {
        if mood != .studying || arrivalTick >= 0 || visitTick >= 0 || outgoingTick >= 0 { return 0 }
        return leavingTicks[0] >= 14 && leavingTicks[0] < 22 ? -1 : leavingTicks[1] >= 14 && leavingTicks[1] < 22 ? 1 : 0
    }
    private var unixSeconds: Int64 { Int64(clock().timeIntervalSince1970.rounded(.down)) }

    private var moment: Int { !focus && mood == .studying && visitTick < 0 && outgoingTick < 0 && arrivalTick < 0 && sendOffSide == 0 && forcedMoment == 0 && moodSeconds * 4 >= lookUntil ? Routine.studyMoment(tick, seed: routineSeed) : 0 }
    private var momentText: String { Routine.line(moment, Routine.momentFrame(tick, seed: routineSeed), laptop: laptop) }

    func subjectChanged() { subjectChangedAt = animationSeconds; wake(); redraw() }
    func nextSeason() {
        let stored = Int(Settings.get("season")) ?? -1
        let season = (0..<4).contains(stored) ? stored : Self.seasonAt(clock())
        remember("season", String((season + 1) % 4)); sceneIndex = nextScene; redraw()
    }
    private var myPose: Sprites.Pose {
        switch mood {
        case .studying:
            if !visitRetort.isEmpty && visitTick >= 10 && visitTick < Travel.leave { return visitSide == 1 ? .lookRight : .lookLeft }
            if forced >= 0 { return Routine.momentPose(forcedMoment, forced) }
            if visitTick >= 6 && visitTick <= 16 && !visitText.contains("일어나") { return .content }
            if animationSeconds - subjectChangedAt < 1.5 { return .bookmark }
            if visitTick >= 0 && visitTick < Travel.arrive { return visitTick < 1 ? (visitSide == 1 ? .glanceRight : .glanceLeft) : visitSide == 1 ? .lookRight : .lookLeft }
            if arrivalTick >= 0 { return Departure.pose(Departure.arrival(arrivalTick)) }
            if sendOffSide != 0 { return sendOffSide < 0 ? (tick / 2 % 2 == 0 ? .sitWaveLeftA : .sitWaveLeftB) : tick / 2 % 2 == 0 ? .sitWaveRightA : .sitWaveRightB }
            if moodSeconds * 4 < lookUntil { return lookSide < 0 ? .lookLeft : .lookRight }
            if moodSeconds < 0.75 && Routine.resting(transitionFrom) { return .recover }
            return focus ? Routine.focusPose(tick, seed: routineSeed) : Routine.studyPose(tick, seed: routineSeed)
        case .dozing: if moodSeconds < 0.75 { return .foldArms }; return Routine.restPose(tick, seed: Self.nameSeed(myName()), restSeconds: moodSeconds, unixSeconds: unixSeconds)
        case .away: return .empty
        case .leaving: return Departure.pose(moodSeconds * 4)
        case .notifying: return tick < 2 ? .stand : tick / 2 % 2 == 0 ? .waveA : .waveB
        }
    }

    /// A seatmate's own moments, keyed by name so each friend keeps to their own rhythm.
    private static func seatSeed(_ seat: Seat) -> Int { nameSeed(seat.name) }
    /// Also picks a desk's bag and sticker, so a friend's screen shows mine the same.
    private static func nameSeed(_ name: String) -> Int { 1 + name.utf16.reduce(0) { $0 + Int($1) } % 211 }

    private func seatMoment(_ seat: Seat) -> Int { !focus && seat.here && !seat.dozing ? Routine.studyMoment(frameCount, seed: Self.seatSeed(seat)) : 0 }

    // Each seatmate works and dozes at their own pace, so no two pets move in lockstep.
    private func seatPose(_ seat: Seat, _ i: Int) -> Sprites.Pose {
        if !seat.here { return .empty }
        if arrivingTicks[i] >= 0 { return Departure.pose(Departure.arrival(arrivingTicks[i])) }
        let seed = Self.seatSeed(seat)
        if seat.dozing { return Routine.restPose(frameCount + seed, seed: seed, restSeconds: restSeconds(i), unixSeconds: unixSeconds) }
        return focus ? Routine.focusPose(frameCount, seed: seed) : Routine.studyPose(frameCount, seed: seed)
    }
    private func restSeconds(_ i: Int) -> Double { restSince[i] < 0 ? 0 : animationSeconds - restSince[i] }

    /// Draws one frame into the current (flipped) graphics context.
    func paint() {
        if let board = board() { drawRoom(board.title, board.lines) } else { windowGlass = .zero }

        let seats = [seatmate(), rightSeatmate()]
        visitorHit = .zero; newsHit = .zero
        let visiting = visitTick >= 0
        let outgoing = outgoingTick >= 0
        let start = visitSide == 1 ? rightX : visitSide == -1 ? seatX : -deskWidth / 2
        let arrived = myX + (visitSide == 1 ? 1 : -1) * (FriendInteractions.touch(visitText) == 2 ? 18 : 25) * scale // a hug stands right up close
        // A cheer from the desk right beside mine comes on a folded note; the friend stays in their seat.
        let passingIn = visiting && visitSide != 0 && FriendInteractions.passesNote(visitText) && seats[visitSide < 0 ? 0 : 1].map { $0.here && !$0.dozing } == true
        let visitorX = passingIn ? (visitSide < 0 ? seatX : rightX) : start + (arrived - start) * CGFloat(Travel.progress(visitTick))
        let walking = Travel.walking(visitTick)
        let cheering = visiting && !visitText.contains("일어나") && !visitText.contains("같이 공부") && !FriendInteractions.isPat(visitText)
        let pat = visiting && FriendInteractions.isPat(visitText)
        let tapping = visiting && !cheering && !walking && !outgoing && (mood == .studying || mood == .dozing) && (!pat || (visitTick >= 6 && visitTick <= 16))
        let tap = tapping && frameCount % 2 == 0
        let cheeredSide = Self.cheeredSide(outgoingTick, outgoingSide, outgoingText)
        let targetSeat = cheeredSide == 0 ? nil : seats[cheeredSide < 0 ? 0 : 1]
        let patting = FriendInteractions.isPat(outgoingText) && targetSeat?.here == true && targetSeat?.dozing == false
        let retorting = visiting && !visitRetort.isEmpty && visitTick >= 10 && visitTick < 22 && mood == .studying
        let answeringSeat = outgoingSide == 0 ? nil : seats[outgoingSide < 0 ? 0 : 1]
        let sentRetort = outgoing && !outgoingRetort.isEmpty && outgoingTick >= 10 && outgoingTick < 22 && (outgoingSide == 0 || (answeringSeat?.here == true && answeringSeat?.dozing == false))
        func hop(_ travel: Double, fromSeat: Bool) -> CGFloat { (Travel.walking(travel) ? CGFloat(abs(sin(travel * .pi))) * scale : 0) - (fromSeat ? CGFloat(Travel.seated(travel)) * 4 * scale : 0) }
        if visiting && !passingIn { drawVisitor(visitLook, pose: walking ? .walk : cheering && !FriendInteractions.noFlames(visitText) ? .cheer : tapping ? .reach : .wave, x: visitorX,
                                 hop: hop(visitTick, fromSeat: visitSide != 0), mirror: (visitSide == 1) != (visitTick > Travel.leave), carried: visitTick < Travel.arrive || visitTick > Travel.leave || FriendInteractions.wakeLevel(visitText) >= 2 ? FriendInteractions.carriedArt(visitText, back: visitTick > Travel.leave) : "", held: !walking && FriendInteractions.wakeLevel(visitText) >= 2) }
        let beside = (FriendInteractions.touch(outgoingText) == 2 ? 18 : 25) * scale
        let destination = outgoingSide < 0 ? seatX + beside : outgoingSide > 0 ? rightX - beside : canvasSize.width - deskWidth / 2
        let passingOut = outgoing && outgoingSide != 0 && mood == .studying && FriendInteractions.passesNote(outgoingText) && seats[outgoingSide < 0 ? 0 : 1]?.here == true
        let outX = passingOut ? myX : myX + (destination - myX) * CGFloat(Travel.progress(outgoingTick))
        // Wave with the far hand: the near one would be behind the friend I'm visiting.
        if outgoing && !passingOut { drawVisitor(look, pose: Travel.walking(outgoingTick) ? .walk : patting ? .reach : outgoingText.contains("일어나") || outgoingText.contains("같이 공부") || FriendInteractions.noFlames(outgoingText) ? .wave : .cheer, x: outX,
                                 hop: hop(outgoingTick, fromSeat: true), mirror: (destination < myX) != (outgoingTick > Travel.leave), leftHand: true, carried: outgoingTick < Travel.arrive || outgoingTick > Travel.leave || FriendInteractions.wakeLevel(outgoingText) >= 2 ? FriendInteractions.carriedArt(outgoingText, back: outgoingTick > Travel.leave) : "", held: !Travel.walking(outgoingTick) && FriendInteractions.wakeLevel(outgoingText) >= 2) }
        for i in 0..<2 {
            if let departing = seats[i], !departing.here && leavingTicks[i] >= 0 { drawDepartureWalker((departingSeats[i] ?? departing).look, origin: i == 0 ? seatX : rightX, tick: leavingTicks[i]) }
            if let coming = seats[i], coming.here && arrivingTicks[i] >= 0 && !(visiting && visitSide == (i == 0 ? -1 : 1)) { drawDepartureWalker(coming.look, origin: i == 0 ? seatX : rightX, tick: Departure.arrival(arrivingTicks[i])) }
        }
        if mood == .leaving { drawDepartureWalker(departureLook ?? look, origin: myX, tick: moodSeconds * 4) }
        else if arrivalTick >= 0 { drawDepartureWalker(look, origin: myX, tick: Departure.arrival(arrivalTick)) }
        // All desks and seated pets cover the visitors walking behind them.
        var effects: [(x: CGFloat, moment: Int, phase: Double)] = []
        var lamps: [CGFloat] = []
        for i in 0..<2 {
            guard var seat = seats[i] else { previousSeats[i] = nil; leavingTicks[i] = -1; arrivingTicks[i] = -1; restSince[i] = -1; continue }
            if previousSeats[i]?.id != seat.id {leavingTicks[i] = -1;arrivingTicks[i] = -1;departingSeats[i]=nil}
            if let away = previousSeats[i], away.id == seat.id && !away.here && seat.here && !focus { arrivingTicks[i] = 0 }
            if !seat.here { arrivingTicks[i] = -1 }
            if !seat.here || !seat.dozing { restSince[i] = -1 } else if restSince[i] < 0 { restSince[i] = animationSeconds }
            if restSince[i] < 0 { worried[i] = false }
            else if !worried[i] && restSeconds(i) >= 600 && !focus {
                worried[i] = true
                if mood == .studying && visitTick < 0 && outgoingTick < 0 { lookSide = i == 0 ? -1 : 1; lookUntil = moodSeconds * 4 + 8 }
                worriedAbout(seat.name, Int(restSeconds(i) / 60))
            }
            if let before = previousSeats[i], before.id == seat.id && before.here && !seat.here && !focus { leavingTicks[i] = 0;departingSeats[i]=before }
            if seat.here { leavingTicks[i] = -1 }
            previousSeats[i] = seat
            if leavingTicks[i]>=0,let snapshot=departingSeats[i] {let note=seat.note;seat=snapshot;seat.here=false;seat.note=note}
            let gone = visiting && visitSide == (i == 0 ? -1 : 1) && !passingIn
            let cheered = cheeredSide == (i == 0 ? -1 : 1) && seat.here && !seat.dozing
            let pose: Sprites.Pose = gone ? .empty : leavingTicks[i] >= 0 ? Departure.pose(leavingTicks[i])
                : passingIn && visitSide == (i == 0 ? -1 : 1) && visitTick < Travel.leave ? (i == 0 ? .lookRight : .lookLeft) : seatForcedFrame(i) >= 0 && seat.here && !seat.dozing ? Routine.momentPose(seatForced[i].moment, seatForcedFrame(i))
                : animationSeconds - celebratedAt[i] < 2 && seat.here && !seat.dozing && arrivingTicks[i] < 0 ? .cheer
                : cheered ? (sentRetort ? (cheeredSide < 0 ? .lookRight : .lookLeft) : .content) : seatPose(seat, i)
            let arriving = !gone && arrivingTicks[i] >= 0 ? Departure.arrival(arrivingTicks[i]) : -1
            let seatMomentNow = !gone && leavingTicks[i] < 0 && arriving < 0 ? seatMoment(seat) : 0
            if seatMomentNow > 0 && seatMomentNow != lastSeatMoment[i] { mimic(i, Routine.momentId(seatMomentNow)) }
            lastSeatMoment[i] = seatMomentNow
            let x = i == 0 ? seatX : rightX
            let lit = seat.here && !seat.dozing && !gone && arriving < 0 && (seat.look.customization?.on("lamp") ?? true)
            if !gone && leavingTicks[i]>=12 && leavingTicks[i]<18 {drawAwaySign(x,lift:CGFloat(Departure.signLift(leavingTicks[i])))}
            if lit { Sprites.drawLampGlow(left: x, top: floorY, scale: scale, lamp: seat.look.customization?.value("lamp") ?? 0, night: night) }
            let seed = Self.seatSeed(seat)
            let seatBlend = blendOf(i).track(pose, animationSeconds * 4)
            Sprites.draw(pose, seat.look, left: x, top: floorY, scale: scale,
                         decor: Sprites.Decor(drink: seat.drink, laptop: seat.laptop, seed: seed, lit: lit, away: !seat.here || arriving >= 0, packed: leavingTicks[i] >= 4 || arriving >= 4, minutes: seat.here ? seat.minutes : -1, studying: seat.here && !seat.dozing), from: seatBlend.from, blend: seatBlend.blend, breath: Routine.breathing(frameCount, seed: seed), blink: Routine.blinking(frameCount, seed: seed))
            if cheered && outgoingRetort.isEmpty && !FriendInteractions.noFlames(outgoingText) { Sprites.drawFlameEyes(left: x, top: floorY, scale: scale, alt: frameCount % 2 == 0) }
            if !gone && leavingTicks[i] < 0 && arriving < 0 { effects.append((x, seatMoment(seat), Routine.momentPhase(animationSeconds * 4, seed: seed))) }
            drawNameplate(seat.name, deskX: x)
            if arriving >= 0 && arriving < 12 { drawDepartureProps(seat.look, laptop: seat.laptop, x: x, tick: arriving) }
            if !seat.here && !gone { if leavingTicks[i] >= 0 { drawDepartureProps(seat.look, laptop: seat.laptop, x: x, tick: leavingTicks[i]) } else { drawAwaySign(x) } }
            if !seat.here && !gone && seat.note && (leavingTicks[i] < 0 || leavingTicks[i] >= 18) { Sprites.drawArt("PostIt", left: x + 45 * scale, top: floorY + 23 * scale, scale: scale) }
            if lit { lamps.append(x) }
        }
        let myLamp = mood == .studying && (!outgoing || passingOut) && arrivalTick < 0 && (look.customization?.on("lamp") ?? true)
        if myLamp { lamps.append(myX); Sprites.drawLampGlow(left: myX, top: floorY, scale: scale, lamp: look.customization?.value("lamp") ?? 0, night: night) }
        if mood == .leaving && moodSeconds*4>=12 && moodSeconds*4<18 {drawAwaySign(myX,lift:CGFloat(Departure.signLift(moodSeconds*4)))}
        let shownPose: Sprites.Pose = outgoing && !passingOut ? .empty : passingOut && outgoingTick < Travel.leave ? (outgoingSide < 0 ? .lookLeft : .lookRight) : myPose
        let myBlend = blendOf(-1).track(shownPose, animationSeconds * 4)
        Sprites.draw(shownPose, mood == .leaving ? departureLook ?? look : look, left: myX, top: floorY, scale: scale, alert: tapping && !pat, lift: tap && !pat ? 1 : 0,
                     decor: Sprites.Decor(drink: drink, laptop: mood == .leaving && departureLook != nil ? departureLaptop : laptop, seed: Self.nameSeed(myName()), lit: myLamp, away: mood == .away || mood == .leaving || arrivalTick >= 0, packed: (mood == .leaving && moodSeconds >= 1) || (arrivalTick >= 0 && Departure.arrival(arrivalTick) >= 4), minutes: mood == .studying || mood == .dozing ? studyMinutes : -1, growth: propGrowth, books: propBooks, studying: mood == .studying && arrivalTick < 0), from: myBlend.from, blend: myBlend.blend, breath: Routine.breathing(tick), blink: Routine.blinking(tick))
        if cheering && visitTick >= 6 && visitTick <= 16 && mood == .studying && !outgoing && !visitText.contains("업데이트") && visitRetort.isEmpty && !FriendInteractions.noFlames(visitText) { Sprites.drawFlameEyes(left: myX, top: floorY, scale: scale, alt: frameCount % 2 == 0) }
        // The tapping arm goes over my pet, or only a stub of it would show.
        if tapping {
            NSGraphicsContext.saveGraphicsState()
            if visitSide == 1 { let t = NSAffineTransform(); t.translateX(by: visitorX + 58 * scale, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat() }
            Sprites.draw(layers: Sprites.reachLayers(visitLook, down: tap, touch: FriendInteractions.touch(visitText)), visitLook, left: visitSide == 1 ? 0 : visitorX, top: floorY, scale: scale)
            NSGraphicsContext.restoreGraphicsState()
        }
        if patting {
            NSGraphicsContext.saveGraphicsState()
            let fromRight = destination < myX
            if fromRight { let t = NSAffineTransform(); t.translateX(by: outX + 58 * scale, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat() }
            Sprites.draw(layers: Sprites.reachLayers(look, down: frameCount % 2 == 0, touch: FriendInteractions.touch(outgoingText)), look, left: fromRight ? 0 : outX, top: floorY, scale: scale)
            NSGraphicsContext.restoreGraphicsState()
        }
        drawNameplate(myName(), deskX: myX)
        if mood == .leaving { drawDepartureProps(departureLook ?? look, laptop: departureLook == nil ? laptop : departureLaptop, x: myX, tick: moodSeconds * 4) }
        else if arrivalTick >= 0 && Departure.arrival(arrivalTick) < 12 { drawDepartureProps(look, laptop: laptop, x: myX, tick: Departure.arrival(arrivalTick)) }
        else if mood == .away && !outgoing { drawAwaySign(myX) }
        if passingIn { drawPassedNote(visitorX, myX, visitTick) }
        if passingOut { drawPassedNote(myX, outgoingSide < 0 ? seatX : rightX, outgoingTick) }
        // Now and then a cat crosses the floor in front of the desks; not with the background hidden, nor in focus mode.
        if board() != nil && !focus { let cat = Sprites.catAt(clock().timeIntervalSince1970); if !cat.frame.isEmpty { Sprites.drawArt(cat.frame, left: (-17 * scale + CGFloat(cat.across) * (canvasSize.width + 17 * scale)).rounded(), top: floorY + 29 * scale, scale: scale) } }
        // The lamps' light over everything at their desks (but under the speech bubbles).
        for x in lamps { Sprites.drawLampPool(left: x, top: floorY, scale: scale, night: night) }
        effects.append((myX, moment, Routine.momentPhase(moodSeconds * 4, seed: routineSeed)))
        let tip = floorY - 2
        let mid = CGFloat(Sprites.dx + 16) * scale
        let narrow = min(canvasSize.width-2,max(deskWidth+16,deskWidth+deskGap-6))
        var top = tip // the top of the bubbles over my desk, where a note goes
        if visiting || outgoing {
            if retorting { top = drawBubble(visitRetort, cx: myX + mid, tipY: tip, maxWidth: canvasSize.width - 2, fill: .white) }
            else if sentRetort { top = drawBubble(outgoingRetort, cx: (outgoingSide == 0 ? myX : outgoingSide < 0 ? seatX : rightX) + mid, tipY: tip, maxWidth: canvasSize.width - 2, fill: .white) }
            else { top = drawBubble(visiting ? visitText : outgoingText, cx: (visiting ? visitorX : outX) + mid, tipY: tip, maxWidth: canvasSize.width - 2, fill: PetWindow.visitYellow) }
            if visiting { visitorHit = lastBubble.union(NSRect(x: visitorX + CGFloat(Sprites.dx + 4) * scale, y: floorY, width: 24 * scale, height: 36 * scale)) }
            if !updateText.isEmpty { top = drawBubble(updateText, cx: (outgoing ? outX : myX) + mid, tipY: top - 2, maxWidth: canvasSize.width - 2, fill: PetWindow.newsMint) }
        }
        else if !focus {
            let talk = mood == .dozing ? Routine.sleepTalk(tick, seed: Self.nameSeed(myName()), restSeconds: moodSeconds) : ""
            if mood != .away && (arrivalTick < 0 || !updateText.isEmpty) { top = drawBubble(!updateText.isEmpty ? updateText : sendOffSide != 0 ? "잘 가 !" : forced >= 0 ? (forcedLine.isEmpty ? Routine.line(forcedMoment, forced, laptop: laptop) : forcedLine) : !talk.isEmpty ? talk : moment == 0 ? bubbleText() : momentText, cx: myX + mid, tipY: tip, maxWidth: updateText.isEmpty ? narrow : canvasSize.width - 2, fill: .white) }
            for i in 0..<2 {
                if let seat = seats[i] { let talk = seat.here && seat.dozing ? Routine.sleepTalk(frameCount, seed: Self.seatSeed(seat), restSeconds: restSeconds(i)) : ""; drawBubble(leavingTicks[i] >= 0 && leavingTicks[i] < 18 ? "다녀올게요!" : !talk.isEmpty ? talk : seat.text,
                                                    cx: (i == 0 ? seatX : rightX) + (seat.here || leavingTicks[i] >= 0 ? mid : 34 * scale), tipY: tip, maxWidth: narrow, fill: .white) }
            }
            let news = mood != .away ? newsText() : ""
            if news != shownNews { shownNews = news; newsShownAt = animationSeconds }
            // Flashes yellow for its first three seconds, so a glance away doesn't miss it.
            let flash = animationSeconds - newsShownAt < 3 && frameCount / 2 % 2 == 0
            if !news.isEmpty { top = drawBubble(news, cx: myX + mid, tipY: top - 2, maxWidth: canvasSize.width - 2, fill: flash ? PetWindow.visitYellow : PetWindow.newsMint); newsHit = lastBubble }
        }
        noteHit = note.map { drawNote($0, cx: myX + mid, bottom: top - 4) } ?? .zero
        // 구미 and 포비: hearts while one visits the other, and now and then from each other's desk.
        if visitTick >= Travel.arrive && visitTick <= Travel.leave && FriendInteractions.isLove(visitText) { drawHearts(myX, visitTick - Travel.arrive, column: visitSide == 1 ? 44 : 16) }
        if outgoingTick >= Travel.arrive && outgoingTick <= Travel.leave && FriendInteractions.isLove(outgoingText) && outgoingSide != 0 { drawHearts(outgoingSide < 0 ? seatX : rightX, outgoingTick - Travel.arrive, column: outgoingSide < 0 ? 44 : 16) }
        for i in 0..<2 { if !focus, let partner = seats[i], partner.here, FriendInteractions.isCouple(myName(), partner.name) { drawHearts(i == 0 ? seatX : rightX, Double(frameCount % 480)) } }
        for i in 0..<2 where seats[i] != nil && animationSeconds - celebratedAt[i] < 3 { drawSparkles(i == 0 ? seatX : rightX, (animationSeconds - celebratedAt[i]) * 4) }
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
        Sprites.drawBag(actor,left:x+12*scale,top:floorY+22*scale,scale:scale)
        Sprites.drawPackingReach(actor,left:x,top:floorY,scale:scale,targetX:15,targetY:23,leftHand:true)
    }
    private func drawDepartureProps(_ actor: Look, laptop: Bool, x: CGFloat, tick: Double) {
        if tick>=4 && tick<10 {let p=Departure.item(tick,laptop);NSGraphicsContext.saveGraphicsState();NSRect(x:x,y:0,width:deskWidth,height:floorY+20*scale).clip();Sprites.drawPackingItem(actor,laptop:laptop,left:x+CGFloat(p.0)*scale,top:floorY+CGFloat(p.1)*scale,scale:scale,turn:Departure.ease((tick-4)/3));NSGraphicsContext.restoreGraphicsState()}
        if tick<18 {let bag=Departure.bag(tick);Sprites.drawBag(actor,left:x+CGFloat(bag.0)*scale,top:floorY+CGFloat(bag.1)*scale,scale:scale,open:tick>=5 && tick<10);if tick>=2 {let target=Departure.hand(tick,laptop);Sprites.drawPackingReach(actor,left:x,top:floorY,scale:scale,targetX:Int(target.0.rounded()),targetY:Int(target.1.rounded()),leftHand:target.0<28)}}
        if tick>=12 {if tick>=18 {drawAwaySign(x,lift:CGFloat(Departure.signLift(tick)))};if tick<16 {Sprites.drawPackingReach(actor,left:x,top:floorY,scale:scale,targetX:34,targetY:Int((20-Departure.signLift(tick)).rounded()))}}
    }
    private func drawAwaySign(_ x: CGFloat, lift: Double = 0) {
        let height = 18
        let top = floorY + (CGFloat(27 - height) - CGFloat(lift)) * scale
        let antialias = NSGraphicsContext.current?.shouldAntialias ?? true
        NSGraphicsContext.current?.shouldAntialias = false
        let grid = Array(Sprites.art("AwaySign").suffix(height))
        let left = 23 // the middle of the desk to the right of the nameplate
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
        var x = deskX + 28 * scale - 8.5 * small, y = floorY + 7 * scale - 12 * small
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

    /// The folded note: lifted off one desk, over the gap, onto the next, and read there until tick 10.
    private func drawPassedNote(_ fromDesk: CGFloat, _ toDesk: CGFloat, _ tick: Double) {
        if tick < 1 || tick > 10 { return }
        let t = CGFloat(Departure.ease((tick - 1) / 4))
        let x = fromDesk + (toDesk - fromDesk) * t + CGFloat(Sprites.dx + 14) * scale
        Sprites.drawArt("Folded", left: x.rounded(), top: floorY + ((22 - sin(t * .pi) * 6) * scale).rounded(), scale: scale)
    }

    /// Three sparkles rising off a desk over three seconds (phase in ticks).
    private func drawSparkles(_ deskX: CGFloat, _ phase: Double) {
        for i in 0..<3 {
            let t = phase - Double(i * 2)
            if t < 0 || t > 8 { continue }
            Sprites.drawArt("Sparkle", left: deskX + CGFloat(18 + i * 9) * scale, top: floorY + CGFloat(12 - Int((t * 1.2).rounded())) * scale - CGFloat(i % 2 * 3) * scale, scale: scale)
        }
    }

    /// Little hearts rising one after another beside the head.
    private func drawHearts(_ deskX: CGFloat, _ phase: Double, column: Int = 38) {
        let small = scale / 2
        for i in 0..<4 {
            let t = phase - Double(i * 5)
            if t < 0 || t > 10 { continue }
            Sprites.drawHeart(left: deskX + CGFloat(column + i % 2 * 3) * scale + CGFloat(sin(t * 1.2)) * small,
                              top: floorY + 20 * scale - CGFloat(t * 1.8) * scale, scale: small)
        }
    }
    private func drawVisitor(_ actor: Look, pose: Sprites.Visiting, x: CGFloat, hop: CGFloat, mirror: Bool, leftHand: Bool = false, carried: String = "", held: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height).clip()
        if mirror { let t = NSAffineTransform(); t.translateX(by: x + 58 * scale, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat() }
        Sprites.draw(layers: Sprites.visitor(actor, pose, alt: frameCount % 2 == 0, leftHand: leftHand), actor, left: mirror ? 0 : x, top: floorY - hop, scale: scale)
        if !carried.isEmpty { Sprites.drawCarried(actor, art: carried, left: mirror ? 0 : x, top: floorY - hop, scale: scale, held: held, shake: held ? frameCount % 2 : 0) }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Lines (split on "\n") in a rounded box whose tail points down at `cx`. Returns the
    /// box's top, so another bubble can stack above it.
    @discardableResult
    private func drawBubble(_ text: String, cx: CGFloat, tipY: CGFloat, maxWidth: CGFloat, fill: NSColor) -> CGFloat {
        lastBubble = .zero
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
        lastBubble = box
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

    /// A friend's note, bottom at `bottom`: a yellow post-it written in pen, tilted a little, its
    /// corner folded over. Returns where clicking takes it down.
    private func drawNote(_ n: (to: String, body: String, from: String), cx: CGFloat, bottom: CGFloat) -> NSRect {
        let hand = Self.noteFont(24 * textFactor), small = Self.noteFont(20 * textFactor)
        let w = min(canvasSize.width - 12, 210 * textFactor), pad: CGFloat = 14, strip: CGFloat = 10, fold: CGFloat = 16
        let line = ceil(small.ascender - small.descender + small.leading)
        // Lines break between words, and a lone "!" or "?" stays with the word before it.
        var rows: [String] = []
        for word in n.body.split(separator: " ").map(String.init) {
            if let last = rows.last, word.allSatisfy({ $0.isPunctuation }) || textWidth(last + " " + word, hand) <= w - 2 * pad { rows[rows.count - 1] = last + " " + word } else { rows.append(word) }
        }
        let ink = Sprites.color(0x2B3A6E) // ballpoint blue
        let attributes: [NSAttributedString.Key: Any] = [.font: hand, .foregroundColor: ink]
        let text = rows.joined(separator: "\n") as NSString
        let wrap = w - pad - 4 // slack past the rows' own width: a row that just fits must not wrap again inside a word
        let body = ceil(text.boundingRect(with: NSSize(width: wrap, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: attributes).height)
        let h = strip + 6 + line + body + line + 10
        let box = NSRect(x: max(6, min(cx - w / 2, canvasSize.width - 6 - w)), y: bottom - h, width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        let turn = NSAffineTransform(); turn.translateX(by: box.midX, yBy: box.midY); turn.rotate(byDegrees: -3); turn.translateX(by: -w / 2, yBy: -h / 2); turn.concat()
        func paper(_ dx: CGFloat, _ dy: CGFloat) -> NSBezierPath {
            let p = NSBezierPath(); p.move(to: NSPoint(x: dx, y: dy))
            for (x, y) in [(w, 0), (w, h - fold), (w - fold, h), (0, h)] { p.line(to: NSPoint(x: x + dx, y: y + dy)) }
            p.close(); return p
        }
        NSColor(srgbRed: 70 / 255, green: 50 / 255, blue: 0, alpha: 55 / 255).setFill(); paper(3, 4).fill()
        NSGradient(starting: Sprites.color(0xFFF6A8), ending: Sprites.color(0xFFEA7E))?.draw(in: paper(0, 0), angle: 90)
        NSColor(srgbRed: 150 / 255, green: 110 / 255, blue: 0, alpha: 28 / 255).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: strip)).fill()
        let back = NSBezierPath(); back.move(to: NSPoint(x: w, y: h - fold)); back.line(to: NSPoint(x: w - fold, y: h)); back.line(to: NSPoint(x: w - fold, y: h - fold)); back.close()
        Sprites.color(0xE9D05C).setFill(); back.fill()
        let y = strip + 6
        drawLine("To. " + n.to, font: small, color: ink, in: NSRect(x: pad, y: y, width: w - 2 * pad, height: line), align: .left)
        text.draw(in: NSRect(x: pad, y: y + line, width: wrap, height: body + 1), withAttributes: attributes)
        drawLine("From. " + n.from, font: small, color: ink, in: NSRect(x: pad, y: y + line + body, width: w - pad - fold, height: line), align: .right)
        NSGraphicsContext.restoreGraphicsState()
        return box
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
        let face = NSRect(x: x, y: floorY + 29 * scale - labelHeight, width: w, height: labelHeight)
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
        let key = "\(canvasSize)|\(title)|\(lines)|\(sky)|\(season)|\(scene)|\(drift)|\(swing ? 0 : minute)|\(boardFactor)|\(Calendar.current.startOfDay(for: now))|\(Settings.get("dday"))"
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
        var open = windowGlass.insetBy(dx: 2 * scale, dy: 2 * scale)
        if windowFrame == 1 { let arch = windowGlass.height * 0.42; open.origin.y += arch; open.size.height -= arch } // no petals in the arch's corners
        open.clip()
        Sprites.drawParticles(Int(windowGlass.width / scale), Int(windowGlass.height / scale), sky: sky, season: scene == Sprites.christmasScene ? 3 : season, t: animationSeconds, left: windowGlass.minX, top: windowGlass.minY, scale: scale)
        let passing = skyNow(clock())
        Sprites.drawWeather(Int(windowGlass.width / scale), Int(windowGlass.height / scale), weather: passing.weather, kind: passing.kind, phase: passing.phase, t: animationSeconds, left: windowGlass.minX, top: windowGlass.minY, scale: scale, frame: windowFrame)
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
        (themed("wall") ?? PetWindow.wall).setFill()
        cardPath.fill()
        NSGraphicsContext.saveGraphicsState()
        cardPath.addClip()
        // Wainscoting under a lit rail, its panels marked off every twelve pixels.
        let railTop = floorY + 20 * scale
        (themed("wainscot") ?? PetWindow.wainscot).setFill()
        NSRect(x: card.minX, y: railTop, width: card.width, height: card.height).fill()
        (themed("rail") ?? PetWindow.wainscotRail).setFill()
        NSRect(x: card.minX, y: railTop, width: card.width, height: scale).fill()
        (themed("shade") ?? PetWindow.wainscotShade).setFill()
        NSRect(x: card.minX, y: railTop + scale, width: card.width, height: scale).fill()
        var panel = card.minX + 6 * scale
        while panel < card.maxX { NSRect(x: panel, y: railTop + 2 * scale, width: max(1, scale / 2), height: 13 * scale).fill(); panel += 12 * scale }
        let floorTop = floorY + 35 * scale
        Customization.drawFloor(NSRect(x:card.minX,y:floorTop,width:card.width,height:card.maxY-floorTop),scale,look.customization?.on("floor") == true,fill:themed("floor"),seam:themed("seam"))
        // The room's lights go down at night so the desk lamps show; the window and garland stay bright.
        if sky == 0 { NSColor(srgbRed: 24.0 / 255, green: 28.0 / 255, blue: 58.0 / 255, alpha: 96.0 / 255).setFill(); card.fill(using: .sourceOver) }
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
        (themed("wood") ?? PetWindow.wood).setFill()
        frame.fill()
        (themed("woodLit") ?? PetWindow.woodLit).setFill()
        NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(1, scale / 2)).fill()
        (themed("slate") ?? PetWindow.slate).setFill()
        slate.fill()
        (themed("woodDark") ?? PetWindow.woodDark).setFill()
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
        // The corner: today's date, and under it the D-day kept on this device. Clicks still switch rooms.
        for (n, text) in Self.boardCorner(clock(), Settings.get("dday")).enumerated() {
            drawLine(text, font: .boldSystemFont(ofSize: 11 * boardFactor), color: n == 0 ? faint : Sprites.color(0xF7D774), in: NSRect(x: slate.minX, y: slate.minY + 4 + CGFloat(n) * 14 * boardFactor, width: slate.width - 8, height: 14 * boardFactor), align: .right)
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
        Sprites.drawWindow(Int(glass.width / scale), Int(glass.height / scale), sky: sky, season: season, left: glass.minX, top: glass.minY, scale: scale, scene: scene, drift: drift, frame: windowFrame)
        if let c = look.customization { c.drawRoom(look, glass, clock(), preview: false, pixel: scale) }
    }
    private func seasonNow(_ now: Date) -> Int {
        let stored = Int(Settings.get("season")) ?? -1
        return (0..<4).contains(stored) ? stored : Self.seasonAt(now)
    }

    private var sceneIndex = Int.random(in: 0..<Sprites.windowScenes)
    private var nextScene: Int { (sceneIndex + Int.random(in: 1..<Sprites.windowScenes)) % Sprites.windowScenes }
    private var sceneBucket = -1
    /// The classroom theme's colour for `part`, nil in the usual classroom.
    private func themed(_ part: String) -> NSColor? { look.customization?.themeColor(part) }
    private var windowScene: Int {
        let bucket = Int(clock().timeIntervalSince1970 / 1800)
        if sceneBucket != bucket { sceneBucket = bucket; sceneIndex = nextScene }
        return sceneIndex
    }
    private var windowFrame: Int { (windowScene + Int(clock().timeIntervalSince1970 / 1800)) % Sprites.windowFrames }
    func nextWindowScene() { sceneIndex = nextScene; redraw() }

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
        if noteHit.contains(p) {
            note = nil
            if mood == .away && visitTick < 0 && outgoingTick < 0 { fading = true } // nothing else kept the empty desk up
            wake(); redraw()
            return
        }
        if visitTick >= 0 && visitorHit.contains(p) { visitorClicked(); return }
        if newsHit.contains(p) { newsClicked(); return }
        if hitBoard(p) { boardClicked(); return }
        if p.y >= floorY - 8 {
            let side = seatUnder(p)
            if side < 0 { seatmateClicked(); return }
            if side > 0 { rightSeatmateClicked(); return }
            if hitSeat(p, x: myX, actor: look, pose: myPose, drink: drink, laptop: laptop) { if mood == .away { awayClicked() } else { petClicked() }; return }
        }
        // A shooting star gets a wish instead of the next season.
        if windowGlass.contains(p) { if skyNow(clock()).kind == 5 { showFeedback("별똥별에 소원 빌었다 ✨\n" + Self.wishes[Int(clock().timeIntervalSince1970 / 3600) % Self.wishes.count]) } else { nextSeason() } }
    }

    /// Which seatmate's desk is at p: -1 left, 1 right, 0 neither.
    func seatUnder(_ p: NSPoint) -> Int {
        if p.y < floorY - 8 { return 0 }
        if let seat = seatmate(), hitSeat(p, x: seatX, actor: seat.look, pose: seatPose(seat, 0), drink: seat.drink, laptop: seat.laptop) { return -1 }
        if let seat = rightSeatmate(), hitSeat(p, x: rightX, actor: seat.look, pose: seatPose(seat, 1), drink: seat.drink, laptop: seat.laptop) { return 1 }
        return 0
    }

    private func hitSeat(_ p: NSPoint, x: CGFloat, actor: Look, pose: Sprites.Pose, drink: Sprites.Drink, laptop: Bool) -> Bool {
        let px = Int(floor((p.x - x) / scale)), py = Int(floor((p.y - floorY) / scale))
        if px >= 1 && px < 17 && py >= 23 && py < 29 { return true }
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
        guard let view = contentView else { return }
        let side = seatUnder(view.convert(event.locationInWindow, from: nil))
        if side != 0, let friend = seatMenu(side) { NSMenu.popUpContextMenu(friend, with: event, for: view); return }
        guard let menu = contextMenu else { return }
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
