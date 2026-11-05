import AppKit

// Sizes in points: the Windows app's layout at 100 %.
private let scale: CGFloat = 4
private let deskWidth = CGFloat(Sprites.width) * scale
private let boardLine: CGFloat = 24
// Room for the tallest chalkboard; a shorter one leaves the top of the window empty.
private let boardSpace = 48 + CGFloat(Room.boardLines) * boardLine
private let bubbleArea: CGFloat = 112 // room for an update reminder above a visitor's bubble
private let floorY = boardSpace + bubbleArea // top of the desks' grid
let petSize = NSSize(width: 3 * deskWidth + 72, height: floorY + CGFloat(Sprites.height) * scale + 48)

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
    private static let floorWood = Sprites.color(0xD2A26E)
    private static let wood = Sprites.color(0xA8744A)
    private static let slate = Sprites.color(0x2F5D50)
    private static let chalk = Sprites.color(0xEEF2E6)
    private static let plateFace = Sprites.color(0xFFF8E9)
    private static let plateTop = Sprites.color(0xECD9BC)
    private static let plateText = Sprites.color(0x57493C)

    private var timer: Timer?
    private var lastStepSeconds = 0.0, animationSeconds = 0.0, moodSeconds = 0.0
    private var windowGlass = NSRect.zero
    private var updateShownAt = 0.0
    private var feedbackText = ""
    private var feedbackUntil = 0.0
    private var transitionFrom = Sprites.Pose.writeA
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
    private var hair: [Int: (Sprites.Pose, Int, Double)] = [:]
    private func hairLag(_ seat: Int, _ pose: Sprites.Pose) -> Int {
        var old = hair[seat] ?? (pose, 0, 0)
        if old.0 != pose {
            let lag = [Sprites.Pose.stretchLeft, .lookLeft].contains(pose) ? 1 : [Sprites.Pose.stretchRight, .lookRight].contains(pose) ? -1 : [Sprites.Pose.stretchLeft, .lookLeft].contains(old.0) ? -1 : [Sprites.Pose.stretchRight, .lookRight].contains(old.0) ? 1 : 0
            old = (pose, lag, animationSeconds + 0.25); hair[seat] = old
        }
        hair[seat] = old
        return animationSeconds < old.2 ? old.1 : 0
    }
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
        let width = CGFloat(count) * deskWidth + CGFloat(count - 1) * deskGap + 32
        return NSSize(width: max(width, 330 * max(boardFactor,textFactor)), height: floorY + CGFloat(Sprites.height) * scale + 12*scale*nameFactor)
    }
    private var deskGap: CGFloat { max(22,190 * max(1,textFactor) - deskWidth) }
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
    private var night: Bool { let hour = Calendar.current.component(.hour, from: clock()); return hour >= 18 || hour < 6 }
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
        if outgoingTick >= 0 { outgoingTick += seconds * 4; if outgoingTick > 24 { outgoingTick = -1; if mood == .away { fading = true } } }
        if visitTick >= 0 {
            visitTick += seconds * 4
            if visitTick > 24 {
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
        let seatEffects = [seatmate(), rightSeatmate()].contains { seat in seat.map { [3, 6].contains(seatMoment($0)) } ?? false }
        let moving = (visitTick >= 0 && (visitTick < 4 || visitTick > 18)) || (outgoingTick >= 0 && (outgoingTick < 4 || outgoingTick > 18)) || moment == 3 || moment == 6 || seatEffects
        if frameCount != beforeFrame || moving || fading || alphaValue < 1 { redraw() }
    }

    func redraw() { fitDesks(); contentView?.needsDisplay = true }

    static let moments = 12

    /// Every 90 seconds of study a 6-second moment plays: a stretch, a dropped pencil, a
    /// butterfly and so on, 1...moments, or 0 for none. Seatmates get their own `seed`, so
    /// they act at other times and in another order. The same as the Windows app.
    static func studyMoment(_ ticks: Int, seed: Int = 0) -> Int {
        let t = ticks + seed * 97
        return t % 360 >= 336 ? (t / 360 + seed) % moments + 1 : 0
    }

    private static func momentPhase(_ ticks: Double, _ seed: Int) -> Double {
        (ticks + Double(seed * 97)).truncatingRemainder(dividingBy: 360) - 336
    }

    private static func writing(_ ticks: Int, beat: Int = 2) -> Sprites.Pose {
        ticks % 12 >= 8 ? .restHands : ticks % 20 == 19 ? (ticks / beat % 2 == 0 ? .blink : .blinkB) : ticks / beat % 2 == 0 ? .writeA : .writeB
    }

    /// One frame (0...23) of a moment.
    private static let momentFrames: [[Sprites.Pose]] = [
        [.restHands, .restHands, .stretchHalf, .stretchHalf, .stretchUp, .stretchUp, .stretchUp, .stretchLeft, .stretchLeft, .stretchUp, .stretchUp, .stretchRight, .stretchRight, .stretchUp, .stretchUp, .stretchHalf, .stretchHalf, .restHands, .restHands, .content, .content, .content, .content, .content],
        [.oops, .oops, .oops, .bend, .bend, .bend, .pickUp, .pickUp, .pickUp, .pickUp, .pickUp, .recover, .recover, .recover, .found, .found, .found, .content, .content, .content, .writeA, .writeA, .writeA, .writeA],
        [.lookRight, .lookRight, .lookRight, .lookRight, .lookRight, .lookUp, .lookUp, .lookUp, .lookUp, .lookUp, .lookUp, .lookUp, .content, .content, .content, .content, .content, .content, .content, .content, .lookUp, .lookUp, .restHands, .restHands],
        [.teaReach, .teaReach, .teaReach, .teaHold, .teaHold, .teaLift, .teaLift, .teaSip, .teaSip, .teaSip, .teaSip, .teaSip, .teaLift, .teaLift, .teaHold, .teaHold, .teaReach, .teaReach, .content, .content, .content, .content, .content, .content],
        [.readA, .readA, .readA, .readA, .readB, .readB, .readB, .readB, .turnPage, .turnPage, .turnPage, .restHands, .restHands, .restHands, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA],
        [.cheer, .cheer, .cheer, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content, .content],
        [.yawnStart, .yawnStart, .yawnStart, .yawn, .yawn, .yawn, .yawn, .yawn, .yawnEnd, .yawnEnd, .yawnEnd, .restHands, .restHands, .restHands, .restHands, .restHands, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA],
        [.nodA, .nodA, .nodA, .nodA, .nodB, .nodB, .nodB, .nodC, .nodC, .nodC, .startle, .startle, .recover, .recover, .recover, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA],
        [.munchA, .munchA, .munchA, .munchA, .munchB, .munchB, .munchB, .munchB, .cookieSmall, .cookieSmall, .cookieSmall, .cookieSmall, .crumbs, .crumbs, .crumbs, .crumbs, .content, .content, .content, .content, .content, .content, .content, .content],
        [.think, .think, .think, .think, .think, .think, .think, .think, .idea, .idea, .idea, .recover, .recover, .recover, .writeB, .writeB, .writeB, .content, .content, .content, .writeA, .writeA, .writeA, .writeA],
        [.restHands, .restHands, .restHands, .spinA, .spinB, .spinC, .spinD, .restHands, .restHands, .restHands, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA, .writeA],
        [.readA, .readA, .readA, .readA, .readA, .readB, .readB, .readB, .readB, .readB, .readA, .readA, .readA, .readA, .readA, .readB, .readB, .readB, .readB, .readB, .restHands, .restHands, .restHands, .restHands],
    ]

    static func momentPose(_ moment: Int, _ f: Int, _ ticks: Int) -> Sprites.Pose {
        guard moment > 0 && moment <= momentFrames.count && f >= 0 && f < 24 else { return writing(ticks) }
        return momentFrames[moment - 1][f]
    }

    static func momentLine(_ moment: Int, _ f: Int) -> String {
        switch moment {
        case 1: return "으쌰, 기지개 한 번"
        case 2: return f < 14 ? "앗, 연필 떨어졌다" : "찾았다"
        case 3: return "어, 나비다"
        case 4: return "차 한 모금"
        case 5: return "다음 장으로"
        case 6: return "오늘 꽤 했다"
        case 7: return "하암…"
        case 8: return f < 12 ? "꾸벅…" : "앗, 안 졸았어"
        case 9: return "당 충전 중"
        case 10: return f < 12 ? "음… 이게 뭐더라" : "아, 알겠다"
        case 11: return "펜 한 바퀴"
        case 12: return "한 줄씩 읽는 중"
        default: return ""
        }
    }

    private var moment: Int { mood == .studying && visitTick < 0 && outgoingTick < 0 ? Self.studyMoment(tick) : 0 }
    private var momentFrame: Int { tick % 360 - 336 }
    private var momentText: String {
        if laptop && [2,5,10,11,12].contains(moment) { return moment == 2 ? "잠깐 화면 읽기" : [5,12].contains(moment) ? "한 줄 내려보기" : moment == 10 ? "다시 집중!" : "손목 잠깐 쉬기" }; return Self.momentLine(moment, momentFrame)
    }

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
            if visitTick >= 0 && visitTick < 4 { return visitTick < 1 ? (visitSide == 1 ? .glanceRight : .glanceLeft) : visitSide == 1 ? .lookRight : .lookLeft }
            if moodSeconds < 0.75 && [.dozeA, .dozeB].contains(transitionFrom) { return tick == 0 ? .nodB : .recover }
            return moment > 0 ? Self.momentPose(moment, momentFrame, tick) : Self.writing(tick)
        case .dozing: if moodSeconds < 0.75 { return tick == 0 ? .restHands : .foldArms }; return tick / 3 % 2 == 0 ? .dozeA : .dozeB
        case .away: return .empty
        case .leaving: return Self.departurePose(moodSeconds * 4)
        case .notifying: return tick < 2 ? .stand : tick / 2 % 2 == 0 ? .waveA : .waveB
        }
    }

    /// A seatmate's own moments, keyed by name so each friend keeps to their own rhythm.
    private static func seatSeed(_ seat: Seat) -> Int { nameSeed(seat.name) }
    /// Also picks a desk's bag and sticker, so a friend's screen shows mine the same.
    private static func nameSeed(_ name: String) -> Int { 1 + name.utf16.reduce(0) { $0 + Int($1) } % 211 }

    private func seatMoment(_ seat: Seat) -> Int { seat.here && !seat.dozing ? Self.studyMoment(frameCount, seed: Self.seatSeed(seat)) : 0 }

    // Each seatmate writes, blinks and dozes at their own pace, so no two pets move in lockstep.
    private func seatPose(_ seat: Seat) -> Sprites.Pose {
        if !seat.here { return .empty }
        let seed = Self.seatSeed(seat)
        if seat.dozing { return (frameCount + seed) / (3 + seed % 2) % 2 == 0 ? .dozeA : .dozeB }
        let moment = seatMoment(seat)
        if moment > 0 { return Self.momentPose(moment, (frameCount + seed * 97) % 360 - 336, frameCount + 1) }
        return Self.writing(frameCount + seed, beat: 2 + seed % 3)
    }

    /// Draws one frame into the current (flipped) graphics context.
    func paint() {
        windowGlass = .zero
        if let board = board() { drawClassroom(board.title, board.lines) }

        let seats = [seatmate(), rightSeatmate()]
        let visiting = visitTick >= 0
        let outgoing = outgoingTick >= 0
        let start = visitSide == 1 ? rightX : visitSide == -1 ? seatX : -deskWidth / 2
        let arrived = myX + (visitSide == 1 ? 19 : -19) * scale
        let visitorX = start + (arrived - start) * CGFloat(Self.travelProgress(visitTick))
        let walking = visitTick < 4 || visitTick > 18
        let cheering = visiting && !visitText.contains("일어나") && !visitText.contains("같이 공부")
        let tapping = visiting && !cheering && !walking && !outgoing && (mood == .studying || mood == .dozing)
        let tap = tapping && frameCount % 2 == 0
        if visiting { drawVisitor(visitLook, pose: walking ? .walk : cheering ? .cheer : tapping ? .reach : .wave, x: visitorX,
                                 hop: walking ? CGFloat(abs(sin(visitTick * .pi))) * scale : 0, mirror: (visitSide == 1) != (visitTick > 18)) }
        let destination = outgoingSide < 0 ? seatX + deskWidth / 2 : outgoingSide > 0 ? rightX - deskWidth / 2 : canvasSize.width - deskWidth / 2
        let outX = myX + (destination - myX) * CGFloat(Self.travelProgress(outgoingTick))
        // Wave with the far hand: the near one would be behind the friend I'm visiting.
        if outgoing { drawVisitor(look, pose: outgoingTick < 4 || outgoingTick > 18 ? .walk : outgoingText.contains("일어나") || outgoingText.contains("같이 공부") ? .wave : .cheer, x: outX,
                                 hop: outgoingTick < 4 || outgoingTick > 18 ? CGFloat(abs(sin(outgoingTick * .pi))) * scale : 0, mirror: (destination < myX) != (outgoingTick > 18), leftHand: true) }
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
            let pose: Sprites.Pose = gone ? .empty : leavingTicks[i] >= 0 ? Self.departurePose(leavingTicks[i]) : seatPose(seat)
            let x = i == 0 ? seatX : rightX
            let lit = night && seat.here && !seat.dozing && !gone && (seat.look.customization?.on("lamp") ?? true)
            Sprites.draw(pose, seat.look, left: x, top: floorY, scale: scale,
                         decor: Sprites.Decor(drink: seat.drink, laptop: seat.laptop, seed: Self.seatSeed(seat), lit: lit, away: !seat.here, packed: leavingTicks[i] >= 4), hairLag: hairLag(i, pose))
            if !gone && leavingTicks[i] < 0 { effects.append((x, seatMoment(seat), Self.momentPhase(animationSeconds * 4, Self.seatSeed(seat)))) }
            drawNameplate(seat.name, deskX: x)
            if !seat.here && !gone { if leavingTicks[i] >= 0 { drawDepartureProps(seat.look, laptop: seat.laptop, x: x, tick: leavingTicks[i]) } else { drawAwaySign(x) } }
            if lit { lamps.append(x) }
        }
        let myLamp = night && mood == .studying && !outgoing && (look.customization?.on("lamp") ?? true)
        if myLamp { lamps.append(myX) }
        Sprites.draw(outgoing ? .empty : myPose, mood == .leaving ? departureLook ?? look : look, left: myX, top: floorY, scale: scale, alert: tapping, lift: tap ? 1 : 0,
                     decor: Sprites.Decor(drink: drink, laptop: mood == .leaving && departureLook != nil ? departureLaptop : laptop, seed: Self.nameSeed(myName()), lit: myLamp, away: mood == .away || mood == .leaving, packed: mood == .leaving && moodSeconds >= 1), hairLag: hairLag(-1, myPose))
        if cheering && visitTick >= 6 && visitTick <= 16 && mood == .studying && !outgoing && !visitText.contains("업데이트") { Sprites.drawFlameEyes(left: myX, top: floorY, scale: scale, alt: frameCount % 2 == 0) }
        // The tapping arm goes over my pet, or only a stub of it would show.
        if tapping {
            NSGraphicsContext.saveGraphicsState()
            if visitSide == 1 { let t = NSAffineTransform(); t.translateX(by: visitorX + deskWidth, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat() }
            Sprites.draw(layers: Sprites.reachLayers(visitLook, down: tap), visitLook, left: visitSide == 1 ? 0 : visitorX, top: floorY, scale: scale)
            NSGraphicsContext.restoreGraphicsState()
        }
        drawNameplate(myName(), deskX: myX)
        if mood == .leaving { drawDepartureProps(departureLook ?? look, laptop: departureLook == nil ? laptop : departureLaptop, x: myX, tick: moodSeconds * 4) }
        else if mood == .away && !outgoing { drawAwaySign(myX) }
        // The lamps' light over everything at their desks (but under the speech bubbles).
        for x in lamps { Sprites.drawLampLight(left: x, top: floorY, scale: scale) }
        effects.append((myX, moment, Self.momentPhase(moodSeconds * 4, 0)))
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
        for effect in effects {
            if effect.moment == 3 { drawButterfly(effect.x, effect.phase) }
            if effect.moment == 6 { drawHearts(effect.x, effect.phase) }
        }
    }

    static func travelProgress(_ tick: Double) -> Double {
        let t = tick < 0 ? 0 : tick < 4 ? tick / 4 : tick <= 18 ? 1 : max(0, (24 - tick) / 6)
        return t * t * (3 - 2 * t)
    }

    static func departurePose(_ tick: Double) -> Sprites.Pose { Departure.pose(tick) }
    private func drawDepartureWalker(_ actor: Look, origin: CGFloat, tick: Double) {
        guard tick>=18 && tick<26 else {return}
        let x=origin-(origin+deskWidth)*CGFloat(Departure.walk(tick))
        drawVisitor(actor,pose:.walk,x:x,hop:0,mirror:false)
        Sprites.drawBag(actor,left:x+8*scale,top:floorY+22*scale,scale:scale)
        Sprites.drawPackingReach(actor,left:x,top:floorY,scale:scale,targetX:9,targetY:22,leftHand:true)
    }
    private func drawDepartureProps(_ actor: Look, laptop: Bool, x: CGFloat, tick: Double) {
        if tick>=4 && tick<10 {let p=Departure.item(tick);NSGraphicsContext.saveGraphicsState();NSRect(x:x,y:0,width:deskWidth,height:floorY+20*scale).clip();Sprites.drawPackingItem(actor,laptop:laptop,left:x+CGFloat(p.0)*scale,top:floorY+CGFloat(p.1)*scale,scale:scale,turn:Departure.ease((tick-4)/3));NSGraphicsContext.restoreGraphicsState()}
        if tick<18 {let bag=Departure.bag(tick);Sprites.drawBag(actor,left:x+CGFloat(bag.0)*scale,top:floorY+CGFloat(bag.1)*scale,scale:scale,open:tick>=5 && tick<10);if tick>=2 {let target=tick>=4 && tick<10 ? Departure.item(tick) : bag;Sprites.drawPackingReach(actor,left:x,top:floorY,scale:scale,targetX:Int((target.0+1).rounded()),targetY:Int((target.1+1).rounded()),leftHand:tick>=10)}}
        if tick>=12 {drawAwaySign(x,lift:CGFloat(Departure.signLift(tick)));if tick<16 {Sprites.drawPackingReach(actor,left:x,top:floorY,scale:scale,targetX:29,targetY:26)}}
    }
    private func drawAwaySign(_ x: CGFloat, lift: Double = 0) {
        let height = 18
        let top = floorY + (CGFloat(27 - height) - CGFloat(lift)) * scale
        let antialias = NSGraphicsContext.current?.shouldAntialias ?? true
        NSGraphicsContext.current?.shouldAntialias = false
        let grid = Array(Sprites.awaySign.suffix(height))
        let left = Int(((1 + min(20, 15 * nameFactor) + CGFloat(Sprites.width - 22)) / 2).rounded())
        for (y, row) in grid.enumerated() {
            for (col, c) in row.enumerated() where c != "." {
                (c == "k" ? PetWindow.wood : c == "d" ? PetWindow.floorWood : c == "u" ? Sprites.color(0xFFF9E7) : Sprites.color(0xFFF1B8)).setFill()
                NSRect(x: x + CGFloat(left + col) * scale, y: top + CGFloat(y) * scale, width: scale, height: scale).fill()
            }
        }
        NSGraphicsContext.current?.shouldAntialias = antialias
        drawLine("자리 비움", font: .boldSystemFont(ofSize: 3.9 * scale), color: PetWindow.ink,
                 in: NSRect(x: x + CGFloat(left + 1) * scale, y: top + scale, width: 19 * scale, height: 8 * scale))
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
        if mirror { let t = NSAffineTransform(); t.translateX(by: x + deskWidth, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat() }
        Sprites.draw(layers: Sprites.visitor(actor, pose, alt: pose == .walk ? Int(x / (2 * scale)) % 2 == 0 : frameCount % 2 == 0, leftHand: leftHand), actor, left: mirror ? 0 : x, top: floorY - hop, scale: scale)
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

    /// A separate name label below the desk leaves the work surface clear.
    private func drawNameplate(_ name: String, deskX: CGFloat) {
        if name.isEmpty { return }
        let font = NSFont.boldSystemFont(ofSize: 3.4 * scale * nameFactor)
        // Keep enlarged labels outside the sprite and its desk props.
        let maxName: CGFloat = min(36,26 * nameFactor)
        let w = min(maxName * scale, max(8 * scale, textWidth(name, font) + 3 * scale))
        let x = deskX + (CGFloat(Sprites.width)*scale-w)/2
        let labelHeight = max(5 * scale, font.ascender - font.descender + 2)
        let face = NSRect(x: x, y: floorY + 40 * scale, width: w, height: labelHeight)
        PetWindow.plateTop.setFill()
        NSRect(x: x + scale / 2, y: face.minY - scale, width: w - scale, height: scale + 1).fill()
        PetWindow.plateFace.setFill()
        face.fill()
        PetWindow.ink.setStroke()
        NSBezierPath(rect: face).stroke()
        drawLine(name, font: font, color: PetWindow.plateText, in: face)
    }

    /// The classroom behind the desks: a wall with a chalkboard (one line per person, so it
    /// grows), wainscoting and a wooden floor, all on one rounded card.
    private func drawClassroom(_ title: String, _ lines: [String]) {
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
        PetWindow.wainscot.setFill()
        NSRect(x: card.minX, y: floorY + 20 * scale, width: card.width, height: card.height).fill()
        let floorTop = floorY + 35 * scale
        Customization.floor(NSRect(x:card.minX,y:floorTop,width:card.width,height:card.maxY-floorTop),scale,look.customization?.on("floor") == true)
        drawWindow(NSRect(x: card.minX + 14, y: boardSpace + 10, width: card.width - 28, height: floorY + 18 * scale - boardSpace - 10))
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
    private func drawWindow(_ wall: NSRect) {
        let w = Int(wall.width * 0.72 / scale), h = Int(wall.height / scale)
        guard w >= 20, h >= 16 else { return }
        let left = (wall.minX + (wall.width - CGFloat(w) * scale) / 2).rounded(.down)
        windowGlass = NSRect(x: left, y: wall.minY, width: CGFloat(w) * scale, height: CGFloat(h) * scale)
        let stored = Int(Settings.get("season")) ?? -1
        Sprites.drawWindow(w, h, sky: Self.skyAt(clock()), season: (0..<4).contains(stored) ? stored : Self.seasonAt(clock()),
                           left: (wall.minX + (wall.width - CGFloat(w) * scale) / 2).rounded(.down), top: wall.minY, scale: scale, scene: windowScene)
        let date = Calendar.current.dateComponents([.hour, .minute], from: clock())
        if let c=look.customization {c.drawRoom(look,windowGlass,clock(),preview:false);c.drawClock(look,9,wall.minY+12,2,clock())}else{Sprites.drawClock(date.hour ?? 0, date.minute ?? 0, left: 9, top: wall.minY + 12, scale: 2)}
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
