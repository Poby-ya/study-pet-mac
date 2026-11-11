import Foundation

/// A room is a chalkboard filter. All permitted rooms carry one shared study state.
final class StudyRooms {
    private let invite: Invite
    private let me: String
    private let token: @Sendable () async throws -> String
    private var channels: [String: Room] = [:]
    private var snapshots: [String: [Member]] = [:]
    private var monitor: Room?
    private var status: [String: Any]?
    private var setupError = ""
    private var disposed = false
    private(set) var selected: String
    var changed: (([Member]) -> Void)?
    var poked: ((Poke) -> Void)?
    var choices: [(id: String, name: String)] {
        channels.map { (id: $0.key, name: $0.value.name.isEmpty ? "방 · " + String($0.key.suffix(4)) : $0.value.name) }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }
    var name: String { channels[selected]?.name ?? "" }
    /// The D-day the owner set for the board on show, or "".
    var dday: String { channels[selected]?.dday ?? "" }
    var error: String { setupError.isEmpty ? channels.values.first(where: { !$0.error.isEmpty })?.error ?? "" : setupError }
    var boardMembers: [Member] { snapshots[selected] ?? [] }

    init(invite: Invite, me: String, token: @escaping @Sendable () async throws -> String) {
        self.invite = invite; self.me = me; self.token = token
        selected = Settings.get("viewRoom")
        Task { @MainActor in
            while !disposed {
            do {
                let credential = try await token()
                let text = try await Room.call("GET", invite.url("access/" + me, credential), nil)
                let map = (try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])) as? [String: Any] ?? [:]
                var ids = map.filter { $0.value as? Bool == true && Invite.isRoomId($0.key) }.map(\.key)
                let legacy = ids.isEmpty
                if legacy, let id = try await Room.resolve(invite, me: me, token: credential) { ids = [id] }
                guard !disposed else { return }
                setupError = ""
                sync(ids)
                monitor = Room(invite: invite, me: me, token: token, followSeat: false, watchAccess: true, listenToRoom: false)
                var hasIndex = !legacy
                monitor?.accessChanged = { [weak self] ids in
                    if !ids.isEmpty { hasIndex = true }
                    if hasIndex { self?.sync(ids) }
                }
                return
            } catch {
                if !disposed {
                    setupError = "여러 방에 연결하지 못했어요. 방장의 최신 보안 규칙 게시와 인터넷 연결을 확인해 주세요. " + describe(error)
                    changed?([])
                }
            }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func sync(_ ids: [String]) {
        guard !disposed else { return }
        for id in Array(channels.keys) where !ids.contains(id) { channels.removeValue(forKey: id)?.dispose(); snapshots.removeValue(forKey: id) }
        for id in ids where channels[id] == nil {
            let channel = Room(invite: invite.withRoom(id), me: me, token: token, followSeat: false)
            channels[id] = channel
            channel.changed = { [weak self, weak channel] members in
                guard let self, let channel, !self.disposed, self.channels[id] === channel else { return }
                self.snapshots[id] = members
                self.changed?(Self.merge(Array(self.snapshots.values)))
            }
            channel.poked = { [weak self] poke in if let self, !self.disposed, self.channels[id] != nil { self.poked?(poke) } }
            if let status { channel.publish(status) }
        }
        if channels[selected] == nil {
            selected = ids.contains(invite.roomId) ? invite.roomId : ids.sorted().first ?? ""
            try? Settings.set("viewRoom", selected)
        }
        changed?(Self.merge(Array(snapshots.values)))
    }

    static func merge(_ rooms: [[Member]]) -> [Member] {
        var unique: [String: Member] = [:]
        for member in rooms.flatMap({ $0 }) {
            if unique[member.id] == nil || unique[member.id]!.updated < member.updated { unique[member.id] = member }
        }
        return unique.values.sorted { $0.name < $1.name }
    }

    func select(_ id: String) throws {
        guard channels[id] != nil else { return }
        try Settings.set("viewRoom", id); selected = id
        changed?(Self.merge(Array(snapshots.values)))
    }
    func next() throws {
        let list = choices
        if list.count > 1 { try select(list[((list.firstIndex { $0.id == selected } ?? -1) + 1) % list.count].id) }
    }
    func publish(_ value: [String: Any]) { status = value; channels.values.forEach { $0.publish(value) } }
    func poke(_ to: String, _ value: [String: Any]) { channel(of: to)?.poke(to, value) }
    func leaveNote(_ to: String, _ value: [String: Any]) { channel(of: to)?.leaveNote(to, value) }
    private func channel(of to: String) -> Room? {
        snapshots.first(where: { $0.value.contains(where: { $0.id == to }) }).flatMap { channels[$0.key] }
    }
    func leave() { channels.values.forEach { $0.leave() } }
    func flush() {
        let pending = channels.values.compactMap { $0.pendingWrites() }
        let done = DispatchSemaphore(value: 0)
        Task.detached { for task in pending { await task.value }; done.signal() }
        _ = done.wait(timeout: .now() + 2)
    }
    func dispose() { disposed = true; monitor?.dispose(); channels.values.forEach { $0.dispose() } }
}
