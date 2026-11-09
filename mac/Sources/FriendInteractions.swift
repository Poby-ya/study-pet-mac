import Foundation

final class FriendInteractions {
    static let updateNotice = "업데이트가 새로 나왔대 !"
    static let cheers = ["파이팅 !", "오늘도 힘내 !", "정말 대단해 !", "잘하고 있어 !", "조금만 더 해보자 !", "꾸준한 네가 멋져 !", "오늘도 응원할게 !", "한 걸음씩 가보자 !", "같이 끝까지 가자 !", "지금처럼만 해봐 !", "우리 해낼 수 있어 !", "집중하는 모습 멋져 !"]
    // Only between 구미 and 포비, whichever of them is sending.
    static func isCouple(_ a: String, _ b: String) -> Bool { a == "포비" && b == "구미" || a == "구미" && b == "포비" }
    private static let love = ["사랑해 !", "많이 사랑해 !", "보고 싶었어 !", "보고 싶어서 왔어 !", "네가 제일 좋아 !", "오늘도 좋아해 !", "내 사랑 파이팅 !", "우리 자기 최고야 !", "자기야 힘내 !", "너밖에 없어 !", "오늘도 귀여워 !", "네가 제일 멋져 !", "오늘도 고마워 !", "곁에 있어서 좋아 !", "네 생각 했어 !", "공부하는 모습 반했어 !", "끝나고 데이트하자 !", "끝나면 맛있는 거 먹자 !", "뽀뽀 쪽 !", "하트 받아 !", "많이 보고 싶어 !", "너 덕에 행복해 !", "네가 있어서 다행이야 !", "네가 내 행복이야 !", "나한테 네가 전부야 !", "자꾸 네 생각나 !", "너랑 있으면 좋아 !", "매일 더 좋아져 !", "너 진짜 좋아 !", "내 마음 알지 ?", "나만 봐줘 !", "내 옆에 있어줘 !", "우리 오래오래 함께하자 !", "손 잡고 싶어 !", "네 목소리 듣고 싶어 !", "네 웃는 얼굴이 좋아 !", "너를 만난 게 행운이야 !", "오늘도 네가 제일 예뻐 !", "밥은 챙겨 먹었어 ?", "무리하지 마, 아프면 안 돼 !", "내가 많이 아껴 !", "우리 자기 고생 많아 !"]
    private static let pats = ["머리 쓰담쓰담", "잘했어 쓰담쓰담", "토닥토닥 고생했어", "어깨 주물주물", "폭 안겼다 !", "꼭 안아줄게 !", "폭 안아줘 !"]
    // What each treat puts on the desk.
    private static let treats: [(line: String, drink: Sprites.Drink)] = [("커피 사 왔어 !", .icedCoffee), ("아이스커피 대령이요 !", .icedCoffee), ("따뜻한 차 한 잔 !", .mug), ("코코아 타 왔어 !", .mug), ("시원한 거 마셔 !", .can)]
    private static let sweet = love + pats
    private static let coupleLines = sweet + treats.map(\.line)
    // Anyone can bring a friend a drink.
    private static let friendLines = cheers + treats.map(\.line)
    /// Hearts instead of flames; the text is all that reaches the other screen.
    static func isLove(_ text: String) -> Bool { text.contains("자기야") || sweet.contains { text.contains($0) } }
    /// A pat on the shoulder rather than a cheer.
    static func isPat(_ text: String) -> Bool { pats.contains { text.contains($0) } }
    /// A cheer gets flames in the eyes; these are gentler.
    static func noFlames(_ text: String) -> Bool { isLove(text) || isTreat(text) }
    /// Where the hand goes: 0 the shoulder, 1 the head, 2 round them in a hug.
    static func touch(_ text: String) -> Int { text.contains("쓰담") ? 1 : text.contains("안겼") || text.contains("안아") ? 2 : 0 }
    static func treatDrink(_ text: String) -> Sprites.Drink { treats.first { text.contains($0.line) }?.drink ?? Sprites.Drink.none }
    static func isTreat(_ text: String) -> Bool { treatDrink(text) != Sprites.Drink.none }
    private static let retorts = ["너도 얼른 공부해 !", "고마워 !\n근데 너는 언제 공부할 거야 ?", "그만 놀고 나랑 공부하자 !", "응원도 고맙지만\n같이 공부하자 !", "너도 얼른 내 옆에 앉아 !"]
    private static let coupleRetorts = ["자기도 얼른 공부해 !", "자기는 언제 공부할 거야 ?", "놀지 말고 옆에 앉아 !", "보고 싶으면 공부하러 와 !"]
    /// What a studying friend says back to someone who cheers them on without studying. Chosen from
    /// the message alone, so both screens show the same words. Wake-ups and invitations get none.
    static func retort(_ message: String, couple: Bool) -> String {
        if message.contains("일어나") || message.contains("같이 공부") || message == updateNotice { return "" }
        if isTreat(message) { return "고마워 ! 너도 공부해 !" }
        let lines = couple ? coupleRetorts : retorts
        return lines[message.utf16.reduce(0) { $0 + Int($1) } % lines.count]
    }
    private var states: [String: String] = [:], greetings: [String: String] = [:]
    private var last: [String: Int] = [:]
    func observe(_ members: [Member]) {
        let latest = Room.latest(members)
        for id in Array(states.keys) where !members.contains(where: { $0.id == id }) { states[id] = "off"; greetings.removeValue(forKey: id) }
        for m in members {
            let state = Room.isHere(m, latest) ? m.state : "off"
            if let before = states[m.id] {
                if before == "off" && state != "off" { greetings[m.id] = "드디어 왔구나 !" }
                else if before == "paused" && state == "studying" { greetings[m.id] = "드디어 깼구나 !" }
            }
            if state == "off" { greetings.removeValue(forKey: m.id) }; states[m.id] = state
        }
    }
    func message(_ m: Member, here: Bool, current: String, me: String = "") -> String {
        if let own = UpdateRelease.version(current) {
            if let other = UpdateRelease.version(m.version) { if other.lexicographicallyPrecedes(own) { return Self.updateNotice } }
            else { return Self.updateNotice }
        }
        let couple = Self.isCouple(me, m.name)
        if couple && !here { return "자기야 같이 공부하자 !" }
        if couple && m.state == "paused" { return "자기야 일어나 !" }
        if !here || m.state == "paused" { return Room.pokeMessage(m, here: here) }
        if let greeting = greetings.removeValue(forKey: m.id) { return greeting }
        let lines = couple ? Self.coupleLines : Self.friendLines
        var index = Int.random(in: 0..<(lines.count - 1))
        if let previous = last[m.id], index >= previous { index += 1 }; last[m.id] = index
        return lines[index]
    }
}
