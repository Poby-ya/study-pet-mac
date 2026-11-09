import AppKit

/// `StudyPet --selftest <folder> [invite]`: checks the record keeping, the room logic and
/// the sprite grids, and writes selftest.txt (PASS or the failures) plus pictures of the
/// art, the pet window, the planner and the stats window into the folder, like
/// SelfTest.cs. With an invite (the local test server's) it also takes a friend through
/// asking to join, being let in, poking the owner and leaving, playing the owner (whose
/// side lives in the Windows app) with plain requests, and saves the room as the Mac app
/// wrote it to room.json, for reading back with the Windows app's code.
enum SelfTest {
    private static var failures: [String] = []

    private static func check(_ ok: Bool, _ what: String) {
        if !ok { failures.append(what) }
    }


    private static func checkCustomization(_ out: URL) {
        let basic=Look(girl:true,2,1,1,2,4,0).withExtras("00000000"),legacy=Customization.legacy(Look(girl:true,2,1,1,2,4,0).withExtras("00000000"))
        let entries=Customization.categories.flatMap { s in s.art.map { (s,$0) } }
        check(entries.count==77,"customization: exactly 77 approved designs")
        let calendar=Calendar(identifier:.gregorian),date=calendar.date(from:DateComponents(year:2026,month:11,day:5,hour:20,minute:10))!
        var fixtures: [[String:Any]]=[]
        func flatten(_ layers: [Sprites.Layer]) -> [String] {var rows=Array(repeating:Array(repeating:Character("."),count:64),count:64);for l in layers {for (y,line) in l.grid.enumerated(){for (x,c) in line.enumerated() where c != "." {let xx=x+l.x,yy=y+l.y;if xx>=0 && xx<64 && yy>=0 && yy<64 {rows[yy][xx]=c}}}};return rows.map{String($0)}}
        let image=render(NSSize(width:1100,height:CGFloat((entries.count+4)/5*240))) {
            Sprites.color(0xF6EEDF).setFill();NSRect(x:0,y:0,width:1100,height:CGFloat((entries.count+4)/5*240)).fill()
            for (i,entry) in entries.enumerated() {let s=entry.0,art=entry.1,c=legacy.copy();c.slots[s.key]!.enabled=true;c.slots[s.key]!.value=art["id"] as! Int;let look=c.legacyLook(basic),grid=art["grid"] as! [String];check(grid.allSatisfy{$0.count==grid[0].count && $0.allSatisfy{Sprites.isKnownColor($0)}},"customization: rectangular known pixels "+s.key)
                let x=CGFloat(i%5*220),y=CGFloat(i/5*240)
                if s.group == "classroom" {c.drawRoom(look,NSRect(x:x+20,y:y+4,width:175,height:120),date)}else{Sprites.draw(.writeA,look,left:x+10,top:y+10,scale:4,decor:Sprites.Decor(drink:.mug,seed:7,lit:true,clock:date))}
                (art["title"] as! String).draw(in:NSRect(x:x+8,y:y+196,width:208,height:42),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.black])
                for (name,pose) in [("WriteA",Sprites.Pose.writeA),("DozeA",.dozeA),("WaveA",.waveA),("Empty",.empty)] {for laptop in [false,true] {let d=Sprites.Decor(laptop:laptop,seed:7,away:pose == .empty,clock:date);fixtures.append(["style":look.code,"extras":look.extra,"customization":c.data(),"pose":name,"decor":["drink":0,"laptop":laptop,"seed":7,"lit":false,"away":pose == .empty,"clock":"2026-11-05T20:10:00"],"pixels":flatten(Sprites.compose(pose,look,decor:d))])}}
            }
        }
        for i in 0..<48 {
            let c=legacy.copy()
            for (index,s) in Customization.categories.enumerated() {let minimum=s.optional && s.key != "lamp" ? 1 : 0;c.slots[s.key]!.enabled=true;c.slots[s.key]!.value=minimum+(i*7+index*3)%(s.count-minimum)}
            let look=c.legacyLook(Look(girl:i%2==0,2,1,1,2,i%2==0 ? 4 : 0,0).withExtras("00000007"))
            for (name,pose) in [("WriteA",Sprites.Pose.writeA),("DozeA",.dozeA),("WaveA",.waveA),("Empty",.empty)] {for laptop in [false,true] {
                let d=Sprites.Decor(laptop:laptop,seed:7,away:pose == .empty,clock:date)
                fixtures.append(["style":look.code,"extras":look.extra,"customization":c.data(),"pose":name,"decor":["drink":0,"laptop":laptop,"seed":7,"lit":false,"away":pose == .empty,"clock":"2026-11-05T20:10:00"],"pixels":flatten(Sprites.compose(pose,look,decor:d)),"visitor":flatten(Sprites.visitor(look,.walk,alt:true))])
            }}
        }
        save(image,out,"customization.png")
        check(!Customization.categories.contains { $0.key.lowercased().contains("sticker") },"customization: stickers are gone")
        let shared=legacy.data(shared:true)["slots"] as! [String:Any];check(shared["floor"] == nil && (shared["hat"] as! [String:Any])["locked"] == nil,"customization: shared state excludes classroom and locks")
        check(Sprites.compose(.empty,basic).first!.grid[0].count==Sprites.width,"desk: visible art matches layout width")
        check(Departure.bag(18).0==12 && Departure.bag(18).1==22 && Departure.signLift(16)==0,"packing: carry and sign end at their resting positions")
        for t in stride(from:0.0,to:16.0,by:0.02) {let a=Departure.hand(t),b=Departure.hand(t+0.02);check(abs(a.0-b.0)<1 && abs(a.1-b.1)<1,"packing: upright head and continuous hand path")}
        do {try JSONSerialization.data(withJSONObject:fixtures).write(to:out.appendingPathComponent("customization-fixtures.json"))}catch{check(false,"customization fixture export failed")}
    }

    private static func checkRevision(_ out: URL) {
        let legacyLook = Look.parse("g001040", girl: false).withExtras("0020030")
        check(legacyLook.additions == 7 && legacyLook.withAdditions(0).additions == 0, "appearance: legacy defaults and all-off flags")
        func signature(_ look: Look) -> String {
            Sprites.compose(.writeA, look, decor: Sprites.Decor(drink: .beer, seed: 7)).map { "\($0.x),\($0.y):" + $0.grid.joined(separator: "/") }.joined(separator: "|")
        }
        check(signature(legacyLook) == signature(legacyLook.withAdditions(7)), "appearance: explicit legacy mask preserves existing pixels")
        check(signature(legacyLook) != signature(legacyLook.withAdditions(0)), "appearance: unchecked additions change rendered pixels")
        for mask in 0..<8 {
            check(Sprites.grids(legacyLook.withAdditions(mask)).allSatisfy { $0.allSatisfy { $0.allSatisfy(Sprites.isKnownColor) } }, "appearance: optional combinations use known pixel colours")
        }
        let displayKeys = ["largeText", "boardTextSize", "bubbleTextSize", "nameTextSize"]
        let displayBefore = displayKeys.map { ($0, Settings.get($0)) }
        do {
            try Settings.setMany(("largeText", "1"), ("boardTextSize", "200"), ("bubbleTextSize", "150"), ("nameTextSize", "75"))
            check(DisplayPreferences.percent("boardTextSize") == 200 && DisplayPreferences.percent("bubbleTextSize") == 150 && DisplayPreferences.percent("nameTextSize") == 75, "sizes: board, bubble and nickname stay independent")
            try Settings.set("nameTextSize", "")
            check(DisplayPreferences.percent("nameTextSize") == 125 && DisplayPreferences.percent("boardTextSize") == 200, "sizes: legacy fallback respects explicit sizes")
        } catch { check(false, "sizes: settings test could not save") }
        for (key, value) in displayBefore { try? Settings.set(key, value) }
        let interactions = FriendInteractions()
        var friend = Member(id: "friend", state: "off", version: "0.5.0", updated: 1000)
        interactions.observe([friend]); friend.state = "studying"; interactions.observe([friend])
        check(interactions.message(friend, here: true, current: "0.5.1") == FriendInteractions.updateNotice, "friend: newer app offers update before greeting")
        friend.version = "0.5.1"; check(interactions.message(friend, here: true, current: "0.5.1") == "드디어 왔구나 !", "friend: return greeting")
        friend.state = "paused"; interactions.observe([friend]); friend.state = "studying"; interactions.observe([friend])
        check(interactions.message(friend, here: true, current: "0.5.1") == "드디어 깼구나 !", "friend: rest greeting")
        var last = ""
        for _ in 0..<100 { let message = interactions.message(friend, here: true, current: "0.5.1"); check(message != last && message.count <= 20, "friend: no repeated cheer, legacy length"); last = message }
        let sweet = FriendInteractions(); var gumi = Member(id: "g", name: "구미", subject: "", state: "studying", minutes: 0, updated: 1); gumi.version = "0.5.1"
        let said = (0..<200).map { _ in sweet.message(gumi, here: true, current: "0.5.1", me: "포비") }
        check(said.allSatisfy(FriendInteractions.isLove) && said.allSatisfy { $0.count <= 20 } && said.contains(where: FriendInteractions.isPat) && said.contains(where: FriendInteractions.isTreat), "couple: 구미 and 포비 get their own interactions, within the message limit")
        check(!FriendInteractions.isLove(FriendInteractions().message(gumi, here: true, current: "0.5.1", me: "민지")), "couple: nobody else gets them")
        friend.version = ""; check(interactions.message(friend, here: true, current: "0.5.1") == FriendInteractions.updateNotice, "friend: unknown legacy version receives notice")
        let plainLook = Look(girl: false, 0, 0, 0, 0, 0, 0)
        let onLaptop = Sprites.compose(.writeA, plainLook, decor: Sprites.Decor(drink: .mug, laptop: true))
        check(onLaptop.firstIndex { $0.grid == Sprites.art("LaptopOpen") }! > onLaptop.firstIndex { $0.grid == Sprites.art("Desk") }! + 1, "laptop: the lid is drawn over the hands on its keyboard")
        let sip = Sprites.compose(.teaSip, plainLook, decor: Sprites.Decor(drink: .mug)).filter { $0.grid == Sprites.art("Drink2") }
        check(sip.count == 1 && sip[0].y == 14, "tea: the raised cup covers the mouth, and the desk no longer holds a second one")
        func places(_ layers: [Sprites.Layer]) -> [String] { layers.map { "\($0.x),\($0.y)" } }
        let halfway = places(Sprites.compose(.stretchUp, plainLook, from: .restHands, blend: 0.5))
        check(halfway != places(Sprites.compose(.stretchUp, plainLook)) && halfway != places(Sprites.compose(.restHands, plainLook)), "motion: halfway between two poses is neither of them")
        let blend = PoseBlend()
        _ = blend.track(.restHands, 0)
        let blendStart = blend.track(.stretchUp, 10), blendMid = blend.track(.stretchUp, 10 + Sprites.blendTicks(.stretchUp) / 2), blendEnd = blend.track(.stretchUp, 30)
        check(blendStart.from == .restHands && blendStart.blend == 0 && blendMid.blend > 0 && blendMid.blend < 1 && blendEnd.blend == 1, "motion: a new pose eases in from the old one")
        check(Set(Sprites.Pose.allCases.filter { $0 != .empty }.map { $0.rawValue }) == Sprites.rigNames, "poses: the code and the shared data name the same poses")
        save(render(NSSize(width: 480, height: Sprites.windowScenes * 102)) {
            for scene in 0..<Sprites.windowScenes { for season in 0..<4 {
                let grid = Sprites.windowGrid(40,34,sky: 2,season: season,scene: scene)
                check(grid.count == 34 && grid.allSatisfy { $0.count == 40 }, "window: valid variant")
                for sky in 0..<4 { for (w, h) in [(40, 34), (98, 55), (68, 55), (180, 100)] {
                    let any = Sprites.windowGrid(w, h, sky: sky, season: season, scene: scene, drift: 7)
                    check(any.count == h && any.allSatisfy { $0.count == w && $0.allSatisfy { Sprites.isWindowColor($0, sky: sky, season: season) } }, "window: every view, sky and size paints in known colours")
                } }
                if scene > 0 { check(grid != Sprites.windowGrid(40,34,sky: 2,season: season), "window: different scene") }
                Sprites.drawWindow(40,34,sky: 2,season: season,left: CGFloat(season*120),top: CGFloat(scene*102),scale: 3,scene: scene)
            } }
        }, out, "window-variants.png")
        save(render(NSSize(width: 624,height: 630)) {
            for drink in 1...5 { for f in 0..<4 { Sprites.draw([Sprites.Pose.teaReach,.teaHold,.teaLift,.teaSip][f], Look(girl: true,1,0,2,2,0,0), left: CGFloat(f*156),top: CGFloat((drink-1)*126),scale: 3,decor: Sprites.Decor(drink: Sprites.Drink(rawValue: drink)!,laptop: true,seed: 7)) } }
        }, out, "tea.png")
        save(render(NSSize(width: 936,height: 252)) {
            let poses: [Sprites.Pose] = [.writeA,.writeB,.readA,.readB,.bookmark,.turnPage,.restHands,.foldArms,.spinA,.idea,.dozeA,.cheer]
            for (i,pose) in poses.enumerated() { Sprites.draw(pose,Look(girl: true,1,0,2,2,0,0),left: CGFloat(i%6*156),top: CGFloat(i/6*126),scale: 3,decor: Sprites.Decor(laptop: true,seed: 7)) }
        }, out, "laptop.png")
        let appearance = AppearanceWindow(Look(girl: true,2,0,3,2,0,1))
        if let content = appearance.contentView { content.layoutSubtreeIfNeeded(); save(capture(content),out,"appearance.png") }
        appearance.orderOut(nil)
    }

    static func run(outDir: String?, invite: String?) -> Int32 {
        let out = URL(fileURLWithPath: outDir ?? NSTemporaryDirectory() + "StudyPet-selftest")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Records.folder = out.appendingPathComponent("data")
        try? FileManager.default.removeItem(at: Records.folder)

        check(HelpWindow.sections().count == 5, "help: five offline sections are bundled")
        checkCustomization(out)
        checkRevision(out)
        checkRecords()
        checkRecovery()
        checkDeviceTransitions()
        checkUpdater()
        checkPetControls(out)
        checkPresentation(out)
        checkRoom()
        checkSprites()
        save(render(NSSize(width: 3 * Sprites.width * 4, height: Sprites.height * 4)) {
            for (i, pose) in [Sprites.Pose.writeA, .content, .found].enumerated() { Sprites.draw(pose, Look(girl: true, 1, 0, 2, 2, 0, 0), left: CGFloat(i * Sprites.width * 4), top: 0, scale: 4) }
        }, out, "expressions.png")
        save(render(NSSize(width: 4 * Sprites.width * 3, height: 3 * Sprites.height * 3)) {
            for i in 0..<12 {
                let look = Look(girl: i % 2 == 0, i % 8, 0, i % 9, i % 10, 0, 1).withExtras("\(i % 4)\(i % 4)\(i % 3)\(i % 4)\(i % 2)\(i % 4)\(i % 4)")
                Sprites.draw(.writeA, look, left: CGFloat(i % 4 * Sprites.width * 3), top: CGFloat(i / 4 * Sprites.height * 3), scale: 3, decor: Sprites.Decor(drink: .mug, laptop: i % 2 == 0, seed: i))
            }
        }, out, "wardrobe.png")
        save(render(NSSize(width: 8 * Sprites.width * 2, height: Routine.moments * Sprites.height * 2)) {
            for moment in 1...Routine.moments {
                for f in stride(from: 0, to: 24, by: 3) { Sprites.draw(Routine.momentPose(moment, f), Look(girl: true, 0, 0, 0, 0, 0, 0), left: CGFloat(f / 3 * Sprites.width * 2), top: CGFloat((moment - 1) * Sprites.height * 2), scale: 2) }
            }
        }, out, "motion.png")
        if let invite { checkNetwork(invite, out); checkManyRooms(invite) }

        save(render(Sprites.sheetSize(scale: 4)) { Sprites.drawSheet(scale: 4) }, out, "sprites.png")
        save(scenes(), out, "scenes.png")
        let planner = Planner(ranking: [Records.Rank(subject: "영어", month: 270, total: 123 * 60),
                                        Records.Rank(subject: "수학", month: 95, total: 20 * 60),
                                        Records.Rank(subject: "알고리즘 문제풀이 백준", month: 30, total: 30)],
                              anchor: NSRect(x: 0, y: 0, width: 10, height: 10))
        let area = NSScreen.main!.visibleFrame
        check(abs(planner.frame.maxX - (area.maxX - 12)) < 1 && abs(planner.frame.minY - (area.minY + 12)) < 1, "planner: floats just inside the bottom-right corner")
        save(capture(planner.contentView!), out, "planner.png")
        let help = HelpWindow()
        help.orderFront(nil)
        help.contentView?.layoutSubtreeIfNeeded()
        save(capture(help.contentView!), out, "help.png")
        help.close()
        let settings = SettingsWindow(updater: Updater(), apply: {}, login: {}, resize: { _ in })
        settings.orderFront(nil)
        settings.contentView?.layoutSubtreeIfNeeded()
        save(capture(settings.contentView!), out, "settings.png")
        settings.close()
        for count in [0, 1, 8] {
            let page = Planner(ranking: (0..<count).map { _ in Records.Rank(subject: "아주 긴 한글 과목 이름", month: 1234, total: 12345) }, anchor: NSRect(x: 0, y: 0, width: 10, height: 10))
            save(capture(page.contentView!), out, "planner-\(count).png")
        }
        let today = Calendar.current.startOfDay(for: Date())
        func at(_ day: Int, _ hours: Double) -> Date { Calendar.current.date(byAdding: .day, value: day, to: today)!.addingTimeInterval(hours * 3600) }
        let stats = StatsWindow(segments: [
            Segment(start: at(0, 9), end: at(0, 10.5), subject: "영어"),
            Segment(start: at(0, 13), end: at(0, 13.75), subject: "국어"),
            Segment(start: at(-1, 20), end: at(-1, 22), subject: "수학"),
            Segment(start: at(-60, 20), end: at(-60, 23), subject: "수학"),
        ])
        // The subjects tab last: the very first off-screen capture comes out with blank tab labels.
        for (i, name) in [(1, "stats-daily.png"), (2, "stats-monthly.png"), (0, "stats-subjects.png")] {
            stats.tabs.selectTabViewItem(at: i)
            save(capture(stats.contentView!), out, name)
        }

        let report = failures.isEmpty ? "PASS" : "FAIL\n" + failures.joined(separator: "\n")
        try? report.write(to: out.appendingPathComponent("selftest.txt"), atomically: true, encoding: .utf8)
        print(report)
        return failures.isEmpty ? 0 : 1
    }

    private static func checkPetControls(_ out: URL) {
        check(StudyCheer.text(1800).hasPrefix("30분 달성!") && StudyCheer.text(3605).hasPrefix("60분 달성!"), "cheer: half-hour milestones use accumulated study time")
        check(StudyCheer.text(1799).isEmpty && StudyCheer.text(1810).isEmpty && !StudyCheer.text(150).isEmpty && StudyCheer.text(158).isEmpty, "cheer: brief messages return to normal time display")
        check([95, 96, 119, 120, 216, 336, 360].map { Routine.studyMoment($0) } == [0, 1, 1, 0, 2, 3, 0], "moments: stretch, pencil and butterfly briefly rotate")
        check([456, 576, 696, 816, 1296, 1416, 1896].map { Routine.studyMoment($0) } == [4, 5, 6, 7, 11, 12, 16], "moments: all of them play before the cycle repeats")
        check((0..<3600).filter { Routine.studyMoment($0, seed: 37) > 0 }.count == 720 && !(0..<3600).allSatisfy { Routine.studyMoment($0, seed: 37) == Routine.studyMoment($0) },
              "moments: a seatmate acts as often as me, on their own schedule")
        check((1...Routine.moments).allSatisfy { m in !Routine.line(m, 0, laptop: false).isEmpty }, "moments: every moment has a line")
        save(render(NSSize(width: 136, height: 64)) {
            Sprites.color(0xFFFDF4).setFill(); NSRect(x: 0, y: 0, width: 136, height: 64).fill()
            Sprites.drawButterfly(left: 10, top: 8, scale: 4, folded: false)
            Sprites.drawButterfly(left: 78, top: 8, scale: 3, folded: true)
        }, out, "butterfly.png")
        check([0.0, 2.5, 5, 19, 21.5, 24].map(Travel.progress) == [0, 0.5, 1, 1, 0.5, 0], "visit: walk out, greet and return")
        let motion = (0...30).map { Travel.progress(Double($0) * 4 / 30) }
        check(Set(motion).count == 31 && zip(motion, motion.dropFirst()).allSatisfy { $1 > $0 && $1 - $0 < 0.06 }, "motion: thirty smooth monotonic positions per second")
        let mixed = (0..<100).map { _ in Look.random(girl: Bool.random()) }
        check(mixed.contains(where: \.girl) && mixed.contains(where: { !$0.girl }), "look: random decoration includes all genders")
        let pet = PetWindow()
        pet.myName = { "지우" }
        pet.bubbleText = { "영어\n23분째 공부 중" }
        pet.seatmate = { PetWindow.Seat(name: "민지", look: Look.parse("g213402", girl: true), here: true, dozing: false, text: "수학\n32분째 공부 중") }
        pet.rightSeatmate = { PetWindow.Seat(name: "준혁", look: Look.parse("b120310", girl: false), here: true, dozing: true, text: "국어 · 5분\n잠깐 쉬는 중") }
        for percent in PetWindow.displaySizes {
            pet.setDisplaySize(percent)
            pet.preview(.studying, frame: 0)
            pet.orderFrontRegardless()
            save(capture(pet.contentView!), out, "three-seats-\(percent).png")
            check(pet.sizePercent == percent && pet.frame.width <= (NSScreen.main?.visibleFrame.width ?? 10000) && pet.frame.height <= (NSScreen.main?.visibleFrame.height ?? 10000), "size: three seats fit screen at \(percent)")
        }
        let threeWidth = pet.frame.width
        let area = NSScreen.main!.visibleFrame
        pet.setFrameOrigin(NSPoint(x: area.maxX - pet.frame.width, y: area.minY))
        pet.rightSeatmate = { nil }
        pet.preview(.studying, frame: 0)
        save(render(pet.canvasSize) { pet.paint() }, out, "two-seats-left.png")
        let twoWidth = pet.frame.width
        check(twoWidth < threeWidth && abs(pet.frame.maxX - area.maxX) < 1, "layout: removing right desk shrinks window at right screen edge")
        pet.seatmate = { nil }
        pet.board = { ("공부방 · 1/2 ↻", ["지우 · 영어 23분"]) }
        pet.preview(.studying, frame: 0)
        save(render(pet.canvasSize) { pet.paint() }, out, "one-seat-board.png")
        check(pet.frame.width < twoWidth && abs(pet.frame.maxX - area.maxX) < 1, "layout: one desk uses its own width")
        check((0..<Int(pet.canvasSize.height)).contains { pet.hitBoard(NSPoint(x: pet.canvasSize.width / 2, y: CGFloat($0))) } && !pet.hitBoard(.zero), "board: visible chalkboard responds to clicks")
        pet.board = { nil }
        check(!(0..<Int(pet.canvasSize.height)).contains { pet.hitBoard(NSPoint(x: pet.canvasSize.width / 2, y: CGFloat($0))) }, "board: hidden background cannot switch rooms")
        pet.rightSeatmate = { PetWindow.Seat(name: "준혁", look: mixed[0], here: false, dozing: false, text: "자리 비움") }
        pet.preview(.studying, frame: 0)
        save(render(pet.canvasSize) { pet.paint() }, out, "two-seats-right-away.png")
        check(abs(pet.frame.width - twoWidth) < 1, "layout: two desks have equal width on either side")
        // A few frames of each moment, with both seatmates mid-moment too.
        pet.seatmate = { PetWindow.Seat(name: "민지", look: Look.parse("g213402", girl: true), here: true, dozing: false, text: "수학\n32분째 공부 중") }
        for at in (0..<Routine.moments).flatMap({ m in [4, 14].map { m * 120 + 96 + $0 } }) {
            pet.preview(.studying, frame: at)
            save(render(pet.canvasSize) { pet.paint() }, out, "moment-\(at).png")
        }
        pet.preview(.studying,frame:0)
        for _ in 0..<8 {pet.advanceAnimation(25);pet.setMood(.studying)}
        pet.advanceAnimation(5)
        let syncedTick=Mirror(reflecting:pet).children.first(where:{$0.label=="tick"})?.value as? Int
        check(syncedTick==820 && Routine.momentPose(7,4) == .yawn,"sync: repeated studying updates preserve animation until the yawn plays")
        let quietPoses: [Sprites.Pose] = [.writeA, .writeB, .writeC, .writeD, .writePause, .readA, .readB, .pageLift, .turnPage, .pageSettle]
        check((0..<1920).allSatisfy { quietPoses.contains(Routine.focusPose($0)) && quietPoses.contains(Routine.focusPose($0, seed: 7)) },"focus: only writing, reading and turning a page")
        check(PetWindow.cheeredSide(10, -1, "민지에게\n파이팅 !") == -1 && PetWindow.cheeredSide(2, -1, "민지에게\n파이팅 !") == 0 && PetWindow.cheeredSide(10, 1, "민지에게\n일어나 !") == 0 && PetWindow.cheeredSide(-1, 1, "") == 0, "cheer: a friend's eyes light up only once my pet has arrived with a cheer")
        check(Sprites.windowFrames == 5, "window: the dense lattice frame stays removed")
        let colon = Customization.digital(Array(repeating: String(repeating: "1", count: 31), count: 18), Date())
        check(Array(colon[7])[15] == "Y" && Array(colon[9])[15] == "Y" && Array(colon[8])[15] == "1", "clock: the digital face shows its colon")
        for f in 0..<Sprites.windowFrames { check(Sprites.windowGrid(98, 52, sky: 2, season: 1, scene: 0, drift: 0, frame: f).count == 52,"window: every frame style draws") }
        pet.setMood(.dozing)
        check(Mirror(reflecting:pet).children.first(where:{$0.label=="animating"})?.value as? Bool == true,"idle: a mood change wakes the timer at once")
        check((Mirror(reflecting:pet).children.first(where:{$0.label=="tick"})?.value as? Int)==0,"sync: a real mood change still starts its transition")
        pet.appear(.studying)
        pet.minimizeScene()
        pet.visit(mixed[0], text: "화이팅!", side: 0)
        check(pet.minimized && !pet.isVisible, "minimize: incoming visitor does not uncover the scene")
        pet.restoreScene()
        check(!pet.minimized && pet.isVisible, "minimize: scene can be restored")
        pet.orderOut(nil)
        for direction in [-1, 1, 0] {
            for tick in [2, 8, 21] {
                pet.preview(.studying, frame: tick, outgoingTick: Double(tick), outgoingDirection: direction)
                save(render(pet.canvasSize) { pet.paint() }, out, "outgoing-\(direction)-\(tick).png")
            }
        }
        pet.preview(.leaving, frame: 4)
        save(render(pet.canvasSize) { pet.paint() }, out, "farewell.png")
        for laptop in [false, true] {
            pet.laptop = laptop
            for phase in [0, 4, 6, 7, 8, 10, 12, 16, 20, 24, 26] {
                pet.preview(.leaving, frame: phase)
                let kind = laptop ? "laptop" : "book"
                save(render(pet.canvasSize) { pet.paint() }, out, "departure-\(kind)-\(phase).png")
            }
            let actor = Look.parse("b120310", girl: false)
            let onDesk = Sprites.compose(.stand, actor, decor: Sprites.Decor(laptop: laptop, away: true))
            let packed = Sprites.compose(.stand, actor, decor: Sprites.Decor(laptop: laptop, away: true, packed: true))
            let desk = Sprites.compose(.empty, actor)[0].grid
            check(onDesk.count > packed.count && packed.contains { $0.grid == desk }, "packing: work item leaves the desk while the desk stays visible")
            let item = Sprites.packingItemGrid(laptop)
            check(item.count == 14 && item.allSatisfy { $0.count == 3 }, "packing: book and closed laptop fit upright into the bag")
        }
        pet.close()
    }

    private static func checkDeviceTransitions() {
        let minute: Int64 = 60000
        func operation(_ type: String, _ id: String, _ at: Int64, _ device: String, _ source: [String: Any], _ subject: String = "수학") -> [String: Any] {
            ["type":type,"id":id,"at":at,"device":device,"observed":DeviceSync.obj(source,"active"),"subject":subject]
        }
        func total(_ source: [String: Any]) -> Int64 {
            DeviceSync.obj(source,"segments").values.compactMap { $0 as? [String:Any] }.reduce(Int64(0)) { $0 + DeviceSync.num($1,"end") - DeviceSync.num($1,"start") }
        }
        do {
            let empty = DeviceSync.empty()
            let pc = try DeviceSync.transition(empty, operation("start","test-start",1000,"test-pc",empty))
            let phone = try DeviceSync.transition(pc, operation("takeover","test-transfer",1000+20*minute,"test-phone",pc))
            check(DeviceSync.str(DeviceSync.obj(phone,"active"),"device") == "test-phone" && total(phone) == 20*minute,"sync: phone takes over the PC timer at one boundary")
            let late = operation("stop","test-late-stop",1000+35*minute,"test-pc",pc)
            let reconciled = try DeviceSync.transition(phone,late)
            check(DeviceSync.str(DeviceSync.obj(reconciled,"active"),"device") == "test-phone" && total(reconciled) == 20*minute,"sync: a late offline stop cannot stop or extend a phone timer")
            let finished = try DeviceSync.transition(reconciled,operation("stop","test-phone-stop",1000+30*minute,"test-phone",reconciled))
            check(DeviceSync.obj(finished,"active").isEmpty && total(finished) == 30*minute,"sync: twenty PC minutes plus ten phone minutes equals thirty")
            let replay = try DeviceSync.transition(finished,late)
            check(total(replay) == total(finished) && DeviceSync.num(replay,"revision") == DeviceSync.num(finished,"revision"),"sync: acknowledged operations are idempotent")
            let early = try DeviceSync.transition(phone,operation("pause","test-early-pause",1000+15*minute,"test-pc",pc))
            check(total(early) == 15*minute && DeviceSync.str(DeviceSync.obj(early,"active"),"device") == "test-phone","sync: an early offline pause only shortens its old segment")
            let paused = try DeviceSync.transition(pc,operation("pause","test-pause",1000+20*minute,"test-pc",pc))
            let transferredPause = try DeviceSync.transition(paused,operation("takeover","test-paused-transfer",1000+50*minute,"test-phone",paused))
            check(DeviceSync.str(DeviceSync.obj(transferredPause,"active"),"state") == "paused" && total(transferredPause) == 20*minute,"sync: transferring a paused session excludes rest time")
            do { _ = try DeviceSync.transition(pc,operation("stop","test-foreign-stop",1000+minute,"test-phone",pc)); check(false,"sync: foreign stop was accepted") } catch { }
            var imported: [String:Any] = ["id":"test-import","type":"import","at":1000,"device":"test-pc","importId":"test-legacy","segments":["test-row":["start":1000,"end":1000+minute,"subject":"수학"]]]
            let migrated = try DeviceSync.transition(empty,imported)
            let deleted = try DeviceSync.transition(migrated,operation("delete","test-delete",1000+2*minute,"test-pc",migrated))
            imported["id"] = "test-import-retry"
            let retried = try DeviceSync.transition(deleted,imported)
            check(total(retried) == 0,"sync: import retry cannot revive a deleted subject")
        } catch { check(false,"sync: pure transitions failed: \(error)") }
    }

    private static func checkPresentation(_ out: URL) {
        let area = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let high = PetWindow.clampDesk(NSPoint(x: 100, y: 2000), area: area, size: NSSize(width: 600, height: 600), deskTop: 540)
        check(high.y == 1020, "position: the desk reaches the top edge with the transparent area off screen")
        check(PetWindow.clampDesk(NSPoint(x: 100, y: 200), area: area, size: NSSize(width: 600, height: 600), deskTop: 540).y == 200, "position: an ordinary saved position is preserved")
        let pet = PetWindow()
        pet.myName = { "지우" }
        pet.bubbleText = { "영어\n23분째 공부 중" }
        pet.seatmate = { PetWindow.Seat(name: "민지", look: Look.parse("g213402", girl: true), here: true, dozing: false, text: "수학\n32분째 공부 중") }
        pet.rightSeatmate = { PetWindow.Seat(name: "준혁", look: Look.parse("b120310", girl: false), here: true, dozing: false, text: "영어\n공부 시작!") }
        pet.setDisplaySize(100)
        pet.preview(.away, frame: 2)
        let empty = render(pet.canvasSize) { pet.paint() }
        func lowerPixels(_ rep: NSBitmapImageRep) -> [UInt8] {
            var pixels: [UInt8] = []
            for y in (empty.pixelsHigh-10-28)..<(empty.pixelsHigh-10) {
                for x in 0..<empty.pixelsWide where empty.bitmapData![y * empty.bytesPerRow + x * 4 + 3] > 0 {
                    let start = rep.bitmapData!.advanced(by: y * rep.bytesPerRow + x * 4)
                    pixels.append(contentsOf: UnsafeBufferPointer(start: start, count: 4))
                }
            }
            return pixels
        }
        func feetVisible(_ rep: NSBitmapImageRep) -> Bool {
            for y in (empty.pixelsHigh-10-44)..<(empty.pixelsHigh-10) {
                for x in 0..<empty.pixelsWide {
                    if empty.bitmapData![y * empty.bytesPerRow + x * 4 + 3] == 0 && rep.bitmapData![y * rep.bytesPerRow + x * 4 + 3] > 0 { return true }
                }
            }
            return false
        }
        var sawFeet = false
        for side in [-1, 1, 0] {
            for time in [2.0, 8, 21] {
                pet.preview(.away, frame: 2, visitTick: time, friend: Look.parse("g213402", girl: true), friendText: "민지 : 화이팅!", incomingDirection: side)
                let incoming = render(pet.canvasSize) { pet.paint() }
                save(incoming, out, "behind-incoming-\(side)-\(Int(time)).png")
                sawFeet = sawFeet || feetVisible(incoming)
                pet.preview(.away, frame: 2, outgoingTick: time, outgoingDirection: side)
                let outgoing = render(pet.canvasSize) { pet.paint() }
                check(lowerPixels(empty) == lowerPixels(incoming) && lowerPixels(empty) == lowerPixels(outgoing), "visit: bodies stay behind all desks at \(side)/\(time)")
            }
        }
        check(sawFeet, "visit: walking feet remain visible below desk height in open space")
        pet.setUpdateAvailable(true)
        pet.advanceAnimation(3600)
        check(pet.updateText.isEmpty, "update: speech returns to study after eight seconds")
        pet.preview(.studying, frame: 0)
        save(render(pet.canvasSize) { pet.paint() }, out, "update-bubble.png")
        pet.minimizeScene()
        pet.setUpdateAvailable(false)
        pet.setUpdateAvailable(true)
        check(pet.minimized && !pet.isVisible, "update: hidden classroom stays hidden")
        pet.restoreScene()
        check(pet.updateText == PetWindow.updateMessage, "update: announcement returns on restore")
        pet.setUpdateAvailable(false)
        check(pet.updateText.isEmpty, "update: current version clears announcement")
        pet.close()
    }

    private static func checkManyRooms(_ code: String) {
        guard let base = Invite.parse(code), base.key.isEmpty else { return }
        let invite = base.withRoom(Room.randomId(20)), second = Room.randomId(20)
        let owner = Room.randomId(12), friend = Room.randomId(12), other = Room.randomId(12)
        func patch(_ body: [String: Any]) {
            let data = Room.json(body)
            _ = finish { try await Room.call("PATCH", invite.url("", ""), data) }
        }
        patch(["rooms/\(invite.roomId)/owner": owner, "rooms/\(invite.roomId)/name": "첫 방", "rooms/\(second)/owner": owner, "rooms/\(second)/name": "둘째 방",
               "rooms/\(invite.roomId)/approved/\(owner)": true, "rooms/\(second)/approved/\(owner)": true,
               "rooms/\(invite.roomId)/approved/\(friend)": true, "rooms/\(second)/approved/\(friend)": true, "rooms/\(second)/approved/\(other)": true,
               "access/\(owner)/\(invite.roomId)": true, "access/\(owner)/\(second)": true,
               "access/\(friend)/\(invite.roomId)": true, "access/\(friend)/\(second)": true, "access/\(other)/\(second)": true])
        let a = StudyRooms(invite: invite, me: owner, token: { "" })
        let b = StudyRooms(invite: invite, me: friend, token: { "" })
        let c = StudyRooms(invite: invite, me: other, token: { "" })
        var seen: [Member] = [], received = false, ready = false
        b.changed = { seen = $0 }
        c.changed = { _ in ready = true }
        c.poked = { received = $0.from == friend }
        func status(_ name: String, _ minutes: Int) -> [String: Any] {
            ["name": name, "look": "boy", "style": "b120310", "state": "studying", "subject": "수학", "minutes": minutes, "updated": Room.serverTime]
        }
        a.publish(status("방장", 5)); b.publish(status("친구", 17)); c.publish(status("다른 친구", 2))
        check(waitFor { a.choices.count == 2 && b.choices.count == 2 && seen.count == 3 && ready }, "multi-room: all allowed rooms and cross-room friends are visible")
        for id in [invite.roomId, second] {
            try? b.select(id)
            check(waitFor { b.boardMembers.contains { $0.id == friend && $0.minutes == 17 } }, "multi-room: one elapsed time is mirrored to every allowed room")
            check(b.boardMembers.contains { $0.id == owner }, "multi-room: the owner appears in all rooms")
        }
        check(Set(seen.map(\.id)).count == seen.count, "multi-room: shared members are deduplicated")
        // The first optional desk write fails; an identical heartbeat must repair it.
        let deskProbe = Room(invite: invite, me: friend, token: { "" }, followSeat: false)
        _ = finish { try await Room.call("POST", invite.database + "/__test/fail-next", Data("PUT".utf8)) }
        var decorated = status("친구", 17); decorated["desk"] = 15
        deskProbe.publish(decorated); deskProbe.flush()
        deskProbe.publish(decorated)
        check(waitFor { a.boardMembers.contains { $0.id == friend && $0.drink == .soju && $0.laptop } }, "desk: identical heartbeat retries a failed drink/laptop write")
        deskProbe.flush(); deskProbe.dispose()
        let recovery = Room(invite: invite, me: friend, token: { "" }, followSeat: false, listenToRoom: false)
        _ = finish { try await Room.call("POST", invite.database + "/__test/fail-next", Data("PATCH:401".utf8)) }
        recovery.publish(status("친구", 17)); recovery.flush()
        check(waitFor { !recovery.error.isEmpty }, "presence: a refused write is reported")
        recovery.publish(status("친구", 17)); recovery.flush()
        check(waitFor { recovery.error.isEmpty }, "presence: successful retry clears refusal without a stream reconnect")
        recovery.dispose()

        let selected = b.selected
        try? b.next()
        check(b.selected != selected && b.boardMembers.contains { $0.id == friend && $0.minutes == 17 }, "board: cycling retains elapsed minutes")
        try? b.next()
        check(b.selected == selected, "board: last room wraps to first")
        try? b.select(invite.roomId)
        b.poke(other, ["from": friend, "name": "친구", "look": "boy", "message": "같이 공부하자 !", "at": Room.serverTime])
        check(waitFor { received }, "multi-room: poke reaches another room's member while viewing the first board")
        patch(["access/\(friend)/\(invite.roomId)": NSNull(), "rooms/\(invite.roomId)/approved/\(friend)": NSNull(), "rooms/\(invite.roomId)/members/\(friend)": NSNull(), "rooms/\(invite.roomId)/names/\(friend)": NSNull()])
        check(waitFor { b.choices.count == 1 && b.selected == second }, "multi-room: revoked room disappears and selection falls back")
        try? b.next()
        check(b.selected == second, "board: single room keeps its selection")
        a.leave(); b.leave(); c.leave(); a.flush(); b.flush(); c.flush()
        a.dispose(); b.dispose(); c.dispose()
    }

    private static func checkUpdater() {
        let hash = String(repeating: "a", count: 64)
        let json = "{\"tag_name\":\"v1.2.3\",\"draft\":false,\"prerelease\":false,\"assets\":[{\"name\":\"StudyPet-mac.zip\",\"size\":123,\"digest\":\"sha256:\(hash)\",\"browser_download_url\":\"\(UpdateRelease.root)v1.2.3/StudyPet-mac.zip\"}]}"
        let parsed = try? UpdateRelease.parse(Data(json.utf8))
        check(parsed?.version == [1, 2, 3] && parsed?.hash == hash && parsed?.size == 123, "update: stable release metadata is read")
        for bad in ["null", "{}", "{", json.replacingOccurrences(of: "v1.2.3", with: "v1.2.3-beta"),
                    json.replacingOccurrences(of: "\"draft\":false", with: "\"draft\":true"),
                    json.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true"),
                    json.replacingOccurrences(of: "https://github.com/", with: "http://github.com/"),
                    json.replacingOccurrences(of: "study-pet-releases/releases/download", with: "other-repo/releases/download"),
                    json.replacingOccurrences(of: "sha256:", with: "sha512:"), json.replacingOccurrences(of: hash, with: "bad")] {
            check((try? UpdateRelease.parse(Data(bad.utf8))) == nil, "update: invalid release was accepted")
        }
        let payload = Records.folder.appendingPathComponent("hash-fixture.txt")
        try? Data("abc".utf8).write(to: payload)
        check((try? Updater.hash(payload)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "update: SHA256 matches known bytes")
        for mode in ["studying", "paused"] {
            let raw = try? UpdateSession(state: mode, subject: "수학", seconds: 1234.567).encode()
            let saved = raw.flatMap(UpdateSession.parse)
            check(saved?.state == mode && saved?.subject == "수학" && saved?.seconds == 1234.567, "update: study/paused state retains elapsed time")
        }
        for bad in ["null", "{}", "{", "{\"state\":\"studying\",\"subject\":\"수학\",\"seconds\":-1}"] {
            check(UpdateSession.parse(bad) == nil, "update: invalid resume state is ignored")
        }
        check(UpdateRedirects.allowed(URL(string: "https://release-assets.githubusercontent.com/file")!) &&
              !UpdateRedirects.allowed(URL(string: "http://github.com/file")!) &&
              !UpdateRedirects.allowed(URL(string: "https://github.com.evil.example/file")!), "update: redirects stay on HTTPS GitHub release hosts")
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

    private static func checkRecovery() {
        let original = Records.folder
        Records.folder = original.appendingPathComponent("recovery-" + UUID().uuidString)
        defer { Records.folder = original }
        let start = Date(timeIntervalSince1970: 1793581200)
        do {
            try Records.saveOpen(start: start, lastSeen: start.addingTimeInterval(900), subject: "복구")
            try Records.append(Segment(start: start, end: start.addingTimeInterval(1200), subject: "복구"))
            try Records.recoverOpen(); try Records.recoverOpen()
            let rows = try Records.load()
            check(rows.count == 1 && rows.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } == 1200, "recovery: 20 minutes stays 20")
        } catch { check(false, "recovery: " + describe(error)) }
    }

    private static func checkRoom() {
        var tree = Room.applyEvent([:], "put", "/",
                                   json(#"{"members":{"aaa":{"name":"민지","state":"studying","look":"girl","style":"g213402","minutes":32,"updated":1000}}}"#))
        var only = Room.members(tree)
        check(only.count == 1 && only[0].name == "민지" && only[0].look == Look(girl: true, 2, 1, 3, 4, 0, 2) && only[0].minutes == 32 && only[0].updated == 1000,
              "room: put / loads members with their look")
        tree = Room.applyEvent(tree, "put", "/versions/aaa", "0.5.0")
        check(Room.members(tree).first?.version == "0.5.0", "room: optional peer version parsed")
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

        // Who's here, and how it reads.
        let now: Int64 = 10_000_000
        func m(_ id: String, _ name: String, _ state: String, _ age: Int64, _ minutes: Int = 0, _ subject: String = "") -> Member {
            Member(id: id, name: name, subject: subject, state: state, minutes: minutes, updated: now - age)
        }
        var members = [m("me", "나", "studying", 0), m("a", "민지", "studying", 30_000, 32, "수학"), m("b", "준혁", "paused", 60_000, 65),
                       m("c", "서연", "off", 0), m("d", "하늘", "studying", Room.staleMs + 1)]
        var board = Room.board(members, now: now)
        check(board.title == "공부 중 2 / 쉬는 중 1 / 노는 중 2" && board.lines == ["민지 · 수학 32분", "나 · 방금 시작", "준혁 · 쉬는 중", "서연 · 1분째 노는 중", "하늘 · 3분째 노는 중"],
              "board: study, rest and absent people keep individual rows: \(board.lines)")
        members += [m("e", "가람", "studying", 0), m("f", "다온", "studying", 0, 0, "국어")]
        board = Room.board(members, now: now)
        check(board.title == "공부 중 4 / 쉬는 중 1 / 노는 중 2" && board.lines.count == 7 && board.lines.contains("다온 · 국어 방금 시작"), "board: a line per person")
        check(Room.board([]).title == "공부 중 0 / 쉬는 중 0 / 노는 중 0", "board: empty room counts are explicit")
        check(Room.board((0..<9).map { m("x\($0)", "친구\($0)", "studying", 0, $0) }).lines.count == 9,
              "board: nine active people fit in five rows")

        let before = Array(members.prefix(4))
        let after = [m("me", "나", "studying", 0), m("a", "민지", "studying", 0, 33, "수학"), m("b", "준혁", "studying", 0, 65),
                     m("c", "서연", "studying", 0), m("g", "하준", "studying", 0)]
        let started = Room.newlyStarted(before: before, after: after, me: "me")
        check(started == ["서연", "하준"], "news: only people who weren't here before: \(started)")
        check(Room.startedText(started) == "서연, 하준이 공부를 시작했어요 !", "news: 이 after 준")
        check(Room.startedText(["민지"]) == "민지가 공부를 시작했어요 !", "news: 가 after 지")
        check(Room.withSubjectMarker("Amy") == "Amy가", "particle: 가 after a non-Hangul name")
        check(Room.companyText(Array(after.prefix(4)), me: "me") == "민지, 서연, 준혁도 같이 공부하고 있어요 !", "company: everyone else studying")
        check(Room.companyText(after, me: "me") == "민지, 서연 외 2명도 같이 공부하고 있어요 !", "company: more than three are counted")
        check(Room.companyText(Array(members.prefix(4)), me: "me") == "민지도 같이 공부하고 있어요 !", "company: paused and off left out")
        check(Room.companyText([m("me", "나", "studying", 0)], me: "me") == "", "company: nothing when alone")

        let hour: Int64 = 3_600_000
        var missed = Poke(at: now - 2 * hour)
        check(Room.deliverPoke(&missed, lastPokeAt: -1, now: now) && missed.missed, "missed poke: one waiting from two hours ago is shown, marked missed")
        var old = Poke(at: now - 13 * hour)
        check(!Room.deliverPoke(&old, lastPokeAt: -1, now: now), "missed poke: older than 12 hours is dropped")
        var undated = Poke(at: 0)
        check(!Room.deliverPoke(&undated, lastPokeAt: -1, now: now), "missed poke: no time is dropped")
        var live = Poke(at: now)
        check(Room.deliverPoke(&live, lastPokeAt: 5, now: now) && !live.missed, "poke: a new one while connected is live")
        var again = Poke(at: 5)
        check(!Room.deliverPoke(&again, lastPokeAt: 5, now: now), "poke: the same one twice is shown once")

        let latest = Room.latest(members)
        check(Room.seatText(members[1], here: Room.isHere(members[1], latest)) == "수학\n32분째 공부 중", "seat: studying text")
        check(Room.seatText(members[2], here: Room.isHere(members[2], latest)) == "공부 · 1시간 5분\n잠깐 쉬는 중", "seat: paused text")
        check(Room.seatText(members[4], here: Room.isHere(members[4], latest), now: now) == "3분째 노는 중", "seat: gone quiet reads as away")
        check(Room.awayText(Member(id: "x", name: "x", subject: "", state: "off", minutes: 5 * 60, updated: 1), now: 1 + 3 * 3_600_000) == "8시간째 노는 중" && Room.awayText(Member(id: "x", name: "x", subject: "", state: "off", minutes: 0, updated: 1), now: 1 + 200 * 3_600_000) == "200시간째 노는 중" && Room.awayText(m("x", "x", "off", 59 * 60_000), now: now) == "59분째 노는 중", "away: minutes under an hour, then always hours, counting time before the app was reopened")
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
        check(pasted?.url("rooms/x", "a+b/c") == "https://pet-1-default-rtdb.asia-southeast1.firebasedatabase.app/rooms/x.json?auth=a%2Bb%2Fc",
              "invite: the token is escaped in the URL")
        let id = Room.randomId(12)
        check(id.count == 12 && id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }, "id: 12 lowercase letters and digits")
        check(Room.cleanName(" 민\t지 ") == "민지" && Room.cleanName(String(repeating: "가", count: 20)).count == Room.maxNameLength, "name: cleaned and cut")
        check(Look.parse("g213402", girl: false).code == "g213402" && Look.parse("b219999", girl: false).code == "b210913",
              "look: codes round-trip; boys' bottoms fold to trousers")
        check(Look.parse("nonsense", girl: true) == Look(girl: true, 0, 0, 2, 2, 0, 0), "look: a bad code is the plain look")
    }

    private static func checkSprites() {
        for i in 0..<24 {
            let look = Look(girl: i % 2 == 1, i / 2 % Look.hairStyles, i % Look.hairColors, i % Look.tops, (i * 3) % 10, i % 8, i % 6).withExtras("\(i % 4)\(i % 4)\(i % 3)\(i % 4)\(i % 2)\(i % 4)\(i % 4)")
            for grid in Sprites.grids(look) {
                check(grid.allSatisfy { $0.count == grid[0].count }, "sprite: ragged grid starting \(grid[0])")
                check(grid.allSatisfy { $0.allSatisfy(Sprites.isKnownColor) }, "sprite: unknown colour in grid starting \(grid[0])")
            }
            for pose in Sprites.Pose.allCases {
                // Moments stop while a visitor taps, so only writing and dozing pets jump.
                let tapped = [Sprites.Pose.writeA, .writeB, .dozeA, .dozeB].contains(pose)
                for layer in Sprites.compose(pose, look, alert: tapped, lift: tapped ? 1 : 0) + Sprites.compose(pose, look) {
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

    /// A friend asks to join, waits, is let in, and pokes the owner; the owner leaves.
    private static func checkNetwork(_ code: String, _ out: URL) {
        guard let base = Invite.parse(code), base.key.isEmpty else {
            check(false, "network: needs a local test server invite, got \(code)")
            return
        }
        let invite = Invite(database: base.database, roomId: Room.randomId(20), key: "")
        let owner = Room.randomId(12), friend = Room.randomId(12)
        func ownerWrites(_ method: String, _ path: String, _ body: Any?) {
            let data = body.flatMap(Room.json)
            _ = finish { try await Room.call(method, invite.url(path, ""), data) }
        }
        // What the Windows owner does on creating the room.
        ownerWrites("PUT", "rooms/\(invite.roomId)/owner", owner)
        ownerWrites("PUT", "rooms/\(invite.roomId)/approved/\(owner)", true)

        _ = finish { try await Room.request(invite, me: friend, token: "", ["name": "다라", "realName": "김다라", "referrer": "가나",
                                                                         "look": "boy", "style": "b120310", "at": Room.serverTime]) }
        check(finish { try await Room.check(invite, me: friend, token: "") } == .waiting, "network: the friend waits for approval")
        let request = finish { try await Room.call("GET", invite.url("requests/\(invite.roomId)/\(friend)", ""), nil) } ?? ""
        check(request.contains("\"realName\":\"김다라\"") && request.contains("\"referrer\":\"가나\"") && request.contains("\"at\":"),
              "network: the request carries what the owner's card shows: \(request)")
        _ = finish { try await Room.cancelRequest(invite, me: friend, token: "") }
        check(finish { try await Room.check(invite, me: friend, token: "") } == .rejected, "network: a withdrawn request reads as not waiting")
        _ = finish { try await Room.request(invite, me: friend, token: "", ["name": "다라", "realName": "김다라", "referrer": "가나",
                                                                         "look": "boy", "style": "b120310", "at": Room.serverTime]) }
        // What the Windows owner does on 승인.
        ownerWrites("PUT", "rooms/\(invite.roomId)/approved/\(friend)", true)
        ownerWrites("DELETE", "requests/\(invite.roomId)/\(friend)", nil)
        check(finish { try await Room.check(invite, me: friend, token: "") } == .approved, "network: the friend is let in")

        let a = Room(invite: invite, me: owner, token: { "" })
        let b = Room(invite: invite, me: friend, token: { "" })
        var seenByB: [Member]?
        var aReady = false
        var pokeAtA: Poke?
        a.changed = { _ in aReady = true }
        a.poked = { pokeAtA = $0 }
        b.changed = { seenByB = $0 }
        a.publish(["name": "가나", "look": "girl", "style": "g213402", "state": "studying", "subject": "영어", "minutes": 5, "updated": Room.serverTime, "desk": 15])
        b.publish(["name": "다라", "look": "boy", "style": "b120310", "state": "paused", "subject": "수학", "minutes": 12, "updated": Room.serverTime])
        check(waitFor { seenByB?.contains { $0.id == owner && $0.name == "가나" && $0.state == "studying" && $0.look.code == "g213402" && $0.updated > 0 } == true },
              "network: B should see A studying (A: \(a.error) B: \(b.error))")
        check(waitFor { seenByB?.contains { $0.id == owner && $0.drink == .soju && $0.laptop } == true },
              "network: B should see A's soju and laptop, which needs the rules allowing desks/ (A: \(a.error))")
        check(waitFor { aReady }, "network: A should get its first snapshot")
        b.poke(owner, ["from": friend, "name": "다라", "look": "boy", "style": "b120310", "message": "일어나 !", "at": Room.serverTime])
        check(waitFor { pokeAtA != nil }, "network: A should be poked (B: \(b.error))")
        check(pokeAtA?.from == friend && pokeAtA?.message == "일어나 !" && pokeAtA?.look.code == "b120310", "network: the poke arrives intact")

        // What the Windows owner does on naming the room and moving the friend to another one.
        ownerWrites("PUT", "rooms/\(invite.roomId)/name", "1반")
        check(waitFor { b.name == "1반" }, "network: the room's name arrives (\(b.name))")
        var movedTo: [String] = []
        b.moved = { movedTo.append($0) }
        let other = Room.randomId(20)
        ownerWrites("PUT", "seats/\(friend)", invite.roomId) // seated where I already am: stay
        ownerWrites("PUT", "seats/\(friend)", other)
        check(waitFor { movedTo == [other] }, "network: being seated in another room is noticed, once: \(movedTo)")
        check(Invite.parse(invite.code)?.withRoom(other).code == "\(invite.database)/rooms/\(other)", "invite: same database, other room")

        // The room as the Mac app wrote it, with one poke left waiting, for the Windows app to read.
        b.poke("macselftest0", ["from": friend, "name": "다라", "look": "boy", "style": "b120310", "message": "화이팅 !", "at": Room.serverTime])
        b.flush()
        a.flush()
        if let text = finish({ try await Room.call("GET", invite.url("rooms/\(invite.roomId)", ""), nil) }) {
            try? text.write(to: out.appendingPathComponent("room.json"), atomically: true, encoding: .utf8)
        }

        a.leave()
        a.flush()
        check(waitFor { seenByB != nil && !seenByB!.contains { $0.id == owner && $0.state != "off" } }, "network: B should see A leave")
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
        // Native content views are transparent; include the window's backing colour.
        let cg = CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
        cg.setFillColor(NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB)!.cgColor)
        cg.fill(rect)
        cg.draw(rep.cgImage!, in: rect)
        return NSBitmapImageRep(cgImage: cg.makeImage()!)
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
            pet.preview(mood, frame: frame, visitTick: Double(visitTick), friend: friend, friendText: friendText)
            shots.append(render(pet.canvasSize) { pet.paint() })
        }

        // With the classroom: a full board, then a short one with news above my bubble.
        mine = "영어\n23분째 공부 중"
        seat = PetWindow.Seat(name: "민지", look: minji, here: true, dozing: false, text: "수학\n32분째 공부 중")
        board = ("공부 중 4 · 쉬는 중 1", ["민지 · 수학 32분", "준혁 · 영어 1시간 5분", "다온 · 국어 방금 시작", "서연 · 과학 12분", "하준 · 쉬는 중"])
        shot(.studying)
        seat = PetWindow.Seat(name: "준혁", look: junhyuk, here: false, dozing: false, text: "자리 비움")
        mine = "영어\n공부 시작!"
        news = "다온이 공부를 시작했어요 !"
        board = ("지금 공부 중 · 1명", ["다온 · 국어 방금 시작"])
        shot(.studying)
        // Background hidden: dozing, then the seatmate walking over and tapping (hand down).
        news = ""
        mine = "영어 · 23분\n잠깐 쉬는 중"
        seat = PetWindow.Seat(name: "민지", look: minji, here: true, dozing: false, text: "수학\n32분째 공부 중")
        board = nil
        shot(.dozing, frame: 1, visitTick: 2, friendText: "민지 : 일어나 !")
        shot(.dozing, frame: 6, visitTick: 6, friendText: "민지 : 일어나 !")
        // A visit while I'm not studying: the friend waves at my empty desk.
        seat = nil
        board = ("친구를 초대하면 여기에 적혀요", [])
        shot(.away, frame: 2, visitTick: 2, friend: junhyuk, friendText: "준혁 : 같이 공부하자 !")
        shot(.away, frame: 8, visitTick: 8, friend: junhyuk, friendText: "준혁 : 같이 공부하자 !")

        let w = CGFloat(shots.map { $0.pixelsWide }.max()!), h = CGFloat(shots.map { $0.pixelsHigh }.max()!)
        return render(NSSize(width: 2 * w, height: CGFloat((shots.count + 1) / 2) * h)) {
            Sprites.color(0xC9CFC4).setFill()
            NSRect(x: 0, y: 0, width: 2 * w, height: CGFloat((shots.count + 1) / 2) * h).fill()
            for (i, image) in shots.enumerated() {
                let cell = NSRect(x: CGFloat(i % 2) * w, y: CGFloat(i / 2) * h, width: w, height: h)
                let rect = NSRect(x: cell.midX - CGFloat(image.pixelsWide) / 2, y: cell.maxY - CGFloat(image.pixelsHigh), width: CGFloat(image.pixelsWide), height: CGFloat(image.pixelsHigh))
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSColor.gray.setStroke()
                NSBezierPath(rect: cell.insetBy(dx: 0.5, dy: 0.5)).stroke()
            }
        }
    }
}
