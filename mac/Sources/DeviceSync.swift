import Foundation
import CryptoKit

final class DeviceSync {
    let invite: Invite
    let auth: Auth
    var data: [String: Any] = DeviceSync.empty()
    var pending: [[String: Any]] = []
    private let cache: URL
    var device = ""
    var account: String { Settings.get("linkedUid").isEmpty ? Settings.get("uid") : Settings.get("linkedUid") }
    var active: [String: Any] { Self.obj(data,"active") }
    var mine: Bool { active.isEmpty || Self.str(active,"device") == device }
    init(invite: Invite, auth: Auth) {
        self.invite = invite; self.auth = auth; device = Settings.get("uid")
        let account = Settings.get("linkedUid").isEmpty ? Settings.get("uid") : Settings.get("linkedUid")
        cache = Records.folder.appendingPathComponent("sync-" + Self.hash(invite.database + account) + ".json")
        if let bytes = try? Data(contentsOf: cache), let saved = try? Self.parse(bytes) { data = Self.obj(saved,"state"); pending = saved["pending"] as? [[String:Any]] ?? [] }
    }
    static func empty() -> [String: Any] { ["schema":1,"revision":0,"segments":[:],"profile":[:],"hidden":[:],"imports":[:],"operations":[:]] }
    static func obj(_ source: [String:Any], _ key: String) -> [String:Any] { source[key] as? [String:Any] ?? [:] }
    static func str(_ source: [String:Any], _ key: String) -> String { source[key] as? String ?? "" }
    static func num(_ source: [String:Any], _ key: String) -> Int64 { (source[key] as? NSNumber)?.int64Value ?? 0 }
    static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format:"%02x",$0) }.joined() }
    static func parse(_ bytes: Data) throws -> [String:Any] { try JSONSerialization.jsonObject(with: bytes,options: [.fragmentsAllowed]) as? [String:Any] ?? empty() }
    private static func key(_ active: [String:Any]) -> String { str(active,"id") + "-" + String(num(active,"start")) }
    private func save() throws { let bytes = try JSONSerialization.data(withJSONObject:["state":data,"pending":pending]); try FileManager.default.createDirectory(at: Records.folder,withIntermediateDirectories:true); try bytes.write(to:cache,options:.atomic) }
    func request(_ path: String, _ method: String = "GET", _ body: Any? = nil, tag: String? = nil) async throws -> (value: [String:Any], raw: Any, tag: String) {
        let token = try await auth.token()
        var request = URLRequest(url: URL(string:invite.url(path,token))!,timeoutInterval:15); request.httpMethod = method
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if let tag { request.setValue(tag == "read" ? "true" : tag,forHTTPHeaderField:tag == "read" ? "X-Firebase-ETag" : "if-match") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject:body,options:.fragmentsAllowed) }
        let (bytes,response) = try await URLSession.shared.data(for:request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 412 { throw NSError(domain:"StudyPet.Sync",code:412) }
        guard (200..<300).contains(status) else { throw RoomError("기기 연결 권한과 인터넷을 확인해 주세요. (\(status))") }
        let raw = try JSONSerialization.jsonObject(with:bytes,options:.fragmentsAllowed)
        return (raw as? [String:Any] ?? Self.empty(),raw,(response as? HTTPURLResponse)?.value(forHTTPHeaderField:"ETag") ?? "")
    }
    private func commit(_ operation: [String:Any]) async throws -> [String:Any] {
        for attempt in 0...4 {
            let read = try await request("users/"+account,tag:"read")
            let next = try Self.transition(read.value,operation)
            do { _ = try await request("users/"+account,"PUT",next,tag:read.tag); return next }
            catch let error as NSError where error.domain == "StudyPet.Sync" && error.code == 412 && attempt < 4 { }
        }
        throw RoomError("다른 기기에서 상태가 바뀌었어요.")
    }
    func pull() async throws {
        while !pending.isEmpty { data = try await commit(pending[0]); pending.removeFirst(); try save() }
        data = try await request("users/"+account).value; try save()
    }
    func change(_ type: String, subject: String = "", fields: [String:Any] = [:]) async throws {
        var operation: [String:Any] = ["id":UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),"type":type,"device":device,"at":Self.now,"observed":active,"subject":Records.cleanSubject(subject)]
        operation.merge(fields) { _,new in new }
        if ["pause","stop"].contains(type) && mine {
            let next = try Self.transition(data,operation), old = data
            pending.append(operation); data = next
            do { try save() } catch { data = old; pending.removeLast(); throw error }
            do { while !pending.isEmpty { data = try await commit(pending[0]); pending.removeFirst(); try save() } } catch { /* Durable pending operations retry on the next pull. */ }
        } else {
            guard pending.isEmpty else { throw RoomError("기기에 보관한 기록을 전송한 뒤 이어가 주세요.") }
            data = try await commit(operation); try save()
        }
    }
    func importRecords(_ profile: [String:Any]) async throws {
        var segments: [String:Any] = [:]
        for row in try Records.load() {
            let start = Int64(row.start.timeIntervalSince1970 * 1000), end = Int64(row.end.timeIntervalSince1970 * 1000)
            segments[Self.hash("\(start),\(end),\(row.subject)")] = ["start":start,"end":end,"subject":row.subject]
        }
        try await change("import",fields:["importId":"legacy","segments":segments])
        if Self.obj(data,"profile").isEmpty { try await change("profile",fields:["profile":profile]) }
        else if account == (await auth.uid) {let missing=SocialProfile.missing(Self.obj(data,"profile"),profile);if !missing.isEmpty {try await change("profile",fields:["profile":missing])}}
    }
    var database: String {invite.database}
    var defaultRoomCode: String {invite.code}
    var elapsed: Double {
        guard !active.isEmpty else { return 0 }
        let closed = Self.obj(data,"segments").values.compactMap { $0 as? [String:Any] }.filter { Self.str($0,"session") == Self.str(active,"id") }.reduce(Int64(0)) { $0 + Self.num($1,"end") - Self.num($1,"start") }
        return Double(closed + (Self.str(active,"state") == "studying" ? max(0,Self.now-Self.num(active,"start")) : 0))/1000
    }
    func mirror() throws {
        let segments = Self.obj(data,"segments").values.compactMap { $0 as? [String:Any] }.map { s in Segment(start:Date(timeIntervalSince1970:Double(Self.num(s,"start"))/1000),end:Date(timeIntervalSince1970:Double(Self.num(s,"end"))/1000),subject:Self.str(s,"subject")) }
        try Records.replaceSynced(segments,hidden:Array(Self.obj(data,"hidden").values.compactMap { $0 as? String }))
    }
    static func transition(_ source: [String:Any], _ op: [String:Any]) throws -> [String:Any] {
        var state = empty().merging(source) { _,value in value }, operations = obj(source,"operations"), segments = obj(source,"segments"), active = obj(source,"active"), hidden = obj(source,"hidden")
        let id = str(op,"id"), type = str(op,"type"), at = num(op,"at"), observed = obj(op,"observed")
        if operations[id] != nil { return state }
        if ["pause","stop","subject","takeover"].contains(type) {
            guard !observed.isEmpty && (type == "takeover" || str(observed,"device") == str(op,"device")) else { throw RoomError("이 기기에서 이어하기를 먼저 눌러 주세요.") }
            if active.isEmpty || key(active) != key(observed) || str(active,"device") != str(observed,"device") {
                guard ["pause","stop"].contains(type) else { throw RoomError("다른 기기에서 상태가 바뀌었어요.") }
                var closed = obj(segments,key(observed))
                if !closed.isEmpty && str(observed,"state") == "studying" { closed["end"] = max(num(closed,"start"),min(num(closed,"end"),at)); segments[key(observed)] = closed }
            } else {
                if str(active,"state") == "studying" { segments[key(active)] = ["start":num(active,"start"),"end":max(at,num(active,"start")),"subject":str(active,"subject"),"session":str(active,"id")] }
                if type == "stop" { active = [:] }
                else { active["start"] = at; if type == "pause" { active["state"] = "paused" }; if type == "takeover" { active["device"] = str(op,"device") }; if type == "subject" { active["subject"] = str(op,"subject"); active["id"] = id } }
            }
        } else if type == "start" {
            guard active.isEmpty else { throw RoomError("이미 공부 중이에요. 이 기기에서 이어하기를 눌러 주세요.") }
            active = ["id":id,"device":str(op,"device"),"state":"studying","subject":str(op,"subject"),"start":at]
        } else if type == "resume" {
            guard str(active,"device") == str(op,"device") && str(active,"state") == "paused" && key(active) == key(observed) else { throw RoomError("다른 기기에서 상태가 바뀌었어요.") }
            active["state"] = "studying"; active["start"] = at
        } else if type == "profile" { state["profile"] = obj(state,"profile").merging(obj(op,"profile")) { _,value in value } }
        else if type == "import" { var imports = obj(state,"imports"); let importId = str(op,"importId"); if imports[importId] == nil { segments.merge(obj(op,"segments")) { old,_ in old }; imports[importId] = true }; state["imports"] = imports }
        else if ["hide","delete"].contains(type) { guard str(active,"subject") != str(op,"subject") else { throw RoomError("공부를 마친 뒤 지워 주세요.") }; hidden[hash(str(op,"subject"))] = str(op,"subject"); if type == "delete" { segments = segments.filter { str($0.value as? [String:Any] ?? [:],"subject") != str(op,"subject") } } }
        else { throw RoomError("지원하지 않는 작업이에요.") }
        if ["start","subject"].contains(type) { hidden = hidden.filter { ($0.value as? String) != str(op,"subject") } }
        if !active.isEmpty && str(active,"subject").isEmpty { throw RoomError("과목을 적어 주세요.") }
        state["active"] = active.isEmpty ? nil : active; state["segments"] = segments; state["hidden"] = hidden
        operations[id] = true; state["operations"] = operations; state["revision"] = num(state,"revision") + 1
        return state
    }
}
