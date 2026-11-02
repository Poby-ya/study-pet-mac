import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) { controller = AppController() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        guard controller?.prepareQuit() != false else { return .terminateCancel }
        if controller?.beginFarewell() == true {
            terminating = true
            // Termination may run a modal loop; dispatching back to the busy main queue can stall it.
            let farewell = Timer(timeInterval: 3, repeats: false) { _ in sender.reply(toApplicationShouldTerminate: true) }
            RunLoop.main.add(farewell, forMode: .common)
            RunLoop.main.add(farewell, forMode: .modalPanel)
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) { controller?.shutDown() }
}

/// Owns the study state (off / studying / paused), the shortcuts, the menu bar icon and
/// the shared room, and turns them into pet moods, rows in sessions.csv and status
/// updates for friends, the way AppController.cs does on Windows.
final class AppController: NSObject, NSMenuDelegate {
    private enum State { case off, studying, paused }

    private static let pokeCooldown: TimeInterval = 10

    private let pet = PetWindow()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let hotkeys = Hotkeys()
    private var heartbeat: Timer?    // runs while the pet is out: saves the open segment, tells friends we're here
    private var pendingCheck: Timer? // runs while waiting for the owner's approval
    private let localId: String      // my id on the local test server, which has no sign-in
    private var myId = ""            // my member id in the room: the Firebase uid, or localId
    private var auth: Auth?

    private var state = State.off
    private var subject = ""
    private var banked: TimeInterval = 0 // closed segments of the current session
    private var segmentStart: Date?      // set while studying
    private var farewell = ""
    private var lastPokes: [String: Date] = [:]
    private var invitePromptOpen = false
    private var quitting = false
    private var news = ""                // "민지가 공부를 시작했어요 !", in a bubble above mine for a while
    private var newsUntil = Date.distantPast
    private var planner: Planner?
    private var stats: StatsWindow?
    private var help: HelpWindow?
    private var settingsWindow: SettingsWindow?
    private var updateNotice: NSPanel?
    private let updater = Updater()
    private var updateCheck: Timer?
    private var pendingCommit: Segment?
    private var room: StudyRooms?
    private var members: [Member] = []
    private var roomSeen = false         // the first snapshot after connecting is the baseline, not news
    private var checking = false

    override init() {
        let saved = Settings.get("id")
        localId = saved.isEmpty ? Room.randomId(12) : saved
        super.init()
        if saved.isEmpty { safely("설정 저장") { try Settings.set("id", self.localId) } }

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.button?.image = Sprites.face(pet.look)
        statusItem.button?.toolTip = "공부 친구 · ⌃⌥S로 공부 시작"
        statusItem.menu = menu

        pet.contextMenu = menu
        pet.bubbleText = { [unowned self] in self.bubble() }
        pet.seatmate = { [unowned self] in self.seatView("seatmate") }
        pet.rightSeatmate = { [unowned self] in self.seatView("seatmateRight") }
        pet.myName = { Settings.get("name") }
        pet.newsText = { [unowned self] in self.state != .off && Date() < self.newsUntil ? self.news : "" }
        pet.board = { [unowned self] in
            if Settings.get("background") == "hidden" { return nil }
            if let room = self.room {
                let board = Room.board(room.boardMembers, me: self.myId)
                return (room.name.isEmpty ? board.title : "\(room.name) · \(board.title)", board.lines)
            }
            return (Settings.get("pending") == "1" ? "방장의 승인을 기다리는 중이에요" : "친구를 초대하면 여기에 적혀요", [])
        }
        pet.seatmateClicked = { [unowned self] in self.pokeSeatmate("seatmate") }
        pet.rightSeatmateClicked = { [unowned self] in self.pokeSeatmate("seatmateRight") }
        pet.petClicked = { [unowned self] in
            if self.state != .off { self.toggle() } // pause or resume; never reopens the planner mid-farewell
        }
        pet.awayClicked = { [unowned self] in
            if self.state == .off { self.showPlanner() }
        }

        Hotkeys.pressed = { [weak self] id in
            if id == 1 { self?.toggle() } else { self?.stop() }
        }
        let startKey = hotkeys.register(1, keyCode: kVK_ANSI_S)
        let stopKey = hotkeys.register(2, keyCode: kVK_ANSI_X)
        if !startKey || !stopKey {
            alert("⌃⌥S 또는 ⌃⌥X를 다른 프로그램이 쓰고 있어요. 메뉴 막대의 펫 얼굴을 눌러 시작할 수 있어요.")
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)

        safely("지난 기록 복구") { try Records.recoverOpen() }
        restoreUpdateState()
        connect()
        updater.found = { [weak self] in self?.showUpdateNotice($0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.updater.check() }
        let check = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.updater.check() }
        RunLoop.main.add(check, forMode: .common)
        updateCheck = check
    }

    private var nickname: String { Settings.get("name") }

    @objc private func toggle() {
        if quitting { return }
        switch state {
        case .studying: pause()
        case .paused: resume()
        case .off: showPlanner()
        }
    }

    private func showPlanner() {
        if quitting { return }
        if let planner, planner.isVisible {
            planner.present()
            return
        }
        var ranking: [Records.Rank] = []
        let month = Calendar.current.dateInterval(of: .month, for: Date())!.start
        safely("기록 읽기") { ranking = try Records.ranking(Records.load(), hidden: Records.hidden(), monthStart: month, count: 8) }
        let page = Planner(ranking: ranking, anchor: pet.frame)
        page.picked = { [weak self] in self?.start($0) }
        page.removed = { [weak self] removed, alsoRecords in
            self?.safely("과목 지우기") {
                try Records.hide(removed)
                if alsoRecords { try Records.deleteSubject(removed) }
            }
        }
        planner = page
        page.present()
    }

    private func start(_ picked: String) {
        guard state == .off, tryCommit() else { return }
        do { try Records.recoverOpen() } catch { alert("지난 기록을 먼저 저장해야 해요.\n" + describe(error)); return }
        safely("과목 목록 저장") { try Records.unhide(picked) }
        subject = picked
        banked = 0
        state = .studying
        openSegment()
        let timer = Timer(timeInterval: 60, target: self, selector: #selector(beat), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
        pet.appear(.studying)
        publish()
    }

    @objc private func beat() {
        saveOpen()
        publish()
    }

    private func pause() {
        closeSegment()
        state = .paused
        pet.setMood(.dozing)
        publish()
    }

    private func resume() {
        if quitting { return }
        guard tryCommit() else { return }
        state = .studying
        openSegment()
        pet.setMood(.studying)
        publish()
    }

    @objc private func stop() {
        if quitting { return }
        guard state != .off else { return }
        guard closeSegment() else { state = .paused; pet.setMood(.dozing); publish(); return }
        heartbeat?.invalidate()
        heartbeat = nil
        state = .off
        var today = 0.0
        let midnight = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: midnight)!
        safely("기록 읽기") { today = Records.minutes(Records.daily(try Records.load()), from: midnight, to: tomorrow) }
        farewell = "수고했어요!\n오늘 \(Records.duration(today))"
        pet.standUpAndLeave()
        publish()
    }

    private func openSegment() {
        segmentStart = Date()
        saveOpen()
    }

    private func saveOpen() {
        guard let start = segmentStart else { return }
        safely("기록 저장") { try Records.saveOpen(start: start, lastSeen: Date(), subject: self.subject) }
    }

    /// Writes the running segment to sessions.csv. Safe to call when nothing is running.
    @discardableResult private func closeSegment() -> Bool {
        if let start = segmentStart {
            let end = Date()
            pendingCommit = Segment(start: start, end: end, subject: subject)
            segmentStart = nil
            banked += end.timeIntervalSince(start)
        }
        return tryCommit()
    }

    private func tryCommit() -> Bool {
        guard let segment = pendingCommit else { return true }
        do { try Records.commit(segment); pendingCommit = nil; return true }
        catch { alert("기록을 저장하지 못했어요. 다시 시작하거나 그만하기를 누르면 재시도해요.\n\n" + describe(error)); return false }
    }

    private var elapsed: TimeInterval { banked + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0) }

    private func bubble() -> String {
        switch state {
        case .studying: return elapsed < 60 ? "\(subject)\n공부 시작!" : "\(subject)\n\(Records.duration(elapsed / 60))째 공부 중"
        case .paused: return "\(subject) · \(Records.duration(elapsed / 60))\n쿨쿨… 쉬는 중"
        case .off: return farewell
        }
    }

    /// One button rolls a complete new look.
    @objc private func switchLook() {
        pet.look = Look.random(girl: Bool.random())
        statusItem.button?.image = Sprites.face(pet.look)
        publish()
    }

    // ---- Friends ------------------------------------------------------------------

    private func connect() {
        room?.dispose()
        room = nil
        members = []
        roomSeen = false
        pendingCheck?.invalidate()
        pendingCheck = nil
        guard let invite = Invite.parse(Settings.get("room")) else { return }
        auth = invite.key.isEmpty ? nil : Auth(apiKey: invite.key)
        myId = auth != nil ? Settings.get("uid") : localId
        if Settings.get("pending") == "1" {
            let check = Timer(timeInterval: 10, target: self, selector: #selector(checkPending), userInfo: nil, repeats: true)
            RunLoop.main.add(check, forMode: .common)
            pendingCheck = check
            return
        }
        if nickname.isEmpty || myId.isEmpty { return }
        let auth = self.auth
        let joined = StudyRooms(invite: invite, me: myId, token: { [weak self] in
            guard let self else { throw RoomError("연결이 종료됐어요.") }; return try await self.roomToken(auth)
        })
        joined.changed = { [weak self, weak joined] list in
            guard let self, self.room === joined else { return }
            let started = Room.newlyStarted(before: self.members, after: list, me: self.myId)
            if self.roomSeen && !started.isEmpty {
                self.news = Room.startedText(started)
                self.newsUntil = Date().addingTimeInterval(8)
            }
            self.roomSeen = true
            self.members = list
        }
        joined.poked = { [weak self, weak joined] poke in
            guard let self, self.room === joined else { return }
            self.receivePoke(poke)
        }
        room = joined
        publish()
    }

    private func roomToken(_ current: Auth?) async throws -> String {
        guard let current else { return "" }
        let value = try await current.token()
        let uid = await current.uid
        let changed = await MainActor.run { () -> Bool in
            guard self.auth === current, self.myId != uid else { return false }
            self.safely("로그인 저장") { try Settings.set("pending", "1") }
            self.alert("로그인 정보가 바뀌어 재승인이 필요해요. 초대 코드를 다시 넣어 주세요.")
            self.connect()
            return true
        }
        if changed { throw RoomError("재승인이 필요해요. 초대 코드를 다시 넣어 주세요.") }
        return value
    }

    private func publish() {
        room?.publish([
            "name": nickname,
            "look": pet.look.girl ? "girl" : "boy",
            "style": pet.look.code,
            "state": state == .studying ? "studying" : state == .paused ? "paused" : "off",
            "subject": state == .off ? "" : subject,
            "minutes": min(10080, Int(elapsed / 60)), // the room's rules cap it at a week
            "updated": Room.serverTime,
        ])
    }

    @discardableResult
    @objc private func askNickname() -> Bool {
        let name = Room.cleanName(ask("친구들에게 보일 이름을 정해 주세요. (\(Room.maxNameLength)자까지)", title: "닉네임", value: nickname))
        if name.isEmpty { return false }
        safely("닉네임 저장") { try Settings.set("name", name) }
        if room == nil { connect() } else { publish() }
        return true
    }

    /// Signs in to the invite's database; the local test server has no sign-in.
    private func signIn(_ invite: Invite) async throws -> (me: String, token: String) {
        if invite.key.isEmpty { return (localId, "") }
        let signIn = Auth(apiKey: invite.key)
        let token = try await signIn.token()
        return (await signIn.uid, token)
    }

    /// Asking to join: nickname, real name and referrer go to the owner, who decides.
    @objc private func joinRoom() {
        let code = ask("친구에게 받은 초대 코드를 붙여 넣어 주세요.", title: "초대 코드 넣기", value: "")
        if code.isEmpty { return }
        guard let invite = Invite.parse(code) else {
            alert("초대 코드가 올바르지 않아요. 받은 코드를 앞뒤 빠짐없이 그대로 붙여 넣었는지 확인해 주세요.")
            return
        }
        guard let form = askJoinForm() else { return }
        safely("닉네임 저장") { try Settings.set("name", form.nickname) }
        let look = pet.look
        Task { @MainActor in
            do {
                let (me, token) = try await self.signIn(invite)
                if let seat = try await Room.resolve(invite, me: me, token: token) {
                    try Settings.setMany(("room", invite.code), ("seat", seat), ("seatmate", ""), ("seatmateRight", ""), ("viewRoom", ""), ("pending", ""))
                    self.connect()
                    return
                }
                try await Room.request(invite, me: me, token: token, [
                    "name": form.nickname, "realName": form.realName, "referrer": form.referrer,
                    "look": look.girl ? "girl" : "boy", "style": look.code, "at": Room.serverTime,
                ])
            } catch {
                self.alert("가입 요청을 보내지 못했어요.\n\n" + describe(error))
                return
            }
            self.safely("방 저장") {
                try Settings.setMany(("room", invite.code), ("seat", ""), ("seatmate", ""), ("pending", "1"))
            }
            self.alert("가입 요청을 보냈어요. 방장이 승인하면 알려 드릴게요.")
            self.connect()
        }
    }

    /// The join form: nickname, real name and who invited you, all required.
    private func askJoinForm() -> (nickname: String, realName: String, referrer: String)? {
        var values = [nickname, "", ""]
        while true {
            let alert = NSAlert()
            alert.messageText = "방에 들어가기"
            alert.informativeText = "방장이 확인하고 승인하면 들어갈 수 있어요.\n이름은 방장만 보고, 승인·거절이 정해지면 지워져요."
            alert.addButton(withTitle: "요청 보내기")
            alert.addButton(withTitle: "취소")
            let labels = ["닉네임", "이름", "추천인"]
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            let fields = labels.indices.map { i -> NSTextField in
                let field = NSTextField(string: values[i])
                field.placeholderString = labels[i]
                field.widthAnchor.constraint(equalToConstant: 260).isActive = true
                let row = NSStackView(views: [NSTextField(labelWithString: labels[i]), field])
                row.views[0].widthAnchor.constraint(equalToConstant: 50).isActive = true
                stack.addArrangedSubview(row)
                return field
            }
            stack.frame = NSRect(x: 0, y: 0, width: 320, height: 90)
            alert.accessoryView = stack
            alert.window.initialFirstResponder = fields[0]
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() != .alertFirstButtonReturn { return nil }
            values = [Room.cleanName(fields[0].stringValue), Room.cleanName(fields[1].stringValue, max: Room.maxRealNameLength),
                      Room.cleanName(fields[2].stringValue)]
            if !values.contains(where: \.isEmpty) { return (values[0], values[1], values[2]) }
            self.alert("닉네임, 이름, 추천인을 모두 적어 주세요.")
        }
    }

    /// While waiting to be let in: has the owner decided yet?
    @objc private func checkPending() {
        guard !checking, let invite = Invite.parse(Settings.get("room")) else { return }
        checking = true
        let auth = self.auth
        Task { @MainActor in
            defer { self.checking = false }
            do {
                let token = try await auth?.token() ?? ""
                let me = await auth?.uid ?? self.localId
                let standing = try await Room.check(invite, me: me, token: token)
                if standing == .waiting || Settings.get("room") != invite.code { return }
                let seat = standing == .approved ? try await Room.resolve(invite, me: me, token: token) ?? "" : ""
                if Settings.get("room") != invite.code { return }
                try Settings.setMany(("pending", ""), ("room", standing == .rejected ? "" : invite.code), ("seat", seat))
                self.alert(standing == .approved ? "방에 들어왔어요! 메뉴의 옆자리 만들기로 친구를 옆에 앉혀 보세요."
                                                 : "방장이 가입 요청을 받지 않았어요.")
                self.connect()
            } catch {
                // Offline or the server hiccupped: the next tick tries again.
            }
        }
    }

    @objc private func copyInvite() {
        let invite = Settings.get("room")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(invite, forType: .string)
        alert("초대 코드를 복사했어요. 카카오톡 등으로 친구에게 보내 주세요.\n\n" + invite)
    }

    /// Leaves the room, or withdraws a join request still waiting.
    @objc private func leaveRoom() {
        if Settings.get("pending") == "1", let invite = Invite.parse(Settings.get("room")) {
            let auth = self.auth, me = myId
            // The owner just won't find it, or will find a stale one; nothing to undo here.
            Task {
                guard let token = try? await auth?.token() ?? "" else { return }
                try? await Room.cancelRequest(invite, me: me, token: token)
            }
        }
        room?.leave()
        room?.flush()
        room?.dispose()
        room = nil
        members = []
        pendingCheck?.invalidate()
        pendingCheck = nil
        safely("방 나가기") {
                try Settings.setMany(("room", ""), ("seat", ""), ("seatmate", ""), ("seatmateRight", ""), ("viewRoom", ""), ("pending", ""))
        }
    }

    private func findSeatmate(_ key: String) -> Member? { members.first { $0.id == Settings.get(key) } }

    private func seatView(_ key: String) -> PetWindow.Seat? {
        guard room != nil, let mate = findSeatmate(key) else { return nil }
        let here = Room.isHere(mate, Room.latest(members))
        return PetWindow.Seat(name: mate.name, look: mate.look, here: here, dozing: here && mate.state == "paused", text: Room.seatText(mate, here: here))
    }

    @objc private func pinSeatmate(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? [String: String], let id = value["id"], let key = value["key"] else { return }
        let other = key == "seatmate" ? "seatmateRight" : "seatmate"
        safely("옆자리 저장") { try Settings.setMany((key, id), (other, Settings.get(other) == id ? "" : Settings.get(other))) }
    }

    private func pokeSeatmate(_ key: String) { if let mate = findSeatmate(key) { pokeMember(mate) } }
    @objc private func pokePerson(_ sender: NSMenuItem) { if let id = sender.representedObject as? String, let mate = members.first(where: { $0.id == id }) { pokeMember(mate) } }
    @objc private func chooseRoom(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { safely("방 선택") { try room?.select(id) } } }

    private func pokeMember(_ mate: Member) {
        guard let room, Date().timeIntervalSince(lastPokes[mate.id] ?? .distantPast) >= AppController.pokeCooldown else { return }
        lastPokes[mate.id] = Date()
        let message = Room.pokeMessage(mate, here: Room.isHere(mate, Room.latest(members)))
        room.poke(mate.id, ["from": myId, "name": nickname, "look": pet.look.girl ? "girl" : "boy", "style": pet.look.code, "message": message, "at": Room.serverTime])
        pet.goVisit(mate.name, message: message, side: mate.id == Settings.get("seatmate") ? -1 : mate.id == Settings.get("seatmateRight") ? 1 : 0)
    }

    private func receivePoke(_ poke: Poke) {
        if quitting { return }
        let side = poke.from == Settings.get("seatmate") ? -1 : poke.from == Settings.get("seatmateRight") ? 1 : 0
        pet.visit(poke.look, text: "\(poke.name) : \(poke.message)", side: side)
        guard state != .studying, !invitePromptOpen else { return }
        invitePromptOpen = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.invitePromptOpen = false }
            if self.quitting { return }
            let alert = NSAlert()
            alert.messageText = "\(poke.name)님이 찾고 있어요."
            alert.informativeText = "공부를 시작하시겠습니까?\n과목을 고르는 스터디플래너가 열립니다."
            alert.addButton(withTitle: "공부 시작")
            alert.addButton(withTitle: "나중에")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                if self.state != .off { self.stop() }
                if self.state == .off { self.showPlanner() }
            }
        }
    }

    // ---- Menu ---------------------------------------------------------------------

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggleItem = item(state == .studying ? "일시정지" : state == .paused ? "다시 시작" : "공부 시작", #selector(toggle))
        toggleItem.keyEquivalent = "s"
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(toggleItem)
        let stopItem = item("그만하기", #selector(stop))
        stopItem.keyEquivalent = "x"
        stopItem.keyEquivalentModifierMask = [.control, .option]
        stopItem.isEnabled = state != .off
        menu.addItem(stopItem)
        menu.addItem(.separator())
        menu.addItem(item("기록 보기", #selector(showStats)))
        menu.addItem(item("사용 설명서", #selector(showHelp)))
        menu.addItem(item("랜덤 꾸미기", #selector(switchLook)))
        menu.addItem(.separator())
        menu.addItem(item(nickname.isEmpty ? "닉네임 정하기…" : "닉네임: \(nickname) (바꾸기…)", #selector(askNickname)))

        let share = NSMenu()
        if Settings.get("pending") == "1" {
            share.addItem(NSMenuItem(title: "방장의 승인을 기다리는 중…", action: nil, keyEquivalent: ""))
            share.addItem(item("가입 요청 취소", #selector(leaveRoom)))
        } else if let room {
            var status = room.error.isEmpty ? "등록 \(room.boardMembers.count)명 · 공부 중 \(room.boardMembers.filter { Room.isHere($0, Room.latest(members)) }.count)명" : "연결 안 됨: " + room.error
            if status.count > 60 { status = String(status.prefix(60)) + "…" }
            share.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
            let views = NSMenu()
            for choice in room.choices {
                let view = item(choice.name, #selector(chooseRoom(_:)))
                view.representedObject = choice.id; view.state = choice.id == room.selected ? .on : .off
                views.addItem(view)
            }
            let viewItem = NSMenuItem(title: "칠판 방 선택", action: nil, keyEquivalent: ""); viewItem.submenu = views; share.addItem(viewItem)
            let calls = NSMenu()
            for friend in members.filter({ $0.id != myId }).sorted(by: { $0.name < $1.name }) {
                let call = item(friend.name, #selector(pokePerson(_:))); call.representedObject = friend.id; calls.addItem(call)
            }
            let callItem = NSMenuItem(title: "친구 부르기", action: nil, keyEquivalent: ""); callItem.submenu = calls; share.addItem(callItem)
            share.addItem(item("초대 코드 복사", #selector(copyInvite)))
            share.addItem(item("방 나가기", #selector(leaveRoom)))
        } else {
            share.addItem(item("초대 코드 넣기…", #selector(joinRoom)))
        }
        let shareItem = NSMenuItem(title: "친구와 공부하기", action: nil, keyEquivalent: "")
        shareItem.submenu = share
        menu.addItem(shareItem)

        if room != nil {
            let allSeats = NSMenu()
            for (key, label) in [("seatmate", "왼쪽 자리"), ("seatmateRight", "오른쪽 자리")] {
                let seats = NSMenu()
                let newest = Room.latest(members)
                for m in members.filter({ $0.id != myId }).sorted(by: { $0.name < $1.name }) {
                    let place = !Room.isHere(m, newest) ? "자리 비움" : m.state == "paused" ? "쉬는 중" : "공부 중"
                    let seat = item("\(m.name) (\(place))", #selector(pinSeatmate(_:)))
                    seat.representedObject = ["id": m.id, "key": key]; seat.state = m.id == Settings.get(key) ? .on : .off
                    seats.addItem(seat)
                }
                let clear = item("자리 비우기", #selector(pinSeatmate(_:))); clear.representedObject = ["id": "", "key": key]; seats.addItem(clear)
                let sideItem = NSMenuItem(title: label, action: nil, keyEquivalent: ""); sideItem.submenu = seats; allSeats.addItem(sideItem)
            }
            let seatsItem = NSMenuItem(title: "양옆 자리 고정", action: nil, keyEquivalent: ""); seatsItem.submenu = allSeats; menu.addItem(seatsItem)
        }
        menu.addItem(item(Settings.get("background") == "hidden" ? "배경 보이기" : "배경 숨기기", #selector(toggleBackground)))
        menu.addItem(.separator())
        let login = item("로그인할 때 자동 실행", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("설정…", #selector(showSettings)))
        menu.addItem(item("종료", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleBackground() {
        safely("배경 설정 저장") { try Settings.set("background", Settings.get("background") == "hidden" ? "" : "hidden") }
    }

    @objc private func toggleLogin() {
        safely("자동 실행 설정") {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        }
        if SMAppService.mainApp.status == .requiresApproval {
            alert("시스템 설정 → 일반 → 로그인 항목에서 '공부 친구'를 허용해 주세요.")
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(updater: updater, apply: { [weak self] in self?.installUpdate() }, login: { [weak self] in self?.toggleLogin() }, resize: { [weak self] in self?.pet.setDisplaySize($0) })
        }
        updateNotice?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        updater.check()
    }

    private func showUpdateNotice(_ tag: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "공부 친구 업데이트"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        let label = NSTextField(labelWithString: "새 버전 \(tag)이 나왔어요.")
        label.frame = NSRect(x: 20, y: 65, width: 320, height: 22)
        let button = NSButton(title: "설정에서 업데이트", target: self, action: #selector(showSettings))
        button.frame = NSRect(x: 18, y: 18, width: 190, height: 32)
        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(button)
        if let screen = NSScreen.main { panel.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 380, y: screen.visibleFrame.maxY - 20)) }
        updateNotice = panel
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak panel] in panel?.orderOut(nil) }
    }

    private func installUpdate() {
        Task { @MainActor in
            do {
                let prepared = try await updater.prepare()
                let previous = state
                guard closeSegment() else { state = .paused; pet.setMood(.dozing); updater.finish("공부 기록을 먼저 저장해야 해요."); return }
                do {
                    let saved = UpdateSession(state: previous == .studying ? "studying" : "paused", subject: subject, seconds: banked)
                    try Settings.set("updateResume", previous == .off ? "" : saved.encode())
                    try Updater.launch(prepared)
                    NSApp.terminate(nil)
                } catch {
                    try? Settings.set("updateResume", "")
                    if previous == .studying { resume() }
                    throw error
                }
            } catch { updater.finish(error.localizedDescription) }
        }
    }

    private func restoreUpdateState() {
        let raw = Settings.get("updateResume")
        guard !raw.isEmpty else { return }
        safely("업데이트 상태 복구") {
            try Settings.set("updateResume", "")
            guard let saved = UpdateSession.parse(raw) else { return }
            subject = saved.subject
            banked = saved.seconds
            state = saved.state == "studying" ? .studying : .paused
            if state == .studying { openSegment() }
            let timer = Timer(timeInterval: 60, target: self, selector: #selector(beat), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            heartbeat = timer
            pet.appear(state == .studying ? .studying : .dozing)
        }
    }

    @objc private func showHelp() {
        if help == nil { help = HelpWindow() }
        NSApp.activate(ignoringOtherApps: true)
        help?.makeKeyAndOrderFront(nil)
    }

    @objc private func showStats() {
        if let stats, stats.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            stats.makeKeyAndOrderFront(nil)
            return
        }
        var segments: [Segment] = []
        safely("기록 읽기") { segments = try Records.load() }
        if let start = segmentStart { segments.append(Segment(start: start, end: Date(), subject: subject)) }
        let window = StatsWindow(segments: segments)
        stats = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // Lid closed: doze, so the night doesn't count as study time.
    @objc private func willSleep() {
        if state == .studying { pause() }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    /// On quitting (from the menu, or when the Mac logs out or shuts down).
    func prepareQuit() -> Bool { closeSegment() }

    func beginFarewell() -> Bool {
        quitting = true
        guard state != .off, pet.isVisible else { return false }
        state = .off
        farewell = "다녀올게요!"
        publish()
        heartbeat?.invalidate()
        pet.standUpAndLeave()
        return true
    }

    func shutDown() {
        closeSegment()
        if state != .off { state = .off; publish() }
        room?.flush()
    }

    private func safely(_ what: String, _ action: () throws -> Void) {
        do {
            try action()
        } catch {
            alert("\(what) 실패: \(error.localizedDescription)")
        }
    }

    private func alert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "공부 친구"
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// A one-line question; "" when cancelled.
    private func ask(_ prompt: String, title: String, value: String) -> String {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = prompt
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}

/// ⌃⌥S and ⌃⌥X anywhere, through Carbon's hot keys (no accessibility permission needed).
final class Hotkeys {
    static var pressed: ((UInt32) -> Void)?
    private var refs: [EventHotKeyRef?] = []

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            Hotkeys.pressed?(id.id)
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(_ id: UInt32, keyCode: Int) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x53545950, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr { refs.append(ref) }
        return status == noErr
    }
}
