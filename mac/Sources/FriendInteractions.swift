import Foundation

final class FriendInteractions {
    static let updateNotice = "업데이트가 새로 나왔대 !"
    static let cheers = ["파이팅 !", "오늘도 힘내 !", "정말 대단해 !", "잘하고 있어 !", "조금만 더 해보자 !", "꾸준한 네가 멋져 !", "오늘도 응원할게 !", "한 걸음씩 가보자 !", "같이 끝까지 가자 !", "지금처럼만 해봐 !", "우리 해낼 수 있어 !", "집중하는 모습 멋져 !"]
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
    func message(_ m: Member, here: Bool, current: String) -> String {
        if let own = UpdateRelease.version(current), let other = UpdateRelease.version(m.version), other.lexicographicallyPrecedes(own) { return Self.updateNotice }
        if !here || m.state == "paused" { return Room.pokeMessage(m, here: here) }
        if let greeting = greetings.removeValue(forKey: m.id) { return greeting }
        var index = Int.random(in: 0..<(Self.cheers.count - 1))
        if let previous = last[m.id], index >= previous { index += 1 }; last[m.id] = index
        return Self.cheers[index]
    }
}
