import AppKit

/// The record book, in the planner's colours, like StatsWindow.cs: a chalkboard with today, this week,
/// this month and the streak; then time per subject, the last 30 days, the last 12 months, and the
/// recent stretches, where one left running too long can be shortened or removed.
final class StatsWindow: NSWindow {
    static let paper = Sprites.color(0xFFFBF2), card = NSColor.white, cardEdge = Sprites.color(0xEADFCB), ink = Sprites.color(0x3A2E39)
    static let pencil = Sprites.color(0x8A8088), grid = Sprites.color(0xEFE6D6), board = Sprites.color(0x2F5D50), chalk = Sprites.color(0xEEF2E6)
    static let chalkFaint = Sprites.color(0xB9CDBF), woodDark = Sprites.color(0x8B5E3C), today = Sprites.color(0xE2574C), todayColumn = Sprites.color(0xFFF4BF), longRow = Sprites.color(0xFFE1DC)
    /// Longer than this, a stretch was most likely left running.
    static let long: TimeInterval = 4 * 3600

    let tabs = NSTabView()
    private var segments: [Segment]
    private var daily: [Date: [String: Double]]
    private var colors: [String: NSColor] = [:]
    private var until = Date()
    private var periodIndex = 1
    private var live: Timer?
    private var periodStarts: [Date] = []
    private let donut = Donut()
    private let closed: () -> [Segment]
    private let edit: ((Segment, Date?) -> Void)?

    init(segments: [Segment], closed: @escaping () -> [Segment] = { [] }, edit: ((Segment, Date?) -> Void)? = nil) {
        self.segments = segments
        daily = Records.daily(segments)
        self.closed = closed
        self.edit = edit
        super.init(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        rebuild(); center()
    }
    private func rebuild() {
        let selected = tabs.selectedTabViewItem?.identifier as? String
        for tab in tabs.tabViewItems { tabs.removeTabViewItem(tab) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        until = calendar.date(byAdding: .day, value: 1, to: today)!
        let weekday = calendar.component(.weekday, from: today)
        let week = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today)!
        let month = calendar.dateInterval(of: .month, for: today)!.start
        title = "공부 기록"
        isReleasedWhenClosed = false
        backgroundColor = Self.paper
        // The planner's colour for each subject: its place in this month's ranking.
        let ranked = Records.ranking(segments, hidden: [], monthStart: month, count: Int.max).map(\.subject)
        colors = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1, Planner.spines[$0 % Planner.spines.count]) })

        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 780, height: 540))
        let total = { (from: Date) in Records.duration(Records.minutes(self.daily, from: from, to: self.until)) }
        let streak = Records.streak(daily, today: today)
        let header = Board(cells: [("오늘", total(today)), ("이번 주", total(week)), ("이번 달", total(month)), ("연속", streak > 0 ? "\(streak)일째" : "오늘부터 !")])
        header.frame = NSRect(x: 12, y: 10, width: 756, height: 66)
        header.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(header)

        tabs.frame = NSRect(x: 8, y: 84, width: 764, height: 448)
        tabs.autoresizingMask = [.width, .height]

        periodStarts = [today, week, month, .distantPast]
        let subjects = FlippedView(frame: NSRect(x: 0, y: 0, width: 740, height: 400))
        let toggles = NSSegmentedControl(labels: ["오늘", "이번 주", "이번 달", "전체"], trackingMode: .selectOne,
                                         target: self, action: #selector(periodChanged(_:)))
        toggles.frame.origin = NSPoint(x: 8, y: 6)
        toggles.selectedSegment = periodIndex // this week
        donut.frame = NSRect(x: 0, y: 40, width: 740, height: 360)
        donut.autoresizingMask = [.width, .height]
        subjects.addSubview(toggles)
        subjects.addSubview(donut)
        tabs.addTabViewItem(page("과목별", subjects))
        showPeriod(periodStarts[periodIndex])

        let days = (0..<30).map { i -> (String, Double, Bool) in
            let d = calendar.date(byAdding: .day, value: i - 29, to: today)!
            return (calendar.component(.day, from: d) == 1 ? label(d, "M/d") : "\(calendar.component(.day, from: d))", Records.minutes(daily, from: d, to: calendar.date(byAdding: .day, value: 1, to: d)!), d == today)
        }
        tabs.addTabViewItem(page("일별 (30일)", BarChart(points: days, daily: true)))
        let months = (0..<12).map { i -> (String, Double, Bool) in
            let m = calendar.date(byAdding: .month, value: i - 11, to: month)!
            return (calendar.component(.month, from: m) == 1 ? label(m, "yy.M") : "\(calendar.component(.month, from: m))월", Records.minutes(daily, from: m, to: calendar.date(byAdding: .month, value: 1, to: m)!), m == month)
        }
        tabs.addTabViewItem(page("월별 (12개월)", BarChart(points: months, daily: false)))
        tabs.addTabViewItem(page("최근 기록", recentPage()))

        content.addSubview(tabs)
        contentView = content
        if let selected { tabs.selectTabViewItem(withIdentifier: selected) }
    }

    /// The last hundred finished stretches, newest first, each with its own fix buttons.
    private func recentPage() -> NSView {
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 740, height: 400))
        let hint = NSTextField(wrappingLabelWithString: "4시간이 넘는 기록은 분홍색이에요. 공부를 마치고 앱을 그대로 둔 기록이라면 끝 시각을 앞당기거나 지울 수 있어요. 늘리거나 옮길 수는 없고, 지금 공부 중인 기록은 끝난 뒤에 고칠 수 있어요.")
        hint.textColor = Self.pencil; hint.font = .systemFont(ofSize: 12)
        hint.frame = NSRect(x: 8, y: 4, width: 724, height: 34); hint.autoresizingMask = [.width]
        view.addSubview(hint)
        let rows = closed().sorted { $0.start > $1.start }.prefix(100)
        let list = FlippedView(frame: NSRect(x: 0, y: 0, width: 720, height: max(320, CGFloat(rows.count) * 28)))
        let date = DateFormatter(); date.locale = Locale(identifier: "ko_KR"); date.dateFormat = "M/d (E)"
        let time = DateFormatter(); time.dateFormat = "HH:mm"
        let dayTime = DateFormatter(); dayTime.dateFormat = "M/d HH:mm"
        for (i, s) in rows.enumerated() {
            let y = CGFloat(i) * 28
            let long = s.end.timeIntervalSince(s.start) > Self.long
            if long { let band = NSBox(frame: NSRect(x: 0, y: y, width: 720, height: 28)); band.boxType = .custom; band.fillColor = Self.longRow; band.borderWidth = 0; list.addSubview(band) }
            let ends = Calendar.current.isDate(s.start, inSameDayAs: s.end) ? time.string(from: s.end) : dayTime.string(from: s.end)
            for (x, width, text) in [(6.0, 96.0, date.string(from: s.start)), (104, 130, s.subject), (236, 200, "\(time.string(from: s.start)) ~ \(ends)"), (438, 110, Records.duration(s.end.timeIntervalSince(s.start) / 60))] {
                let label = NSTextField(labelWithString: text)
                label.font = long ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
                label.textColor = Self.ink; label.lineBreakMode = .byTruncatingTail
                label.frame = NSRect(x: CGFloat(x), y: y + 5, width: CGFloat(width), height: 18)
                list.addSubview(label)
            }
            guard edit != nil else { continue }
            let shorten = RowButton(title: "앞당기기", target: self, action: #selector(shorten(_:))); shorten.segment = s
            shorten.frame = NSRect(x: 552, y: y + 2, width: 82, height: 24); list.addSubview(shorten)
            let remove = RowButton(title: "지우기", target: self, action: #selector(remove(_:))); remove.segment = s
            remove.frame = NSRect(x: 638, y: y + 2, width: 70, height: 24); list.addSubview(remove)
        }
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 44, width: 724, height: 350))
        scroll.documentView = list; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        view.addSubview(scroll)
        return view
    }

    @objc private func shorten(_ sender: RowButton) {
        guard let s = sender.segment, let edit else { return }
        let latest = s.end.addingTimeInterval(-1)
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        picker.datePickerStyle = .textFieldAndStepper; picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.minDate = min(s.start.addingTimeInterval(60), latest); picker.maxDate = latest; picker.dateValue = latest
        let alert = NSAlert()
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"
        alert.messageText = "\(s.subject) · \(f.string(from: s.start))에 시작한 기록을 언제 끝낸 것으로 할까요?"
        alert.informativeText = "원래 \(f.string(from: s.end))"
        alert.accessoryView = picker
        alert.addButton(withTitle: "앞당기기"); alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        edit(s, picker.dateValue)
        reload()
    }

    @objc private func remove(_ sender: RowButton) {
        guard let s = sender.segment, let edit else { return }
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"
        let alert = NSAlert()
        alert.messageText = "\(f.string(from: s.start))부터 \(Records.duration(s.end.timeIntervalSince(s.start) / 60)) 동안의 \(s.subject) 기록을 지울까요?"
        alert.addButton(withTitle: "지우기"); alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        edit(s, nil)
        reload()
    }

    private var source: (() -> [Segment])?
    private func reload() { if let source { segments = source(); daily = Records.daily(segments) }; rebuild() }

    func follow(_ source: @escaping () -> [Segment]) {
        self.source = source
        live = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            // Rebuilding flickers, so only when a recorded minute has actually changed.
            let next = source()
            if abs(Records.minutes(Records.daily(next), from: .distantPast, to: .distantFuture) - Records.minutes(self.daily, from: .distantPast, to: .distantFuture)) < 1 { return }
            self.segments = next; self.daily = Records.daily(next); self.rebuild()
        }
        RunLoop.main.add(live!, forMode: .common)
    }
    deinit { live?.invalidate() }
    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func periodChanged(_ sender: NSSegmentedControl) { periodIndex = sender.selectedSegment; showPeriod(periodStarts[periodIndex]) }

    private func showPeriod(_ from: Date) {
        var minutes: [String: Double] = [:]
        for (day, subjects) in daily where day >= from && day < until {
            for (subject, m) in subjects { minutes[subject, default: 0] += m }
        }
        donut.caption = ["오늘", "이번 주", "이번 달", "전체"][periodIndex]
        donut.slices = minutes.filter { $0.value >= 0.5 }.sorted { $0.value > $1.value }.map { ($0.key, $0.value, colors[$0.key] ?? Planner.spines[abs($0.key.hashValue) % Planner.spines.count]) }
    }

    private func page(_ title: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    private func label(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }
}

/// A button that remembers which stretch its row is.
final class RowButton: NSButton {
    var segment: Segment?
    convenience init(title: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero); self.title = title; self.target = target; self.action = action; bezelStyle = .rounded; controlSize = .small
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The chalkboard across the top: a label and a big number per cell, on slate in a wooden frame.
private final class Board: NSView {
    private let cells: [(String, String)]
    init(cells: [(String, String)]) { self.cells = cells; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        StatsWindow.woodDark.setFill(); bounds.fill()
        StatsWindow.board.setFill(); bounds.insetBy(dx: 3, dy: 3).fill()
        let cell = bounds.width / CGFloat(cells.count)
        for (i, (name, value)) in cells.enumerated() {
            let x = CGFloat(i) * cell
            drawLine(name, font: .systemFont(ofSize: 12), color: StatsWindow.chalkFaint, in: NSRect(x: x, y: 8, width: cell, height: 18))
            drawLine(value, font: .boldSystemFont(ofSize: 19), color: StatsWindow.chalk, in: NSRect(x: x, y: 28, width: cell, height: 28))
            if i > 0 { Sprites.color(0x4A7568).setFill(); NSRect(x: x, y: 12, width: 1, height: bounds.height - 24).fill() }
        }
    }
}

/// Time per subject as a ring in the planner's colours, the total in the hole and a legend on the right.
private final class Donut: NSView {
    var slices: [(String, Double, NSColor)] = [] { didSet { needsDisplay = true } }
    var caption = ""

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        StatsWindow.card.setFill()
        bounds.fill()
        let total = slices.reduce(0) { $0 + $1.1 }
        let area = NSRect(x: 0, y: bounds.height * 0.02, width: bounds.width * 0.5, height: bounds.height * 0.96)
        let radius = min(area.width, area.height) / 2 * 0.9
        let center = NSPoint(x: area.midX, y: area.midY)
        if total < 0.5 { StatsWindow.grid.setFill(); NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)).fill() }
        // From twelve o'clock, clockwise on screen (the view is flipped), like the Windows chart.
        var angle: CGFloat = -90
        for slice in slices where total > 0 {
            let sweep = CGFloat(slice.1 / total) * 360
            let ring = NSBezierPath()
            ring.appendArc(withCenter: center, radius: radius, startAngle: angle, endAngle: angle + sweep, clockwise: false)
            ring.appendArc(withCenter: center, radius: radius * 0.54, startAngle: angle + sweep, endAngle: angle, clockwise: true)
            ring.close()
            slice.2.setFill()
            ring.fill()
            angle += sweep
        }
        drawLine(total < 0.5 ? "기록 없음" : Records.duration(total), font: .boldSystemFont(ofSize: 19), color: StatsWindow.ink,
                 in: NSRect(x: center.x - radius, y: center.y - 22, width: 2 * radius, height: 28))
        drawLine(caption, font: .systemFont(ofSize: 12), color: StatsWindow.pencil, in: NSRect(x: center.x - radius, y: center.y + 8, width: 2 * radius, height: 18))

        let rowHeight: CGFloat = 28
        var y = max(16, bounds.midY - CGFloat(min(slices.count, 10)) * rowHeight / 2)
        let x = bounds.width * 0.54
        for slice in slices.prefix(10) {
            slice.2.setFill()
            NSRect(x: x, y: y + 7, width: 14, height: 14).fill()
            drawLine(slice.0, font: .boldSystemFont(ofSize: 13), color: StatsWindow.ink, in: NSRect(x: x + 22, y: y + 3, width: 160, height: 22), align: .left)
            let percent = total > 0 ? Int((slice.1 / total * 100).rounded()) : 0
            drawLine("\(Records.duration(slice.1))  \(percent)%", font: .systemFont(ofSize: 12), color: StatsWindow.pencil,
                     in: NSRect(x: x, y: y + 4, width: bounds.width - x - 20, height: 20), align: .right)
            y += rowHeight
        }
        if slices.count > 10 { drawLine("그 밖에 \(slices.count - 10)과목", font: .systemFont(ofSize: 12), color: StatsWindow.pencil, in: NSRect(x: x + 22, y: y + 4, width: 200, height: 20), align: .left) }
    }
}

/// Bars with their value on top and the axis in minutes and hours; today's (or this month's) stands out.
private final class BarChart: NSView {
    private let points: [(String, Double, Bool)] // label, minutes, now
    private let daily: Bool

    init(points: [(String, Double, Bool)], daily: Bool) {
        self.points = points
        self.daily = daily
        super.init(frame: NSRect(x: 0, y: 0, width: 740, height: 400))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        StatsWindow.card.setFill()
        bounds.fill()
        let plot = NSRect(x: 76, y: 34, width: bounds.width - 96, height: bounds.height - 70)
        let most = max(points.map(\.1).max() ?? 0, 30)
        let step = [15.0, 30, 60, 120, 180, 240, 300, 600, 1200, 1800, 3000, 6000].first { most / $0 <= 5 } ?? 12000
        let top = (most / step).rounded(.up) * step
        func y(_ value: Double) -> CGFloat { plot.maxY - CGFloat(value / top) * plot.height }
        let font = NSFont.systemFont(ofSize: 11), bold = NSFont.boldSystemFont(ofSize: 11)

        var value = 0.0
        while value <= top + 1e-9 {
            StatsWindow.grid.setFill()
            NSRect(x: plot.minX, y: y(value), width: plot.width, height: 1).fill()
            drawLine(value == 0 ? "0" : Records.duration(value), font: font, color: StatsWindow.pencil, in: NSRect(x: 0, y: y(value) - 9, width: plot.minX - 8, height: 18), align: .right)
            value += step
        }
        let n = points.count
        let slot = plot.width / CGFloat(n)
        let bar = max(2, slot * 0.66)
        for (i, point) in points.enumerated() {
            let cx = plot.minX + (CGFloat(i) + 0.5) * slot
            if point.2 { StatsWindow.todayColumn.setFill(); NSRect(x: cx - slot / 2, y: plot.minY - 22, width: slot, height: plot.height + 42).fill() }
            if point.1 >= 0.5 {
                (point.2 ? StatsWindow.today : Planner.spines[0]).setFill()
                NSRect(x: cx - bar / 2, y: y(point.1), width: bar, height: plot.maxY - y(point.1)).fill()
                // Every bar gets its value, short enough to fit over a day's narrow bar.
                let m = Int(point.1)
                let text = daily ? (m < 60 ? "\(m)분" : String(format: "%d:%02d", m / 60, m % 60)) : Records.duration(point.1)
                drawLine(text, font: point.2 ? bold : font, color: point.2 ? StatsWindow.today : StatsWindow.ink, in: NSRect(x: cx - slot, y: y(point.1) - 18, width: slot * 2, height: 16))
            }
            if !daily || point.2 || (n - 1 - i) % 5 == 0 {
                drawLine(point.2 ? (daily ? "오늘" : "이번 달") : point.0, font: point.2 ? bold : font, color: point.2 ? StatsWindow.today : StatsWindow.pencil,
                         in: NSRect(x: cx - slot * 2, y: plot.maxY + 4, width: slot * 4, height: 18))
            }
        }
        StatsWindow.pencil.setFill()
        NSRect(x: plot.minX, y: plot.maxY, width: plot.width, height: 1).fill()
    }
}
