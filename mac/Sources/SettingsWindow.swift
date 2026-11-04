import AppKit

final class SettingsWindow: NSWindow {
    private let resize: (Int) -> Void
    private var sliders: [NSSlider] = []
    private var values: [NSTextField] = []
    private let keys = ["petSize","boardTextSize","bubbleTextSize","nameTextSize"]
    init(updater: Updater, apply: @escaping () -> Void, login: @escaping () -> Void, resize: @escaping (Int) -> Void) {
        self.resize = resize
        super.init(contentRect: NSRect(x: 0,y: 0,width: 440,height: 300),styleMask: [.titled,.closable],backing: .buffered,defer: false)
        title = "크기 조정 · 공부 친구"; isReleasedWhenClosed = false
        for (i, title) in ["캐릭터","칠판 글자","말풍선","닉네임"].enumerated() {
            let label = NSTextField(labelWithString: title); label.frame = NSRect(x: 20,y: CGFloat(244-i*58),width: 85,height: 24); contentView?.addSubview(label)
            let initial = i == 0 ? max(50,min(150,Int(Settings.get("petSize")) ?? 75)) : DisplayPreferences.percent(keys[i])
            let slider = NSSlider(value: Double(initial), minValue: i == 0 ? 50 : 75, maxValue: i == 0 ? 150 : 200,target: self,action: #selector(changed(_:)))
            slider.tag = i; slider.frame = NSRect(x: 110,y: CGFloat(242-i*58),width: 230,height: 28); slider.isContinuous = true; contentView?.addSubview(slider); sliders.append(slider)
            let value = NSTextField(labelWithString: "\(initial)%"); value.frame = NSRect(x: 355,y: CGFloat(244-i*58),width: 65,height: 24); contentView?.addSubview(value); values.append(value)
        }
        center()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    @objc private func changed(_ sender: NSSlider) {
        let percent = Int((sender.doubleValue / 5).rounded()) * 5
        do { try Settings.set(keys[sender.tag],String(percent)); values[sender.tag].stringValue = "\(percent)%"; resize(Int(Settings.get("petSize")) ?? 75) }
        catch { let alert = NSAlert(); alert.messageText = "크기를 저장하지 못했어요."; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
}
