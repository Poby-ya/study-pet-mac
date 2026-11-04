import AppKit

final class AppearanceWindow: NSWindow {
    private var choices: [NSPopUpButton] = []
    private var locks: [NSButton] = []
    private let preview = NSImageView(frame: NSRect(x: 25, y: 65, width: 430, height: 145))
    private var selected: Look
    private var applied = false

    init(_ look: Look) {
        selected = look
        super.init(contentRect: NSRect(x: 0, y: 0, width: 490, height: 660), styleMask: [.titled], backing: .buffered, defer: false)
        title = "캐릭터 꾸미기"; isReleasedWhenClosed = false
        let labels = ["머리", "머리색", "상의", "상의 색", "하의", "리본 색", "착용", "피부색", "모자", "소매", "주로 쓰는 손", "문구 스티커", "가방", "캐릭터"]
        let values = [
            ["기본 1", "기본 2", "기본 3", "기본 4", "기본 5", "땋은 머리", "투블럭", "웨이브 단발"],
            ["갈색", "검정", "연갈색", "적갈색", "꿀색"],
            ["후드", "니트", "카디건", "줄무늬", "재킷", "하트 니트", "세일러", "멜빵", "배색 칼라"],
            ["파랑", "민트", "분홍", "노랑", "회색", "라벤더", "남색", "베이지", "빨강", "올리브"],
            (1...8).map { "하의 \($0)" }, ["분홍", "빨강", "노랑", "민트", "남색", "흰색"],
            ["없음", "둥근 안경", "별 머리핀", "헤드폰"], ["기본", "피부색 2", "피부색 3", "피부색 4"],
            ["없음", "비니", "베레모"], ["기본", "접은 소매", "긴소매", "손목 밴드"],
            ["오른손", "왼손"], ["없음", "별", "클로버", "귤 조각"], ["기본", "복주머니", "메신저백", "에코백"], ["남자", "여자"]
        ]
        let initial = [look.hair, look.hairColor, look.top, look.topColor, look.bottom, look.ribbon, look.accessory, look.skin, look.hat, look.sleeve, look.leftHanded ? 1 : 0, look.sticker, look.bag, look.girl ? 1 : 0]
        let saved = Array(Settings.get("appearanceLocks"))
        for i in values.indices {
            let y = CGFloat(620 - i * 28)
            let label = NSTextField(labelWithString: labels[i]); label.frame = NSRect(x: 18, y: y + 2, width: 115, height: 24)
            let choice = NSPopUpButton(frame: NSRect(x: 140, y: y, width: 220, height: 26))
            choice.addItems(withTitles: values[i]); choice.selectItem(at: initial[i]); choice.target = self; choice.action = #selector(changed)
            let lock = NSButton(checkboxWithTitle: "잠금", target: nil, action: nil); lock.frame = NSRect(x: 375, y: y, width: 90, height: 26)
            lock.state = i < saved.count && saved[i] == "1" ? .on : .off
            choices.append(choice); locks.append(lock); contentView?.addSubview(label); contentView?.addSubview(choice); contentView?.addSubview(lock)
        }
        contentView?.addSubview(preview)
        for (title, x, action) in [("잠금 빼고 랜덤", 20, #selector(roll)), ("적용", 290, #selector(apply)), ("취소", 385, #selector(cancel))] {
            let button = NSButton(title: title, target: self, action: action); button.frame = NSRect(x: CGFloat(x), y: 20, width: title.count > 4 ? 145 : 80, height: 30); contentView?.addSubview(button)
        }
        changed(); center()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    private func read() -> Look {
        let v = choices.map { $0.indexOfSelectedItem }
        return Look(girl: v[13] == 1, v[0], v[1], v[2], v[3], v[4], v[5]).withExtras(v[6...12].map(String.init).joined())
    }
    @objc private func changed() {
        let look = read()
        preview.image = NSImage(size: NSSize(width: 430, height: 145), flipped: true) { _ in
            for (i, pose) in [Sprites.Pose.writeA, .dozeA, .waveA].enumerated() { Sprites.draw(pose, look, left: CGFloat(i * 143), top: 8, scale: 3) }
            return true
        }
    }
    @objc private func roll() { for i in choices.indices where locks[i].state == .off { choices[i].selectItem(at: Int.random(in: 0..<choices[i].numberOfItems)) }; changed() }
    @objc private func apply() {
        do { try Settings.set("appearanceLocks", locks.map { $0.state == .on ? "1" : "0" }.joined()); selected = read(); applied = true; NSApp.stopModal() }
        catch { let alert = NSAlert(); alert.messageText = "설정을 저장하지 못했어요."; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
    @objc private func cancel() { NSApp.stopModal() }
    static func choose(_ look: Look) -> Look? {
        let window = AppearanceWindow(look)
        NSApp.activate(ignoringOtherApps: true); NSApp.runModal(for: window); window.orderOut(nil)
        return window.applied ? window.selected : nil
    }
}
