import AppKit

final class DeviceLinkWindow: NSWindow {
    private let status = NSTextField(wrappingLabelWithString: "")
    private let code = NSTextField(string: "")
    private let connected: () -> Void
    private var sync: DeviceSync?
    private var auth: Auth?
    private var offered = "", requested = ""
    private var timer: Timer?
    private var busy = false
    private let finishForLink: () -> Bool
    init(connected: @escaping () -> Void, finishForLink: @escaping () -> Bool) {
        self.connected = connected; self.finishForLink = finishForLink
        super.init(contentRect:NSRect(x:0,y:0,width:500,height:410),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        title = "계정·기기 연결"; isReleasedWhenClosed = false
        let note = NSTextField(wrappingLabelWithString:"사용하던 기기에서 코드를 만들고 새 기기에 입력하세요.\n코드는 10분 동안 한 번만 사용할 수 있어요.\n새 기기는 이 기기에서 승인한 뒤 연결됩니다.")
        note.frame = NSRect(x:24,y:305,width:450,height:80); contentView?.addSubview(note)
        let rows = (try? Records.load()) ?? []
        let count = NSTextField(labelWithString:"이 기기 기록 \(rows.count)개 · 처음 연결할 때 가져오고 원본을 백업합니다."); count.frame = NSRect(x:24,y:270,width:450,height:24); contentView?.addSubview(count)
        let create = NSButton(title:"이 기기에서 연결 코드 만들기",target:self,action:#selector(createCode)); create.frame = NSRect(x:24,y:220,width:300,height:32); contentView?.addSubview(create)
        code.frame = NSRect(x:24,y:173,width:300,height:30); code.placeholderString = "연결 코드 10자리"; contentView?.addSubview(code)
        let use = NSButton(title:"다른 기기의 코드 입력",target:self,action:#selector(useCode)); use.frame = NSRect(x:24,y:126,width:300,height:32); contentView?.addSubview(use)
        status.frame = NSRect(x:24,y:20,width:450,height:90); contentView?.addSubview(status); center()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    static func defaultInvite() throws -> Invite {
        guard let url = Bundle.main.url(forResource:"web-config",withExtension:"json"), let config = try? DeviceSync.parse(Data(contentsOf:url)), let invite = Invite.parse(DeviceSync.str(config,"database") + "/rooms/accountlink00000001?key=" + DeviceSync.str(config,"key")) else { throw RoomError("기기 연결 설정을 확인하지 못했어요.") }
        return invite
    }
    private func run(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { @MainActor in defer { busy = false }; do { try await action() } catch { status.stringValue = error.localizedDescription } }
    }
    private func prepare() async throws {
        let invite: Invite
        if let saved = Invite.parse(Settings.get("room")) { invite = saved } else { invite = try Self.defaultInvite() }
        guard invite.database == (try Self.defaultInvite()).database else { throw RoomError("이 교실에서는 아직 기기 연결을 지원하지 않아요.") }
        let auth = Auth(apiKey:invite.key); _ = try await auth.token(); self.auth = auth
        sync = DeviceSync(invite:invite,auth:auth)
    }
    private func startTimer() { timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval:2.5,repeats:true) { [weak self] _ in Task { @MainActor in guard let self, self.isVisible else { return }; self.run { try await self.check() } } } }
    @objc private func createCode() { run {
        guard self.finishForLink() else { return }
        try await self.prepare(); guard let sync = self.sync, let auth = self.auth else { return }
        try await sync.pull()
        var profile=SocialProfile.capture();profile.merge(["name":Settings.get("name"),"style":Settings.get("style"),"extra":Settings.get("lookExtras"),"customization":Customization.parse(Settings.get("customization"),Look.parse(Settings.get("style"),girl:false).withExtras(Settings.get("lookExtras"))).data(),"desk":Settings.get("laptop") == "1" ? 11 : 1,"invite":Settings.get("room")]) {_,value in value};try await sync.importRecords(profile)
        try Settings.set("cloudSync","1"); self.connected()
        self.offered = Room.randomId(10).uppercased(); self.requested = ""
        _ = try await sync.request("pairings/"+self.offered,"PUT",["issuer":await auth.uid,"account":sync.account,"created":Room.serverTime])
        self.code.stringValue = String(self.offered.prefix(5))+"-"+String(self.offered.suffix(5)); self.status.stringValue = "새 기기에 위 코드를 입력하세요. 연결 요청이 오면 승인할 수 있어요."; self.startTimer()
    } }
    @objc private func useCode() { run {
        guard Settings.get("cloudSync") != "1" else { throw RoomError("이미 연결된 기기예요.") }
        let alert = NSAlert(); alert.messageText = "이 기기의 기록을 백업하고 원래 계정의 기록을 불러올까요?"; alert.addButton(withTitle:"연결"); alert.addButton(withTitle:"취소"); guard alert.runModal() == .alertFirstButtonReturn else { return }
        self.requested = self.code.stringValue.replacingOccurrences(of:"-",with:"").trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        guard matches(self.requested,"^[A-Z0-9]{10}$") else { throw RoomError("연결 코드 10자리를 확인해 주세요.") }
        guard self.finishForLink() else { return }
        try await self.prepare(); guard let sync = self.sync, let auth = self.auth else { return }
        let uid = await auth.uid
        _ = try await sync.request("pairings/"+self.requested+"/candidate","PUT",uid)
        self.offered = ""; self.status.stringValue = "원래 기기에서 승인해 주세요. 요청 기기 " + String(uid.prefix(6)); self.startTimer()
    } }
    private func check() async throws {
        guard let sync, let auth else { return }; let key = offered.isEmpty ? requested : offered
        let pair = try await sync.request("pairings/"+key).value
        guard DeviceSync.now-DeviceSync.num(pair,"created") <= 600000 else { timer?.invalidate(); throw RoomError("코드가 만료됐어요.") }
        if !offered.isEmpty {
            let candidate = DeviceSync.str(pair,"candidate"); guard !candidate.isEmpty && pair["accepted"] == nil else { return }; timer?.invalidate()
            let alert = NSAlert(); alert.messageText = "요청 기기 " + String(candidate.prefix(6)) + "…"; alert.informativeText = "직접 입력한 기기가 맞으면 연결을 승인하세요."; alert.addButton(withTitle:"승인"); alert.addButton(withTitle:"거절")
            guard alert.runModal() == .alertFirstButtonReturn else { _ = try await sync.request("pairings/"+key,"DELETE"); status.stringValue = "연결을 거절했어요."; return }
            _ = try await sync.request("","PATCH",["deviceAccounts/"+candidate:["account":sync.account,"pair":key],"pairings/"+key+"/accepted":true]); status.stringValue = "연결을 승인했어요. 같은 자리와 기록을 사용해요."
        } else if pair["accepted"] as? Bool == true {
            guard finishForLink() else { timer?.invalidate(); return }
            let uid = await auth.uid; let mapping = try await sync.request("deviceAccounts/"+uid).value
            try Settings.set("linkedUid",DeviceSync.str(mapping,"account")); try await prepare(); guard let current = self.sync else { return }; try await current.pull()
            try Settings.setMany(("cloudSync","1"),("room",DeviceSync.str(DeviceSync.obj(current.data,"profile"),"invite")),("pending","")); try current.mirror(); timer?.invalidate(); connected(); status.stringValue = "기기 연결이 완료됐어요."
        }
    }
}
