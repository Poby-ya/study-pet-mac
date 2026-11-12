import Foundation

final class FriendInteractions {
    static let updateNotice = "업데이트가 새로 나왔대 !"
    /// Calling a friend who isn't studying: one of these at random, not the same twice in a row (picked by the
    /// user, 2026-11-13). Each says 같이 공부, which is how every version tells an invitation from a cheer.
    /// Windows: Calls, web: calls in app.js.
    static let calls = ["같이 공부하자 !", "나랑 같이 공부할래 ?", "쉬엄쉬엄 같이 공부하자 !", "오늘 하루도 같이 공부하자 !", "어디 있어 ? 같이 공부하자 !", "여기 있나~ 같이 공부하자 !", "똑똑 ! 같이 공부할 사람 ~",
                        "그만 놀고 같이 공부하자 !", "노는 거 다 보여 ! 같이 공부하자", "얼른 와 ! 같이 공부하자 !", "놀 만큼 놀았잖아 ! 같이 공부하자", "쉬는 시간 끝 ! 같이 공부하자 !", "딱 30분만 같이 공부하자 !", "자리 맡아 놨어 ! 같이 공부하자"]
    static let cheers = ["파이팅 !", "오늘도 힘내 !", "정말 대단해 !", "잘하고 있어 !", "조금만 더 해보자 !", "꾸준한 네가 멋져 !", "오늘도 응원할게 !", "한 걸음씩 가보자 !", "같이 끝까지 가자 !", "지금처럼만 해봐 !", "우리 해낼 수 있어 !", "집중하는 모습 멋져 !"]
    // Only between 구미 and 포비, whichever of them is sending.
    static func isCouple(_ a: String, _ b: String) -> Bool { a == "포비" && b == "구미" || a == "구미" && b == "포비" }
    private static let love = ["사랑해 !", "많이 사랑해 !", "보고 싶었어 !", "보고 싶어서 왔어 !", "네가 제일 좋아 !", "오늘도 좋아해 !", "내 사랑 파이팅 !", "우리 자기 최고야 !", "자기야 힘내 !", "너밖에 없어 !", "오늘도 귀여워 !", "네가 제일 멋져 !", "오늘도 고마워 !", "곁에 있어서 좋아 !", "네 생각 했어 !", "공부하는 모습 반했어 !", "끝나고 데이트하자 !", "끝나면 맛있는 거 먹자 !", "뽀뽀 쪽 !", "하트 받아 !", "많이 보고 싶어 !", "너 덕에 행복해 !", "네가 있어서 다행이야 !", "네가 내 행복이야 !", "나한테 네가 전부야 !", "자꾸 네 생각나 !", "너랑 있으면 좋아 !", "매일 더 좋아져 !", "너 진짜 좋아 !", "내 마음 알지 ?", "나만 봐줘 !", "내 옆에 있어줘 !", "우리 오래오래 함께하자 !", "손 잡고 싶어 !", "네 목소리 듣고 싶어 !", "네 웃는 얼굴이 좋아 !", "너를 만난 게 행운이야 !", "오늘도 네가 제일 예뻐 !", "밥은 챙겨 먹었어 ?", "무리하지 마, 아프면 안 돼 !", "내가 많이 아껴 !", "우리 자기 고생 많아 !"]
    private static let pats = ["머리 쓰담쓰담", "잘했어 쓰담쓰담", "토닥토닥 고생했어", "어깨 주물주물", "폭 안겼다 !", "꼭 안아줄게 !", "폭 안아줘 !"]
    // What each treat puts on the desk.
    private static let treats: [(line: String, drink: Sprites.Drink)] = [("커피 사 왔어 !", .icedCoffee), ("아이스커피 대령이요 !", .icedCoffee), ("따뜻한 차 한 잔 !", .mug), ("코코아 타 왔어 !", .mug), ("시원한 거 마셔 !", .can)]
    // A snack is carried over and eaten; the desk's drink stays as it is.
    static let snacks = ["쿠키 먹고 해 !", "귤 까 왔어 !", "초콜릿 하나 줄게 !", "사탕 받아 !"]
    private static let snackArts = ["Cookie", "Tangerine", "Chocolate", "Candy"]
    /// Left on an empty desk; read when its owner comes back. Written by hand after noteMark, which old
    /// versions show as it is ("민지 : 쪽지: 내일 봐"); the fixed lines are what v0.7.0 sent, still read as notes.
    static let notes = ["오늘도 수고했어 !", "내일은 같이 하자 !", "먼저 갈게, 파이팅 !", "기다리고 있을게 !", "내일 봐 !"]
    static let noteMark = "쪽지: ", noteArrived = "쪽지가 왔어요 !"
    static let noteLength = 20 - 4 // the room's 20 characters less noteMark
    /// From v0.7.1 (and the web app at that protocol) notes go in their own entries and none is lost; older apps
    /// only read the one poke slot.
    static func keepsNotes(_ version: String) -> Bool {
        let parts = version.split(separator: ".").map { Int($0) }
        guard parts.count == 3, !parts.contains(nil) else { return false }
        return parts.map { $0! }.lexicographicallyPrecedes([0, 7, 1]) == false
    }
    /// What the friend wrote, without noteMark.
    static func noteText(_ message: String) -> String { message.hasPrefix(noteMark) ? String(message.dropFirst(noteMark.count)) : message }
    /// The notes I've received, kept in settings ("notes") so all can be read again: oldest first, the
    /// last 20, each "ms\tfrom\ttext\tread" joined by U+001E (names and texts are cleaned of control characters).
    typealias Received = (at: Int64, from: String, text: String, read: Bool)
    static func inbox(_ stored: String) -> [Received] {
        stored.components(separatedBy: "\u{1E}").compactMap { entry -> Received? in
            let f = entry.components(separatedBy: "\t")
            guard f.count == 4, let at = Int64(f[0]) else { return nil }
            return (at, f[1], f[2], f[3] == "1")
        }
    }
    static func inbox(_ notes: [Received]) -> String { notes.suffix(20).map { "\($0.at)\t\($0.from)\t\($0.text)\t\($0.read ? 1 : 0)" }.joined(separator: "\u{1E}") }
    static let whatStudy = "뭐 공부해 ?"
    static let thanks = "고마워 !"
    static func celebration(_ hours: Int) -> String { "\(hours)시간 달성 축하해 !" }
    /// Waking a friend gets louder each time they don't get up: a tap, an alarm clock, a pot and spoon.
    /// Every one says 일어나, so older versions still take it as a wake-up.
    private static let wakes = ["일어나 !", "일어나 ! 따르릉 !", "일어나 !! 땡땡땡 !"]
    static func wake(_ level: Int, couple: Bool) -> String { (couple ? "자기야 " : "") + wakes[max(1, min(3, level)) - 1] }
    /// 1 a tap, 2 the alarm clock, 3 the pot, read from the words alone.
    static func wakeLevel(_ text: String) -> Int { text.contains("땡땡땡") ? 3 : text.contains("따르릉") ? 2 : text.contains("일어나") ? 1 : 0 }
    static let seatInvite = "내 옆에 앉아 !"
    /// Only the invitation itself, not "너도 얼른 내 옆에 앉아 !" said back to a cheer.
    static func isSeatInvite(_ text: String) -> Bool { text == seatInvite || text.hasSuffix(" : " + seatInvite) || text.contains("에게\n" + seatInvite) }
    static let borrow = "지우개 좀 빌려줘 !", giveBack = "고마워, 잘 썼어 !", handOver = "여기 !"
    static func isBorrow(_ text: String) -> Bool { text.contains(borrow) }
    static func isGiveBack(_ text: String) -> Bool { text.contains(giveBack) }
    /// A cheer for the friend right beside me is passed over on a folded note instead of a walk: every
    /// other cheer, chosen from its words, so both screens agree. Only plain cheers; the rest still walk.
    static func passesNote(_ text: String) -> Bool {
        guard let cheer = cheers.first(where: { text.hasSuffix($0) }) else { return false }
        return cheer.utf16.reduce(0) { sum, unit in sum + Int(unit) } % 2 == 0
    }
    static func snackArt(_ text: String) -> String { snacks.firstIndex { text.contains($0) }.map { snackArts[$0] } ?? "" }
    static func isSnack(_ text: String) -> Bool { !snackArt(text).isEmpty }
    /// As sent, or with "name : " or "name에게\n" in front.
    static func isNote(_ text: String) -> Bool { text.hasPrefix(noteMark) || text.contains(" : " + noteMark) || text.contains("\n" + noteMark) || notes.contains { text.contains($0) } }
    static func isWhatStudy(_ text: String) -> Bool { text.contains(whatStudy) }
    /// Only a plain thank-you, as sent or with "name : " or "name에게\n" in front.
    static func isThanks(_ text: String) -> Bool { text == thanks || text.hasSuffix(" : " + thanks) || text.hasSuffix("\n" + thanks) }
    /// What earns a thank-you: cheers, drinks, snacks, celebrations. Not a wake-up, an invitation, a
    /// note, a question or another thank-you, so the two can't go on thanking each other.
    static func thankable(_ text: String) -> Bool { !text.contains("일어나") && !text.contains("같이 공부") && text != updateNotice && !isThanks(text) && !isNote(text) && !isWhatStudy(text) && !isSeatInvite(text) && !isBorrow(text) && !isGiveBack(text) }
    /// What a visitor holds on the way over (`back`: on the way home): a drink or a snack to give, an
    /// eraser borrowed or brought back, the alarm clock or pot they wake you with (all the way).
    static func carriedArt(_ text: String, back: Bool = false) -> String {
        let wake = wakeLevel(text)
        if wake >= 2 { return wake == 2 ? "AlarmClock" : "Pot" }
        if back { return isBorrow(text) ? "Eraser" : "" }
        return isGiveBack(text) ? "Eraser" : treatDrink(text) != .none ? "Drink\(treatDrink(text).rawValue)" : snackArt(text)
    }
    /// The answer to 뭐 공부해 ?, e.g. "수학 32분째 !": the one asked uses their own subject and minutes,
    /// the one asking the friend's from the room, so both screens say the same.
    static func answer(_ subject: String, _ minutes: Int) -> String {
        (subject.isEmpty ? "공부" : subject) + " " + (minutes < 60 ? "\(minutes)분" : minutes % 60 == 0 ? "\(minutes / 60)시간" : "\(minutes / 60)시간 \(minutes % 60)분") + "째 !"
    }
    private static let sweet = love + pats
    private static let coupleLines = sweet + treats.map(\.line) + snacks
    // Anyone can bring a friend a drink, or now and then a snack.
    private static let friendLines = cheers + treats.map(\.line) + snacks
    /// Hearts instead of flames; the text is all that reaches the other screen.
    static func isLove(_ text: String) -> Bool { text.contains("자기야") || sweet.contains { text.contains($0) } }
    /// A pat on the shoulder rather than a cheer.
    static func isPat(_ text: String) -> Bool { pats.contains { text.contains($0) } }
    /// A cheer gets flames in the eyes; these are gentler.
    static func noFlames(_ text: String) -> Bool { isLove(text) || isTreat(text) || isSnack(text) || isNote(text) || isWhatStudy(text) || isThanks(text) || isSeatInvite(text) || isBorrow(text) || isGiveBack(text) }
    /// Where the hand goes: 0 the shoulder, 1 the head, 2 round them in a hug.
    static func touch(_ text: String) -> Int { text.contains("쓰담") ? 1 : text.contains("안겼") || text.contains("안아") ? 2 : 0 }
    static func treatDrink(_ text: String) -> Sprites.Drink { treats.first { text.contains($0.line) }?.drink ?? Sprites.Drink.none }
    static func isTreat(_ text: String) -> Bool { treatDrink(text) != Sprites.Drink.none }
    private static let retorts = ["너도 얼른 공부해 !", "고마워 !\n근데 너는 언제 공부할 거야 ?", "그만 놀고 나랑 공부하자 !", "응원도 고맙지만\n같이 공부하자 !", "너도 얼른 내 옆에 앉아 !"]
    private static let coupleRetorts = ["자기도 얼른 공부해 !", "자기는 언제 공부할 거야 ?", "놀지 말고 옆에 앉아 !", "보고 싶으면 공부하러 와 !"]
    /// What a studying friend says back to someone who cheers them on without studying. Chosen from
    /// the message alone, so both screens show the same words. Wake-ups and invitations get none.
    static func retort(_ message: String, couple: Bool) -> String {
        if message.contains("일어나") || message.contains("같이 공부") || message == updateNotice || isNote(message) || isWhatStudy(message) || isThanks(message) || isSeatInvite(message) || isGiveBack(message) { return "" }
        if isBorrow(message) { return handOver }
        if isTreat(message) || isSnack(message) { return "고마워 ! 너도 공부해 !" }
        let lines = couple ? coupleRetorts : retorts
        return lines[message.utf16.reduce(0) { $0 + Int($1) } % lines.count]
    }
    private var states: [String: String] = [:], greetings: [String: String] = [:]
    private var last: [String: Int] = [:], minutes: [String: Int] = [:]
    private var wakeLevels: [String: (level: Int, at: Date)] = [:] // how loud my last wake-up for each friend was
    /// Returns the friends who just passed another hour of study: their next cheer from me congratulates them.
    /// Nobody does on the first look at the room, which only sets where everyone is.
    @discardableResult func observe(_ members: [Member]) -> [String] {
        var crossed: [String] = []
        let latest = Room.latest(members)
        for id in Array(states.keys) where !members.contains(where: { $0.id == id }) { states[id] = "off"; greetings.removeValue(forKey: id) }
        for m in members {
            let state = Room.isHere(m, latest) ? m.state : "off"
            if let before = states[m.id] {
                if before == "off" && state != "off" { greetings[m.id] = "드디어 왔구나 !" }
                else if before == "paused" && state == "studying" { greetings[m.id] = "드디어 깼구나 !" }
                if state == "studying", let was = minutes[m.id], m.minutes >= 60, m.minutes / 60 > was / 60 { greetings[m.id] = Self.celebration(m.minutes / 60); crossed.append(m.id) }
            }
            minutes[m.id] = state == "off" ? 0 : m.minutes
            if state != "paused" { wakeLevels.removeValue(forKey: m.id) } // up again: next time starts with a tap
            if state == "off" { greetings.removeValue(forKey: m.id) }; states[m.id] = state
        }
        return crossed
    }
    func message(_ m: Member, here: Bool, current: String, me: String = "") -> String {
        if let own = UpdateRelease.version(current) {
            if let other = UpdateRelease.version(m.version) { if other.lexicographicallyPrecedes(own) { return Self.updateNotice } }
            else { return Self.updateNotice }
        }
        let couple = Self.isCouple(me, m.name)
        if couple && !here { return "자기야 같이 공부하자 !" }
        if here && m.state == "paused" {
            let level = wakeLevels[m.id].map { Date().timeIntervalSince($0.at) < 1800 ? $0.level + 1 : 1 } ?? 1
            wakeLevels[m.id] = (min(3, level), Date())
            return Self.wake(level, couple: couple)
        }
        if !here { return pick(m.id + "\ncall", Self.calls) }
        if let greeting = greetings.removeValue(forKey: m.id) { return greeting }
        return pick(m.id, couple ? Self.coupleLines : Self.friendLines)
    }

    /// One of `lines` at random, not the one last picked under `key`.
    private func pick(_ key: String, _ lines: [String]) -> String {
        var index = Int.random(in: 0..<(lines.count - 1))
        if let previous = last[key], index >= previous { index += 1 }; last[key] = index
        return lines[index]
    }
}
