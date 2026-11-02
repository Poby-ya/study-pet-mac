import AppKit
import ServiceManagement

final class SettingsWindow: NSWindow {
    private let updater: Updater
    private let apply: () -> Void
    private let login: () -> Void
    private let resize: (Int) -> Void
    private let sizeChoice = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let check = NSButton(title: "업데이트 확인", target: nil, action: nil)
    private let install = NSButton(title: "업데이트하고 다시 시작", target: nil, action: nil)

    init(updater: Updater, apply: @escaping () -> Void, login: @escaping () -> Void, resize: @escaping (Int) -> Void = { _ in }) {
        self.updater = updater
        self.apply = apply
        self.login = login
        self.resize = resize
        super.init(contentRect: NSRect(x: 0, y: 0, width: 540, height: 390), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "설정 · 공부 친구"
        isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 24),
                                     stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -24),
                                     stack.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 24)])
        let startup = NSButton(checkboxWithTitle: "로그인할 때 자동 실행", target: self, action: #selector(toggleLogin(_:)))
        startup.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let background = NSButton(checkboxWithTitle: "교실 배경 보이기", target: self, action: #selector(toggleBackground(_:)))
        background.state = Settings.get("background") == "hidden" ? .off : .on
        stack.addArrangedSubview(startup)
        stack.addArrangedSubview(background)
        let sizeLabel = NSTextField(labelWithString: "캐릭터 크기")
        let sizes = [50, 75, 100, 125, 150]
        sizeChoice.addItems(withTitles: sizes.map { "\($0)%" })
        sizeChoice.selectItem(at: sizes.firstIndex(of: Int(Settings.get("petSize")) ?? 75) ?? 1)
        sizeChoice.target = self; sizeChoice.action = #selector(changeSize)
        let sizeRow = NSStackView(views: [sizeLabel, sizeChoice]); sizeRow.spacing = 12
        stack.addArrangedSubview(sizeRow)
        let heading = NSTextField(labelWithString: "업데이트 · 현재 버전 " + Updater.current)
        heading.font = .boldSystemFont(ofSize: 15)
        stack.addArrangedSubview(heading)
        status.preferredMaxLayoutWidth = 490
        stack.addArrangedSubview(status)
        check.target = self; check.action = #selector(checkUpdate)
        install.target = self; install.action = #selector(installUpdate)
        let buttons = NSStackView(views: [check, install])
        buttons.spacing = 12
        stack.addArrangedSubview(buttons)
        let note = NSTextField(wrappingLabelWithString: "새 버전은 앱 시작 시와 매시간 확인해 알려 드려요.\n업데이트할 때 공부 기록을 저장하고 재실행 후 이어갑니다.")
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        updater.changed = { [weak self] in self?.refresh() }
        refresh()
        center()
    }

    private func refresh() {
        status.stringValue = updater.status
        check.isEnabled = !updater.checking && !updater.installing
        install.isEnabled = updater.available && !updater.checking && !updater.installing
    }
    @objc private func changeSize() {
        let percent = [50, 75, 100, 125, 150][sizeChoice.indexOfSelectedItem]
        do { try Settings.set("petSize", String(percent)); resize(percent) }
        catch { let alert = NSAlert(); alert.messageText = "설정을 저장하지 못했어요."; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
    @objc private func checkUpdate() { updater.check() }
    @objc private func installUpdate() { apply() }
    @objc private func toggleLogin(_ sender: NSButton) { login(); sender.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    @objc private func toggleBackground(_ sender: NSButton) {
        do { try Settings.set("background", sender.state == .on ? "" : "hidden") }
        catch { sender.state = sender.state == .on ? .off : .on; let alert = NSAlert(); alert.messageText = "설정을 저장하지 못했어요."; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
}
