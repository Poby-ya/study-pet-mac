import Foundation

/// One stretch of actual study. Pausing ends it and resuming starts a new one,
/// so paused time never lands in the totals.
struct Segment {
    let start: Date
    let end: Date
    let subject: String
}

/// sessions.csv (one segment per line) plus the small files beside it, in the same format
/// as the Windows app's Records.cs, so a record file can move between the two.
enum Records {
    /// ~/Library/Application Support/StudyPet; the self-test points it at a scratch folder.
    static var folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("StudyPet")

    private static var sessionsURL: URL { folder.appendingPathComponent("sessions.csv") }
    private static var openURL: URL { folder.appendingPathComponent("open.txt") }
    static var settingsURL: URL { folder.appendingPathComponent("settings.txt") }
    private static var hiddenURL: URL { folder.appendingPathComponent("hidden.txt") }
    static var backupURL: URL { folder.appendingPathComponent("sessions.bak.csv") }

    static let maxSubjectLength = 16

    /// The planner's list: a subject with this month's and all-time minutes.
    struct Rank {
        let subject: String
        let month: Double
        let total: Double
    }

    /// The same text as .NET's "yyyy-MM-ddTHH:mm:sszzz": 2026-11-02T09:00:00+09:00.
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return f
    }()

    private static var files: FileManager { FileManager.default }

    static func load() throws -> [Segment] {
        guard files.fileExists(atPath: sessionsURL.path) else { return [] }
        return lines(try String(contentsOf: sessionsURL, encoding: .utf8)).dropFirst().compactMap(parse)
    }

    static func append(_ segment: Segment) throws {
        guard segment.end > segment.start else { return }
        guard let normalized = parse(format(segment)), normalized.end > normalized.start else { return }
        let existing = try load()
        if existing.contains(where: { $0.subject == normalized.subject && $0.start <= normalized.start && $0.end >= normalized.end }) { return }
        let old = files.fileExists(atPath: sessionsURL.path) ? try String(contentsOf: sessionsURL, encoding: .utf8) : "\u{FEFF}start,end,subject\r\n"
        let separator = old.hasSuffix("\n") ? "" : "\r\n"
        try (old + separator + format(normalized) + "\r\n").write(to: sessionsURL, atomically: true, encoding: .utf8)
    }

    static func commit(_ segment: Segment) throws {
        try saveOpen(start: segment.start, lastSeen: segment.end, subject: segment.subject)
        try append(segment)
        try clearOpen()
    }

    /// Rewritten every minute while studying, so a crash or power cut loses at most a minute.
    static func saveOpen(start: Date, lastSeen: Date, subject: String) throws {
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try format(Segment(start: start, end: lastSeen, subject: subject)).write(to: openURL, atomically: true, encoding: .utf8)
    }

    static func clearOpen() throws {
        if files.fileExists(atPath: openURL.path) { try files.removeItem(at: openURL) }
    }

    /// A leftover open.txt means the last run ended without closing its segment.
    static func recoverOpen() throws {
        guard files.fileExists(atPath: openURL.path) else { return }
        let text = try String(contentsOf: openURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let segment = parse(text) else { throw RoomError("복구 기록을 읽지 못했어요. open.txt를 보존했어요.") }
        try append(segment)
        try files.removeItem(at: openURL)
    }

    /// Commas and quotes would break the CSV, so they become spaces.
    static func cleanSubject(_ raw: String) -> String {
        let spaced = String(raw.map { c -> Character in c == "," || c == "\"" || isControl(c) ? " " : c })
        return cut(spaced.trimmingCharacters(in: .whitespacesAndNewlines), maxSubjectLength)
    }

    static func isControl(_ c: Character) -> Bool { c.unicodeScalars.contains { $0.properties.generalCategory == .control } }

    static func cut(_ s: String, _ length: Int) -> String {
        s.count > length ? String(s.prefix(length)).trimmingCharacters(in: .whitespacesAndNewlines) : s
    }

    /// Subjects with this month's and all-time totals, most studied this month first.
    static func ranking(_ segments: [Segment], hidden: Set<String>, monthStart: Date, count: Int) -> [Rank] {
        var month: [String: Double] = [:]
        var total: [String: Double] = [:]
        for (day, subjects) in daily(segments) {
            for (subject, minutes) in subjects where !hidden.contains(subject) {
                total[subject, default: 0] += minutes
                if day >= monthStart { month[subject, default: 0] += minutes }
            }
        }
        let ranks = total.map { Rank(subject: $0.key, month: month[$0.key] ?? 0, total: $0.value) }
        return Array(ranks.sorted { a, b in
            if a.month != b.month { return a.month > b.month }
            if a.total != b.total { return a.total > b.total }
            return a.subject < b.subject
        }.prefix(count))
    }

    /// "30m", "4h 30m", "20h", "5d 3h", "5d".
    static func short(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m >= 1440 { return m / 60 % 24 == 0 ? "\(m / 1440)d" : "\(m / 1440)d \(m / 60 % 24)h" }
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }

    /// Drops every segment of a subject from sessions.csv. The file as it was is kept as
    /// sessions.bak.csv, in case it was a slip.
    static func deleteSubject(_ subject: String) throws {
        guard files.fileExists(atPath: sessionsURL.path) else { return }
        var all = lines(try String(contentsOf: sessionsURL, encoding: .utf8))
        guard !all.isEmpty else { return }
        let header = all.removeFirst().replacingOccurrences(of: "\u{FEFF}", with: "")
        let kept = all.filter { parse($0)?.subject != subject }
        if files.fileExists(atPath: backupURL.path) { try files.removeItem(at: backupURL) }
        try files.copyItem(at: sessionsURL, to: backupURL)
        try ("\u{FEFF}" + ([header] + kept).joined(separator: "\r\n") + "\r\n").write(to: sessionsURL, atomically: true, encoding: .utf8)
    }

    /// Subjects removed from the planner. Unless deleted too, their study time stays in sessions.csv.
    static func hidden() throws -> Set<String> {
        guard files.fileExists(atPath: hiddenURL.path) else { return [] }
        return Set(lines(try String(contentsOf: hiddenURL, encoding: .utf8)))
    }

    static func hide(_ subject: String) throws {
        var hidden = try hidden()
        if hidden.insert(subject).inserted { try saveHidden(hidden) }
    }

    /// Starting a hidden subject again puts it back on the list.
    static func unhide(_ subject: String) throws {
        var hidden = try hidden()
        if hidden.remove(subject) != nil { try saveHidden(hidden) }
    }

    private static func saveHidden(_ hidden: Set<String>) throws {
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try hidden.map { $0 + "\n" }.joined().write(to: hiddenURL, atomically: true, encoding: .utf8)
    }

    /// Minutes per day (keyed by local midnight) per subject. A segment that runs past
    /// midnight is split between the two days.
    static func daily(_ segments: [Segment]) -> [Date: [String: Double]] {
        let calendar = Calendar.current
        var days: [Date: [String: Double]] = [:]
        for segment in segments {
            var from = segment.start
            while from < segment.end {
                let day = calendar.startOfDay(for: from)
                let to = min(calendar.date(byAdding: .day, value: 1, to: day)!, segment.end)
                days[day, default: [:]][segment.subject, default: 0] += to.timeIntervalSince(from) / 60
                from = to
            }
        }
        return days
    }

    /// Total minutes on days in [from, to).
    static func minutes(_ daily: [Date: [String: Double]], from: Date, to: Date) -> Double {
        daily.filter { $0.key >= from && $0.key < to }.values.reduce(0) { $0 + $1.values.reduce(0, +) }
    }

    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m < 60 { return "\(m)분" }
        return m % 60 == 0 ? "\(m / 60)시간" : "\(m / 60)시간 \(m % 60)분"
    }

    private static func lines(_ text: String) -> [String] { text.split(whereSeparator: \.isNewline).map(String.init) }

    private static func format(_ s: Segment) -> String { stamp.string(from: s.start) + "," + stamp.string(from: s.end) + "," + s.subject }

    private static func parse(_ line: String) -> Segment? {
        let parts = line.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[2].isEmpty,
              let start = stamp.date(from: String(parts[0])), let end = stamp.date(from: String(parts[1])) else { return nil }
        return Segment(start: start, end: end, subject: String(parts[2]))
    }
}

/// settings.txt: one key=value per line. Read once, rewritten whole on every change.
enum Settings {
    private static var values: [String: String] = {
        var values: [String: String] = [:]
        guard let text = try? String(contentsOf: Records.settingsURL, encoding: .utf8) else { return values }
        for line in text.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2 { values[String(pair[0])] = String(pair[1]) }
        }
        return values
    }()

    // Sign-in saves its tokens from a background task.
    private static let lock = NSLock()

    static func get(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return values[key] ?? ""
    }

    /// Throws when the file can't be written; callers decide whether that matters.
    static func set(_ key: String, _ value: String) throws { try setMany((key, value)) }

    static func setMany(_ changes: (String, String)...) throws {
        lock.lock()
        defer { lock.unlock() }
        var next = values
        for (key, value) in changes { next[key] = value }
        try FileManager.default.createDirectory(at: Records.folder, withIntermediateDirectories: true)
        try next.map { $0.key + "=" + $0.value + "\n" }.joined().write(to: Records.settingsURL, atomically: true, encoding: .utf8)
        values = next
    }
}
