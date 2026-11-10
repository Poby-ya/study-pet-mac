import AppKit

/// One pet's appearance, the same code as Look in the Windows app's Sprites.cs: gender,
/// then one digit each for hairstyle, hair colour, top, top colour, bottoms and ribbon
/// colour ("g213402"). An older version reads each digit modulo its own, smaller counts.
struct Look: Equatable {
    static let hairStyles = 8
    static let hairColors = 5
    static let tops = 9
    static let topColors = 10
    static let bottoms = 8     // 0-3 trousers, 4-7 skirt (girls only)
    static let ribbons = 6

    var customization: Customization?
    func withCustomization(_ value: Customization?) -> Look {var result=self;result.customization=value;return result}
    var extra = "0000000"
    var accessory: Int { Int(Array(extra)[0].asciiValue! - 48) }
    var skin: Int { Int(Array(extra)[1].asciiValue! - 48) }
    var hat: Int { Int(Array(extra)[2].asciiValue! - 48) }
    var sleeve: Int { Int(Array(extra)[3].asciiValue! - 48) }
    var leftHanded: Bool { Array(extra)[4] == "1" }
    var bag: Int { Int(Array(extra)[6].asciiValue! - 48) }
    // Older seven-digit looks keep all additions visible.
    var additions: Int { extra.count == 8 ? Int(Array(extra)[7].asciiValue! - 48) : 7 }
    func withAdditions(_ value: Int) -> Look { withExtras(String(extra.prefix(7)) + String(value & 7)) }
    func withExtras(_ value: String) -> Look {
        var result = self
        result.extra = value.range(of: "^[0-3][0-3][0-2][0-3][0-1][0-3][0-3][0-7]?$", options: .regularExpression) != nil ? value : "0000000"
        return result
    }
    let girl: Bool
    let hair: Int
    let hairColor: Int
    let top: Int
    let topColor: Int
    let bottom: Int
    let ribbon: Int

    init(girl: Bool, _ hair: Int, _ hairColor: Int, _ top: Int, _ topColor: Int, _ bottom: Int, _ ribbon: Int) {
        self.girl = girl
        self.hair = hair % Look.hairStyles
        self.hairColor = hairColor % Look.hairColors
        self.top = top % Look.tops
        self.topColor = topColor % Look.topColors
        self.bottom = girl ? bottom % Look.bottoms : bottom % 4
        self.ribbon = ribbon % Look.ribbons
    }

    var skirt: Bool { bottom >= 4 }

    var code: String { "\(girl ? "g" : "b")\(hair)\(hairColor)\(top)\(topColor)\(bottom)\(ribbon)" }

    /// A friend on an older version sends no code; they get a plain look of their gender.
    static func parse(_ code: String, girl: Bool) -> Look {
        guard code.range(of: "^[bg][0-9]{6}$", options: .regularExpression) != nil else {
            return Look(girl: girl, 0, 0, girl ? 2 : 0, girl ? 2 : 0, 0, 0)
        }
        let d = code.unicodeScalars.map { Int($0.value) - 48 }
        return Look(girl: code.hasPrefix("g"), d[1], d[2], d[3], d[4], d[5], d[6])
    }

    static func random(girl: Bool) -> Look {
        Look(girl: girl, .random(in: 0..<hairStyles), .random(in: 0..<hairColors), .random(in: 0..<tops),
             .random(in: 0..<topColors), .random(in: 0..<(girl ? bottoms : 4)), .random(in: 0..<ribbons))
    }
}
/// The pets as pixel art: grids of characters where one character is one pixel ('.' is
/// transparent). All art, colours, poses and routines come from Shared/customization.json (see
/// tools/build-customization.cjs); this composes them, pixel for pixel like Sources/Sprites.cs.
enum Sprites {
    static let width = 52
    static let height = 40
    static let clockSize = 31

    /// The person sits a little right of the desk's middle, leaving the left end of the
    /// desk top free for the nameplate (cols 1..16).
    static let dx = 15

    enum Pose: String, CaseIterable {
        case empty = "Empty", writeA = "WriteA", writeB = "WriteB", writeC = "WriteC", writeD = "WriteD", writePause = "WritePause", ponder = "Ponder", readA = "ReadA", readB = "ReadB", bookNudgeA = "BookNudgeA", bookNudgeB = "BookNudgeB", restHands = "RestHands", content = "Content", glanceLeft = "GlanceLeft", glanceRight = "GlanceRight", lookLeft = "LookLeft", lookRight = "LookRight", lookUp = "LookUp", lookWindow = "LookWindow"
        case pageLift = "PageLift", turnPage = "TurnPage", pageSettle = "PageSettle", bookmark = "Bookmark", stretchHalf = "StretchHalf", stretchUp = "StretchUp", stretchLeft = "StretchLeft", stretchRight = "StretchRight", oops = "Oops", oopsFall = "OopsFall", bend = "Bend", pickUp = "PickUp", recover = "Recover", found = "Found"
        case teaReach = "TeaReach", teaHold = "TeaHold", teaLift = "TeaLift", teaSip = "TeaSip", cheer = "Cheer", yawnStart = "YawnStart", yawn = "Yawn", yawnEnd = "YawnEnd", nodA = "NodA", nodB = "NodB", nodC = "NodC", startle = "Startle", munchA = "MunchA", munchB = "MunchB", cookieSmall = "CookieSmall", crumbs = "Crumbs"
        case think = "Think", idea = "Idea", spinA = "SpinA", spinB = "SpinB", spinC = "SpinC", spinD = "SpinD", chinRest = "ChinRest", chinRestB = "ChinRestB", scratchA = "ScratchA", scratchB = "ScratchB", neckLeft = "NeckLeft", neckRight = "NeckRight", eraseA = "EraseA", eraseB = "EraseB", blowCrumbs = "BlowCrumbs"
        case foldArms = "FoldArms", dozeA = "DozeA", dozeB = "DozeB", stand = "Stand", waveA = "WaveA", waveB = "WaveB", packR = "PackR", packBoth = "PackBoth", packWaveA = "PackWaveA", packWaveB = "PackWaveB"
    }

    /// A friend on their feet: walking, carrying a bag (their left arm is the one holding it),
    /// waving, cheering, with the right arm held out to tap (the arm itself comes from
    /// `reachLayers`), or just standing.
    enum Visiting: CaseIterable { case walk, carry, wave, reach, cheer, stand }

    /// A drink at the right end of the desk, picked at random for each study session.
    enum Drink: Int { case none, icedCoffee, mug, can, beer, soju }
    static let drinks = 5

    struct Layer {
        let grid: [String]
        let x: Int
        let y: Int
        init(_ grid: [String], _ x: Int, _ y: Int) {
            self.grid = grid
            self.x = x
            self.y = y
        }
    }

    static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    private static func color(_ hex: String) -> NSColor { color(Int(hex.dropFirst(), radix: 16) ?? 0) }
    private static func colors(_ table: [String: String]) -> [Character: NSColor] {
        var out: [Character: NSColor] = [:]
        for (key, value) in table { out[Character(key)] = color(value) }
        return out
    }
    static func art(_ name: String) -> [String] { Customization.artwork(name) }

    private static let root = Customization.root
    private static let colorData = root["colors"] as! [String: Any]
    private static let palette = colors(root["palette"] as! [String: String])
    private static let hairColorSet = (colorData["hair"] as! [[String]]).map { $0.map { color($0) } }
    private static let topColorSet = (colorData["tops"] as! [[String]]).map { $0.map { color($0) } }
    private static let bottomColorSet = (colorData["bottoms"] as! [String]).map { color($0) }
    private static let ribbonSet = (colorData["ribbons"] as! [String]).map { color($0) }
    private static let skinSet = (colorData["skins"] as! [String]).map { color($0) }

    private struct ArmRig {
        var elbowX: Int, elbowY: Int, handX: Int, handY: Int, layer: Int
        var flipped: ArmRig { ArmRig(elbowX: 30 - elbowX, elbowY: elbowY, handX: 30 - handX, handY: handY, layer: layer) }
        init?(_ value: Any?) {
            guard let a = value as? [Int], a.count >= 4 else { return nil }
            elbowX = a[0]; elbowY = a[1]; handX = a[2]; handY = a[3]; layer = a.count > 4 ? a[4] : 2
        }
        init(elbowX: Int, elbowY: Int, handX: Int, handY: Int, layer: Int) {
            self.elbowX = elbowX; self.elbowY = elbowY; self.handX = handX; self.handY = handY; self.layer = layer
        }
    }
    private struct Rig {
        var eyes = "Open", mouth = "Small"
        var book: String?, lap: String?, drink: String?, mark: String?, itemArt: String?, itemSide: String?
        var y = 4, b = 20, x = 0, z = 0, itemX = 0, itemY = 0
        var front = false, flip = false
        var blend = 1.0
        var l: ArmRig?, r: ArmRig?
        var p: [Int]?
        init(_ d: [String: Any]) {
            eyes = d["e"] as? String ?? "Open"; mouth = d["m"] as? String ?? "Small"
            book = d["book"] as? String; lap = d["lap"] as? String; drink = d["drink"] as? String; mark = d["mark"] as? String
            y = d["y"] as? Int ?? 4; b = d["b"] as? Int ?? 20; x = d["x"] as? Int ?? 0; z = d["z"] as? Int ?? 0
            front = d["front"] != nil; flip = d["flip"] != nil
            blend = d["blend"] as? Double ?? 1
            l = ArmRig(d["L"]); r = ArmRig(d["R"]); p = d["P"] as? [Int]
            if let item = d["item"] as? [Any] { itemArt = item[0] as? String; itemSide = item[1] as? String; itemX = item[2] as? Int ?? 0; itemY = item[3] as? Int ?? 0 }
        }
        var flipped: Rig {
            var copy = self
            copy.l = r?.flipped; copy.r = l?.flipped
            if let p { copy.p = [31 - p[0], p[1], 31 - p[2], p[3]] }
            return copy
        }
    }
    private static let rigs: [String: Rig] = (root["rigs"] as! [String: [String: Any]]).mapValues { Rig($0) }
    private static func rigOf(_ pose: Pose, _ look: Look) -> Rig {
        let rig = rigs[pose.rawValue]!
        return look.leftHanded && rig.flip ? rig.flipped : rig
    }
    /// How long, in ticks (four a second), this pose takes to settle from the one before.
    static func blendTicks(_ pose: Pose) -> Double { pose == .empty ? 0 : rigs[pose.rawValue]!.blend }
    static var rigNames: Set<String> { Set(rigs.keys) }

    private static func round(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }
    private static func lerp(_ a: Int, _ b: Int, _ t: Double) -> Int { round(Double(a) + Double(b - a) * t) }
    private static func mirror(_ grid: [String]) -> [String] { grid.map { String($0.reversed()) } }

    // ---- Heads ----------------------------------------------------------------------------------

    private static let faceData = root["face"] as! [String: Any]
    private static func face(_ eyes: String, _ mouth: String) -> [String] {
        var rows = (faceData["rows"] as! [String]).map { Array($0) }
        let parts = [(faceData["eyes"] as! [String: [[Any]]])[eyes]!, (faceData["mouths"] as! [String: [[Any]]])[mouth]!]
        for part in parts {
            for mark in part {
                let row = mark[0] as! Int, col = mark[1] as! Int
                for (i, c) in (mark[2] as! String).enumerated() { rows[row][col + i] = c }
            }
        }
        return rows.map { String($0) }
    }

    /// Hair hanging behind the face, then the head itself with anything worn on it.
    private static func headLayers(_ look: Look, _ eyes: String, _ mouth: String, _ x: Int, _ y: Int, lag: Int = 0) -> ([Layer], [Layer]) {
        let custom = look.customization
        let newHair = (custom?.value("hair") ?? 0) >= 8
        let ribbon = look.additions & 1 != 0
        let style = (root["hair"] as! [String: [[String: Any]]])[look.girl ? "girl" : "boy"]![look.hair]
        func place(_ layer: [Any]) -> Layer {
            let name = layer[0] as! String
            return Layer(layer.count > 3 ? mirror(art(name)) : art(name), x + (layer[1] as! Int), y + (layer[2] as! Int))
        }
        let crown = newHair ? Array(repeating: String(repeating: ".", count: 18), count: 10) : art(style["crown"] as! String)
        var back: [Layer] = []
        if !newHair, let backs = style["back"] as? [[Any]] { for layer in backs { let placed = place(layer); back.append(Layer(placed.grid, placed.x + lag, placed.y)) } }
        var front = [Layer(crown + face(eyes, mouth), x, y)]
        if !newHair {
            if let fronts = style["front"] as? [[Any]] { for layer in fronts { front.append(place(layer)) } }
            if ribbon && style["bow"] != nil { front.append(Layer(art("Bow"), x + 11, y + 1)) }
            if ribbon && style["pin"] != nil { front.append(Layer(art("Hairpin"), x + 13, y + 7)) }
        }
        if let custom { front.insert(contentsOf: custom.layers("hair", x, y), at: 1) }
        // A hat pulled down to its `cut` row hides the hair above it, and with it any bun, bow or hairpin.
        let cut = custom?.hatCut
        if let cut {
            front = front.map { layer in
                Layer(layer.grid.enumerated().map { j, row in layer.y + j < y + cut ? String(repeating: ".", count: row.count) : row }, layer.x, layer.y)
            }
        }
        if cut == nil, custom.map({ $0.on("head") && $0.value("head") == 1 }) ?? (look.accessory == 2) { front.append(Layer(art("StarClip"), x + 12, y + 5)) }
        if custom.map({ $0.on("ear") && $0.value("ear") == 1 }) ?? (look.accessory == 3) {
            back.append(Layer(art("EarBand"), x, y + 4))
            front.append(Layer(art("EarPad"), x - 1, y + 9))
            front.append(Layer(art("EarPad"), x + 16, y + 9))
        }
        if look.additions & 4 != 0 && look.hat == 1 { front.append(Layer(art("Hat1"), x + 1, y + 1)) }
        if look.additions & 4 != 0 && look.hat == 2 { front.append(Layer(art("Hat2"), x - 1, y + 1)) }
        if let custom { front += custom.headLayers(x, y) }
        if ribbon { return (back, front) }
        func plain(_ l: Layer) -> Layer { Layer(l.grid.map { $0.replacingOccurrences(of: "R", with: "h") }, l.x, l.y) }
        return (back.map(plain), front.map(plain))
    }

    // ---- Bodies ---------------------------------------------------------------------------------

    /// One torso for sitting and standing; seated, only the part the desk doesn't hide is needed.
    private static func body(_ look: Look, seated: Bool = false) -> [String] {
        var rows = (root["bodies"] as! [[String]])[look.top]
        if !seated { rows += (root["waist"] as! [String: [String]])[look.skirt ? "skirt" : "pants"]! }
        if let custom = look.customization {
            for layer in custom.layers("top") {
                var cells = rows.map { Array($0) }
                for (y, line) in layer.grid.enumerated() {
                    for (x, c) in line.enumerated() {
                        let xx = x + layer.x, yy = y + layer.y
                        if yy < cells.count && xx < cells[yy].count && "AaCJRw".contains(cells[yy][xx]) && c != "." { cells[yy][xx] = c }
                    }
                }
                rows = cells.map { String($0) }
            }
        }
        return rows
    }

    /// Legs; a walking step lifts one foot by taking a row out of that leg.
    private static func legs(_ look: Look, lifted: Int) -> [String] {
        let rows = art(look.skirt ? "BareLegs" : "Trousers")
        if lifted == 0 { return rows }
        let from = lifted == 1 ? 0 : 10
        return rows.enumerated().map { i, row in
            var cells = Array(row)
            let source = Array(i == 0 ? row : i + 1 < rows.count ? rows[i + 1] : String(repeating: ".", count: 20))
            for c in from..<(from + 10) { cells[c] = source[c] }
            return String(cells)
        }
    }

    /// An arm or a pencil along a path of joints: every point stamps a size×size block
    /// (the last one `tip`) and the whole gets a one-pixel outline, except next to an
    /// arm's first point, where it grows out of the body.
    private static func stroke(_ path: [(Int, Int)], size: Int, fill: (Int, Int) -> Character, tip: Character, rooted: Bool) -> Layer {
        var points = [path[0]]
        for i in 1..<path.count {
            let (x0, y0) = path[i - 1], (x1, y1) = path[i]
            let n = max(abs(x1 - x0), abs(y1 - y0))
            if n > 0 { for s in 1...n { points.append((x0 + round(Double((x1 - x0) * s) / Double(n)), y0 + round(Double((y1 - y0) * s) / Double(n)))) } }
        }
        struct Cell: Hashable { let x: Int, y: Int }
        var cells: [Cell: Character] = [:]
        for (i, point) in points.enumerated() {
            for dy in 0..<size { for dx in 0..<size { cells[Cell(x: point.0 + dx, y: point.1 + dy)] = i == points.count - 1 ? tip : fill(i, points.count) } }
        }
        let root = points[0]
        for cell in Array(cells.keys) {
            for near in [Cell(x: cell.x - 1, y: cell.y), Cell(x: cell.x + 1, y: cell.y), Cell(x: cell.x, y: cell.y - 1), Cell(x: cell.x, y: cell.y + 1)] {
                let atRoot = rooted && near.x >= root.0 - 1 && near.x <= root.0 + size && near.y >= root.1 - 1 && near.y <= root.1 + size
                if cells[near] == nil && !atRoot { cells[near] = "k" }
            }
        }
        if rooted, let end = points.last {
            for (y, row) in art("Hand").enumerated() {
                for (x, c) in row.enumerated() where c != "." { cells[Cell(x: end.0 - 1 + x, y: end.1 - 1 + y)] = c }
            }
        }
        let left = cells.keys.map { $0.x }.min()!, top = cells.keys.map { $0.y }.min()!
        let right = cells.keys.map { $0.x }.max()!, bottom = cells.keys.map { $0.y }.max()!
        let grid = (top...bottom).map { y in String((left...right).map { x in cells[Cell(x: x, y: y)] ?? "." }) }
        return Layer(grid, left, top)
    }

    /// An arm from the shoulder to a hand, the sleeve patterned like the top.
    private static func arm(_ look: Look, _ path: (Int, Int)...) -> Layer {
        stroke(path, size: 2, fill: { i, count in
            if look.sleeve == 1 && i >= count - 3 { return "C" }
            if look.sleeve == 3 && i >= count - 3 { return "R" }
            switch look.top {
            case 1: return i >= count - 3 ? "a" : "A" // sweater cuff
            case 3: return i % 2 == 0 ? "C" : "A"     // stripes
            default: return "A"
            }
        }, tip: look.sleeve == 2 ? "A" : "s", rooted: true)
    }

    private static func pencil(_ path: (Int, Int)...) -> Layer {
        stroke(path, size: 1, fill: { i, _ in i == 0 ? "r" : "p" }, tip: "k", rooted: false)
    }

    // ---- Composing poses ------------------------------------------------------------------------

    /// Every grid a look can use, for the self-test.
    static func grids(_ look: Look) -> [[String]] {
        var all: [[String]] = []
        for pose in Pose.allCases { all += compose(pose, look, alert: true).map { $0.grid } }
        for name in Customization.baseArtNames { all.append(art(name)) }
        for pose in Visiting.allCases {
            for alt in [false, true] {
                all += visitor(look, pose, alt: alt).map { $0.grid }
                all += visitor(look, pose, alt: alt, leftHand: true).map { $0.grid }
            }
        }
        all += reachLayers(look, down: true).map { $0.grid }
        return all
    }

    static func isKnownColor(_ c: Character) -> Bool { c == "." || palette[c] != nil || "hHAaCJR".contains(c) }

    /// What surrounds a desk. `seed` comes from the owner's name, so everyone sees the same
    /// bag and sticker; `lit` turns on the lamp (its light is drawLampGlow and drawLampPool);
    /// `away` takes the bag and drink too (stepping over to a friend leaves them).
    struct Decor {
        var drink: Drink = .none
        var laptop = false
        var seed = 0
        var lit = false
        var away = false
        var packed = false
        var clock = Date()
    }

    private static func bagArt(_ color: Int) -> [String] {
        let tint = String(Array("ztgprV")[color])
        return art("Bag").map { $0.replacingOccurrences(of: "M", with: tint).replacingOccurrences(of: "H", with: "i") }
    }

    /// On the desk's front and hook: its stickers and bag.
    private static func deskScene(_ d: Decor, _ look: Look) -> [Layer] {
        var layers: [Layer] = []
        if !d.away { layers.append(Layer(bagArt(look.bag), 50, 28)) }
        return layers
    }

    /// A cup's corner and the hand holding it, for each stage of raising it to the lips.
    /// The subject picks the book's cover; a colour too close to the top moves on to the next.
    private static func bookCover(_ look: Look, _ kind: Drink) -> String {
        let covers = Array("BzgVy"), clash = Array("zgBy-VzyBg"), i = kind.rawValue - 1
        return String(covers[covers[i] == clash[look.topColor] ? (i + 1) % 5 : i])
    }

    private static func drinkPlace(_ state: String, _ kind: Drink) -> (x: Int, y: Int, handX: Int, handY: Int) {
        let cup = art("Drink\(kind.rawValue)")
        let w = cup[0].count, h = cup.count
        switch state {
        case "rest": let x = width - 1 - w - dx, y = 29 - h; return (x, y, x - 1, y + h / 2 - 1)
        case "lift": let x = 27 - w / 2, y = 22 - h; return (x, y, x + w - 2, y + h / 2)
        case "near": let x = 23 - w / 2, y = 19 - h * 3 / 4; return (x, y, x + w - 2, y + h / 2)
        default: let x = 16 - w / 2, y = 14; return (x, y, x + w - 2, y + h / 2)
        }
    }

    /// A pet at its desk, part way (`blend` 0...1) from pose `from` to `pose`. `alert` adds the "!"
    /// of a pet being tapped awake; `lift` raises the person (not the desk) for a startled little
    /// jump; `breath` sinks the head a row; `blink` shuts the eyes. `decor` adds the things around a
    /// desk: lamp, stickers and, while someone sits there, their bag and drink. Without it, a bare desk.
    static func compose(_ pose: Pose, _ look: Look, alert: Bool = false, lift: Int = 0, decor: Decor? = nil, from: Pose? = nil, blend: Double = 1, breath: Bool = false, blink: Bool = false) -> [Layer] {
        let d = decor ?? Decor()
        let custom = look.customization
        var layers: [Layer] = []
        if decor != nil && (custom?.on("lamp") ?? true) {
            if let custom, custom.value("lamp") > 0 { layers += custom.layers("lamp", lit: d.lit) }
            else { layers.append(Layer(art(d.lit ? "LampOn" : "LampOff"), 1, 10)) }
        }
        let desk = custom?.layers("desk").first ?? Layer(art("Desk"), 0, 26)
        let scene = decor != nil ? deskScene(d, look) : []
        let prop = decor != nil ? (custom?.layers("prop", clock: d.clock) ?? []) : []
        if pose == .empty { return layers + [desk] + scene + prop }

        let to = rigOf(pose, look)
        let moving = from != nil && from != .empty && from != pose
        let start = moving ? rigOf(from!, look) : to
        let t = moving ? max(0, min(1, blend)) : 1
        let now = t >= 0.5 ? to : start
        let sway = lerp(start.x, to.x, t)
        let lag = t < 1 ? (start.x - to.x).signum() : 0
        let headY = lerp(start.y, to.y, t) + (breath && !now.front ? 1 : 0) - lift
        let bodyY = lerp(start.b, to.b, t) - lift
        let eyes = blink && now.eyes != "Happy" ? "Closed" : now.eyes
        let holding = start.drink != nil && to.drink != nil
        let kind: Drink = d.drink == .none ? .mug : d.drink

        func joints(_ rig: Rig, left: Bool) -> ArmRig? {
            guard var arm = left ? rig.l : rig.r else { return nil }
            if !left, let state = rig.drink { let place = drinkPlace(state, kind); arm.handX = place.handX; arm.handY = place.handY }
            return arm
        }
        var arms: [(left: Bool, layer: Int, handX: Int, handY: Int, grid: Layer)] = []
        for left in [true, false] {
            let a = joints(start, left: left), b = joints(to, left: left)
            let only = t >= 0.5 ? b : a
            if !(a != nil && b != nil) && only == nil { continue }
            var elbowX: Int, elbowY: Int, handX: Int, handY: Int
            if let a, let b { elbowX = lerp(a.elbowX, b.elbowX, t); elbowY = lerp(a.elbowY, b.elbowY, t); handX = lerp(a.handX, b.handX, t); handY = lerp(a.handY, b.handY, t) }
            else { elbowX = only!.elbowX; elbowY = only!.elbowY; handX = only!.handX; handY = only!.handY }
            let layer = d.laptop && now.book != nil ? 2 : (joints(now, left: left) ?? a ?? b)!.layer
            // Typing happens behind the open lid: keep the fists inside its width so none peek out.
            if d.laptop && now.lap == nil && layer == 2 { handX = left ? max(handX, 10) : min(handX, 19); handY = max(handY, 23) }
            elbowX += sway; elbowY -= lift; handX += sway; handY -= lift
            arms.append((left, layer, handX, handY, arm(look, ((left ? 9 : 21) + sway, bodyY + 2), (elbowX, elbowY), (handX, handY))))
        }
        func armsAt(_ layer: Int) -> [Layer] { arms.filter { $0.layer == layer }.map { $0.grid } }
        func shift(_ list: [Layer]) -> [Layer] { list.map { Layer($0.grid, $0.x + dx, $0.y) } }

        let (back, faceLayers) = headLayers(look, eyes, now.mouth, 7 + sway, headY, lag: lag)
        var person = [Layer(body(look, seated: bodyY >= 19), 6 + sway, bodyY)]
        if !now.front { person += back + armsAt(0) + faceLayers + armsAt(1) }
        layers += shift(person)
        layers.append(desk)
        layers += scene

        var under: [Layer] = []
        if !d.packed {
            let cover = bookCover(look, kind)
            let lying = d.laptop ? art(now.lap ?? "LaptopOpen") : art(now.book ?? "Book").map { $0.replacingOccurrences(of: "B", with: cover) }
            under.append(Layer(lying, 16 - lying[0].count / 2, 29 - lying.count))
        }
        // Arms go behind the book so it stays whole and only the hands lie on it, over the props too.
        // An open lid hides the hands as well.
        layers += shift(armsAt(2)) + shift(under) + prop
        layers += shift(arms.filter { $0.layer == 2 && !(d.laptop && now.lap == nil) }.map { Layer(art("Hand"), $0.handX - 1, $0.handY - 1) })
        if now.front { layers += shift(back) + shift(armsAt(0)) + shift(faceLayers) + shift(armsAt(1)) }

        // After the lid and the book: the drink, pencil and whatever else is in hand.
        var top: [Layer] = []
        if decor != nil && !d.away && d.drink != .none && start.drink == nil && to.drink == nil {
            let g = art("Drink\(d.drink.rawValue)")
            layers.append(Layer(g, width - 1 - g[0].count, 29 - g.count))
        }
        if start.drink != nil || to.drink != nil {
            let a = drinkPlace(holding ? start.drink! : now.drink ?? "rest", kind)
            let b = drinkPlace(holding ? to.drink! : now.drink ?? "rest", kind)
            top.append(Layer(art("Drink\(kind.rawValue)"), lerp(a.x, b.x, holding ? t : 1), lerp(a.y, b.y, holding ? t : 1)))
        }
        var drawn = now.p
        if let p0 = start.p, let p1 = to.p { drawn = zip(p0, p1).map { lerp($0, $1, t) } }
        if let p = drawn, !d.packed, !(d.laptop && (now.r?.handY ?? 0) >= 22) {
            top.append(pencil((p[0] + sway, p[1] - lift), (p[2] + sway, p[3] - lift)))
        }
        if let name = now.itemArt, !d.packed, !(d.laptop && now.itemSide == nil) {
            let anchor = now.itemSide == nil ? nil : arms.first { $0.left == (now.itemSide == "L") }
            top.append(Layer(art(name), (anchor?.handX ?? 0) + now.itemX, (anchor?.handY ?? 0) + now.itemY))
        }
        top += armsAt(3)
        if alert || now.mark != nil { top.append(Layer(art(now.mark == "?" ? "Question" : "Exclaim"), now.mark == "?" ? 28 : 26, 1)) }
        if !alert && now.z == 1 { top.append(Layer(art("ZBig"), 26, 4)) }
        if !alert && now.z == 2 { top.append(Layer(art("ZSmall"), 24, 7)); top.append(Layer(art("ZBig"), 27, 1)) }
        return layers + shift(top)
    }

    /// A friend on their feet. `leftHand` waves with the other hand, the one a seated friend won't hide.
    static func visitor(_ look: Look, _ pose: Visiting, alt: Bool, leftHand: Bool = false) -> [Layer] {
        let walking = pose == .walk || pose == .carry
        let left = leftHand && (pose == .wave || pose == .cheer)
        let (back, head) = headLayers(look, "Open", walking ? "Small" : "Smile", 7, 0)
        var layers = [Layer(body(look), 6, 16), Layer(legs(look, lifted: walking ? (alt ? 1 : 2) : 0), 6, 27)] + back
        let shoulderL = (9, 18), shoulderR = (21, 18)
        if walking {
            if pose == .walk { layers.append(arm(look, shoulderL, (alt ? 7 : 10, 22), (alt ? 6 : 11, 25))) }
            layers.append(arm(look, shoulderR, (alt ? 22 : 19, 22), (alt ? 23 : 18, 25)))
        } else {
            if pose == .cheer { layers.append(left ? arm(look, shoulderL, (5, 20), (4, alt ? 15 : 16)) : arm(look, shoulderR, (25, 20), (26, alt ? 15 : 16))) }
            else if pose == .wave { layers.append(left ? arm(look, shoulderL, (5, 15), alt ? (4, 8) : (2, 9)) : arm(look, shoulderR, (25, 15), alt ? (26, 8) : (28, 9))) }
            if !left { layers.append(arm(look, shoulderL, (7, 21), (7, 25))) }
            if left || pose == .stand { layers.append(arm(look, shoulderR, (23, 21), (23, 25))) }
        }
        return (layers + head).map { Layer($0.grid, $0.x + dx, $0.y) }
    }

    /// The visitor's arm reaching right to a shoulder; drawn after the pet it taps.
    /// `down` is the tap, the other frame the hand lifted.
    /// `touch`: 0 a tap on the shoulder, 1 stroking the top of the head, 2 an arm round them.
    static func reachLayers(_ look: Look, down: Bool, touch: Int = 0) -> [Layer] {
        let reach: Layer
        switch touch {
        case 1: reach = arm(look, (21, 18), (27, 13), (down ? 32 : 35, 8))
        case 2: reach = arm(look, (21, 18), (29, 21), (down ? 38 : 37, 22))
        default: reach = arm(look, (21, 18), (25, down ? 21 : 20), (30, down ? 21 : 20))
        }
        return [Layer(reach.grid, reach.x + dx, reach.y)]
    }

    static func draw(_ pose: Pose, _ look: Look, left: CGFloat, top: CGFloat, scale: CGFloat, alert: Bool = false, lift: Int = 0, decor: Decor? = nil, from: Pose? = nil, blend: Double = 1, breath: Bool = false, blink: Bool = false) {
        draw(layers: compose(pose, look, alert: alert, lift: lift, decor: decor, from: from, blend: blend, breath: breath, blink: blink), look, left: left, top: top, scale: scale)
    }

    private static let plainLook = Look(girl: false, 0, 0, 0, 0, 0, 0)
    static func drawButterfly(left: CGFloat, top: CGFloat, scale: CGFloat, folded: Bool) {
        draw(layers: [Layer(art(folded ? "ButterflyShut" : "ButterflyOpen"), 0, 0)], plainLook, left: left, top: top, scale: scale)
    }
    static func drawHeart(left: CGFloat, top: CGFloat, scale: CGFloat) {
        draw(layers: [Layer(art("Heart"), 0, 0)], plainLook, left: left, top: top, scale: scale)
    }
    /// A drink carried in the hand on the way to someone's desk.
    static func drawCarried(_ look: Look, drink: Drink, left: CGFloat, top: CGFloat, scale: CGFloat) {
        draw(layers: [Layer(art("Drink\(drink.rawValue)"), dx + 13, 19)], look, left: left, top: top, scale: scale)
    }
    static func drawFlameEyes(left: CGFloat, top: CGFloat, scale: CGFloat, alt: Bool) {
        draw(layers: [Layer(art(alt ? "FlameB" : "FlameA"), 25, 10), Layer(art(alt ? "FlameA" : "FlameB"), 33, 10)], plainLook, left: left, top: top, scale: scale)
    }

    // ---- A lit lamp -----------------------------------------------------------------------------

    /// Each lamp's beam: the two ends of its opening at the top, and where its edges land on row 27.
    /// Tilted heads throw it toward the book; round shades spread it straight down and wide.
    private static let lampBeams = [(10, 15, 17, 22, 42), (11, 14, 17, 24, 40), (4, 11, 18, -4, 35), (4, 11, 18, -4, 35), (4, 11, 16, -4, 36), (5, 13, 14, 4, 34), (3, 10, 17, -2, 32), (11, 14, 16, 24, 40)]

    /// The cone of light, drawn before the pet so it never washes over them: it shows on the wall
    /// beside them, and drawLampPool picks it up on the book and the desk top.
    static func drawLampGlow(left: CGFloat, top: CGFloat, scale: CGFloat, lamp: Int = 0, night: Bool = false) {
        let which = max(0, min(7, lamp))
        func strip(_ y: Int, _ from: Int, _ to: Int) {
            NSRect(x: left + CGFloat(from) * scale, y: top + CGFloat(y) * scale, width: CGFloat(to - from + 1) * scale, height: scale).fill(using: .sourceOver)
        }
        func warm(_ alpha: Int) { NSColor(srgbRed: 1, green: 216.0 / 255, blue: 96.0 / 255, alpha: CGFloat(alpha) / 255).setFill() }
        if which == 6 { // A lantern lights everything around it, like the garland's bulbs.
            for (r, alpha) in night ? [(19, 42), (13, 84), (7, 130)] : [(11, 40), (6, 76)] {
                warm(alpha)
                for y in (20 - r)...min(29, 20 + r) {
                    let half = Int(Double(r * r - (y - 20) * (y - 20)).squareRoot())
                    strip(y, max(-6, 7 - half), 7 + half)
                }
            }
            return
        }
        let (a, b, oy, c, d) = lampBeams[which]
        func cone(_ l: Int, _ r: Int, _ footL: Int, _ footR: Int, _ alpha: Int) {
            warm(alpha)
            for y in oy...28 {
                let t = Double(y - oy) / Double(28 - oy)
                strip(y, max(0, l + round(Double(footL - l) * t)), min(46, r + round(Double(footR - r) * t)))
            }
        }
        cone(a, b, c, d, night ? 84 : 40)
        cone(a + 2, b, c + 4, d - 4, night ? 122 : 60) // a soft edge round a brighter middle
    }

    /// The warm pool where the light lands, drawn over the book or laptop and the desk under it.
    static func drawLampPool(left: CGFloat, top: CGFloat, scale: CGFloat, night: Bool = false) {
        NSColor(srgbRed: 1, green: 226.0 / 255, blue: 130.0 / 255, alpha: (night ? 124 : 58) / 255).setFill()
        // Only the bare desk beside the book or laptop, so white pages and a silver lid keep their colour.
        for (y, from, to) in [(27, 15, 19), (28, 14, 19), (29, 16, 45)] {
            NSRect(x: left + CGFloat(from) * scale, y: top + CGFloat(y) * scale, width: CGFloat(to - from + 1) * scale, height: scale).fill(using: .sourceOver)
        }
    }

    // ---- Packing up -----------------------------------------------------------------------------

    static func packingItemGrid(_ laptop: Bool, turn: Double = 1) -> [String] {
        let source = art(laptop ? "LaptopPacked" : "BookClosed").map { Array($0) }
        let w = source[0].count, h = source.count
        if turn >= 1 { return (0..<w).map { x in String(source.reversed().map { $0[x] }) } }
        let angle = turn * .pi / 2, cosine = cos(angle), sine = sin(angle)
        let wide = Int(ceil(Double(w) * cosine + Double(h) * sine)), tall = Int(ceil(Double(w) * sine + Double(h) * cosine))
        return (0..<tall).map { y in
            String((0..<wide).map { x -> Character in
                let px = Double(x) - Double(wide - 1) / 2, py = Double(y) - Double(tall - 1) / 2
                let xx = round(cosine * px + sine * py + Double(w - 1) / 2), yy = round(-sine * px + cosine * py + Double(h - 1) / 2)
                return xx >= 0 && xx < w && yy >= 0 && yy < h ? source[yy][xx] : "."
            })
        }
    }
    static func drawPackingItem(_ look: Look, laptop: Bool, left: CGFloat, top: CGFloat, scale: CGFloat, turn: Double = 1) {
        draw(layers: [Layer(packingItemGrid(laptop, turn: turn), 0, 0)], look, left: left, top: top, scale: scale)
    }
    static func packingArm(_ look: Look, _ targetX: Int, _ targetY: Int, _ leftHand: Bool = false) -> Layer {
        var tx = targetX, ty = targetY
        let sx = leftHand ? 24 : 36, ox = Double(tx - sx), oy = Double(ty - 18), distance = (ox * ox + oy * oy).squareRoot()
        // A hand follows the prop only within a normal arm's reach.
        if distance > 12 { tx = sx + round(ox * 12 / distance); ty = 18 + round(oy * 12 / distance) }
        return arm(look, (sx, 18), (round(Double(sx + tx) / 2), round(Double(18 + ty) / 2) + 2), (tx, ty))
    }
    static func drawPackingReach(_ look: Look, left: CGFloat, top: CGFloat, scale: CGFloat, targetX: Int, targetY: Int, leftHand: Bool = false) {
        draw(layers: [packingArm(look, targetX, targetY, leftHand)], look, left: left, top: top, scale: scale)
    }
    static func drawBag(_ look: Look, left: CGFloat, top: CGFloat, scale: CGFloat, open: Bool = false) {
        draw(layers: [Layer(bagArt(look.bag), 0, 0)], look, left: left, top: top, scale: scale)
        if open { draw(layers: [Layer(["kkkkk", "kkkkk"], 1, 3)], look, left: left, top: top, scale: scale) }
    }

    // ---- The window -----------------------------------------------------------------------------

    private static let windowData = root["windowArt"] as! [String: Any]
    private static let panoramaWidth = windowData["width"] as! Int, panoramaHeight = windowData["height"] as! Int
    private static func unpack(_ rows: [String]) -> [[Character]] {
        rows.map { row in
            var out: [Character] = []
            var n = 0
            for c in row {
                if let digit = c.wholeNumberValue, c.isASCII { n = n * 10 + digit }
                else { out.append(contentsOf: repeatElement(c, count: max(1, n))); n = 0 }
            }
            return out
        }
    }
    private static let skies = (windowData["skies"] as! [[String]]).map(unpack)
    private static let views = (windowData["scenes"] as! [[String: [String]]]).map { (leafy: unpack($0["leafy"]!), winter: unpack($0["winter"]!)) }
    private static let glows: [Int: [[Character]]] = {
        var out: [Int: [[Character]]] = [:]
        for (key, value) in windowData["glow"] as! [String: [String]] { out[Int(key)!] = unpack(value) }
        return out
    }()
    private static let clouds = (windowData["clouds"] as! [[String: Any]]).map { (grid: ($0["grid"] as! [String]).map { Array($0) }, x: $0["x"] as! Int, y: $0["y"] as! Int, speed: $0["speed"] as! Int) }
    private static let windowPalettes = (windowData["palettes"] as! [[[String: String]]]).map { $0.map(colors) }

    /// The classroom's window, w×h: the middle of its panorama, anchored at the sill (a taller
    /// window just shows more sky), inside a wooden frame. `drift` is how far the clouds have moved.
    /// Window frames: pane width (0 = none), transom, arch, shutter width, open. One changes with each view.
    private static let frames: [(pane: Int, transom: Bool, arch: Bool, shutter: Int, open: Bool)] = [(56, true, false, 0, false), (44, false, true, 0, false), (90, false, false, 0, false), (56, false, false, 9, false), (0, false, false, 0, true)]
    static var windowFrames: Int { frames.count }
    static var windowScenes: Int { views.count }
    /// Snow falls past this view whatever the season.
    static let christmasScene = 6

    static func windowGrid(_ w: Int, _ h: Int, sky: Int, season: Int, scene: Int = 0, drift: Int = 0, frame: Int = 0) -> [String] {
        let view = season == 3 ? views[scene].winter : views[scene].leafy
        let glow = sky == 2 ? nil : glows[scene]
        let skyGrid = skies[sky]
        let ox = Int((Double(panoramaWidth - w) / 2).rounded(.down)), oy = panoramaHeight - h
        func at(_ rows: [[Character]], _ x: Int, _ y: Int) -> Character { rows[y < 0 ? (y % 20 + 20) % 20 : y][max(0, min(panoramaWidth - 1, x))] }
        var grid = (0..<h).map { y in (0..<w).map { x in at(skyGrid, x + ox, y + oy) } }
        func put(_ x: Int, _ y: Int, _ c: Character) { if c != "." && x >= 0 && x < w && y >= 0 && y < h { grid[y][x] = c } }
        for cloud in clouds {
            let span = panoramaWidth + 60
            let left = ((cloud.x + drift * cloud.speed) % span + span) % span - 30 - ox
            for (j, row) in cloud.grid.enumerated() { for (i, c) in row.enumerated() { put(left + i, cloud.y - oy + j, c) } }
        }
        for y in max(0, -oy)..<h {
            for x in 0..<w {
                put(x, y, at(view, x + ox, y + oy))
                if let glow { put(x, y, at(glow, x + ox, y + oy)) }
            }
        }
        let style = frames[frame], L = style.shutter, R = w - 1 - style.shutter
        if style.pane > 0 {
            let panes = max(1, round(Double(R - L - 1) / Double(style.pane)))
            if panes > 1 { for p in 1..<panes { let m = L + (R - L) * p / panes; for y in 1..<(h - 2) { grid[y][m] = "|"; grid[y][m + 1] = "\"" } } }
        }
        let third = h / 3
        for x in (L + 1)..<R { if style.transom { grid[third][x] = "_"; grid[third + 1][x] = "|" }; grid[h - 3][x] = "_"; grid[1][x] = "\"" }
        for y in 1..<(h - 2) { grid[y][L + 1] = "|"; grid[y][R - 1] = "|" }
        for x in L...R { grid[0][x] = "#"; grid[h - 2][x] = "#" }
        for x in 0..<w { grid[h - 1][x] = "\"" }
        for y in 0..<(h - 1) { grid[y][L] = "#"; grid[y][R] = "#" }
        if style.shutter > 0 {
            for a in [0, w - style.shutter] { for y in 0..<(h - 1) { for x in a..<(a + style.shutter) {
                grid[y][x] = x == a || x == a + style.shutter - 1 || y == 0 || y == h - 2 ? "#" : y % 3 == 0 ? "|" : y % 3 == 1 ? "_" : "\""
            } } }
        }
        if style.arch {
            let archTop = Int((Double(h) * 0.42).rounded(.down))
            let a = Double(R - L) / 2, cx = Double(L + R) / 2, m = min(a, Double(archTop))
            for y in 0...archTop { for x in L...R {
                let ex = (Double(x) - cx) / a, ey = Double(y - archTop) / Double(archTop), e = (ex * ex + ey * ey).squareRoot(), d = (1 - e) * m
                if e > 1 { grid[y][x] = "." } else if d < 1.2 { grid[y][x] = "#" } else if d < 2.4 && y < archTop { grid[y][x] = "|" }
            } }
            for x in (L + 1)..<R { grid[archTop][x] = "_"; grid[archTop + 1][x] = "|" }
        }
        if style.open {
            let s = max(8, Int((Double(R - L) * 0.15).rounded(.down))), mid = s / 2
            for side in 0..<2 { for i in 0...s {
                let x = side == 1 ? R - 2 - i : L + 2 + i, k = Double(i) / Double(s)
                let top = 2 + round(k * 4), bottom = h - 4 - round(k * 3)
                grid[top][x] = "\""; grid[bottom][x] = "|"
                if i == 0 || i == s || i == mid { for y in top...bottom { grid[y][x] = i == mid ? "|" : "\"" } }
            } }
        }
        return grid.map { String($0) }
    }

    static func isWindowColor(_ c: Character, sky: Int, season: Int) -> Bool { windowPalettes[sky][season][c] != nil }
    static func drawWindow(_ w: Int, _ h: Int, sky: Int, season: Int, left: CGFloat, top: CGFloat, scale: CGFloat, scene: Int = 0, drift: Int = 0, frame: Int = 0) {
        drawGrid(windowGrid(w, h, sky: sky, season: season, scene: scene, drift: drift, frame: frame), windowPalettes[sky][season], left: left, top: top, scale: scale)
    }

    /// Petals, leaves or snow drifting past the glass; `t` in seconds. Summer stays clear.
    static func windowParticles(_ w: Int, _ h: Int, season: Int, t: Double) -> [(x: Int, y: Int)] {
        if season == 1 { return [] }
        let count = w * h / (season == 3 ? 90 : 360), span = w - 4
        return (0..<count).map { i in
            let speed = season == 3 ? 2.2 + Double(i * 7 % 5) * 0.5 : 1.6 + Double(i * 3 % 4) * 0.4
            let x = i * 37 + Int((t * (season == 3 ? 0.6 : 1.2) + sin(t * 0.5 + Double(i)) * 3).rounded(.down))
            return ((x % span + span) % span + 2, Int((Double(i * 53) + t * speed).rounded(.down)) % (h - 5) + 1)
        }
    }
    static func drawParticles(_ w: Int, _ h: Int, sky: Int, season: Int, t: Double, left: CGFloat, top: CGFloat, scale: CGFloat) {
        guard let paint = windowPalettes[sky][season]["`"] else { return }
        paint.setFill()
        for p in windowParticles(w, h, season: season, t: t) {
            NSRect(x: left + CGFloat(p.x) * scale, y: top + CGFloat(p.y) * scale, width: scale, height: scale).fill(using: .sourceOver)
        }
    }

    // ---- The clock ------------------------------------------------------------------------------

    static func clockGrid(_ hour: Int, _ minute: Int) -> [String] {
        let center = 15
        var grid = Array(repeating: Array(repeating: Character("."), count: clockSize), count: clockSize)
        for y in 0..<clockSize {
            for x in 0..<clockSize {
                let radius = (x - center) * (x - center) + (y - center) * (y - center)
                if radius <= 210 { grid[y][x] = radius >= 169 ? "d" : "b" }
            }
        }
        for tick in 0..<12 {
            let angle = Double(tick) * .pi / 6
            for radius in (tick % 3 == 0 ? 10 : 11)...11 {
                grid[center - round(cos(angle) * Double(radius))][center + round(sin(angle) * Double(radius))] = "D"
            }
        }
        func hand(_ angle: Double, _ length: Int) {
            for i in 0...(length * 3) { grid[center - round(cos(angle) * Double(i) / 3)][center + round(sin(angle) * Double(i) / 3)] = "k" }
        }
        hand((Double(hour % 12) + Double(minute) / 60) * .pi / 6, 7)
        hand(Double(minute) * .pi / 30, 9)
        grid[center][center] = "t"
        return grid.map { String($0) }
    }
    static func drawClock(_ hour: Int, _ minute: Int, left: CGFloat, top: CGFloat, scale: CGFloat) {
        draw(layers: [Layer(clockGrid(hour, minute), 0, 0)], plainLook, left: left, top: top, scale: scale)
    }

    // ---- Menu bar icon and contact sheet ---------------------------------------------------------

    /// The face alone, for the menu bar icon.
    /// `dot`: a red dot in the top-right corner, for a friend's call not yet answered.
    static func face(_ look: Look, dot: Bool = false) -> NSImage {
        let (back, head) = headLayers(look, "Open", "Small", 3, 2)
        return NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            Sprites.draw(layers: back + head, look, left: 0, top: 0, scale: 0.75)
            if dot {
                let circle = NSBezierPath(ovalIn: NSRect(x: 9.5, y: 0.5, width: 8, height: 8))
                Sprites.color(0xE53935).setFill(); circle.fill()
                NSColor.white.setStroke(); circle.lineWidth = 1; circle.stroke()
            }
            return true
        }
    }

    static let sheetColumns = 12
    private static let poseRows = (Pose.allCases.count + sheetColumns - 1) / sheetColumns

    static func sheetSize(scale: CGFloat) -> NSSize {
        NSSize(width: CGFloat(sheetColumns * width) * scale, height: CGFloat((2 * poseRows + 4) * height) * scale)
    }

    /// For eyeballing the art, laid out exactly like the Windows app's Sheet, twelve to a
    /// row: a boy and a girl through every pose, two dozen looks covering every hairstyle,
    /// colour and top, then visitors and furnished desks.
    static func drawSheet(scale: CGFloat) {
        color(0xF4F5F7).setFill()
        NSRect(origin: .zero, size: sheetSize(scale: scale)).fill()
        let boy = Look(girl: false, 0, 0, 0, 0, 0, 0)
        let girl = Look(girl: true, 0, 0, 3, 2, 5, 0)
        func at(_ cell: Int) -> (CGFloat, CGFloat) {
            (CGFloat(cell % sheetColumns * width) * scale, CGFloat(cell / sheetColumns * height) * scale)
        }
        for (i, pose) in Pose.allCases.enumerated() {
            let (bx, by) = at(i)
            draw(pose, boy, left: bx, top: by, scale: scale)
            let (gx, gy) = at(poseRows * sheetColumns + i)
            draw(pose, girl, left: gx, top: gy, scale: scale)
        }
        for i in 0..<(2 * sheetColumns) {
            let look = Look(girl: i % 2 == 1, i / 2 % Look.hairStyles, i % Look.hairColors, i % Look.tops, (i * 3) % 10, i % 8, i % 6)
            let (x, y) = at(2 * poseRows * sheetColumns + i)
            draw(.writeA, look, left: x, top: y, scale: scale)
        }
        let row = (2 * poseRows + 2) * sheetColumns
        let cells: [([Layer], Look)] = [
            (visitor(boy, .walk, alt: true), boy),
            (visitor(boy, .walk, alt: false), boy),
            (visitor(girl, .wave, alt: true), girl),
            (visitor(girl, .wave, alt: false), girl),
            (visitor(girl, .reach, alt: true) + reachLayers(girl, down: true), girl),
            (compose(.writeA, girl, alert: true, lift: 1), girl),
            (visitor(girl, .wave, alt: true, leftHand: true), girl),
            (visitor(girl, .carry, alt: false), girl),
        ]
        for (i, cell) in cells.enumerated() {
            let (x, y) = at(row + i)
            draw(layers: cell.0, cell.1, left: x, top: y, scale: scale)
        }
        let desks: [(Pose, Look, Decor, Int)] = [
            (.writeA, boy, Decor(drink: .icedCoffee, laptop: false, seed: 0, lit: false), 0),
            (.writeA, girl, Decor(drink: .mug, laptop: false, seed: 7, lit: false), 0),
            (.writeA, boy, Decor(drink: .can, laptop: false, seed: 14, lit: false), 0),
            (.writeA, girl, Decor(drink: .beer, laptop: false, seed: 21, lit: false), 0),
            (.writeA, boy, Decor(drink: .soju, laptop: false, seed: 28, lit: false), 0),
            (.writeA, girl, Decor(drink: .mug, laptop: true, seed: 5, lit: true), 0),
            (.writeB, boy, Decor(drink: .can, laptop: true, seed: 11, lit: false), 0),
            (.dozeA, girl, Decor(drink: .beer, laptop: true, seed: 17, lit: false), 0),
            (.stretchLeft, boy, Decor(drink: .icedCoffee, laptop: false, seed: 23, lit: true), 0),
            (.teaSip, girl, Decor(drink: .soju, laptop: true, seed: 29, lit: true), 0),
            (.writeA, boy, Decor(drink: .can, laptop: false, seed: 2, lit: false), 1),
            (.empty, girl, Decor(drink: .beer, laptop: true, seed: 8, lit: false, away: true), 0),
        ]
        for (i, d) in desks.enumerated() {
            let (x, y) = at(row + sheetColumns + i)
            draw(d.0, d.1, left: x, top: y, scale: scale, alert: d.3 > 0, lift: d.3, decor: d.2)
        }
    }

    static func draw(layers: [Layer], _ look: Look, left: CGFloat, top: CGFloat, scale: CGFloat) {
        let hair = hairColorSet[look.hairColor], dress = topColorSet[look.topColor]
        var paints = palette
        paints["s"] = skinSet[look.skin]
        paints["h"] = hair[0]
        paints["H"] = hair[1]
        paints["A"] = dress[0]
        paints["a"] = dress[1]
        paints["C"] = dress[2]
        paints["J"] = bottomColorSet[look.bottom % 4]
        paints["R"] = ribbonSet[look.ribbon]
        for layer in layers { drawGrid(layer.grid, paints, left: left + CGFloat(layer.x) * scale, top: top + CGFloat(layer.y) * scale, scale: scale) }
    }

    private static func drawGrid(_ grid: [String], _ paints: [Character: NSColor], left: CGFloat, top: CGFloat, scale: CGFloat) {
        // Anti-aliasing would show seams between the pixel squares.
        let context = NSGraphicsContext.current
        let antialias = context?.shouldAntialias ?? true
        context?.shouldAntialias = scale < 1
        for (row, line) in grid.enumerated() {
            for (col, c) in line.enumerated() {
                guard let paint = paints[c] else { continue }
                paint.setFill()
                NSRect(x: left + CGFloat(col) * scale, y: top + CGFloat(row) * scale, width: scale, height: scale).fill(using: .sourceOver)
            }
        }
        context?.shouldAntialias = antialias
    }
}
