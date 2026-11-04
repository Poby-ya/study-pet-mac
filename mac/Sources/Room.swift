import Foundation

/// One person in the room, as everyone else sees them.
struct Member {
    var id = ""
    var name = ""
    var subject = ""
    var state = "off" // studying, paused, off
    var girl = false
    var style = ""     // Look.code; empty from versions before random looks
    var minutes = 0
    var updated: Int64 = 0 // server clock, ms
    var look: Look { Look.parse(style, girl: girl) }
}

/// A friend came over to wake you up.
struct Poke {
    var from = ""
    var name = ""
    var message = ""
    var girl = false
    var style = ""
    var at: Int64 = 0
    var missed = false // it was waiting when we connected: sent while the app was off
    var look: Look { Look.parse(style, girl: girl) }
}

struct RoomError: Error {
    let message: String
    /// Firebase answered, and said no (as opposed to not answering at all).
    var refused = false
    var invalidIdentity = false
    init(_ message: String, refused: Bool = false) {
        self.message = message
        self.refused = refused
    }
}

/// What went wrong, in words for the menu or a message box.
func describe(_ error: Error) -> String { (error as? RoomError)?.message ?? error.localizedDescription }

/// What an invite code holds: the database, the room, and the project's Web API key for
/// anonymous sign-in. Written as https://{database}/rooms/{room}?key={apiKey}. Without a
/// key it only works on this machine (the local test server, which has no sign-in).
struct Invite {
    let database: String
    let roomId: String
    let key: String

    var code: String { "\(database)/rooms/\(roomId)" + (key.isEmpty ? "" : "?key=" + key) }

    func url(_ path: String, _ token: String) -> String {
        "\(database)/\(path).json" + (token.isEmpty ? "" : "?auth=" + escape(token))
    }

    static func parse(_ text: String) -> Invite? {
        guard let parsed = Invite.database(text) else { return nil }
        let (components, database) = parsed
        let segments = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "/")
        guard segments.count == 2, segments[0] == "rooms", isRoomId(segments[1]) else { return nil }
        let key = (components.percentEncodedQuery ?? "").split(separator: "&").first { $0.hasPrefix("key=") }.map { String($0.dropFirst(4)) } ?? ""
        guard keyFits(components, key) else { return nil }
        return Invite(database: database, roomId: segments[1], key: key)
    }

    /// Another room in the same database, e.g. the one the owner seated me in.
    func withRoom(_ roomId: String) -> Invite { Invite(database: database, roomId: roomId, key: key) }

    static func isRoomId(_ text: String) -> Bool { matches(text, "^[a-z0-9]{16,40}$") }

    // A real database needs sign-in, so a key; the local test server takes none.
    private static func keyFits(_ components: URLComponents, _ key: String) -> Bool {
        isLoopback(components) ? key.isEmpty : matches(key, "^AIza[0-9A-Za-z_-]{30,45}$")
    }

    private static func isLoopback(_ components: URLComponents) -> Bool {
        let host = components.host?.lowercased() ?? ""
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return host == "localhost" || host == "[::1]" || host == "::1" ||
            (parts.count == 4 && parts[0] == "127" && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false })
    }

    /// https anywhere, or plain http on this machine; and the scheme://host[:port] part.
    private static func database(_ text: String) -> (URLComponents, String)? {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil,
              (scheme == "http" && isLoopback(components)) ||
                (scheme == "https" && (components.port == nil || components.port == 443) &&
                    (host.hasSuffix(".firebaseio.com") || host.hasSuffix(".firebasedatabase.app"))) else { return nil }
        let defaultPort = scheme == "https" ? 443 : 80
        let port = components.port.map { $0 == defaultPort ? "" : ":\($0)" } ?? ""
        return (components, "\(scheme)://\(host)\(port)")
    }
}

func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }

func escape(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? text
}

/// Anonymous sign-in with Firebase Authentication, like Auth.cs, so the database rules can
/// tell who is writing. The first call signs up (Firebase makes a user id for this
/// install); later calls refresh the hour-long ID token.
actor Auth {
    private let apiKey: String
    private let remember: Bool
    private var refreshToken: String
    private var idToken = ""
    private var expires = Date.distantPast
    private var pending: Task<String, Error>?

    /// This install's Firebase user id; empty until the first sign-in.
    private(set) var uid: String

    /// `remember: false` keeps the identity in memory only (the self-test's clients).
    init(apiKey: String, remember: Bool = true) {
        self.apiKey = apiKey
        self.remember = remember
        uid = remember ? Settings.get("uid") : ""
        // shortcut: the refresh token sits in settings.txt in the user's own Library, not the
        // Keychain, because an ad-hoc signed app would ask for Keychain access after every update.
        refreshToken = remember ? Settings.get("refresh") : ""
    }

    /// A valid ID token, signing up or refreshing when needed. One renewal at a time, so
    /// two callers never sign up twice.
    func token() async throws -> String {
        if !idToken.isEmpty && Date() < expires { return idToken }
        if let pending { return try await pending.value }
        let saved = (uid, refreshToken, idToken, expires)
        let task = Task<String, Error> {
            do { return try await self.renew() }
            catch { (self.uid, self.refreshToken, self.idToken, self.expires) = saved; throw error }
        }
        pending = task
        defer { pending = nil }
        return try await task.value
    }

    private func renew() async throws -> String {
        var seconds = ""
        if !refreshToken.isEmpty && !uid.isEmpty {
            do {
                let reply = try await Auth.post("https://securetoken.googleapis.com/v1/token?key=" + apiKey,
                                                type: "application/x-www-form-urlencoded",
                                                body: "grant_type=refresh_token&refresh_token=" + escape(refreshToken))
                idToken = Auth.str(reply, "id_token")
                refreshToken = Auth.str(reply, "refresh_token")
                uid = Auth.str(reply, "user_id")
                seconds = Auth.str(reply, "expires_in")
            } catch let error as RoomError where error.invalidIdentity {
                // Firebase turned the token down (another project's, or a deleted user): start over
                // below. A plain network error propagates instead, so being offline never costs the uid.
                refreshToken = ""
                uid = ""
            }
        }
        if uid.isEmpty {
            let reply = try await Auth.post("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + apiKey,
                                            type: "application/json", body: #"{"returnSecureToken":true}"#)
            idToken = Auth.str(reply, "idToken")
            refreshToken = Auth.str(reply, "refreshToken")
            uid = Auth.str(reply, "localId")
            seconds = Auth.str(reply, "expiresIn")
        }
        guard !uid.isEmpty, !idToken.isEmpty, !refreshToken.isEmpty else { throw RoomError("로그인 응답을 읽지 못했어요. 다시 시도해 주세요.") }
        // Renew five minutes early, so a token never runs out mid-request.
        expires = Date().addingTimeInterval(Double((Int(seconds) ?? 3600) - 300))
        if remember {
            try Settings.setMany(("uid", uid), ("refresh", refreshToken))
        }
        return idToken
    }

    private static func post(_ url: String, type: String, body: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            var error = RoomError(explain(reply, status), refused: true)
            let code = (reply["error"] as? [String: Any])?["message"] as? String ?? ""
            error.invalidIdentity = ["INVALID_REFRESH_TOKEN", "TOKEN_EXPIRED", "USER_NOT_FOUND"].contains(code)
            throw error
        }
        return reply
    }

    /// Firebase's error codes, in words the person can act on.
    private static func explain(_ reply: [String: Any], _ status: Int) -> String {
        let code = (reply["error"] as? [String: Any])?["message"] as? String ?? ""
        if code.contains("CONFIGURATION_NOT_FOUND") { return "Firebase Authentication을 먼저 시작하고 로그인 방법에서 익명을 켜 주세요." }
        if code.contains("OPERATION_NOT_ALLOWED") || code.contains("ADMIN_ONLY_OPERATION") {
            return "Firebase에서 익명 로그인이 꺼져 있어요. Authentication → 로그인 방법 → 익명을 켜 주세요."
        }
        if code.range(of: "API key", options: .caseInsensitive) != nil || code.contains("API_KEY") {
            return "웹 API 키가 맞지 않아요. 프로젝트 설정 → 일반의 웹 API 키를 다시 확인해 주세요."
        }
        return "로그인하지 못했어요 (\(status) \(code))"
    }

    private static func str(_ reply: [String: Any], _ key: String) -> String { reply[key] as? String ?? "" }
}

/// A study room in a Firebase Realtime Database through its REST API, speaking exactly
/// what the Windows app's Room.cs speaks. Writes are plain PUTs, one at a time in order;
/// a streaming GET (server-sent events) keeps a local copy of the room current. Every call
/// carries the signed-in user's token. The Mac app only joins rooms: creating one and
/// approving requests stay with the owner on Windows.
///
/// seats/{uid}                  = the room that person sits in (the owner moves people)
/// rooms/{room}/name            = the room's name, set by the owner
/// rooms/{room}/owner           = owner's uid
/// rooms/{room}/approved/{uid}  = true (written by the owner)
/// rooms/{room}/members/{uid}   = { name, look, style, state, subject, minutes, updated }
/// rooms/{room}/pokes/{to}      = { from, name, look, style, message, at }
/// requests/{room}/{uid}        = { name, realName, referrer, look, style, at }
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class Room: @unchecked Sendable {
    enum Standing { case approved, waiting, rejected }

    /// Heartbeats go out every minute; three missed ones and the person counts as away.
    static let staleMs: Int64 = 3 * 60_000
    static let maxNameLength = 12
    static let maxRealNameLength = 20
    static let boardLines = 6
    static let serverTime = [".sv": "timestamp"]

    private static let stream: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 128
        config.timeoutIntervalForRequest = 120 // Firebase sends a keep-alive every 30 s
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    private let invite: Invite
    private let me: String
    private let token: @Sendable () async throws -> String
    private let writeLock = NSLock()
    private var lastWrite: Task<Void, Never>?
    private var listeners: [Task<Void, Never>] = []
    private var tree: [String: Any] = [:]        // only touched by the room listener
    private var lastPokeAt: Int64 = -1           // -1 until the first snapshot: pokes already waiting then are stale

    /// Called on the main thread with everyone in the room.
    var changed: (([Member]) -> Void)?
    var poked: ((Poke) -> Void)?
    /// The owner has seated me in another room; reconnect there.
    var moved: ((String) -> Void)?
    var accessChanged: (([String]) -> Void)?
    private var accessTree: [String: Any] = [:]

    /// The room's name as the owner set it; "" until known. Main thread.
    private(set) var name = ""

    /// Why the last request failed, or "" while things work. Main thread.
    private(set) var error = ""

    /// `token` gives the signed-in user's ID token ("" for the local test server).
    init(invite: Invite, me: String, token: @escaping @Sendable () async throws -> String, followSeat: Bool = true, watchAccess: Bool = false, listenToRoom: Bool = true) {
        self.invite = invite
        self.me = me
        self.token = token
        if listenToRoom { listeners.append(Task.detached { [weak self] in await self?.listen(self?.roomPath ?? "") { self?.applyRoom($0, $1) } }) }
        if followSeat { listeners.append(Task.detached { [weak self] in await self?.listen("seats/" + me) { self?.applySeat($0, $1) } }) }
        if watchAccess { listeners.append(Task.detached { [weak self] in await self?.listen("access/" + me) { self?.applyAccess($0, $1) } }) }
    }

    private var roomPath: String { "rooms/" + invite.roomId }

    func publish(_ status: [String: Any]) { write("PATCH", "", ["\(roomPath)/members/\(me)": status, "\(roomPath)/names/\(me)": status["name"] ?? ""]) }

    func poke(_ to: String, _ poke: [String: Any]) { write("PUT", "\(roomPath)/pokes/\(to)", poke) }

    func leave() { write("DELETE", "\(roomPath)/members/\(me)", nil) }

    /// Waits up to two seconds for queued writes, so "off" reaches friends before exit.
    func pendingWrites() -> Task<Void, Never>? {
        writeLock.lock(); defer { writeLock.unlock() }; return lastWrite
    }

    func flush() {
        writeLock.lock()
        let last = lastWrite
        writeLock.unlock()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await last?.value
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    private var disposed = false
    func dispose() { disposed = true; listeners.forEach { $0.cancel() } }

    // ---- Before being in a room ----------------------------------------------------

    static func request(_ invite: Invite, me: String, token: String, _ request: [String: Any]) async throws {
        _ = try await call("PUT", invite.url("requests/\(invite.roomId)/\(me)", token), json(request))
    }

    static func cancelRequest(_ invite: Invite, me: String, token: String) async throws {
        _ = try await call("DELETE", invite.url("requests/\(invite.roomId)/\(me)", token), nil)
    }

    /// Approved, still waiting, or turned down (the owner deleted the request).
    static func check(_ invite: Invite, me: String, token: String) async throws -> Standing {
        if try await resolve(invite, me: me, token: token) != nil { return .approved }
        return try await call("GET", invite.url("requests/\(invite.roomId)/\(me)", token), nil) == "null" ? .rejected : .waiting
    }

    static func resolve(_ invite: Invite, me: String, token: String) async throws -> String? {
        let text = try await call("GET", invite.url("seats/\(me)", token), nil)
        let seat = (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])) as? String ?? invite.roomId
        guard Invite.isRoomId(seat) else { return nil }
        return try await call("GET", invite.url("rooms/\(seat)/approved/\(me)", token), nil) == "true" ? seat : nil
    }

    static func json(_ value: Any) -> Data? { try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) }

    /// One request; the body of the reply, or an error saying what went wrong.
    static func call(_ method: String, _ url: String, _ body: Data?) async throws -> String {
        guard let target = URL(string: url) else { throw RoomError("주소가 올바르지 않아요: " + url) }
        var request = URLRequest(url: target, timeoutInterval: 15)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await Room.stream.data(for: request)
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return text }
        throw RoomError(status == 401 ? "권한이 없어요. Firebase에 새 규칙(firebase-rules.json)을 게시했는지 확인해 주세요." : "\(status) \(text)")
    }

    // ---- In the room ---------------------------------------------------------------

    private func write(_ method: String, _ path: String, _ body: Any?) {
        let data = body.flatMap(Room.json)
        writeLock.lock()
        defer { writeLock.unlock() }
        // One at a time, in order: a quick pause-then-resume must not land backwards.
        let previous = lastWrite
        lastWrite = Task.detached { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let token = try await self.token()
                _ = try await Room.call(method, self.invite.url(path, token), data)
            } catch {
                self.report(describe(error))
            }
        }
    }

    private func report(_ message: String) { DispatchQueue.main.async { self.error = message } }

    private func listen(_ path: String, _ apply: (String, String) -> Void) async {
        var wait: UInt64 = 2
        while !Task.isCancelled {
            var revoked = false
            do {
                let current = try await token()
                guard let url = URL(string: invite.url(path, current)) else { return }
                var request = URLRequest(url: url)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await Room.stream.bytes(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw RoomError(http.statusCode == 401 ? "방에 들어갈 권한이 없어요"
                                    : "\(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))")
                }
                report("")
                wait = 2
                var type = ""
                for try await line in bytes.lines {
                    if line.hasPrefix("event: ") {
                        type = String(line.dropFirst(7))
                    } else if !line.hasPrefix("data: ") {
                        continue
                    } else if type == "put" || type == "patch" {
                        apply(type, String(line.dropFirst(6)))
                    } else if type == "auth_revoked" {
                        revoked = true // the hour-long token ran out: reconnect with a new one
                        break
                    } else if type == "cancel" {
                        throw RoomError("방에 들어갈 권한이 없어요: " + String(line.dropFirst(6)))
                    }
                }
            } catch {
                if Task.isCancelled { return }
                report(describe(error))
            }
            if revoked { continue }

            // Dropped or refused: try again, backing off to once a minute.
            do { try await Task.sleep(nanoseconds: wait * 1_000_000_000) } catch { return }
            wait = min(wait * 2, 60)
        }
    }

    private static func event(_ json: String) -> (path: String, data: Any?)? {
        guard let e = (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])) as? [String: Any] else { return nil }
        return (e["path"] as? String ?? "/", nonNull(e["data"]))
    }

    /// seats/{me}: the room the owner has me sitting in. Being moved out also takes my
    /// approval in the old room away, so its stream gets a "cancel"; that's expected.
    private func applyAccess(_ type: String, _ json: String) {
        guard let e = Room.event(json) else { return }
        accessTree = Room.applyEvent(accessTree, type, e.path, e.data)
        let ids = accessTree.filter { $0.value as? Bool == true && Invite.isRoomId($0.key) }.map(\.key).sorted()
        DispatchQueue.main.async { if !self.disposed { self.accessChanged?(ids) } }
    }

    private func applySeat(_ type: String, _ json: String) {
        guard let e = Room.event(json), e.path == "/", let seat = e.data as? String,
              seat != invite.roomId, Invite.isRoomId(seat) else { return }
        DispatchQueue.main.async { if !self.disposed { self.moved?(seat) } }
    }

    private func applyRoom(_ type: String, _ json: String) {
        guard let e = Room.event(json) else { return }
        tree = Room.applyEvent(tree, type, e.path, e.data)
        let roomName = Room.str(tree, "name")
        let members = Room.members(tree)
        var waiting = Room.pokeFor(tree, me)
        let fresh = waiting != nil && Room.deliverPoke(&waiting!, lastPokeAt: lastPokeAt, now: Int64(Date().timeIntervalSince1970 * 1000))
        let poke = waiting
        if let poke {
            lastPokeAt = max(lastPokeAt, poke.at)
            write("DELETE", "\(roomPath)/pokes/\(me)", nil)
        } else if lastPokeAt < 0 {
            lastPokeAt = 0
        }
        DispatchQueue.main.async {
            if self.disposed { return }
            self.name = roomName
            self.changed?(members)
            if fresh, let poke { self.poked?(poke) }
        }
    }

    static func nonNull(_ value: Any?) -> Any? { value is NSNull ? nil : value }

    /// Applies one streaming event to the local copy. "put" replaces the value at path;
    /// "patch" replaces each child it names.
    static func applyEvent(_ tree: [String: Any], _ type: String, _ path: String, _ data: Any?) -> [String: Any] {
        if type == "patch" {
            var result = tree
            var base = path
            while base.hasSuffix("/") { base.removeLast() }
            for (key, value) in data as? [String: Any] ?? [:] { result = applyEvent(result, "put", base + "/" + key, nonNull(value)) }
            return result
        }
        let keys = path.split(separator: "/").map(String.init)
        if keys.isEmpty { return data as? [String: Any] ?? [:] }
        return put(tree, keys[...], data) as? [String: Any] ?? [:]
    }

    private static func put(_ node: Any?, _ keys: ArraySlice<String>, _ data: Any?) -> Any? {
        guard let key = keys.first else { return data }
        var dict = node as? [String: Any] ?? [:]
        dict[key] = put(dict[key], keys.dropFirst(), data)
        return dict
    }

    static func members(_ tree: [String: Any]) -> [Member] {
        let all = tree["members"] as? [String: Any] ?? [:]
        var result = all.compactMap { (id, value) -> Member? in
            guard let m = value as? [String: Any] else { return nil }
            return Member(id: id, name: str(m, "name"), subject: str(m, "subject"), state: str(m, "state"), girl: str(m, "look") == "girl",
                          style: str(m, "style"), minutes: Int(num(m, "minutes")), updated: num(m, "updated"))
        }
        for (id, value) in tree["names"] as? [String: Any] ?? [:] {
            if let name = value as? String, !result.contains(where: { $0.id == id }) { result.append(Member(id: id, name: name)) }
        }
        return result
    }

    /// A poke left while my app was off still counts for this long.
    static let missedPokeMs: Int64 = 12 * 3_600_000
    static let missedPokeNote = "자리 비운 사이에 왔었어요"
    /// Under my outgoing bubble when the friend isn't at their desk: their app may be off.
    static let offPokeHint = "꺼져 있으면 켤 때 전해져요"

    /// Whether to show a poke. One already waiting at the first snapshot (lastPokeAt -1)
    /// was sent while the app was off: shown, marked missed, if it's recent.
    static func deliverPoke(_ poke: inout Poke, lastPokeAt: Int64, now: Int64) -> Bool {
        if lastPokeAt >= 0 { return poke.at > lastPokeAt }
        poke.missed = poke.at > 0 && now - poke.at < missedPokeMs
        return poke.missed
    }

    static func pokeFor(_ tree: [String: Any], _ me: String) -> Poke? {
        guard let p = (tree["pokes"] as? [String: Any])?[me] as? [String: Any] else { return nil }
        return Poke(from: str(p, "from"), name: str(p, "name"), message: str(p, "message"), girl: str(p, "look") == "girl",
                    style: str(p, "style"), at: num(p, "at"))
    }

    // Other people's data: nothing read back is trusted to have the right type or size.
    private static func str(_ node: [String: Any], _ key: String) -> String { node[key] as? String ?? "" }

    private static func num(_ node: [String: Any], _ key: String) -> Int64 {
        guard let n = node[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return 0 }
        let d = n.doubleValue
        return d.isFinite ? Int64(max(-9e15, min(9e15, d))) : 0
    }

    /// The newest heartbeat anyone sent. Comparing against it rather than the local clock
    /// keeps a laptop with a wrong clock from marking everyone away.
    static func latest(_ members: [Member]) -> Int64 { members.map(\.updated).max() ?? 0 }

    static func isHere(_ m: Member, _ latest: Int64) -> Bool { (m.state == "studying" || m.state == "paused") && latest - m.updated <= staleMs }

    /// The chalkboard: everyone else at their desk, studying first. It grows a line per
    /// person up to boardLines; the title always has the head count.
    static func board(_ members: [Member], me: String) -> (title: String, lines: [String]) {
        let newest = latest(members)
        let here = members.filter { isHere($0, newest) }.sorted { a, b in
            if (a.state == "paused") != (b.state == "paused") { return b.state == "paused" }
            if a.minutes != b.minutes { return a.minutes > b.minutes }
            return a.name < b.name
        }
        let lines = here.prefix(boardLines).map { m -> String in
            if m.state == "paused" { return "\(m.name) · 쉬는 중" }
            let what = m.subject.isEmpty ? "" : m.subject + " "
            return m.minutes < 1 ? "\(m.name) · \(what)방금 시작" : "\(m.name) · \(what)\(Records.duration(Double(m.minutes)))"
        }
        return (here.isEmpty ? "지금 공부 중" : "지금 공부 중 · \(here.count)명", lines)
    }

    /// Who went from away (or not in the room) to studying between two snapshots.
    /// Coming back from a pause doesn't count.
    static func newlyStarted(before: [Member], after: [Member], me: String) -> [String] {
        let latestBefore = latest(before)
        let latestAfter = latest(after)
        return after.filter { m in
            m.id != me && m.state == "studying" && isHere(m, latestAfter) && !before.contains { $0.id == m.id && isHere($0, latestBefore) }
        }.map(\.name).sorted()
    }

    /// The reminder every 20 minutes: "민지, 준혁도 같이 공부하고 있어요 !", or "" when no one else is.
    static func companyText(_ members: [Member], me: String) -> String {
        let newest = latest(members)
        let names = members.filter { $0.id != me && $0.state == "studying" && isHere($0, newest) }.map(\.name).sorted()
        if names.isEmpty { return "" }
        let shown = names.count > 3 ? names.prefix(2).joined(separator: ", ") + " 외 \(names.count - 2)명" : names.joined(separator: ", ")
        return shown + "도 같이 공부하고 있어요 !"
    }

    /// "민지가 공부를 시작했어요 !" / "민지, 준혁이 공부를 시작했어요 !"
    static func startedText(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        return (Array(names.dropLast()) + [withSubjectMarker(last)]).joined(separator: ", ") + " 공부를 시작했어요 !"
    }

    /// 민지가 / 준혁이: 이 after a final consonant.
    static func withSubjectMarker(_ name: String) -> String {
        let last = name.unicodeScalars.last?.value ?? 0
        let batchim = last >= 0xAC00 && last <= 0xD7A3 && (last - 0xAC00) % 28 != 0
        return name + (batchim ? "이" : "가")
    }

    /// The seatmate's bubble; their name is on the desk's name tag.
    static func seatText(_ m: Member, here: Bool) -> String {
        if !here { return "자리 비움" }
        let time = Records.duration(Double(m.minutes))
        let subject = m.subject.isEmpty ? "공부" : m.subject
        if m.state == "paused" { return "\(subject) · \(time)\n잠깐 쉬는 중" }
        return m.minutes < 1 ? subject + "\n공부 시작!" : "\(subject)\n\(time)째 공부 중"
    }

    static func pokeMessage(_ m: Member, here: Bool) -> String { !here ? "같이 공부하자 !" : m.state == "paused" ? "일어나 !" : "화이팅 !" }

    static func cleanName(_ raw: String, max: Int = maxNameLength) -> String {
        Records.cut(String(raw.filter { !Records.isControl($0) }).trimmingCharacters(in: .whitespacesAndNewlines), max)
    }

    /// Lowercase letters and digits: safe as a Firebase key and in a URL.
    static func randomId(_ length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}
