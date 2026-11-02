import AppKit

/// One pet's appearance, the same code as Look in the Windows app's Sprites.cs: gender,
/// then one digit each for hairstyle, hair colour, top, top colour, bottoms and ribbon
/// colour ("g213402").
struct Look: Equatable {
    static let hairStyles = 3
    static let hairColors = 4
    static let tops = 4        // hoodie, sweater, cardigan, striped tee
    static let topColors = 10
    static let bottoms = 8     // 0-3 trousers, 4-7 skirt (girls only)
    static let ribbons = 6

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

/// The pets as pixel art written in text, the same grids and colours as the Windows app:
/// one character is one pixel ('.' is transparent). Fixed colours come from `palette`;
/// hair (h H), top (A a C), bottoms (J) and ribbon (R) come from the pet's Look. A pose
/// stacks layers on a width×height grid, drawn `scale` points a pixel.
enum Sprites {
    static let width = 44
    static let height = 38

    /// The person sits a little right of the desk's middle, leaving the left end of the
    /// desk top free for the nameplate (cols 1..16).
    static let dx = 10

    enum Pose: CaseIterable { case writeA, writeB, blink, dozeA, dozeB, stand, waveA, waveB, empty }

    /// A visiting friend: walking over, waving at an empty desk, or with the right arm
    /// held out to tap (the arm itself comes from `reachLayers`).
    enum Visiting { case walk, wave, reach }

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

    static let palette: [Character: NSColor] = [
        "k": color(0x3A2E39), // outline
        "s": color(0xFFE0C8), // skin
        "c": color(0xFFA8A8), // cheeks
        "e": color(0x2B222A), // eyes
        "w": color(0xFFFFFF),
        "m": color(0xD06A6A), // mouth
        "l": color(0xECBA88), // desk top
        "d": color(0xC98B5A), // desk edge
        "D": color(0xA86E42), // desk front
        "b": color(0xFFFBF0), // pages
        "B": color(0xF07C7C), // book cover
        "p": color(0xFFD14A), // pencil, the "!"
        "r": color(0xFF8FB1), // eraser
        "z": color(0x6A8CE8), // Zzz
    ]

    // (base, shine): dark brown, black, light brown, ash
    private static let hairColorSet = [(0x5A3E36, 0x8A6352), (0x2E2A33, 0x555060), (0x8B5E3C, 0xB8865C), (0x6E6259, 0x9A8D82)]

    // (main, shade, accent): blue, mint, pink, yellow, grey, lavender, navy, beige, red, olive
    private static let topColorSet = [
        (0x7AA7F5, 0x5C86DB, 0xFFFFFF), (0x8FD3B6, 0x6BB596, 0xFFFFFF), (0xF5A9C0, 0xDB86A0, 0xFFFFFF),
        (0xF7D774, 0xD9B651, 0x8A6A3A), (0xB9BDC7, 0x9499A6, 0xFFFFFF), (0xB9A7E8, 0x9887C9, 0xFFFFFF),
        (0x4F5D8C, 0x3D4A73, 0xE9EDF7), (0xE3C9A3, 0xC8AD86, 0x8A6A4A), (0xE57373, 0xC65A5A, 0xFFFFFF),
        (0x9DB36B, 0x7F9550, 0xF1F1E1),
    ]

    private static let bottomColorSet = [0x5B78A8, 0x3E3B45, 0xC8B08A, 0x7D8494] // denim, black, beige, grey

    private static let ribbonSet = [0xFF8FB1, 0xE54B4B, 0xFFC93C, 0x5FC9A8, 0x4F5D8C, 0xFFFFFF]

    private static func r(_ c: Character, _ n: Int) -> String { String(repeating: c, count: n) }

    // ---- Heads ----------------------------------------------------------------------

    // The face below the hair line is the same for everyone.
    private static let face = [
        "khsssssssssssssshk",
        "khssewssssssewsshk",
        "khsseesssssseesshk",
        "khsccsssmmsssccshk",
        "khsssssssssssssshk",
        ".kssssssssssssssk.",
        "..kksssssssssskk..",
        "....kkkkkkkkkk....",
    ]

    private static let boyTops: [[String]] = [
        [ // cowlick and an M-shaped fringe
            "..........kk......",
            ".........kk.......",
            ".....kkkkkkkk.....",
            "...kkhhhhhhhhkk...",
            "..khhhhhhhhhhhhk..",
            ".khhhHHhhhhhhhhhk.",
            ".khhHHhhhhhhhhhhk.",
            "khhhhhhhhhhhhhhhhk",
            "khhhshhhhhhhhshhhk",
            "khhsssshhhhsssshhk",
        ],
        [ // fringe swept to one side
            "..................",
            "..................",
            ".....kkkkkkkk.....",
            "...kkhhhhhhhhkk...",
            "..khhhhhhhhHHhhk..",
            ".khhhhhhhhHHhhhhk.",
            ".khhhhhhhhhhhhhhk.",
            "khhhhhhhhhhhhhhhhk",
            "khhhhhhhhhhhssshhk",
            "khhhhhhhsssssssshk",
        ],
        [ // round bowl cut with straight bangs
            "..................",
            "..................",
            ".....kkkkkkkk.....",
            "...kkhhhhhhhhkk...",
            "..khhhhhhhhhhhhk..",
            ".khhHHHhhhhhhhhhk.",
            ".khhhhhhhhhhhhhhk.",
            "khhhhhhhhhhhhhhhhk",
            "khhhhhhhhhhhhhhhhk",
            "khhsssssssssssshhk",
        ],
    ]

    // Long: M fringe without the cowlick; bob: straight bangs; pigtails: M fringe.
    private static let girlTops: [[String]] = [
        [r(".", 18), r(".", 18)] + boyTops[0].dropFirst(2),
        boyTops[2],
        [r(".", 18), r(".", 18)] + boyTops[0].dropFirst(2),
    ]

    private static func head(_ top: [String], closedEyes: Bool) -> [String] {
        let head = top + face
        return closedEyes ? withRows(head, [(11, "khsssssssssssssshk"), (12, "khsseesssssseesshk")]) : head
    }

    // Long hair falls past the shoulders; a bob stops at the chin; pigtails flare out
    // with a hair tie in the ribbon colour.
    private static let longLeft = [".khk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", ".khk", "..kk"]
    private static let bobLeft = [".khk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", "kkhk", ".kkk"]
    private static let pigtailLeft = ["....k", "...kh", "..kRR", ".khhk", "khhhk", "khhhk", "khhhk", "khhk.", ".kk.."]

    private static let bow = [
        "kk...kk",
        "kRk.kRk",
        "kRRkRRk",
        "kRk.kRk",
        "kk...kk",
    ]

    private static let hairpin = ["kkkk", "kRRk", "kkkk"]

    private static func headLayers(_ look: Look, closedEyes: Bool, _ x: Int, _ y: Int) -> [Layer] {
        if !look.girl { return [Layer(head(boyTops[look.hair], closedEyes: closedEyes), x, y)] }
        let h = head(girlTops[look.hair], closedEyes: closedEyes)
        switch look.hair {
        case 0: return [Layer(longLeft, x - 3, y + 7), Layer(mirror(longLeft), x + 17, y + 7), Layer(h, x, y), Layer(bow, x + 11, y + 1)]
        case 1: return [Layer(bobLeft, x - 3, y + 7), Layer(mirror(bobLeft), x + 17, y + 7), Layer(h, x, y), Layer(hairpin, x + 13, y + 7)]
        default: return [Layer(pigtailLeft, x - 4, y + 9), Layer(mirror(pigtailLeft), x + 17, y + 9), Layer(h, x, y)]
        }
    }

    // ---- Bodies ---------------------------------------------------------------------

    // Narrower than the head, chibi style. Arms are the two-column strips at each side.
    private static let sittingBody = [
        "......kkkkkkkk......",
        "....kkAAAAAAAAkk....",
        "...kAAAAAAAAAAAAk...",
        "..kAAkAAAAAAAAkAAk..",
        "..kAAkAAAAAAAAkAAk..",
        "..kAAkAAAAAAAAkAAk..",
        "..kAAkAAAAAAAAkAAk..",
        "..kkkkkkkkkkkkkkkk..",
    ]

    private static let standingBody = [
        "......kkkkkkkk......",
        "....kkAAAAAAAAkk....",
        "...kAAAAAAAAAAAAk...",
        "..kAAkAAAAAAAAkAAk..",
        "..kAAkAAAAAAAAkAAk..",
        "..kAAkAAAAAAAAkAAk..",
        "..ksskAAAAAAAAkssk..",
        "...kkkAAAAAAAAkkk...",
        ".....kJJJJJJJJk.....",
        ".....kJJJJJJJJk.....",
        ".....kkkkkkkkkk.....",
    ]

    private static let skirtRows = [
        ".....kJJJJJJJJk.....",
        "....kJJJJJJJJJJk....",
        "....kkkkkkkkkkkk....",
    ]

    private static let trousers = [
        ".....kJJk..kJJk.....",
        ".....kJJk..kJJk.....",
        ".....kJJk..kJJk.....",
        ".....kkkk..kkkk.....",
        "....kwwwk..kwwwk....",
        "....kkkkk..kkkkk....",
    ]

    private static let bareLegs = [
        "......ksk..ksk......",
        "......ksk..ksk......",
        "......kwk..kwk......",
        "......kwk..kwk......",
        ".....kkkk..kkkk.....",
        ".....kkkk..kkkk.....",
    ]

    /// Paints the top's pattern onto a body: hoodie strings, a sweater collar, a cardigan
    /// over a shirt, or stripes. Only the main colour 'A' is painted over.
    private static func dress(_ body: [String], _ top: Int) -> [String] {
        var rows = body.map { Array($0) }
        func paint(_ row: Int, _ col: Int, _ c: Character) {
            if row < rows.count && rows[row][col] == "A" { rows[row][col] = c }
        }
        switch top {
        case 0: // hoodie: hood rim and two strings
            for col in 6...13 { paint(1, col, "a") }
            for row in 2...4 {
                paint(row, 8, "C")
                paint(row, 11, "C")
            }
        case 1: // sweater: collar and cuffs
            for col in 7...12 { paint(1, col, "C") }
            for row in 2...(rows.count - 1) {
                paint(row, 3, row % 2 == 0 ? "a" : "A")
                paint(row, 16, row % 2 == 0 ? "a" : "A")
            }
        case 2: // cardigan open over a shirt
            for row in 1...7 {
                paint(row, 9, "C")
                paint(row, 10, "C")
                paint(row, 8, "a")
                paint(row, 11, "a")
            }
        default: // striped tee
            for row in stride(from: 2, through: 7, by: 2) {
                for col in 2...17 { paint(row, col, "C") }
            }
        }
        return rows.map { String($0) }
    }

    private static func body(_ look: Look, sitting: Bool, rightArmUp: Bool) -> [String] {
        let shape = sitting ? sittingBody : look.skirt ? Array(standingBody.prefix(8)) + skirtRows : standingBody
        let body = dress(shape, look.top)
        if !rightArmUp { return body }
        // The raised arm is drawn separately; take the hanging one off the right side.
        return body.enumerated().map { i, row in (3...7).contains(i) ? String(row.prefix(15)) + "....." : row }
    }

    // ---- Props ----------------------------------------------------------------------

    private static let desk: [String] = [
        r("k", 44),
        "k" + r("l", 42) + "k",
        "k" + r("d", 42) + "k",
        r("k", 44),
        ".k" + r("D", 40) + "k.",
        ".k" + r("D", 40) + "k.",
        ".k" + r("D", 17) + r("k", 6) + r("D", 17) + "k.",
        ".k" + r("D", 40) + "k.",
        "." + r("k", 42) + ".",
        ".kDk" + r(".", 36) + "kDk.",
        ".kkk" + r(".", 36) + "kkk.",
    ]

    private static let book = [
        "kkkkkkkkkkkkkk",
        "kbbbbbkkbbbbbk",
        "kBBBBBBBBBBBBk",
    ]

    private static let hand = [".kk.", "kssk", ".kk."]

    private static let pencilHand = [
        "...kr",
        "..kpk",
        ".kssk",
        ".kssk",
        "..kk.",
    ]

    private static let waveArmA = [
        ".....kk..",
        "....kssk.",
        "....kssk.",
        ".....kk..",
        ".....kAk.",
        ".....kAk.",
        ".....kAk.",
        "....kAAk.",
        "...kAAk..",
        "..kAAk...",
        ".kAAk....",
    ]

    private static let waveArmB = withRows(waveArmA, [(0, "......kk."), (1, ".....kssk"), (2, ".....kssk"), (3, "......kk.")])

    // An arm held out to the right, the hand resting on someone's shoulder.
    private static let reachArm = [
        "kkkkkkkk.kk.",
        "AAAAAAAAkssk",
        "AAAAAAAAkssk",
        "kkkkkkkk.kk.",
    ]

    private static let zBig = ["zzzz", "..z.", ".z..", "zzzz"]
    private static let zSmall = ["zzz", ".z.", "zzz"]

    // Pops over the head of a pet being tapped awake.
    private static let exclaim = [".k.", "kpk", "kpk", "kpk", ".k.", "kpk", ".k."]

    // ---- Composing poses ------------------------------------------------------------

    /// Every grid a look can use, for the self-test.
    static func grids(_ look: Look) -> [[String]] {
        var all: [[String]] = []
        for closed in [false, true] { all += headLayers(look, closedEyes: closed, 0, 0).map(\.grid) }
        for sitting in [false, true] {
            for armUp in [false, true] { all.append(body(look, sitting: sitting, rightArmUp: armUp)) }
        }
        return all + [trousers, bareLegs, desk, book, hand, pencilHand, waveArmA, waveArmB, reachArm, zBig, zSmall, exclaim]
    }

    static func isKnownColor(_ c: Character) -> Bool { c == "." || palette[c] != nil || "hHAaCJR".contains(c) }

    /// A pet at its desk. `alert` adds the "!" of a pet being tapped awake; `lift` raises
    /// the person (not the desk) by that many rows, for a startled little jump.
    static func compose(_ pose: Pose, _ look: Look, alert: Bool = false, lift: Int = 0) -> [Layer] {
        if pose == .empty { return [Layer(desk, 0, 27)] }
        let layers = composeAt(pose, look, alert: alert)
        if lift == 0 { return layers }
        return layers.map { $0.grid == desk ? $0 : Layer($0.grid, $0.x, $0.y - lift) }
    }

    private static func composeAt(_ pose: Pose, _ look: Look, alert: Bool) -> [Layer] {
        let standing = pose == .stand || pose == .waveA || pose == .waveB
        let waving = pose == .waveA || pose == .waveB
        let dozing = pose == .dozeA || pose == .dozeB
        let headY = standing ? 0 : pose == .dozeA ? 10 : pose == .dozeB ? 11 : 4
        var person = [Layer(body(look, sitting: !standing, rightArmUp: waving), 6, standing ? 16 : dozing ? 22 : 20)]

        if dozing {
            // Head down on the desk, so the desk goes underneath it.
            person.append(Layer(book, 9, 24))
            person += headLayers(look, closedEyes: true, 7, headY)
            if alert {
                person.append(Layer(exclaim, 26, 1))
            } else if pose == .dozeA {
                person.append(Layer(zBig, 26, 4))
            } else {
                person.append(Layer(zSmall, 24, 7))
                person.append(Layer(zBig, 27, 1))
            }
            var shifted = shift(person)
            shifted.insert(Layer(desk, 0, 27), at: 1) // after the body, before the head resting on it
            return shifted
        }

        person += headLayers(look, closedEyes: pose == .blink, 7, headY)
        var front = [Layer(book, 9, 24)]
        if waving {
            front.append(Layer(pose == .waveA ? waveArmA : waveArmB, 20, 7))
        } else if !standing {
            front.append(Layer(hand, 7, 24))
            front.append(Layer(pencilHand, pose == .writeB ? 18 : 19, 22))
        }
        if alert { front.append(Layer(exclaim, 26, 1)) }
        // Person, then the desk in front of their lap, then what lies on the desk.
        return shift(person) + [Layer(desk, 0, 27)] + shift(front)
    }

    /// A friend standing up, with legs since no desk hides them.
    static func visitor(_ look: Look, _ pose: Visiting, alt: Bool) -> [Layer] {
        var layers = [
            Layer(body(look, sitting: false, rightArmUp: pose != .walk), 6, 16),
            Layer(look.skirt ? bareLegs : trousers, 6, 27),
        ]
        layers += headLayers(look, closedEyes: false, 7, 0)
        if pose == .wave { layers.append(Layer(alt ? waveArmA : waveArmB, 20, 7)) }
        return shift(layers)
    }

    /// The visitor's arm reaching right to a shoulder; drawn after the pet it taps.
    /// `down` is the tap, the other frame the hand lifted.
    static func reachLayers(down: Bool) -> [Layer] { shift([Layer(reachArm, 19, down ? 19 : 18)]) }

    private static func shift(_ layers: [Layer]) -> [Layer] { layers.map { Layer($0.grid, $0.x + dx, $0.y) } }

    static func draw(_ pose: Pose, _ look: Look, left: CGFloat, top: CGFloat, scale: CGFloat, alert: Bool = false, lift: Int = 0) {
        draw(layers: compose(pose, look, alert: alert, lift: lift), look, left: left, top: top, scale: scale)
    }

    /// The face alone, for the menu bar icon.
    static func face(_ look: Look) -> NSImage {
        let layers = headLayers(look, closedEyes: false, 3, 2)
        return NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            Sprites.draw(layers: layers, look, left: 0, top: 0, scale: 0.75)
            return true
        }
    }

    static let sheetColumns = max(Pose.allCases.count, 6)

    static func sheetSize(scale: CGFloat) -> NSSize {
        NSSize(width: CGFloat(sheetColumns * width) * scale, height: CGFloat(5 * height) * scale)
    }

    /// For eyeballing the art, laid out exactly like the Windows app's Sheet: two looks
    /// through every pose, then a dozen looks, then visitors walking, waving and reaching.
    static func drawSheet(scale: CGFloat) {
        let w = CGFloat(width) * scale, h = CGFloat(height) * scale
        color(0xF4F5F7).setFill()
        NSRect(origin: .zero, size: sheetSize(scale: scale)).fill()
        let boy = Look(girl: false, 0, 0, 0, 0, 0, 0)
        let girl = Look(girl: true, 0, 0, 2, 2, 5, 0)
        for (i, pose) in Pose.allCases.enumerated() {
            draw(pose, boy, left: CGFloat(i) * w, top: 0, scale: scale)
            draw(pose, girl, left: CGFloat(i) * w, top: h, scale: scale)
        }
        for i in 0..<(2 * sheetColumns) {
            // Every hairstyle and top, spread over colours.
            let look = Look(girl: i % 2 == 1, i / 2 % 3, i % 4, i % 4, (i * 3) % 10, i % 8, i % 6)
            draw(.writeA, look, left: CGFloat(i % sheetColumns) * w, top: CGFloat(2 + i / sheetColumns) * h, scale: scale)
        }
        let row = 4 * h
        draw(layers: visitor(boy, .walk, alt: true), boy, left: 0, top: row, scale: scale)
        draw(layers: visitor(girl, .wave, alt: true), girl, left: w, top: row, scale: scale)
        draw(layers: visitor(girl, .wave, alt: false), girl, left: 2 * w, top: row, scale: scale)
        draw(layers: visitor(boy, .reach, alt: true), boy, left: 3 * w, top: row, scale: scale)
        draw(layers: reachLayers(down: true), boy, left: 3 * w, top: row, scale: scale)
        draw(.writeA, girl, left: 4 * w, top: row, scale: scale, alert: true, lift: 1)
    }

    static func draw(layers: [Layer], _ look: Look, left: CGFloat, top: CGFloat, scale: CGFloat) {
        let hair = hairColorSet[look.hairColor]
        let top3 = topColorSet[look.topColor]
        var colors = palette
        colors["h"] = color(hair.0)
        colors["H"] = color(hair.1)
        colors["A"] = color(top3.0)
        colors["a"] = color(top3.1)
        colors["C"] = color(top3.2)
        colors["J"] = color(bottomColorSet[look.bottom % 4])
        colors["R"] = color(ribbonSet[look.ribbon])

        // Anti-aliasing would show seams between the pixel squares.
        let context = NSGraphicsContext.current
        let antialias = context?.shouldAntialias ?? true
        context?.shouldAntialias = scale < 1
        for layer in layers {
            for (row, line) in layer.grid.enumerated() {
                for (col, c) in line.enumerated() {
                    guard let paint = colors[c] else { continue }
                    paint.setFill()
                    NSRect(x: left + CGFloat(layer.x + col) * scale, y: top + CGFloat(layer.y + row) * scale,
                           width: scale, height: scale).fill(using: .sourceOver)
                }
            }
        }
        context?.shouldAntialias = antialias
    }

    private static func withRows(_ grid: [String], _ rows: [(Int, String)]) -> [String] {
        var copy = grid
        for (row, text) in rows { copy[row] = text }
        return copy
    }

    private static func mirror(_ grid: [String]) -> [String] { grid.map { String($0.reversed()) } }
}
