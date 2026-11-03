import Foundation

enum StudyCheer {
    static func text(_ seconds: TimeInterval) -> String {
        if seconds >= 1800 && seconds.truncatingRemainder(dividingBy: 1800) < 10 {
            return "\(Int(seconds / 1800) * 30)분 달성!\n차곡차곡 쌓였어요 ♪"
        }
        let phase = seconds.truncatingRemainder(dividingBy: 300)
        if seconds >= 150 && phase >= 150 && phase < 158 {
            let messages = ["할 수 있다!\n한 줄씩, 한 걸음씩 ♪", "집중하는 나, 멋져!\n조금만 더 해볼까?", "오늘의 나에게 박수!\n짝짝짝 ♪", "천천히 해도 괜찮아\n꾸준히 가는 중!"]
            return messages[Int(seconds / 300) % messages.count]
        }
        return ""
    }
}
