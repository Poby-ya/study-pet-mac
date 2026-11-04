import AppKit

private final class AppearanceContent: NSView { override var isFlipped: Bool { true } }
final class AppearanceWindow: NSWindow {
    private var values: [Int]
    private var locks: [Int: NSButton] = [:]
    private let preview = NSImageView(frame: NSRect(x: 20, y: 348, width: 468, height: 126))
    private var selected: Look
    private var applied = false
    private let categories = [(0, "머리"), (1, "머리색"), (2, "상의"), (3, "상의 색"), (4, "하의"), (5, "리본 색"), (8, "모자"), (9, "소매"), (11, "문구 스티커"), (12, "가방 색")]
    init(_ look: Look) {
        selected = look
        values = [look.hair, look.hairColor, look.top, look.topColor, look.bottom, look.ribbon, look.accessory < 2 ? 0 : look.accessory - 1, look.skin, look.hat, look.sleeve, look.leftHanded ? 1 : 0, look.sticker, look.bag, look.girl ? 1 : 0]
        super.init(contentRect: NSRect(x: 0, y: 0, width: 528, height: 570), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        title = "캐릭터 꾸미기"; isReleasedWhenClosed = false; minSize = NSSize(width: 440, height: 400)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 65, width: 528, height: 505)); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autoresizingMask = [.width, .height]
        let body = AppearanceContent(frame: NSRect(x: 0, y: 0, width: 508, height: 505)); scroll.documentView = body; contentView?.addSubview(scroll)
        let toggles = [("캐릭터", 13, ["남자", "여자"]), ("쓰는 손", 10, ["오른손", "왼손"]), ("액세서리", 6, ["없음", "별 머리핀", "헤드폰"]), ("피부색", 7, ["", "", "", ""])]
        for (n, entry) in toggles.enumerated() {
            let (title, index, items) = entry
            let label = NSTextField(labelWithString: title); label.frame = NSRect(x: 20, y: CGFloat(20 + n * 38), width: 80, height: 24); body.addSubview(label)
            let toggle: NSSegmentedControl
            if index == 7 {
                let images = [0xFFF4EC, 0xFFE0C8, 0xD2A17C, 0x83523E].map { color in NSImage(size: NSSize(width: 40,height: 18)) { rect in Sprites.color(color).setFill(); rect.fill(); return true } }
                toggle = NSSegmentedControl(images: images, trackingMode: .selectOne, target: self, action: #selector(toggleChanged(_:)))
            } else { toggle = NSSegmentedControl(labels: items, trackingMode: .selectOne, target: self, action: #selector(toggleChanged(_:))) }
            toggle.tag = index; toggle.selectedSegment = index == 7 ? [1,0,2,3].firstIndex(of: values[index])! : values[index]; toggle.frame = NSRect(x: 105, y: CGFloat(16 + n * 38), width: 380, height: 30); body.addSubview(toggle)
        }
        let hint = NSTextField(labelWithString: "고정할 것을 선택하세요."); hint.frame = NSRect(x: 20, y: 180, width: 480, height: 24); body.addSubview(hint)
        let saved = Array(Settings.get("appearanceLocks"))
        for (n, entry) in categories.enumerated() {
            let (i, title) = entry
            let check = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            check.frame = NSRect(x: CGFloat(20 + (n % 3) * 160), y: CGFloat(216 + (n / 3) * 28), width: 155, height: 26)
            check.state = i < saved.count && saved[i] == "1" ? .on : .off; locks[i] = check; body.addSubview(check)
        }
        body.addSubview(preview)
        for (i,title) in ["필기", "잠깐 쉬기", "손인사"].enumerated() { let caption = NSTextField(labelWithString: title); caption.alignment = .center; caption.frame = NSRect(x: CGFloat(20+i*156),y: 478,width: 156,height: 24); body.addSubview(caption) }

        for (title, x, width, action) in [("랜덤 뽑기", 20, 130, #selector(roll)), ("적용", 330, 80, #selector(apply)), ("취소", 420, 80, #selector(cancel))] {
            let button = NSButton(title: title, target: self, action: action); button.frame = NSRect(x: CGFloat(x), y: 20, width: CGFloat(width), height: 30); contentView?.addSubview(button)
            if title == "적용" { button.keyEquivalent = "\r" }; if title == "취소" { button.keyEquivalent = "\u{1b}" }
        }
        changed(); center()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    private func read() -> Look { Look(girl: values[13] == 1, values[0], values[1], values[2], values[3], values[4], values[5]).withExtras((6...12).map { String($0 == 6 ? [0, 2, 3][values[$0]] : values[$0]) }.joined()) }
    @objc private func toggleChanged(_ sender: NSSegmentedControl) { values[sender.tag] = sender.tag == 7 ? [1,0,2,3][sender.selectedSegment] : sender.selectedSegment; changed() }
    private func changed() {
        let look = read()
        preview.image = NSImage(size: NSSize(width: 468, height: 126), flipped: true) { _ in
            for (i, pose) in [Sprites.Pose.writeA, .dozeA, .waveA].enumerated() { Sprites.draw(pose, look, left: CGFloat(i * 156), top: 6, scale: 3, decor: Sprites.Decor(seed: 7)) }
            return true
        }
    }
    @objc private func roll() {
        let counts = [8, 5, 9, 10, values[13] == 1 ? 8 : 4, 6, 3, 4, 3, 4, 2, 4, 4, 2]
        for (i, _) in categories where locks[i]?.state == .off { values[i] = Int.random(in: 0..<counts[i]) }; changed()
    }
    @objc private func apply() {
        do { try Settings.set("appearanceLocks", (0..<14).map { locks[$0]?.state == .on ? "1" : "0" }.joined()); selected = read(); applied = true; NSApp.stopModal() }
        catch { let alert = NSAlert(); alert.messageText = "설정을 저장하지 못했어요."; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
    @objc private func cancel() { NSApp.stopModal() }
    static func choose(_ look: Look) -> Look? {
        let window = AppearanceWindow(look)
        NSApp.activate(ignoringOtherApps: true); NSApp.runModal(for: window); window.orderOut(nil)
        return window.applied ? window.selected : nil
    }
}
