import Foundation

/// What a pet does with its time, at four ticks a second: mostly working through `work`, with a
/// six-second moment every thirty seconds, and blinking and breathing throughout. Everything is a
/// pure function of the clock, so seatmates (with their own seed) never move in lockstep.
/// The same functions as Sources/Routine.cs and web/moments.js.
enum Routine {
    private static func expand(_ frames: [Any]) -> [Sprites.Pose] {
        var list: [Sprites.Pose] = []
        for i in stride(from: 0, to: frames.count, by: 2) {
            list += Array(repeating: Sprites.Pose(rawValue: frames[i] as! String)!, count: frames[i + 1] as! Int)
        }
        return list
    }
    private static let work = (Customization.root["work"] as! [[Any]]).map(expand)
    private static let momentData = Customization.root["moments"] as! [[String: Any]]
    private static let frames = momentData.map { expand($0["frames"] as! [Any]) }

    static var moments: Int { frames.count }

    /// 1...moments while one is playing, 0 otherwise.
    static func studyMoment(_ ticks: Int, seed: Int = 0) -> Int {
        let t = ticks + seed * 97
        return t % 120 >= 96 ? (t / 120 + seed) % moments + 1 : 0
    }
    static func momentFrame(_ ticks: Int, seed: Int = 0) -> Int { (ticks + seed * 97) % 120 - 96 }
    static func momentPhase(_ ticks: Double, seed: Int = 0) -> Double { (ticks + Double(seed * 97)).truncatingRemainder(dividingBy: 120) - 96 }
    static func effect(_ moment: Int) -> String { momentData[moment - 1]["effect"] as? String ?? "" }

    static func workPose(_ ticks: Int, seed: Int = 0) -> Sprites.Pose { work[(ticks / 48 + seed) % work.count][ticks % 48] }
    static func studyPose(_ ticks: Int, seed: Int = 0) -> Sprites.Pose {
        let moment = studyMoment(ticks, seed: seed)
        return moment > 0 ? frames[moment - 1][momentFrame(ticks, seed: seed)] : workPose(ticks, seed: seed)
    }
    static func momentPose(_ moment: Int, _ frame: Int) -> Sprites.Pose { frames[moment - 1][frame] }

    /// The moment's caption; a number in the list is the frame where the next line takes over.
    static func line(_ moment: Int, _ frame: Int, laptop: Bool) -> String {
        let data = momentData[moment - 1]
        let parts = (laptop ? data["laptopLine"] as? [Any] : nil) ?? data["line"] as! [Any]
        return parts.count == 3 && frame >= parts[1] as! Int ? parts[2] as! String : parts[0] as! String
    }

    /// A blink lasts one tick, somewhere in every five-second stretch; now and then a double one.
    static func blinking(_ ticks: Int, seed: Int = 0) -> Bool {
        let stretch = (ticks + seed) / 20
        let at = (stretch * 37 + seed * 11) % 14
        let into = (ticks + seed) % 20
        return into == at || (stretch % 4 == 0 && into == at + 2)
    }
    /// The head settles a row and rises again every five seconds.
    static func breathing(_ ticks: Int, seed: Int = 0) -> Bool { (ticks + seed * 5) % 20 >= 12 }
}

/// Follows one pet's pose over time, so a change sweeps from the old pose to the new one.
final class PoseBlend {
    private var current = Sprites.Pose.empty, previous = Sprites.Pose.empty
    private var changedAt = 0.0
    private var started = false

    func track(_ pose: Sprites.Pose, _ ticks: Double) -> (from: Sprites.Pose, blend: Double) {
        if !started || ticks < changedAt { started = true; current = pose; previous = pose; changedAt = ticks }
        else if pose != current { previous = current; current = pose; changedAt = ticks }
        if previous == current { return (current, 1) }
        let span = Sprites.blendTicks(current)
        let t = span <= 0 ? 1 : min(1, (ticks - changedAt) / span)
        return (previous, t * t * (3 - 2 * t))
    }

    /// Still on its way, and far enough that it should be drawn more often than every tick.
    func moving(_ ticks: Double) -> Bool { started && previous != current && Sprites.blendTicks(current) > 1 && ticks - changedAt < Sprites.blendTicks(current) }
}
