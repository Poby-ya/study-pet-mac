import AppKit

/// One pet's appearance, the same code as Look in the Windows app's Sprites.cs: gender,
/// then one digit each for hairstyle, hair colour, top, top colour, bottoms and ribbon
/// colour ("g213402"). An older version reads each digit modulo its own, smaller counts.
struct Look: Equatable {
    static let hairStyles = 5
    static let hairColors = 5
    static let tops = 6        // hoodie, sweater, cardigan, striped tee, uniform, heart sweater
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

    enum Pose: CaseIterable {
        case writeA, writeB, blink, dozeA, dozeB, stand, waveA, waveB, empty
        case stretchHalf, stretchUp, stretchLeft, stretchRight, content, oops, pickUp, found, lookUp
        case teaHold, teaSip, turnPage, cheer, yawn, nodA, nodB, nodC, startle, munchA, munchB
        case think, idea, spinA, spinB, spinC, spinD
    }

    /// A visiting friend: walking over, waving at an empty desk, or with the right arm
    /// held out to tap (the arm itself comes from `reachLayers`).
    enum Visiting: CaseIterable { case walk, wave, reach }

    private enum Eyes { case open, closed, happy, up }
    private enum Mouth { case small, open, smile }

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
        "l": color(0xECBA88), // desk top, cookie
        "d": color(0xC98B5A), // desk edge
        "D": color(0xA86E42), // desk front, chocolate chips
        "b": color(0xFFFBF0), // pages
        "B": color(0xF07C7C), // book cover
        "p": color(0xFFD14A), // pencil, the "!" and "?"
        "r": color(0xFF8FB1), // eraser
        "z": color(0x6A8CE8), // Zzz
        "f": color(0xA17999), // butterfly outline
        "F": color(0xF6BED7), // rose wings
        "q": color(0xDF95BC),
        "v": color(0xD3C3F1), // lilac wings
        "V": color(0xB29BDB),
        "u": color(0xFFF8E9), // wing highlights
        "n": color(0x775B78), // tiny body
        "o": color(0x7A4E36), // coffee
        "O": color(0xA87452), // coffee shine
        "i": color(0xDCF0F8), // ice, glass
        "t": color(0xE25252), // can
        "x": color(0xC9CED6), // can metal
        "y": color(0xF2B23A), // beer
        "g": color(0x6CC08A), // soju bottle
        "G": color(0x489866), // soju cap, bottle shade
    ]

    /// A drink at the right end of the desk, picked at random for each study session.
    enum Drink: Int { case none, icedCoffee, mug, can, beer, soju }
    static let drinks = 5

    private static let drinkArt: [[String]] = [
        [],
        ["....kk.", "....k..", "kkkkkkk", "kiiiiik", ".koiok.", ".kiook.", ".kooik.", ".koiok.", ".koook.", ".kkkkk."],
        ["kkkkkk..", "koooOk..", "kwwwwkkk", "kwwwwk.k", "kwwwwkkk", "kwwwwk..", ".kkkk..."],
        [".kkkk.", "kxxxxk", "kttttk", "ktwwtk", "ktwwtk", "kttttk", "kxxxxk", ".kkkk."],
        ["kkkkkk", "kwwwbk", "kyyyyk", "kyiyyk", "kyyiyk", "kyyyyk", ".kyyk.", ".kkkk."],
        [".kkkk.", ".kGGk.", ".kggk.", ".kggk.", "kggggk", "kwwwwk", "kwzzwk", "kwwwwk", "kggggk", "kgGggk", ".kkkk."],
    ]

    /// Standing on the desk top, in desk coordinates (not shifted by dx).
    private static func drinkLayer(_ drink: Drink) -> Layer { Layer(drinkArt[drink.rawValue], 36, 27 - drinkArt[drink.rawValue].count) }

    // (base, shine): dark brown, black, light brown, auburn, honey
    private static let hairColorSet = [(0x5A3E36, 0x8A6352), (0x2E2A33, 0x555060), (0x8B5E3C, 0xB8865C), (0x8E452F, 0xBC6C4E), (0xD09C52, 0xEEC884)]

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

    /// The face below the hair line, the same for everyone apart from the expression.
    private static func face(_ eyes: Eyes, _ mouth: Mouth) -> [String] {
        let rows = [
            "khsssssssssssssshk",
            "khsssssssssssssshk",
            "khsssssssssssssshk",
            "khsccssssssssccshk",
            "khsssssssssssssshk",
            ".kssssssssssssssk.",
            "..kksssssssssskk..",
            "....kkkkkkkkkk....",
        ]
        let marks: [(Int, Int, String)]
        switch eyes {
        case .open: marks = [(1, 4, "ew"), (1, 12, "ew"), (2, 4, "ee"), (2, 12, "ee")]
        case .closed: marks = [(2, 4, "ee"), (2, 12, "ee")]
        case .happy: marks = [(1, 4, "ee"), (1, 12, "ee"), (2, 3, "e"), (2, 6, "e"), (2, 11, "e"), (2, 14, "e")]
        case .up: marks = [(0, 4, "ew"), (0, 12, "ew"), (1, 4, "ee"), (1, 12, "ee")]
        }
        let lips: [(Int, Int, String)]
        switch mouth {
        case .small: lips = [(3, 8, "mm")]
        case .open: lips = [(3, 8, "ee"), (4, 8, "mm")]
        case .smile: lips = [(3, 7, "m"), (3, 10, "m"), (4, 8, "mm")]
        }
        return put(rows, marks + lips)
    }

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
        [ // spiky
            "...kk...kk...kk...",
            "..khhkkkhhkkkhhk..",
            ".khhhhhhhhhhhhhhk.",
            ".khhHHhhhhhhhhhhk.",
            ".khHHhhhhhhhhhhhk.",
            ".khhhhhhhhhhhhhhk.",
            "khhhhhhhhhhhhhhhhk",
            "khhhhhhhhhhhhhhhhk",
            "khhhhhhhhhhhhhhhhk",
            "khhsshhhsshhhsshhk",
        ],
        [ // curly
            "..................",
            "...kk.kk..kk.kk...",
            "..khhkhhkkhhkhhk..",
            ".khhHhhhhhhhhHhhk.",
            ".khHhhHhhhhHhhHhk.",
            "khhhhhhhhhhhhhhhhk",
            "khhHhhhHhhHhhhHhhk",
            "khhhhhhhhhhhhhhhhk",
            "khhhhhhhhhhhhhhhhk",
            "khhshhsshhsshhshhk",
        ],
    ]

    private static let bare = [r(".", 18), r(".", 18)] + boyTops[0].dropFirst(2)

    // Long: M fringe; bob: straight bangs; pigtails; two buns; side ponytail.
    private static let girlTops: [[String]] = [bare, boyTops[2], bare, boyTops[2], boyTops[1]]

    // Long hair falls past the shoulders; a bob stops at the chin; pigtails flare out
    // with a hair tie in the ribbon colour.
    private static let longLeft = [".khk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", ".khk", "..kk"]
    private static let bobLeft = [".khk", "khhk", "khhk", "khhk", "khhk", "khhk", "khhk", "kkhk", ".kkk"]
    private static let pigtailLeft = ["....k", "...kh", "..kRR", ".khhk", "khhhk", "khhhk", "khhhk", "khhk.", ".kk.."]
    private static let bun = [".kkkk.", "khhHhk", "khhhhk", "kRRRRk"]

    private static let bow = [
        "kk...kk",
        "kRk.kRk",
        "kRRkRRk",
        "kRk.kRk",
        "kk...kk",
    ]

    private static let hairpin = ["kkkk", "kRRk", "kkkk"]

    /// Hair hanging behind the face, then the head itself with anything worn on it.
    private static func headLayers(_ look: Look, _ eyes: Eyes, _ mouth: Mouth, _ x: Int, _ y: Int) -> (back: [Layer], front: [Layer]) {
        let tops = look.girl ? girlTops : boyTops
        let head = Layer(tops[look.hair] + face(eyes, mouth), x, y)
        if !look.girl { return ([], [head]) }
        switch look.hair {
        case 0: return ([Layer(longLeft, x - 3, y + 7), Layer(mirror(longLeft), x + 17, y + 7)], [head, Layer(bow, x + 11, y + 1)])
        case 1: return ([Layer(bobLeft, x - 3, y + 7), Layer(mirror(bobLeft), x + 17, y + 7)], [head, Layer(hairpin, x + 13, y + 7)])
        case 2: return ([Layer(pigtailLeft, x - 4, y + 9), Layer(mirror(pigtailLeft), x + 17, y + 9)], [head])
        case 3: return ([Layer(bun, x, y), Layer(bun, x + 12, y)], [head])
        default: return ([Layer(mirror(pigtailLeft), x + 16, y + 4)], [head])
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
    /// over a shirt, stripes, a blazer with a tie, or a heart. Only the main colour 'A'
    /// is painted over.
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
        case 3: // striped tee
            for row in stride(from: 2, through: 7, by: 2) {
                for col in 2...17 { paint(row, col, "C") }
            }
        case 4: // blazer over a white shirt and a tie in the ribbon colour
            for row in 1...3 {
                paint(row, 7 + row - 1, "a")
                paint(row, 12 - row + 1, "a")
            }
            for col in 8...11 { paint(1, col, "w") }
            paint(2, 8, "w"); paint(2, 11, "w")
            for row in 1...5 {
                paint(row, 9, "R")
                paint(row, 10, "R")
            }
        default: // sweater with a heart on the chest
            for col in 7...12 { paint(1, col, "a") }
            for (row, from, to) in [(2, 7, 8), (2, 11, 12), (3, 7, 12), (4, 8, 11), (5, 9, 10)] {
                for col in from...to { paint(row, col, "C") }
            }
        }
        return rows.map { String($0) }
    }

    /// A body with either hanging arm taken off, for poses that draw that arm themselves.
    private static func body(_ look: Look, sitting: Bool, leftArm: Bool = false, rightArm: Bool = false) -> [String] {
        let shape = sitting ? sittingBody : look.skirt ? Array(standingBody.prefix(8)) + skirtRows : standingBody
        return dress(shape, look.top).enumerated().map { i, row in
            if i < 3 || i > 7 { return row }
            let cells = Array(row)
            let left = leftArm ? "....." + String(cells[5..<15]) : String(cells[0..<15])
            return left + (rightArm ? "....." : String(cells[15...]))
        }
    }

    /// Legs; a walking step lifts one foot by taking a row out of that leg.
    private static func legs(_ look: Look, lifted: Int) -> [String] {
        let legs = look.skirt ? bareLegs : trousers
        if lifted == 0 { return legs }
        let from = lifted == 1 ? 0 : 10
        return legs.enumerated().map { i, row in
            let source = Array(i == 0 ? row : i + 1 < legs.count ? legs[i + 1] : r(".", 20))
            let cells = Array(row)
            return String(cells[0..<from]) + String(source[from..<(from + 10)]) + String(cells[(from + 10)...])
        }
    }

    private struct Cell: Hashable { let x: Int, y: Int }

    /// An arm or a pencil along a path of joints: every point stamps a size×size block
    /// (the last one `tip`) and the whole gets a one-pixel outline, except next to an
    /// arm's first point, where it grows out of the body.
    private static func stroke(_ path: [(Int, Int)], size: Int, fill: (Int, Int) -> Character, tip: Character, rooted: Bool) -> Layer {
        var points = [path[0]]
        for i in 1..<path.count {
            let (x0, y0) = path[i - 1], (x1, y1) = path[i]
            let n = max(abs(x1 - x0), abs(y1 - y0))
            if n == 0 { continue }
            for s in 1...n {
                points.append((x0 + Int(floor(Double((x1 - x0) * s) / Double(n) + 0.5)), y0 + Int(floor(Double((y1 - y0) * s) / Double(n) + 0.5))))
            }
        }
        var cells: [Cell: Character] = [:]
        for (i, p) in points.enumerated() {
            for dy in 0..<size {
                for dx in 0..<size { cells[Cell(x: p.0 + dx, y: p.1 + dy)] = i == points.count - 1 ? tip : fill(i, points.count) }
            }
        }
        let root = points[0]
        func atRoot(_ c: Cell) -> Bool { rooted && c.x >= root.0 - 1 && c.x <= root.0 + size && c.y >= root.1 - 1 && c.y <= root.1 + size }
        for c in Array(cells.keys) {
            for near in [Cell(x: c.x - 1, y: c.y), Cell(x: c.x + 1, y: c.y), Cell(x: c.x, y: c.y - 1), Cell(x: c.x, y: c.y + 1)] {
                if cells[near] == nil && !atRoot(near) { cells[near] = "k" }
            }
        }
        let xs = cells.keys.map(\.x), ys = cells.keys.map(\.y)
        let left = xs.min()!, top = ys.min()!
        let grid = (top...ys.max()!).map { y in String((left...xs.max()!).map { x in cells[Cell(x: x, y: y)] ?? "." }) }
        return Layer(grid, left, top)
    }

    /// An arm from the shoulder to a hand, the sleeve patterned like the top.
    private static func arm(_ look: Look, _ path: (Int, Int)...) -> Layer {
        stroke(path, size: 2, fill: { i, count in
            switch look.top {
            case 1: return i >= count - 3 ? "a" : "A"  // sweater cuff
            case 3: return i % 2 == 0 ? "C" : "A"      // stripes
            default: return "A"
            }
        }, tip: "s", rooted: true)
    }

    private static func pencil(_ path: (Int, Int)...) -> Layer {
        stroke(path, size: 1, fill: { i, _ in i == 0 ? "r" : "p" }, tip: "k", rooted: false)
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

    private static let zBig = ["zzzz", "..z.", ".z..", "zzzz"]
    private static let zSmall = ["zzz", ".z.", "zzz"]

    // Pops over the head of a pet being tapped awake, or one that just had an idea.
    private static let exclaim = [".k.", "kpk", "kpk", "kpk", ".k.", "kpk", ".k."]
    private static let question = [".kkk.", "kpppk", "kkkpk", ".kppk", ".kpkk", "..k..", ".kpk.", "..k.."]
    private static let teacup = [".kkkk...", "kwwwwkk.", "kwuuukwk", "kwuuukk.", ".kkkk..."]
    private static let cookie = [".kkk.", "klDlk", "kDllk", "kllDk", ".kkk."]
    private static let bitten = [".kk..", "klDk.", "kDllk", "kllDk", ".kkk."]
    private static let turningPage = ["......bk......", ".....bbk......", "kkkkkbbkkkkkkk", "kbbbbbkkbbbbbk", "kBBBBBBBBBBBBk"]
    static let heart = [".ff.ff.", "fFFfFFf", "fFFFFFf", ".fFFFf.", "..fFf..", "...f..."]

    static func butterfly(_ folded: Bool) -> [String] {
        let half = folded
            ? [".....f..", "......f.", "......ff", ".....fFf", "....fFuf", "....fFFf", ".....fqf", "......ff", ".....fVf", ".....fvf", "......ff", "........"]
            : [".....f..", "......f.", "..fff..f", ".fFFFf..", "fFuFFFf.", "fFuuFFff", ".fFqqFff", "..fqqfff", "..fVvvff", "..fvuvf.", "...fvvf.", "....ff.."]
        return half.enumerated().map { i, row in row + (i < 2 ? "." : "n") + String(row.reversed()) }
    }

    static func drawButterfly(left: CGFloat, top: CGFloat, scale: CGFloat, folded: Bool) {
        draw(layers: [Layer(butterfly(folded), 0, 0)], Look(girl: false, 0, 0, 0, 0, 0, 0), left: left, top: top, scale: scale)
    }
    static func drawHeart(left: CGFloat, top: CGFloat, scale: CGFloat) {
        draw(layers: [Layer(heart, 0, 0)], Look(girl: false, 0, 0, 0, 0, 0, 0), left: left, top: top, scale: scale)
    }

    // ---- Composing poses ------------------------------------------------------------

    /// Every grid a look can use, for the self-test.
    static func grids(_ look: Look) -> [[String]] {
        var all: [[String]] = []
        for pose in Pose.allCases { all += compose(pose, look, alert: true).map(\.grid) }
        all += drinkArt.dropFirst()
        for pose in Visiting.allCases {
            for alt in [false, true] {
                all += visitor(look, pose, alt: alt).map(\.grid)
                all += visitor(look, pose, alt: alt, leftHand: true).map(\.grid)
            }
        }
        all += reachLayers(look, down: true).map(\.grid)
        return all + [butterfly(false), butterfly(true), heart]
    }

    static func isKnownColor(_ c: Character) -> Bool { c == "." || palette[c] != nil || "hHAaCJR".contains(c) }

    /// A pet at its desk. `alert` adds the "!" of a pet being tapped awake; `lift` raises
    /// the person (not the desk) by that many rows, for a startled little jump.
    static func compose(_ pose: Pose, _ look: Look, alert: Bool = false, lift: Int = 0, drink: Drink = .none) -> [Layer] {
        if pose == .empty { return [Layer(desk, 0, 27)] }
        var layers = composeAt(pose, look, alert: alert)
        if lift != 0 { layers = layers.map { $0.grid == desk ? $0 : Layer($0.grid, $0.x, $0.y - lift) } }
        // Just above the desk: in front of the person, behind hands and whatever they hold.
        if drink != .none, let at = layers.firstIndex(where: { $0.grid == desk }) { layers.insert(drinkLayer(drink), at: at + 1) }
        return layers
    }

    private static func composeAt(_ pose: Pose, _ look: Look, alert: Bool) -> [Layer] {
        if pose == .pickUp {
            let (back, head) = headLayers(look, .open, .small, 10, 12)
            var shifted = shift([Layer(body(look, sitting: true), 6, 22)] + back + head + [Layer(pencilHand, 28, 30)])
            shifted.insert(Layer(desk, 0, 27), at: 1)
            return shifted
        }
        if pose == .dozeA || pose == .dozeB {
            // Head down on the desk, so the desk goes underneath it.
            let (back, head) = headLayers(look, .closed, .small, 7, pose == .dozeA ? 10 : 11)
            var resting = [Layer(body(look, sitting: true), 6, 22), Layer(book, 9, 24)] + back + head
            if alert {
                resting.append(Layer(exclaim, 26, 1))
            } else if pose == .dozeA {
                resting.append(Layer(zBig, 26, 4))
            } else {
                resting.append(Layer(zSmall, 24, 7))
                resting.append(Layer(zBig, 27, 1))
            }
            var shifted = shift(resting)
            shifted.insert(Layer(desk, 0, 27), at: 1) // after the body, before the head resting on it
            return shifted
        }

        let standing = pose == .stand || pose == .waveA || pose == .waveB
        var eyes = Eyes.open
        var mouth = Mouth.small
        var headY = standing ? 0 : 4
        var sway = 0, rise = 0
        var leftArm = false, rightArm = false
        var bookLayer = Layer(book, 9, 24)
        var leftHand: Layer? = standing ? nil : Layer(hand, 7, 24)
        var rightHand: Layer? = standing ? nil : Layer(pencilHand, 19, 22)
        var behind: [Layer] = [] // between the hair and the face
        var front: [Layer] = []  // in front of the face
        var mark: [String]? = alert ? exclaim : nil

        switch pose {
        case .writeB:
            rightHand = Layer(pencilHand, 18, 22)
        case .blink:
            eyes = .closed
        case .waveA, .waveB:
            mouth = .smile
            rightArm = true
            behind.append(arm(look, (21, 18), (25, 15), pose == .waveA ? (26, 8) : (28, 9)))
        case .stretchHalf:
            leftArm = true; rightArm = true
            leftHand = nil; rightHand = nil
            eyes = .closed
            behind.append(arm(look, (21, 22), (25, 18), (28, 13)))
            behind.append(arm(look, (9, 22), (5, 18), (2, 13)))
        case .stretchUp, .stretchLeft, .stretchRight:
            // Both arms up in a V, leaning with the body on the side frames.
            leftArm = true; rightArm = true
            leftHand = nil; rightHand = nil
            eyes = .happy
            mouth = .open
            rise = 1
            sway = pose == .stretchLeft ? -1 : pose == .stretchRight ? 1 : 0
            switch pose {
            case .stretchLeft:
                behind.append(arm(look, (21, 22), (24, 15), (23, 5)))
                behind.append(arm(look, (9, 22), (4, 16), (1, 8)))
            case .stretchRight:
                behind.append(arm(look, (21, 22), (26, 16), (29, 8)))
                behind.append(arm(look, (9, 22), (6, 15), (7, 5)))
            default:
                behind.append(arm(look, (21, 22), (25, 15), (27, 5)))
                behind.append(arm(look, (9, 22), (5, 15), (3, 5)))
            }
        case .content:
            eyes = .happy
            mouth = .smile
        case .oops:
            mouth = .open
            rightHand = Layer(hand, 20, 24)
            front.append(pencil((27, 30), (31, 33)))
        case .found:
            eyes = .happy
            mouth = .smile
            rightArm = true
            rightHand = nil
            behind.append(pencil((27, 9), (27, 15)))
            behind.append(arm(look, (21, 22), (25, 20), (26, 15)))
        case .lookUp:
            eyes = .up
            headY = 3
        case .teaHold:
            rightHand = nil
            front.append(Layer(teacup, 20, 18))
            front.append(Layer(hand, 20, 22))
        case .teaSip:
            eyes = .closed
            rightHand = nil
            front.append(Layer(teacup, 14, 16))
            front.append(Layer(hand, 15, 20))
        case .turnPage:
            bookLayer = Layer(turningPage, 9, 22)
        case .cheer:
            eyes = .happy
            mouth = .smile
            rightArm = true
            rightHand = nil
            behind.append(arm(look, (21, 22), (25, 20), (25, 15)))
        case .yawn:
            eyes = .closed
            mouth = .open
            leftArm = true
            leftHand = nil
            front.append(arm(look, (9, 22), (11, 20), (12, 18)))
        case .nodA, .nodB, .nodC:
            eyes = .closed
            headY = pose == .nodA ? 5 : pose == .nodB ? 6 : 8
        case .startle:
            mouth = .open
            rise = 1
            mark = exclaim
        case .munchA, .munchB:
            eyes = .happy
            mouth = pose == .munchA ? .open : .small
            leftArm = true
            leftHand = nil
            front.append(pose == .munchA ? Layer(cookie, 10, 15) : Layer(bitten, 10, 16))
            front.append(arm(look, (9, 22), (10, 21), (11, 19)))
        case .think:
            eyes = .up
            rightArm = true
            rightHand = nil
            front.append(pencil((26, 13), (25, 17)))
            front.append(arm(look, (21, 22), (24, 21), (24, 18)))
            mark = question
        case .idea:
            eyes = .happy
            mouth = .smile
            mark = exclaim
        case .spinA, .spinB, .spinC, .spinD:
            rightHand = Layer(hand, 19, 23)
            switch pose {
            case .spinA: front.append(pencil((21, 20), (21, 24)))
            case .spinB: front.append(pencil((23, 20), (19, 24)))
            case .spinC: front.append(pencil((23, 22), (19, 22)))
            default: front.append(pencil((23, 24), (19, 20)))
            }
        default:
            break
        }

        let (hairBack, faceLayers) = headLayers(look, eyes, mouth, 7, headY)
        let person = [Layer(body(look, sitting: !standing, leftArm: leftArm, rightArm: rightArm), 6, standing ? 16 : 20)] + hairBack + behind + faceLayers
        var onDesk: [Layer] = []
        if let left = leftHand { onDesk.append(left) }
        if let right = rightHand { onDesk.append(right) }
        onDesk += front
        if let mark = mark { onDesk.append(Layer(mark, mark == question ? 28 : 26, 1)) }
        func move(_ l: Layer) -> Layer { Layer(l.grid, l.x + sway, l.y - rise) }
        // Person, then the desk in front of their lap, then what lies on the desk.
        return shift(person.map(move)) + [Layer(desk, 0, 27)] + shift([bookLayer] + onDesk.map(move))
    }

    /// A friend standing up, with legs since no desk hides them. `leftHand` waves with the
    /// other hand, the one away from a seated friend who would hide it.
    static func visitor(_ look: Look, _ pose: Visiting, alt: Bool, leftHand: Bool = false) -> [Layer] {
        let walking = pose == .walk
        let left = leftHand && pose == .wave
        let (back, head) = headLayers(look, .open, walking ? .small : .smile, 7, 0)
        var layers = [
            Layer(body(look, sitting: false, leftArm: left, rightArm: !walking && !left), 6, 16),
            Layer(legs(look, lifted: walking ? (alt ? 1 : 2) : 0), 6, 27),
        ] + back
        if left { layers.append(arm(look, (9, 18), (5, 15), alt ? (4, 8) : (2, 9))) }
        else if pose == .wave { layers.append(arm(look, (21, 18), (25, 15), alt ? (26, 8) : (28, 9))) }
        return shift(layers + head)
    }

    /// The visitor's arm reaching right to a shoulder; drawn after the pet it taps.
    /// `down` is the tap, the other frame the hand lifted.
    static func reachLayers(_ look: Look, down: Bool) -> [Layer] {
        shift([arm(look, (21, 18), (24, down ? 21 : 20), (29, down ? 21 : 20))])
    }

    private static func shift(_ layers: [Layer]) -> [Layer] { layers.map { Layer($0.grid, $0.x + dx, $0.y) } }

    static func draw(_ pose: Pose, _ look: Look, left: CGFloat, top: CGFloat, scale: CGFloat, alert: Bool = false, lift: Int = 0, drink: Drink = .none) {
        draw(layers: compose(pose, look, alert: alert, lift: lift, drink: drink), look, left: left, top: top, scale: scale)
    }

    /// The face alone, for the menu bar icon.
    /// `dot`: a red dot in the top-right corner, for a friend's call not yet answered.
    static func face(_ look: Look, dot: Bool = false) -> NSImage {
        let (back, head) = headLayers(look, .open, .small, 3, 2)
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
    /// colour and top, then visitors.
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
            (visitor(girl, .wave, alt: false, leftHand: true), girl),
        ]
        for (i, cell) in cells.enumerated() {
            let (x, y) = at(row + i)
            draw(layers: cell.0, cell.1, left: x, top: y, scale: scale)
        }
        for i in 1...drinks {
            let (x, y) = at(row + sheetColumns + i - 1)
            draw(.writeA, boy, left: x, top: y, scale: scale, drink: Drink(rawValue: i)!)
        }
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

    private static func put(_ grid: [String], _ marks: [(Int, Int, String)]) -> [String] {
        var copy = grid.map { Array($0) }
        for (row, col, text) in marks {
            for (i, c) in text.enumerated() { copy[row][col + i] = c }
        }
        return copy.map { String($0) }
    }

    private static func mirror(_ grid: [String]) -> [String] { grid.map { String($0.reversed()) } }
}
