import AppKit

/// Today / this week / this month on top; below, a donut of time per subject for a chosen
/// period, and line charts of the daily and monthly totals, like StatsWindow.cs.
final class StatsWindow: NSWindow {
    let tabs = NSTabView()
    private var daily: [Date: [String: Double]]
    private var until = Date()
    private var periodIndex = 1
    private var live: Timer?
    private var periodStarts: [Date] = []
    private let donut = Donut()

    init(segments: [Segment]) {
        daily = Records.daily(segments)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480), styleMask: [.titled, .closable, .miniaturizable, .resizable],
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

        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 760, height: 480))
        let total = { (from: Date) in Records.duration(Records.minutes(self.daily, from: from, to: self.until)) }
        let summary = NSTextField(labelWithString: "오늘 \(total(today))   ·   이번 주 \(total(week))   ·   이번 달 \(total(month))")
        summary.font = .boldSystemFont(ofSize: 15)
        summary.frame = NSRect(x: 14, y: 10, width: 732, height: 22)
        summary.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(summary)

        tabs.frame = NSRect(x: 8, y: 40, width: 744, height: 432)
        tabs.autoresizingMask = [.width, .height]

        periodStarts = [today, week, month, .distantPast]
        let subjects = FlippedView(frame: NSRect(x: 0, y: 0, width: 720, height: 380))
        let toggles = NSSegmentedControl(labels: ["오늘", "이번 주", "이번 달", "전체"], trackingMode: .selectOne,
                                         target: self, action: #selector(periodChanged(_:)))
        toggles.frame.origin = NSPoint(x: 8, y: 6)
        toggles.selectedSegment = periodIndex // this week
        donut.frame = NSRect(x: 0, y: 40, width: 720, height: 340)
        donut.autoresizingMask = [.width, .height]
        subjects.addSubview(toggles)
        subjects.addSubview(donut)
        tabs.addTabViewItem(page("과목별", subjects))
        showPeriod(periodStarts[periodIndex])

        let days = (0..<30).map { i -> (String, Double) in
            let d = calendar.date(byAdding: .day, value: i - 29, to: today)!
            return (label(d, "M/d"), Records.minutes(daily, from: d, to: calendar.date(byAdding: .day, value: 1, to: d)!))
        }
        tabs.addTabViewItem(page("일별 추이 (최근 30일)", LineChart(points: days, labelPoints: false)))
        let months = (0..<12).map { i -> (String, Double) in
            let m = calendar.date(byAdding: .month, value: i - 11, to: month)!
            return (label(m, "yy.MM"), Records.minutes(daily, from: m, to: calendar.date(byAdding: .month, value: 1, to: m)!))
        }
        tabs.addTabViewItem(page("월별 추이 (최근 12개월)", LineChart(points: months, labelPoints: true)))

        content.addSubview(tabs)
        contentView = content
        if let selected { tabs.selectTabViewItem(withIdentifier: selected) }
    }

    func follow(_ source: @escaping () -> [Segment]) {
        live = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.daily = Records.daily(source()); self.rebuild()
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
        donut.slices = minutes.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
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

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Time per subject as a ring, the total in the hole and a legend on the right.
private final class Donut: NSView {
    // The Windows chart's BrightPastel palette.
    private static let colors = [0x418CF0, 0xFCB441, 0xE0400A, 0x056492, 0xBFBFBF, 0x1A3B69, 0xFFE382, 0x129CDD,
                                 0xCA6B4B, 0x005CDB, 0xF3D288, 0x506381, 0xF1B9A8, 0xE0830A, 0x7893BE].map(Sprites.color)

    var slices: [(String, Double)] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let total = slices.reduce(0) { $0 + $1.1 }
        let area = NSRect(x: 0, y: bounds.height * 0.02, width: bounds.width * 0.58, height: bounds.height * 0.96)
        let radius = min(area.width, area.height) / 2 * 0.92
        let center = NSPoint(x: area.midX, y: area.midY)
        // From three o'clock, clockwise on screen (the view is flipped), like the Windows chart.
        var angle: CGFloat = 0
        for (i, slice) in slices.enumerated() where total > 0 {
            let sweep = CGFloat(slice.1 / total) * 360
            let ring = NSBezierPath()
            ring.appendArc(withCenter: center, radius: radius, startAngle: angle, endAngle: angle + sweep, clockwise: false)
            ring.appendArc(withCenter: center, radius: radius * 0.55, startAngle: angle + sweep, endAngle: angle, clockwise: true)
            ring.close()
            Donut.colors[i % Donut.colors.count].setFill()
            ring.fill()
            angle += sweep
        }
        drawLine(total < 1 ? "기록 없음" : Records.duration(total), font: .boldSystemFont(ofSize: 17), color: .black,
                 in: NSRect(x: center.x - radius, y: center.y - 14, width: 2 * radius, height: 28))

        let rowHeight: CGFloat = 24
        var y = bounds.midY - CGFloat(slices.count) * rowHeight / 2
        let font = NSFont.systemFont(ofSize: 13)
        for (i, slice) in slices.enumerated() {
            Donut.colors[i % Donut.colors.count].setFill()
            NSRect(x: bounds.width * 0.6, y: y + 5, width: 36, height: 14).fill()
            let percent = total > 0 ? Int((slice.1 / total * 100).rounded()) : 0
            drawLine("\(slice.0)  \(Records.duration(slice.1)) (\(percent)%)", font: font, color: .black,
                     in: NSRect(x: bounds.width * 0.6 + 46, y: y, width: bounds.width * 0.4 - 56, height: rowHeight), align: .left)
            y += rowHeight
        }
    }
}

/// Hours per day or month as a line with dots; `labelPoints` writes each value above its dot.
private final class LineChart: NSView {
    private let points: [(String, Double)] // label, minutes
    private let labelPoints: Bool

    init(points: [(String, Double)], labelPoints: Bool) {
        self.points = points
        self.labelPoints = labelPoints
        super.init(frame: NSRect(x: 0, y: 0, width: 720, height: 380))
    }

    func follow(_ source: @escaping () -> [Segment]) {
        live = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.daily = Records.daily(source()); self.rebuild()
        }
        RunLoop.main.add(live!, forMode: .common)
    }
    deinit { live?.invalidate() }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let plot = NSRect(x: 64, y: 24, width: bounds.width - 92, height: bounds.height - 68)
        let hours = points.map { $0.1 / 60 }
        let most = max(hours.max() ?? 0, 1)
        let step = [0.25, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500].first { $0 >= most / 4 } ?? 1000
        let top = (most / step).rounded(.up) * step
        func y(_ value: Double) -> CGFloat { plot.maxY - CGFloat(value / top) * plot.height }
        let font = NSFont.systemFont(ofSize: 12)

        var value = 0.0
        while value <= top + 1e-9 {
            Sprites.color(0xDCDCDC).setStroke()
            line(NSPoint(x: plot.minX, y: y(value)), NSPoint(x: plot.maxX, y: y(value)))
            drawLine(number(value), font: font, color: .black, in: NSRect(x: 0, y: y(value) - 9, width: plot.minX - 8, height: 18), align: .right)
            value += step
        }
        NSColor.black.setStroke()
        line(NSPoint(x: plot.minX, y: plot.minY), NSPoint(x: plot.minX, y: plot.maxY))
        line(NSPoint(x: plot.minX, y: plot.maxY), NSPoint(x: plot.maxX, y: plot.maxY))
        drawLine("시간", font: font, color: .black, in: NSRect(x: 4, y: plot.midY - 9, width: 30, height: 18), align: .left)

        let n = points.count
        let xs = (0..<n).map { plot.minX + (CGFloat($0) + 0.5) * plot.width / CGFloat(n) }
        for i in 0..<n where labelPoints || (n - 1 - i) % 5 == 0 {
            drawLine(points[i].0, font: font, color: .black, in: NSRect(x: xs[i] - 30, y: plot.maxY + 6, width: 60, height: 18))
        }
        let color = Sprites.color(0x5C86DB)
        let path = NSBezierPath()
        path.lineWidth = 3
        path.lineJoinStyle = .round
        for i in 0..<n {
            let p = NSPoint(x: xs[i], y: y(hours[i]))
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        color.setStroke()
        path.stroke()
        color.setFill()
        for i in 0..<n {
            NSBezierPath(ovalIn: NSRect(x: xs[i] - 3.5, y: y(hours[i]) - 3.5, width: 7, height: 7)).fill()
            // A row of zeros is just noise.
            if labelPoints && points[i].1 >= 1 {
                drawLine(number(hours[i]), font: font, color: .black, in: NSRect(x: xs[i] - 30, y: y(hours[i]) - 24, width: 60, height: 18))
            }
        }
    }

    private func line(_ a: NSPoint, _ b: NSPoint) {
        let path = NSBezierPath()
        path.move(to: a)
        path.line(to: b)
        path.lineWidth = 1
        path.stroke()
    }

    /// "0.#": 2, 1.5, 3.8.
    private func number(_ v: Double) -> String {
        let text = String(format: "%.1f", v)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
