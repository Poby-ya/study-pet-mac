import AppKit

/// `StudyPet --selftest <folder> [invite]`: checks the record keeping, the room logic and
/// the sprite grids, and writes selftest.txt (PASS or the failures) plus pictures of the
/// art, the pet window, the planner and the stats window into the folder, like
/// SelfTest.cs. With an invite (the local test server's) it also runs a room owner and a
/// friend through joining, approval, a poke and leaving, and saves the room as the Mac
/// app wrote it to room.json, for reading back with the Windows app's code.
enum SelfTest {
    private static var failures: [String] = []

    private static func check(_ ok: Bool, _ what: String) {
        if !ok { failures.append(what) }
    }

    static func run(outDir: String?, invite: String?) -> Int32 {
        let out = URL(fileURLWithPath: outDir ?? NSTemporaryDirectory() + "StudyPet-selftest")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Records.folder = out.appendingPathComponent("data")
        try? FileManager.default.removeItem(at: Records.folder)

        checkRecords()
        checkRoom()
        checkSprites()
        if let invite { checkNetwork(invite, out) }

        save(render(Sprites.sheetSize(scale: 4)) { Sprites.drawSheet(scale: 4) }, out, "sprites.png")
        save(scenes(), out, "scenes.png")
        let planner = Planner(ranking: [Records.Rank(subject: "영어", month: 270, total: 123 * 60),
                                        Records.Rank(subject: "수학", month: 95, total: 20 * 60),
                                        Records.Rank(subject: "알고리즘 문제풀이 백준", month: 30, total: 30)],
                              anchor: NSRect(x: 0, y: 0, width: 10, height: 10))
        save(capture(planner.contentView!), out, "planner.png")
        let today = Calendar.current.startOfDay(for: Date())
        func at(_ day: Int, _ hours: Double) -> Date { Calendar.current.date(byAdding: .day, value: day, to: today)!.addingTimeInterval(hours * 3600) }
        let stats = StatsWindow(segments: [
            Segment(start: at(0, 9), end: at(0, 10.5), subject: "영어"),
            Segment(start: at(0, 13), end: at(0, 13.75), subject: "국어"),
            Segment(start: at(-1, 20), end: at(-1, 22), subject: "수학"),
            Segment(start: at(-60, 20), end: at(-60, 23), subject: "수학"),
        ])
        for (i, name) in ["stats-subjects.png", "stats-daily.png", "stats-monthly.png"].enumerated() {
            stats.tabs.selectTabViewItem(at: i)
            save(capture(stats.contentView!), out, name)
        }

        let report = failures.isEmpty ? "PASS" : "FAIL\n" + failures.joined(separator: "\n")
        try? report.write(to: out.appendingPathComponent("selftest.txt"), atomically: true, encoding: .utf8)
        print(report)
        return failures.isEmpty ? 0 : 1
    }

    // ---- Records --------------------------------------------------------------------

    private static func checkRecords() {
        let calendar = Calendar.current
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }
        func plus(_ date: Date, days: Int = 0, hours: Double = 0) -> Date {
            calendar.date(byAdding: .day, value: days, to: date)!.addingTimeInterval(hours * 3600)
        }

        // A segment across midnight is split between the two days.
        let nov2 = day(2026, 11, 2)
        let segments = [
            Segment(start: plus(nov2, hours: 23.5), end: plus(nov2, days: 1, hours: 0.5), subject: "영어"),
            Segment(start: plus(nov2, hours: 9), end: plus(nov2, hours: 10), subject: "수학"),
        ]
        let daily = Records.daily(segments)
        check(daily[nov2]?["영어"] == 30 && daily[nov2]?["수학"] == 60, "daily: Nov 2 should be 영어 30 + 수학 60")
        check(daily[plus(nov2, days: 1)]?["영어"] == 30, "daily: the half hour after midnight belongs to Nov 3")
        check(Records.minutes(daily, from: nov2, to: plus(nov2, days: 2)) == 120, "minutes: Nov 2-3 should total 120")

        // The planner's ranking: this month first, then all time; hidden subjects left out.
        let nov1 = day(2026, 11, 1)
        let ranking = Records.ranking([
            Segment(start: plus(nov1, days: 1, hours: 9), end: plus(nov1, days: 1, hours: 10), subject: "영어"),
            Segment(start: plus(nov1, days: -3, hours: 9), end: plus(nov1, days: -3, hours: 14), subject: "수학"),
            Segment(start: plus(nov1, days: 2, hours: 9), end: plus(nov1, days: 2, hours: 11), subject: "수학"),
            Segment(start: plus(nov1, days: -40), end: plus(nov1, days: -40, hours: 1), subject: "국어"),
            Segment(start: plus(nov1, days: 3), end: plus(nov1, days: 3, hours: 3), subject: "과학"),
        ], hidden: ["과학"], monthStart: nov1, count: 8)
        check(ranking.map(\.subject) == ["수학", "영어", "국어"] && ranking[0].month == 120 && ranking[0].total == 420,
              "ranking: this month first, totals alongside: \(ranking.map(\.subject))")
        check(Records.short(30) == "30m" && Records.short(270) == "4h 30m" && Records.short(123 * 60) == "5d 3h" &&
              Records.short(20 * 60) == "20h" && Records.short(120 * 60) == "5d", "short: 30m / 4h 30m / 5d 3h / 20h / 5d")
        check(Records.duration(59.9) == "59분" && Records.duration(65) == "1시간 5분" && Records.duration(120) == "2시간", "duration")
        check(Records.cleanSubject("  a,b\"c\t ") == "a b c", "clean: commas, quotes and tabs become spaces")
        check(Records.cleanSubject(String(repeating: "가", count: 30)).count == 16, "clean: subjects are cut to 16 characters")

        // CSV round trip, recovery of a segment left open by a crash, hiding and deleting.
        do {
            try Records.append(segments[0])
            try Records.saveOpen(start: plus(nov2, days: 2, hours: 8), lastSeen: plus(nov2, days: 2, hours: 8.5), subject: "수학")
            try Records.recoverOpen()
            let loaded = try Records.load()
            check(loaded.count == 2, "csv: expected 2 segments after recovery, got \(loaded.count)")
            check(loaded.count == 2 && loaded[0].start == segments[0].start && loaded[0].end == segments[0].end && loaded[0].subject == "영어",
                  "csv: first segment should round-trip unchanged")
            check(loaded.count == 2 && loaded[1].subject == "수학" && loaded[1].end.timeIntervalSince(loaded[1].start) == 1800,
                  "csv: recovered segment should run to the last heartbeat")
            try Records.hide("수학")
            try check(Records.ranking(loaded, hidden: Records.hidden(), monthStart: .distantPast, count: 8).map(\.subject) == ["영어"],
                      "hide: a removed subject leaves the list")
            try check(Records.load().count == 2, "hide: removing a subject keeps its study time")
            try Records.unhide("수학")
            try check(Records.hidden().isEmpty, "hide: starting the subject again brings it back")
            try Records.deleteSubject("수학")
            try check(Records.load().map(\.subject) == ["영어"], "delete: only the other subject's records are left")
            check(FileManager.default.fileExists(atPath: Records.backupURL.path), "delete: the old file is kept as a backup")

            // A file the Windows app wrote: BOM, CRLF, its own time zone.
            let windows = "\u{FEFF}start,end,subject\r\n2026-11-02T09:00:00+09:00,2026-11-02T10:30:00+09:00,영어\r\n"
            try windows.write(to: Records.folder.appendingPathComponent("sessions.csv"), atomically: true, encoding: .utf8)
            let read = try Records.load()
            check(read.count == 1 && read[0].subject == "영어" && read[0].end.timeIntervalSince(read[0].start) == 5400,
                  "csv: a Windows sessions.csv reads back")
        } catch {
            check(false, "csv: \(error)")
        }
    }

    // ---- Room -----------------------------------------------------------------------

    private static func json(_ text: String) -> Any? {
        Room.nonNull(try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]))
    }

    private static func checkRoom() {
        var tree = Room.applyEvent([:], "put", "/",
                                   json(#"{"members":{"aaa":{"name":"민지","state":"studying","look":"girl","style":"g213402","minutes":32,"updated":1000}}}"#))
        var only = Room.members(tree)
        check(only.count == 1 && only[0].name == "민지" && only[0].look == Look(girl: true, 2, 1, 3, 4, 0, 2) && only[0].minutes == 32 && only[0].updated == 1000,
              "room: put / loads members with their look")
        tree = Room.applyEvent(tree, "patch", "/members/aaa", json(#"{"state":"paused"}"#))
        only = Room.members(tree)
        check(only.first?.state == "paused" && only.first?.name == "민지", "room: patch changes one field and keeps the rest")
        tree = Room.applyEvent(tree, "put", "/pokes/me", json(#"{"from":"aaa","name":"준혁","message":"일어나 !","look":"boy","at":5}"#))
        let poke = Room.pokeFor(tree, "me")
        check(poke?.from == "aaa" && poke?.name == "준혁" && poke?.message == "일어나 !" && poke?.girl == false && poke?.at == 5,
              "room: a poke for me is found")
        check(poke?.look == Look.parse("", girl: false), "look: no style means the plain look of that gender")
        check(Room.pokeFor(tree, "someone") == nil, "room: someone else's poke isn't mine")
        tree = Room.applyEvent(tree, "put", "/pokes/me", nil)
        check(Room.pokeFor(tree, "me") == nil, "room: put null removes")
        tree = Room.applyEvent(tree, "put", "/members/bbb", json(#"{"name":5,"minutes":"lots","updated":true,"style":"x9"}"#))
        check(Room.members(tree).count == 2 && Room.members(tree).contains { $0.id == "bbb" && $0.name == "" && $0.minutes == 0 && $0.updated == 0 },
              "room: wrong types read as empty instead of throwing")
        check(Room.members(Room.applyEvent(tree, "put", "/", nil)).isEmpty, "room: put / null empties the room")
        let requests = Room.requests(Room.applyEvent([:], "put", "/",
            json(#"{"u2":{"name":"나중","realName":"이름2","referrer":"민지","at":9},"u1":{"name":"먼저","realName":"이름1","referrer":"민지","at":3}}"#)))
        check(requests.map(\.name) == ["먼저", "나중"] && requests[0].realName == "이름1" && requests[0].uid == "u1", "requests: oldest first")

        // Who's here, and how it reads.
        let now: Int64 = 10_000_000
        func m(_ id: String, _ name: String, _ state: String, _ age: Int64, _ minutes: Int = 0, _ subject: String = "") -> Member {
            Member(id: id, name: name, subject: subject, state: state, minutes: minutes, updated: now - age)
        }
        var members = [m("me", "나", "studying", 0), m("a", "민지", "studying", 30_000, 32, "수학"), m("b", "준혁", "paused", 60_000, 65),
                       m("c", "서연", "off", 0), m("d", "하늘", "studying", Room.staleMs + 1)]
        var board = Room.board(members, me: "me")
        check(board.title == "지금 공부 중 · 2명" && board.lines == ["민지 · 수학 32분", "준혁 · 쉬는 중"],
              "board: everyone else at their desk, studying first, away and off left out: \(board.lines)")
        members += [m("e", "가람", "studying", 0), m("f", "다온", "studying", 0, 0, "국어")]
        board = Room.board(members, me: "me")
        check(board.title == "지금 공부 중 · 4명" && board.lines.count == 4 && board.lines.contains("다온 · 국어 방금 시작"), "board: a line per person")
        check(Room.board((0..<9).map { m("x\($0)", "친구\($0)", "studying", 0, $0) }, me: "me").lines.count == Room.boardLines,
              "board: grows only up to boardLines")

        let before = Array(members.prefix(4))
        let after = [m("me", "나", "studying", 0), m("a", "민지", "studying", 0, 33, "수학"), m("b", "준혁", "studying", 0, 65),
                     m("c", "서연", "studying", 0), m("g", "하준", "studying", 0)]
        let started = Room.newlyStarted(before: before, after: after, me: "me")
        check(started == ["서연", "하준"], "news: only people who weren't here before: \(started)")
        check(Room.startedText(started) == "서연, 하준이 공부를 시작했어요 !", "news: 이 after 준")
        check(Room.startedText(["민지"]) == "민지가 공부를 시작했어요 !", "news: 가 after 지")
        check(Room.withSubjectMarker("Amy") == "Amy가", "particle: 가 after a non-Hangul name")

        let latest = Room.latest(members)
        check(Room.seatText(members[1], here: Room.isHere(members[1], latest)) == "수학\n32분째 공부 중", "seat: studying text")
        check(Room.seatText(members[2], here: Room.isHere(members[2], latest)) == "공부 · 1시간 5분\n쿨쿨… 쉬는 중", "seat: paused text")
        check(Room.seatText(members[4], here: Room.isHere(members[4], latest)) == "자리 비움", "seat: gone quiet reads as away")
        check(Room.pokeMessage(members[1], here: true) == "화이팅 !" && Room.pokeMessage(members[2], here: true) == "일어나 !" &&
              Room.pokeMessage(members[3], here: Room.isHere(members[3], latest)) == "같이 공부하자 !", "poke: message follows their state")

        // Invites, looks and names.
        let key = "AIza" + String(repeating: "x", count: 35)
        let pasted = Invite.parse(" https://pet-1-default-rtdb.asia-southeast1.firebasedatabase.app/rooms/abcdefghij0123456789?key=\(key) ")
        check(pasted?.code == "https://pet-1-default-rtdb.asia-southeast1.firebasedatabase.app/rooms/abcdefghij0123456789?key=\(key)",
              "invite: a pasted invite is accepted")
        check(Invite.parse("https://pet-1.firebaseio.com/rooms/abcdefghij0123456789") == nil, "invite: a real database needs a key")
        check(Invite.parse("http://127.0.0.1:8790/rooms/abcdefghij0123456789")?.code == "http://127.0.0.1:8790/rooms/abcdefghij0123456789",
              "invite: plain http on this machine needs no key")
        check(Invite.parse("http://example.com/rooms/abcdefghij0123456789?key=\(key)") == nil, "invite: plain http elsewhere is refused")
        check(Invite.parse("https://example.com/rooms/short?key=\(key)") == nil, "invite: a short room id is refused")
        check(Invite.parse("https://example.com/rooms/ABCDEFGHIJ0123456789?key=\(key)") == nil, "invite: uppercase room id is refused")
        check(Invite.parse("https://example.com/rooms/abcdefghij0123456789?key=nope") == nil, "invite: a malformed key is refused")
        check(Invite.create(database: "https://pet-1-default-rtdb.firebaseio.com/", key: key).flatMap { Invite.parse($0.code) } != nil,
              "invite: a new room makes a valid invite")
        check(pasted?.url("rooms/x", "a+b/c") == "https://pet-1-default-rtdb.asia-southeast1.firebasedatabase.app/rooms/x.json?auth=a%2Bb%2Fc",
              "invite: the token is escaped in the URL")
        let id = Room.randomId(12)
        check(id.count == 12 && id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }, "id: 12 lowercase letters and digits")
        check(Room.cleanName(" 민\t지 ") == "민지" && Room.cleanName(String(repeating: "가", count: 20)).count == Room.maxNameLength, "name: cleaned and cut")
        check(Look.parse("g213402", girl: false).code == "g213402" && Look.parse("b219999", girl: false).code == "b211913",
              "look: codes round-trip; boys' bottoms fold to trousers")
        check(Look.parse("nonsense", girl: true) == Look(girl: true, 0, 0, 2, 2, 0, 0), "look: a bad code is the plain look")
    }

    private static func checkSprites() {
        for i in 0..<12 {
            let look = Look(girl: i % 2 == 1, i / 2 % 3, i % 4, i % 4, (i * 3) % 10, i % 8, i % 6)
            for grid in Sprites.grids(look) {
                check(grid.allSatisfy { $0.count == grid[0].count }, "sprite: ragged grid starting \(grid[0])")
                check(grid.allSatisfy { $0.allSatisfy(Sprites.isKnownColor) }, "sprite: unknown colour in grid starting \(grid[0])")
            }
            for pose in Sprites.Pose.allCases {
                for layer in Sprites.compose(pose, look, alert: true) + Sprites.compose(pose, look) {
                    check(layer.x >= 0 && layer.y >= 0 && layer.x + layer.grid[0].count <= Sprites.width && layer.y + layer.grid.count <= Sprites.height,
                          "sprite: \(pose) (\(look.code)) has a layer off the canvas at \(layer.x),\(layer.y)")
                }
            }
        }
    }

    // ---- Network --------------------------------------------------------------------

    /// Runs async work to the end while keeping the main run loop (and so room events) going.
    private final class Outcome<T>: @unchecked Sendable {
        var value: T?
        var error: Error?
        var done = false
    }

    private static func finish<T>(_ work: @escaping @Sendable () async throws -> T) -> T? {
        let outcome = Outcome<T>()
        Task.detached {
            do { outcome.value = try await work() } catch { outcome.error = error }
            outcome.done = true
        }
        _ = waitFor { outcome.done }
        if let error = outcome.error { check(false, "network: \(describe(error))") }
        return outcome.value
    }

    private static func waitFor(_ condition: () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(15)
        while Date() < until {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    /// The owner creates the room, a friend asks to join and is let in, the friend pokes
    /// the owner, the owner leaves.
    private static func checkNetwork(_ code: String, _ out: URL) {
        guard let base = Invite.parse(code), base.key.isEmpty else {
            check(false, "network: needs a local test server invite, got \(code)")
            return
        }
        guard let invite = Invite.create(database: base.database, key: "") else { return }
        let owner = Room.randomId(12), friend = Room.randomId(12)
        _ = finish { try await Room.create(invite, me: owner, token: "") }
        _ = finish { try await Room.request(invite, me: friend, token: "", ["name": "다라", "realName": "김다라", "referrer": "가나",
                                                                        "look": "boy", "style": "b120350", "at": Room.serverTime]) }
        check(finish { try await Room.check(invite, me: friend, token: "") } == .waiting, "network: the friend waits for approval")

        let a = Room(invite: invite, me: owner, token: { "" }, owner: true)
        var waiting: [JoinRequest] = []
        var aReady = false
        var pokeAtA: Poke?
        a.requested = { waiting = $0 }
        a.changed = { _ in aReady = true }
        a.poked = { pokeAtA = $0 }
        check(waitFor { waiting.contains { $0.uid == friend && $0.realName == "김다라" && $0.referrer == "가나" } },
              "network: the owner sees the request (\(a.error))")
        a.approve(friend)
        a.flush()
        check(finish { try await Room.check(invite, me: friend, token: "") } == .approved, "network: the friend is let in")
        check(waitFor { waiting.isEmpty }, "network: the request (with the real name) is gone once decided")

        let b = Room(invite: invite, me: friend, token: { "" }, owner: false)
        var seenByB: [Member]?
        b.changed = { seenByB = $0 }
        a.publish(["name": "가나", "look": "girl", "style": "g213402", "state": "studying", "subject": "영어", "minutes": 5, "updated": Room.serverTime])
        b.publish(["name": "다라", "look": "boy", "style": "b120350", "state": "paused", "subject": "수학", "minutes": 12, "updated": Room.serverTime])
        check(waitFor { seenByB?.contains { $0.id == owner && $0.name == "가나" && $0.state == "studying" && $0.look.code == "g213402" && $0.updated > 0 } == true },
              "network: B should see A studying (A: \(a.error) B: \(b.error))")
        check(waitFor { aReady }, "network: A should get its first snapshot")
        b.poke(owner, ["from": friend, "name": "다라", "look": "boy", "style": "b120350", "message": "일어나 !", "at": Room.serverTime])
        check(waitFor { pokeAtA != nil }, "network: A should be poked (B: \(b.error))")
        check(pokeAtA?.from == friend && pokeAtA?.message == "일어나 !" && pokeAtA?.look.code == "b120350", "network: the poke arrives intact")

        // The room as the Mac app wrote it, with one poke left waiting, for the Windows app to read.
        b.poke("macselftest0", ["from": friend, "name": "다라", "look": "boy", "style": "b120350", "message": "화이팅 !", "at": Room.serverTime])
        b.flush()
        a.flush()
        if let text = finish({ try await Room.call("GET", invite.url("rooms/\(invite.roomId)", ""), nil) }) {
            try? text.write(to: out.appendingPathComponent("room.json"), atomically: true, encoding: .utf8)
        }

        a.leave()
        a.flush()
        check(waitFor { seenByB != nil && !seenByB!.contains { $0.id == owner } }, "network: B should see A leave")
        b.leave()
        b.flush()
        a.dispose()
        b.dispose()
    }

    // ---- Pictures -------------------------------------------------------------------

    /// Draws into an sRGB bitmap one pixel per point, top-left origin, so the pixel art can
    /// be compared with the Windows app's pictures pixel for pixel.
    static func render(_ size: NSSize, _ draw: () -> Void) -> NSBitmapImageRep {
        let cg = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return NSBitmapImageRep(cgImage: cg.makeImage()!)
    }

    private static func capture(_ view: NSView) -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private static func save(_ rep: NSBitmapImageRep, _ out: URL, _ name: String) {
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name))
    }

    /// The pet window at a few moments, two to a row on a grey backdrop, like SelfTest.cs.
    private static func scenes() -> NSBitmapImageRep {
        let pet = PetWindow()
        pet.look = Look(girl: false, 0, 0, 0, 0, 0, 0)
        var seat: PetWindow.Seat?
        var mine = ""
        var news = ""
        var board: (title: String, lines: [String])?
        pet.bubbleText = { mine }
        pet.newsText = { news }
        pet.myName = { "지우" }
        pet.seatmate = { seat }
        pet.board = { board }
        let minji = Look(girl: true, 0, 0, 2, 2, 5, 0)
        let junhyuk = Look(girl: false, 2, 1, 1, 6, 1, 0)

        var shots: [NSBitmapImageRep] = []
        func shot(_ mood: PetWindow.Mood, frame: Int = 0, visitTick: Int = -1, friend: Look = minji, friendText: String = "") {
            pet.preview(mood, frame: frame, visitTick: visitTick, friend: friend, friendText: friendText)
            shots.append(render(petSize) { pet.paint() })
        }

        // With the classroom: a full board, then a short one with news above my bubble.
        mine = "영어\n23분째 공부 중"
        seat = PetWindow.Seat(name: "민지", look: minji, here: true, dozing: false, text: "수학\n32분째 공부 중")
        board = ("지금 공부 중 · 5명", ["민지 · 수학 32분", "준혁 · 영어 1시간 5분", "다온 · 국어 방금 시작", "서연 · 과학 12분", "하준 · 쉬는 중"])
        shot(.studying)
        seat = PetWindow.Seat(name: "준혁", look: junhyuk, here: false, dozing: false, text: "자리 비움")
        mine = "영어\n공부 시작!"
        news = "다온이 공부를 시작했어요 !"
        board = ("지금 공부 중 · 1명", ["다온 · 국어 방금 시작"])
        shot(.studying)
        // Background hidden: dozing, then the seatmate walking over and tapping (hand down).
        news = ""
        mine = "영어 · 23분\n쿨쿨… 쉬는 중"
        seat = PetWindow.Seat(name: "민지", look: minji, here: true, dozing: false, text: "수학\n32분째 공부 중")
        board = nil
        shot(.dozing, frame: 1, visitTick: 2, friendText: "민지 : 일어나 !")
        shot(.dozing, frame: 6, visitTick: 6, friendText: "민지 : 일어나 !")
        // A visit while I'm not studying: the friend waves at my empty desk.
        seat = nil
        board = ("친구를 초대하면 여기에 적혀요", [])
        shot(.away, frame: 2, visitTick: 2, friend: junhyuk, friendText: "준혁 : 같이 공부하자 !")
        shot(.away, frame: 8, visitTick: 8, friend: junhyuk, friendText: "준혁 : 같이 공부하자 !")

        let w = petSize.width, h = petSize.height
        return render(NSSize(width: 2 * w, height: CGFloat((shots.count + 1) / 2) * h)) {
            Sprites.color(0xC9CFC4).setFill()
            NSRect(x: 0, y: 0, width: 2 * w, height: CGFloat((shots.count + 1) / 2) * h).fill()
            for (i, image) in shots.enumerated() {
                let cell = NSRect(x: CGFloat(i % 2) * w, y: CGFloat(i / 2) * h, width: w, height: h)
                image.draw(in: cell, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSColor.gray.setStroke()
                NSBezierPath(rect: cell.insetBy(dx: 0.5, dy: 0.5)).stroke()
            }
        }
    }
}
