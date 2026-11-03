import Foundation

enum StudyCheer {
    static func text(_ seconds: TimeInterval) -> String {
        if seconds >= 1800 && seconds.truncatingRemainder(dividingBy: 1800) < 10 {
            return "\(Int(seconds / 1800) * 30)분 달성!\n잘 쌓이고 있어요"
        }
        let phase = seconds.truncatingRemainder(dividingBy: 300)
        if seconds >= 150 && phase >= 150 && phase < 158 {
            let messages = ["한 줄씩\n천천히 가 보자", "집중 잘 되는 중\n조금만 더 해볼까", "벌써 이만큼 했네\n좋아, 계속 가자", "천천히 해도 괜찮아\n꾸준히 가는 중"]
            return messages[Int(seconds / 300) % messages.count]
        }
        return ""
    }
}
