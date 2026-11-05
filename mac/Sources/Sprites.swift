import AppKit

/// One pet's appearance, the same code as Look in the Windows app's Sprites.cs: gender,
/// then one digit each for hairstyle, hair colour, top, top colour, bottoms and ribbon
/// colour ("g213402"). An older version reads each digit modulo its own, smaller counts.
struct Look: Equatable {
    static let hairStyles = 8
    static let hairColors = 5
    static let tops = 9        // hoodie, sweater, cardigan, striped tee, uniform, heart sweater
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
    var sticker: Int { Int(Array(extra)[5].asciiValue! - 48) }
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
/// The pets as pixel art written in text, the same grids and colours as the Windows app:
/// one character is one pixel ('.' is transparent). Fixed colours come from `palette`;
/// hair (h H), top (A a C), bottoms (J) and ribbon (R) come from the pet's Look. A pose
/// stacks layers on a width×height grid, drawn `scale` points a pixel.
enum Sprites {
    static let width = 44
    static let height = 38
    static let clockSize = 31

    /// The person sits a little right of the desk's middle, leaving the left end of the
    /// desk top free for the nameplate (cols 1..16).
    static let dx = 10

    enum Pose: CaseIterable {
        case writeA, writeB, blink, dozeA, dozeB, stand, waveA, waveB, empty
        case stretchHalf, stretchUp, stretchLeft, stretchRight, content, oops, pickUp, found, lookUp
        case teaHold, teaSip, turnPage, cheer, yawn, nodA, nodB, nodC, startle, munchA, munchB
        case think, idea, spinA, spinB, spinC, spinD
        case restHands, blinkB, bend, recover, teaReach, teaLift, cookieSmall, crumbs, yawnStart, yawnEnd, readA, readB, bookmark, lookLeft, lookRight, foldArms, glanceLeft, glanceRight
    }

    /// A visiting friend: walking over, waving at an empty desk, or with the right arm
    /// held out to tap (the arm itself comes from `reachLayers`).
    enum Visiting: CaseIterable { case walk, wave, reach, cheer }

    private enum Eyes { case open, closed, happy, up, left, right, down }
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
        "Y": color(0xFFE27A), // lit bulb
        "1": color(0x2E3A66), // night sky
        "2": color(0xF6C2AE), // dawn
        "3": color(0x9ED3F6), // day
        "4": color(0xF4A36C), // sunset
        "5": color(0x9BD8A6), // sunlit leaves
        "6": color(0x65ABC4), "7": color(0x91AFC3), "8": color(0x73A78E), "9": color(0xBBB5CF), "0": color(0xF4D6A4),
        "S": color(0xC4E4F3), "T": color(0xCB8270), "U": color(0x966468), "W": color(0xFAD98B), "L": color(0xB5CE93), "N": color(0xEBCDB1),
        "X": color(0x9AA0AA), // laptop hinge and base
    ]

    /// A drink at the right end of the desk, picked at random for each study session.
    enum Drink: Int { case none, icedCoffee, mug, can, beer, soju }
    static let drinks = 5

    private static let drinkArt: [[String]] = [
        [],
        ["....kk.", "....k..", "kkkkkkk", "kiiiiik", ".koiok.", ".kiook.", ".kooik.", ".koiok.", ".koook.", ".kkkkk."],
        ["kkkkkk..", "koooOk..", "kwwwwkkk", "kwwwwk.k", "kwwwwkkk", "kwwwwk..", ".kkkk..."],
        [".kkkk.", "kxxxxk", "kttttk", "ktwwtk", "ktwwtk", "kttttk", "kxxxxk", ".kkkk."],
        ["kkkkkk..", "kwwwbkk.", "kyyyykkk", "kyiyyk.k", "kyyyyk.k", "kyyiykkk", "kyyyykk.", "kiiiik..", "kkkkkk.."],
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
        case .happy: marks = [(1, 4, "e"), (1, 12, "e"), (2, 3, "ese"), (2, 11, "ese")]
        case .down: marks = [(2, 4, "ew"), (2, 12, "ew"), (3, 4, "ee"), (3, 12, "ee")]
        case .left: marks = [(1, 3, "ew"), (1, 11, "ew"), (2, 3, "ee"), (2, 11, "ee")]
        case .right: marks = [(1, 5, "ew"), (1, 13, "ew"), (2, 5, "ee"), (2, 13, "ee")]
        case .up: marks = [(0, 4, "ew"), (0, 12, "ew"), (1, 4, "ee"), (1, 12, "ee")]
        }
        let lips: [(Int, Int, String)]
        switch mouth {
        case .small: lips = [(3, 8, "mm")]
        case .open: lips = [(3, 8, "ee"), (4, 8, "mm")]
        case .smile: lips = [(3, 7, "msm"), (4, 8, "m")]
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
    private static func headLayers(_ look: Look, _ eyes: Eyes, _ mouth: Mouth, _ x: Int, _ y: Int, lag: Int = 0) -> ([Layer], [Layer])
    {
        let tops = look.girl ? girlTops : boyTops
        let head = Layer(tops[look.hair % 5] + face(eyes, mouth), x, y)
        var back: [Layer] = []
        var front: [Layer] = [head]
        if look.girl && look.hair % 5 == 0 { back.append(Layer(longLeft, x - 3, y + 7)); back.append(Layer(mirror(longLeft), x + 17, y + 7))
        }
        if look.hair == 5 { back.append(Layer(["kRk", "khk", "kHk", "khk", "kHk", "khk", "kRk", ".k."], x + 16, y + 12)) }
        else if look.hair == 6 { front[0] = Layer(["........kk........", ".....kkkkkkkk.....", "...kkhhhhhhHhkk...", "..khhhhhhhhhhhhk..", ".khhhhhhhhhhhHhhk.", ".ksshhhhhhhhhhhhk.", ".ksssshhhhhhhhhhk.", ".ksssssshhhhhhhhk.", ".kssssssssshhhhhk."] + face(eyes, mouth), x, y) }
        else if look.hair == 7 || look.girl && look.hair == 1 { let side = look.hair == 7 ? ["..khk", ".khhk", "khhhk", ".khhk", "khHhk", ".khhk", "khhhk", ".khhk", "khhhk", ".khhk", "..khk", "...k."] : bobLeft; back.append(Layer(side, x - (look.hair == 7 ? 4 : 3), y + 7)); back.append(Layer(mirror(side), x + 17, y + 7))
        }
        else if look.girl && look.hair == 2 { back.append(Layer(pigtailLeft, x - 4, y + 9)); back.append(Layer(mirror(pigtailLeft), x + 17, y + 9))
        }
        else if look.girl && look.hair == 3 { front.append(Layer(bun, x, y)); front.append(Layer(bun, x + 12, y))
        }
        else if look.girl && look.hair == 4 { back.append(Layer(mirror(pigtailLeft), x + 16, y + 4)) }
        if look.additions & 1 != 0 && look.girl && look.hair == 0 { front.append(Layer(bow.enumerated().map { i, row in i < 3 || lag == 0 ? row : lag > 0 ? "." + String(row.dropLast()) : String(row.dropFirst()) + "." }, x + 11, y + 1)) }
        back = back.map { Layer($0.grid, $0.x + lag, $0.y) }
        if look.additions & 1 != 0 && look.girl && look.hair == 1 { front.append(Layer(hairpin, x + 13, y + 7)) }
        if look.additions & 1 == 0 {
            back = back.map { Layer($0.grid.map { $0.replacingOccurrences(of: "R", with: "h") }, $0.x, $0.y) }
            front = front.map { Layer($0.grid.map { $0.replacingOccurrences(of: "R", with: "h") }, $0.x, $0.y) }
        }
        if (look.customization.map{$0.on("head") && $0.value("head")==1} ?? (look.accessory == 2)) { front.append(Layer(["..p..", "ppppp", ".ppp.", ".p.p."], x + 12, y + 5)) }
        if (look.customization.map{$0.on("ear") && $0.value("ear")==1} ?? (look.accessory == 3)) { back.append(Layer(["..kkkkkkkkkkkkkk..", ".kk............kk.", "kk..............kk"], x, y + 4)); front.append(Layer(["kRk", "kRk", "kRk", "kkk"], x - 1, y + 9)); front.append(Layer(["kRk", "kRk", "kRk", "kkk"], x + 16, y + 9))
        }
        if look.additions & 4 != 0 && look.hat == 1 { front.append(Layer(["....kkkkkkkk....", "..kkAAAAAAAAkk..", ".kAAAAAAAAAAAAk.", "kCCCCCCCCCCCCCCk", "kkkkkkkkkkkkkkkk"], x + 1, y + 1)) }
        if look.additions & 4 != 0 && look.hat == 2 { front.append(Layer(["......kkkk......", "..kkkkAAAAkkkk..", "kkAAAAAAAAAAAAkk", ".kkkkkkkkkkkkkk."], x - 1, y + 1)) }
        if let custom=look.customization {front += custom.headLayers(x,y)}
        return (back, front)
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
        case 6:
            for col in 5...14 { paint(1, col, "C") }
            paint(2, 7, "C"); paint(2, 12, "C"); paint(3, 9, "R"); paint(3, 10, "R")
        case 7:
            for row in 0..<7 { paint(row, 7, "C") }
            paint(2, 7, "p")
        case 8:
            for col in 6...13 { paint(1, col, "C") }
            paint(2, 6, "C"); paint(2, 13, "C")
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
        var dressed = dress(shape, look.top)
        if let custom=look.customization {for layer in custom.layers("top") {var rows=dressed.map{Array($0)};for y in 0..<layer.grid.count {let line=Array(layer.grid[y]);for x in 0..<line.count {let xx=x+layer.x,yy=y+layer.y;if yy<rows.count && xx<rows[yy].count && "AaCJRw".contains(rows[yy][xx]) && line[x] != "." {rows[yy][xx]=line[x]}}};dressed=rows.map{String($0)}}}
        if look.sleeve > 0 { dressed = put(dressed, [(6, 3, look.sleeve == 3 ? "RR" : look.sleeve == 2 ? "AA" : "CC"), (6, 15, look.sleeve == 3 ? "RR" : look.sleeve == 2 ? "AA" : "CC")]) }
        return dressed.enumerated().map { i, row in
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
            if look.sleeve == 1 && i >= count - 3 { return "C" }
            if look.sleeve == 3 && i >= count - 3 { return "R" }
            switch look.top {
            case 1: return i >= count - 3 ? "a" : "A"  // sweater cuff
            case 3: return i % 2 == 0 ? "C" : "A"      // stripes
            default: return "A"
            }
        }, tip: look.sleeve == 2 ? "A" : "s", rooted: true)
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
    static func personalSticker(_ style: Int) -> [String] { style == 1 ? bigStickers[1] : style == 2 ? bigStickers[3] : ["pppp.", "ywy..", "yy...", "y...."] }
    static let awaySign = ["..kkkkkkkkkkkkkkkkkk..", ".kbbbbbbbbbbbbbbbbbbk.", "kbbbbbbbbbbbbbbbbbbbbk", "kbbbbbbbbbbbbbbbbbbbbk", "kbbbbbbbbbbbbbbbbbbbbk", "kbbbbbbbbbbbbbbbbbbbbk", "kbbbbbbbbbbbbbbbbbbbbk", "kbbbbbbbbbbbbbbbbbbbbk", "kbbbbbbbbbbbbbbbbbbbbk", ".kbbbbbbbbbbbbbbbbbbk.", "..kkkkkkkkkkkkkkkkkk..", "..........dd..........", "..........dd..........", "..........dd..........", "..........dd..........", "..........dd..........", "......kkkkkkkkkk......", ".....dddddddddddd....."]
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
        all += [lampOff, lampOn, laptopOpen, laptopShut] + bags + bigStickers + smallStickers
        for sky in 0..<4 { for season in 0..<4 { all.append(windowGrid(40, 30, sky: sky, season: season)) } }
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
    /// `decor` adds the things around a desk: the lamp, the sticker on its front and, while
    /// someone sits there, their bag on the hook and their drink. Without it, a bare desk.
    static func compose(_ pose: Pose, _ look: Look, alert: Bool = false, lift: Int = 0, decor: Decor? = nil, hairLag: Int = 0) -> [Layer] {
        let d = decor ?? Decor()
        var layers = pose == .empty ? [Layer(desk, 0, 27)] : composeAt(pose, look, alert: alert, laptop: d.laptop, hairLag: hairLag)
        if d.packed { layers.removeAll { $0.grid == book || $0.grid == laptopOpen || $0.grid == laptopShut || $0.grid == turningPage || $0.grid == pencilHand } }
        if lift != 0 { layers = layers.map { $0.grid == desk || $0.grid == book || $0.grid == laptopOpen || $0.grid == laptopShut ? $0 : Layer($0.grid, $0.x, $0.y - lift) } }
        guard decor != nil else { return layers }
        // The lamp first, so arms stretching left pass in front of it.
        let custom=look.customization
        if custom?.on("lamp") ?? true {if let c=custom,c.value("lamp")>0 {layers.insert(contentsOf:c.layers("lamp",lit:d.lit),at:0)}else{layers.insert(Layer(d.lit ? lampOn : lampOff,1,11),at:0)}}
        if let c=custom {layers.insert(contentsOf:c.layers("chair"),at:0)}
        // Just after the desk: on and in front of it, behind hands and whatever they hold.
        let at = (layers.firstIndex { $0.grid == desk } ?? 0) + 1
        let big = d.seed % bigStickers.count
        if custom?.on("deskStickers") ?? (look.additions & 2 != 0) {
            layers.insert(contentsOf: [
                Layer(bigStickers[big], 25, 31), Layer(smallStickers[d.seed % 2], 31, 32),
                Layer(bigStickers[(big + 1 + d.seed / bigStickers.count % 4) % bigStickers.count], 35, 31), Layer(smallStickers[1 - d.seed % 2], 4, 32),
            ], at: at)
        }
        if let c=custom {if c.on("deskStickers") && c.value("deskStickers")>0 {layers.removeAll{bigStickers.contains($0.grid)||smallStickers.contains($0.grid)};let designs=Customization.categories.first{$0.key == "deskStickers"}!.art,points=[(25,31),(31,32),(35,31),(4,32)];for i in 0..<4 {let art=designs[(c.value("deskStickers")-1+i*3)%designs.count];layers.insert(Layer(art["grid"] as! [String],points[i].0,points[i].1),at:at)}};layers.insert(contentsOf:c.layers("prop",clock:d.clock),at:at);if let replacement=c.layers("desk").first,let index=layers.firstIndex(where:{$0.grid == desk}){layers[index]=replacement}}
        if d.away { return layers }
        layers.insert(Layer(bags[look.bag], 42, 28), at: at)
        if !d.packed && (custom?.on("documentSticker") ?? (look.additions & 2 != 0 && look.sticker > 0)) { var sticker=custom?.layers("documentSticker").first?.grid ?? personalSticker(custom?.value("documentSticker") ?? look.sticker);let isNew=(custom?.value("documentSticker") ?? 0)>=4;if isNew {let height=d.laptop ? 4 : 3;sticker=(0..<height).map { y in sticker[Int((Double(y)*Double(sticker.count-1)/Double(height-1)).rounded(.toNearestOrEven))] }};layers.append(Layer(sticker,d.laptop ? 23 : 21,isNew ? (d.laptop ? 20 : 24) : (d.laptop ? 21 : 25))) }
        if [.teaReach, .teaHold, .teaLift, .teaSip].contains(pose) {
            layers.removeAll { $0.grid == teacup }
            let kind: Drink = d.drink == .none ? .mug : d.drink
            let step = pose == .teaSip ? 2 : pose == .teaLift ? 1 : 0
            let drink = tiltDrink(kind, step: step)
            var x = pose == .teaReach ? 35 : pose == .teaHold ? 30 : pose == .teaLift ? 28 : 24
            var y = (pose == .teaReach ? 27 : pose == .teaHold ? 23 : pose == .teaLift ? 21 : 19) - drink.count
            if step > 0 { (x,y) = drinkPosition(kind,step: step,rotated: drink,lipX: pose == .teaLift ? 30 : 25,lipY: look.hair == 6 ? 16 : 17) }
            layers.append(Layer(drink, x, y))
        } else if d.drink != .none { layers.insert(drinkLayer(d.drink), at: at) }
        return layers
    }

    /// What surrounds a desk. `seed` comes from the owner's name, so everyone sees the same
    /// bag and sticker; `lit` turns on the lamp (at night, studying; its light is drawLampLight);
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

    // A desk lamp behind the nameplate: base, a stem curving over into a shade tilted toward
    // the book. Lit, its bulb shows in the opening and beam slants down from it.
    private static let lampOff = [
        "...kkk........", "..k...kkk.....", "..k....kwk....", "..k...kwwwkk..", "..k....kwwwik.", "..k....kwwik..", "..k.....kwk...", "..k.....kk....",
        "..k...........", "..k...........", "..k...........", "..k...........", "..k...........", "..k...........", ".kkk..........", "kwwwk.........",
    ]
    // Lit, the inside of the shade's mouth glows too, so it reads at a glance.
    private static let lampOn = lampOff.enumerated().map { y, row -> String in
        switch y {
        case 3: return "..k...kwwYkk.."
        case 4: return "..k....kwYYYk."
        case 5: return "..k....kYYYk.."
        case 6: return "..k.....kYk..."
        default: return row
        }
    }
    // The lamp's light, from the shade's mouth down to the book and the desk top under it.
    // Drawn last and see-through, over the nameplate and whoever sits there.
    private static let beam = [
        "...........LL", "..........LLLL", ".........LLLLLL", ".........LLLLLLLL", "........LLLLLLLLLL", "........LLLLLLLLLLLL",
        ".......LLLLLLLLLLLLLL", ".......LLLLLLLLLLLLLLLL", "......LLLLLLLLLLLLLLLLLL", "......LLLLLLLLLLLLLLLLLLL", ".....LLLLLLLLLLLLLLLLLLLLL",
        "", "....LLLLLLLLLLLLLLLLLLLLLLLL",
    ]

    /// The light of a lit lamp, for drawing after everything else at that desk.
    static func drawLampLight(left: CGFloat, top: CGFloat, scale: CGFloat) {
        color(0xFFD855).withAlphaComponent(100.0 / 255).setFill()
        for (row, line) in beam.enumerated() {
            for (col, c) in line.enumerated() where c == "L" {
                NSRect(x: left + CGFloat(1 + col) * scale, y: top + CGFloat(16 + row) * scale, width: scale, height: scale).fill(using: .sourceOver)
            }
        }
    }

    // A backpack seen from the side, hanging by its strap on the hook at the desk's right end, in one of six colours.
    static func packingItemGrid(_ laptop: Bool, turn: Double=1) -> [String] {
        let source = (laptop ? laptopShut : book).map { Array($0) }
        if turn>=1 {return (0..<source[0].count).map { x in String(source.reversed().map { $0[x] }) }}
        let angle=turn * Double.pi/2,cosine=cos(angle),sine=sin(angle),w=source[0].count,h=source.count
        let width=Int(ceil(Double(w)*cosine+Double(h)*sine)),height=Int(ceil(Double(w)*sine+Double(h)*cosine))
        return (0..<height).map { y in String((0..<width).map { x -> Character in let dx=Double(x)-Double(width-1)/2,dy=Double(y)-Double(height-1)/2;let xx=Int(floor(cosine*dx+sine*dy+Double(w-1)/2+0.5)),yy=Int(floor(-sine*dx+cosine*dy+Double(h-1)/2+0.5));return xx>=0 && xx<w && yy>=0 && yy<h ? source[yy][xx] : "." }) }
    }
    static func drawPackingItem(_ look: Look, laptop: Bool, left: CGFloat, top: CGFloat, scale: CGFloat, turn: Double=1) {
        draw(layers: [Layer(packingItemGrid(laptop,turn:turn), 0, 0)], look, left: left, top: top, scale: scale)
    }
    static func drawPackingReach(_ look: Look,left: CGFloat,top: CGFloat,scale: CGFloat,targetX: Int,targetY: Int,leftHand: Bool=false) {draw(layers:[arm(look,(leftHand ? 19 : 31,18),(leftHand ? 19 : 32,21),(targetX,targetY))],look,left:left,top:top,scale:scale)}
    static func drawBag(_ look: Look, left: CGFloat, top: CGFloat, scale: CGFloat, open: Bool = false) {
        draw(layers: [Layer(bags[look.bag], 0, 0)], look, left: left, top: top, scale: scale)
        if open { draw(layers: [Layer(["kkkkk","kkkkk"], 1, 3)], look, left: left, top: top, scale: scale) }
    }

    private static let bags = "ztgprV".map { c in
        [".kk....", "k..k...", "k..kk..", "kkkMMk.", "kMMMMMk", "kMMMMMk", "kMMMkkk", "kMMMkMk", "kMMMkMk", ".kkkkk."].map { $0.replacingOccurrences(of: "M", with: String(c)) }
    }

    // Stickers on the desk's front, a few per desk: heart, star, smiley, clover, flower; and two little ones.
    private static let bigStickers = [
        [".r.r.", "rrrrr", ".rrr.", "..r.."],
        ["..p..", "ppppp", ".ppp.", ".p.p."],
        [".ppp.", "pkpkp", "pkkkp", ".ppp."],
        [".g.g.", "ggggg", ".ggg.", "..G.."],
        [".F.F.", "FFpFF", ".FFF.", "..g.."],
    ]
    private static let smallStickers = [["r.r", "rrr", ".r."], [".p.", "ppp", "p.p"]]

    /// The classroom's window, `w`×`h` pixels, any size from about 20×16: the sky of the hour
    /// (0 night, 1 dawn, 2 day, 3 sunset) with its sun, moon, clouds or stars at the right, and
    /// the tree in its season (0 spring, 1 summer, 2 autumn, 3 winter) high in the left corner.
    private static var windowCache: [String: [String]] = [:]
    private static var windowSize = ""
    static func windowGrid(_ w: Int, _ h: Int, sky: Int, season: Int, scene: Int = 0) -> [String] {
        let size = "\(w)x\(h)"
        if windowSize != size { windowCache.removeAll(); windowSize = size }
        let key = "\(sky)-\(season)-\(scene)"
        if let grid = windowCache[key] { return grid }
        let grid = buildWindow(w, h, sky: sky, season: season, scene: scene)
        windowCache[key] = grid
        return grid
    }
    private static func buildWindow(_ w: Int, _ h: Int, sky: Int, season: Int, scene: Int = 0) -> [String] {
        var grid = Array(repeating: Array(repeating: Array("1234")[sky], count: w), count: h)
        func put(_ x: Int, _ y: Int, _ c: Character) { if x > 0 && x < w - 1 && y > 0 && y < h - 2 { grid[y][x] = c } }
        func stamp(_ art: [String], _ x0: Int, _ y0: Int, _ c: Character) {
            for (y, row) in art.enumerated() { for (x, ch) in row.enumerated() where ch != "." { put(x0 + x, y0 + y, c) } }
        }
        if sky == 0 {
            for i in 0..<(w * h / 100) { put(w / 3 + (i * 7 + 3) % (w * 2 / 3 - 1), 1 + (i * 5 + 2) % (h * 2 / 3), "Y") }
            stamp([".YY", "YY.", "YY.", ".YY"], w - 7, 3, "Y")
        } else if sky == 2 {
            let cloud = ["..www...", ".wwwwww.", "wwwwwwww"]
            stamp(cloud, w - 11, 3, "w")
            stamp(cloud, w / 2 - 2, h / 3 + 1, "w")
        } else {
            stamp([".pp.", "pppp", "pppp", ".pp."], w - 9, 3, sky == 1 ? "Y" : "p")
        }

        func box(_ x0: Int,_ y0: Int,_ width: Int,_ height: Int,_ c: Character) { guard width > 0 && height > 0 else { return }; for y in y0..<(y0+height) { for x in x0..<(x0+width) { put(x,y,c) } } }
        func art(_ image: [String],_ x0: Int,_ y0: Int) { for (y,row) in image.enumerated() { for (x,c) in row.enumerated() where c != "." { put(x0+x,y0+y,c) } } }
        let grass: Character = season == 3 ? "b" : season == 2 ? "y" : "L"
        let leaf: Character = season == 0 ? "F" : season == 1 ? "g" : season == 2 ? "T" : "8"
        func tree(_ cx: Int,_ bottom: Int,_ r: Int) {
            box(cx,bottom-r-2,1,r+3,"o")
            for y in -r...r { for x in -r...r {
                if x*x+y*y <= r*r+1 && (abs(x)+abs(y)<r || (x*7+y*3+50)%4 != 0) {
                    let c: Character = season == 3 && y < -r/3 ? "w" : (x+y < -r/2 || (x*3+y*5+100)%11 == 0) ? (season == 3 ? "i" : season == 0 ? "b" : season == 1 ? "5" : "p") : leaf
                    put(cx+x,bottom-r-3+y,c)
                }
            } }
        }
        if sky == 2 { for y in (h/3)..<(h-2) { for x in 1..<(w-1) where grid[y][x] == "3" { put(x,y,"S") } } }
        if scene == 0 {
        // The tree: a trunk up from the sill, its crown in the season's colours, high up
        // in the corner where speech bubbles and heads don't hide it.
        // A trunk, then branches forking up and out of it; in winter they stay bare under
        // snow, otherwise leaves cover them in a few overlapping clumps, lit from the top left.
        let r = max(4, min(w / 5, h / 3))
        let cx = r, cy = r - 1
        for y in cy..<(h - 2) { put(cx, y, "o"); put(cx + 1, y, "o") }
        var branches: [(Int, Int)] = []
        for i in 1..<r {
            branches.append((cx - i, cy + 1 - i))          // up and to the left
            branches.append((cx + 1 + i, cy - i))          // up and to the right
            branches.append((cx + i % 2, cy - i))          // the leader, wavering up
            if i >= 2 { branches.append((cx - i + 1, cy - i - i % 2)) } // a twig off the left one
        }
        for (x, y) in branches { put(x, y, "o") }
        let (light, mid, dark): (Character, Character, Character) = season == 0 ? ("b", "F", "r") : season == 1 ? ("5", "g", "G") : ("p", "y", "t")
        if season == 3 {
            for (x, y) in branches where (x * 7 + y * 3) % 3 != 0 { put(x, y - 1, "w") }
        } else {
            let clumps = [(cx - r / 2, cy + r / 3, r * 2 / 3), (cx + 1 + r / 2, cy + r / 4, r * 2 / 3), (cx, cy - r / 3, r * 3 / 4), (cx + r, cy - r / 4, r / 2), (cx - r, cy, r / 2)]
            for y in 1..<(h - 2) {
                for x in 1..<(w - 1) {
                    for (qx, qy, q) in clumps {
                        let dx = x - qx, dy = y - qy, d2 = dx * dx + dy * dy
                        if d2 > q * q + q { continue }
                        // A ragged edge with gaps the branches show through.
                        if d2 > q * q - q && (x * 5 + y * 3) % 4 == 0 { break }
                        let s = dx + dy
                        put(x, y, s > q / 2 ? dark : s < -q / 2 || (x * 3 + y * 5) % 11 == 0 ? light : mid)
                        break
                    }
                }
            }
        }
        // Drifting: a few petals or leaves, or snow everywhere.
        let drift = season == 3 ? w * h / 30 : season == 0 || season == 2 ? 3 : 0
        for i in 0..<drift { put(2 + (i * 11 + 5) % (w - 4), 1 + (i * 7 + 3) % (h - 4), season == 3 ? "w" : dark) }

        if season == 1 { put(w - 4, h / 3 - 1, "G"); put(w - 5, h / 3 - 2, "i"); put(w - 3, h / 3 - 2, "i") }
        if season == 2 { put(w - 5, h - 3, "t"); put(w - 4, h - 3, "y"); put(w - 4, h - 4, "p") }
        if season == 3 { for i in 1...4 { put(w - 1 - i, h - 2 - i, "i"); put(w - 2 - i, h - 2 - i, "w") } }
        } else if scene == 1 {
            for x in 1..<(w-1) { let ridge = h/2 + Int((sin(Double(x)*0.18)*2).rounded(.toNearestOrEven)); for y in ridge..<(h-2) { put(x,y,grass) } }
            for y in (h/2)..<(h-2) { let center = w/2 + Int((sin(Double(y)*0.24)*3).rounded(.toNearestOrEven)); let width = 1+(y-h/2)/5; box(center-width,y,width*2+1,1,season == 3 ? "i" : "0") }
            let fence = h*2/3; box(1,fence,w-2,1,"b"); for x in stride(from:2,to:w-1,by:4) { box(x,fence-1,1,4,"w") }
            for i in 0..<(w*h/55) { let x = 2+(i*13+7)%(w-4); let y = h/2+2+(i*7+3)%max(1,h/2-5); if abs(x-w/2)>4 { put(x,y,"8"); put(x,y-1,season == 0 ? "r" : season == 1 ? "p" : season == 2 ? "t" : "w"); put(x+1,y-1,season == 0 ? "F" : season == 1 ? "b" : season == 2 ? "y" : "i") } }
            tree(w/5,h/2+3,max(3,min(w/8,h/5))); tree(w-6,h/2+4,3)
            art(["kkk","D.D","DDD"],w-8,h-7)
        } else if scene == 2 {
            box(1,h*2/3,w-2,h/3,"0"); box(1,h-5,w-2,1,"N")
            for x0 in stride(from:2,to:w-5,by:12) {
                let roof = h/2-2+(x0%3)*2; let height = h-6-roof
                box(x0,roof,9,height,"N"); box(x0,roof,1,height,"T")
                for y in 0..<4 { box(x0+4-y,roof-4+y,1+y*2,1,season == 3 ? "b" : y%2 == 0 ? "T" : "U") }
                box(x0+6,roof-5,1,3,"U")
                for x in stride(from:x0+2,to:x0+8,by:4) { for y in stride(from:roof+2,to:h-8,by:5) { box(x,y,2,3,sky == 0 ? "W" : "i"); box(x,y+1,2,1,sky == 0 ? "p" : "7") } }
                box(x0+4,h-9,2,4,"U"); box(x0+4,h-9,1,1,"W"); art(["ggg","FrF","DDD"],x0+1,h-7)
            }
            tree(w-5,h-4,3); for x in stride(from:2,to:w-2,by:5) { put(x,h-3,season == 3 ? "w" : season == 2 ? "T" : "N") }
        } else if scene == 3 {
            for x in 1..<(w-1) {
                let far = h/3+abs(x-w/3)/3; let near = h/3+2+abs(x-w*3/4)/2
                if far < h*2/3 { for y in far..<(h*2/3) { put(x,y,y < far+2 ? "i" : "7") } }
                if near < h*2/3 { for y in near..<(h*2/3) { put(x,y,y < near+2 && season == 3 ? "w" : "9") } }
                for y in (h*2/3)..<(h-2) { put(x,y,sky == 0 ? "1" : season == 3 ? "i" : "6") }
            }
            for y in stride(from:h*2/3+1,to:h-3,by:3) { let length = 2+y%5; let x = w/2-length/2+y%3; box(x,y,length,1,sky == 0 ? "7" : "i") }
            box(1,h-4,7,2,grass); tree(4,h-4,3); art(["...o...","...o...","..ww...",".www...","kkkkkkk",".DDDDD."],w*2/3,h-10)
        } else if scene == 4 {
            box(1,h/2,w-2,h/2,grass); tree(5,h/2+4,4); tree(w-6,h/2+2,3)
            for y in 0..<(h/3) { for x in 1..<(w-1) { let dx=x-w/2; let dy=y-h/6; if dx*dx*4+dy*dy*16 < w*w/2 { put(x,h/2+4+y,season == 3 ? "i" : "6") } } }
            let bridge=h*2/3; for x in (w/3)..<(w*2/3) { let y=bridge-min(2,min(x-w/3,w*2/3-1-x)); box(x,y,1,2,"0"); put(x,y+2,"D"); if x%3 == 0 { box(x,y-2,1,2,"b") } }
            art(["..p..",".pwp.","ggggg"],w-12,h-6); art([".w.","pww",".ww"],w/3,h-8)
            for x in stride(from:3,to:w-3,by:8) { put(x,h-4,"8"); put(x,h-5,season == 0 ? "F" : season == 1 ? "p" : season == 2 ? "T" : "w") }
        } else {
            for y in (h/2)..<(h-2) { box(1,y,w-2,1,sky == 0 ? "1" : "6") }
            for y in stride(from:h/2+2,to:h-3,by:4) { for x in stride(from:3+y%5,to:w-4,by:9) { box(x,y,4,1,sky == 0 ? "7" : "i") } }
            for x in 1..<(w/3+3) { let shore=h-4-(w/3-x)/3; for y in shore..<(h-2) { put(x,y,season == 3 ? "b" : "0") } }
            let ly=h-17
            art(["...t...","..ttt..",".UUUUU.",".kWWWk.",".kkkkk.","..bwb..","..bwb..","..ttt..","..ttt..","..bwb..","..bwb..","..ttt..",".DDDDD."],3,ly)
            art(["...9...","..999..",".99999.","9999999"],w-12,h-7); art(["w...w",".w.w.","..w.."],w/2,h/3)
            if sky == 0 { box(10,ly+3,4,1,"W"); box(14,ly+2,4,2,"Y") }
        }
        if scene != 0 && season == 3 { for i in 0..<(w*h/60) { put(2+(i*11+5)%(w-4),1+(i*7+3)%(h-4),"w") } }
        // Mullions every 16 pixels or so, a transom, then the frame and the sill.
        let panes = max(1, Int((Double(w - 2) / 16).rounded(.toNearestOrEven)))
        for p in stride(from: 1, to: panes, by: 1) { for y in 1..<(h - 2) { grid[y][(w - 1) * p / panes] = "d" } }
        for x in 1..<(w - 1) { grid[h / 3][x] = "d" }
        for x in 0..<w { grid[0][x] = "k"; grid[h - 2][x] = "k"; grid[h - 1][x] = "D" }
        for y in 0..<(h - 1) { grid[y][0] = "k"; grid[y][w - 1] = "k" }
        return grid.map { String($0) }
    }

    static func drawWindow(_ w: Int, _ h: Int, sky: Int, season: Int, left: CGFloat, top: CGFloat, scale: CGFloat, scene: Int = 0) {
        draw(layers: [Layer(windowGrid(w, h, sky: sky, season: season, scene: scene), 0, 0)], Look(girl: false, 0, 0, 0, 0, 0, 0), left: left, top: top, scale: scale)
    }

    // A laptop seen from the front of the desk: the back of its lid, and shut for a nap.
    // The lid leans back (its top edge narrower), over a darker hinge and the base's front edge.
    private static let laptopOpen = ["...kkkkkkkkkkkk...", "..kxxxxxxxxxxxxk..", "..kxxxxxwwxxxxxk..", "..kxxxxxwwxxxxxk..", "..kxxxxxxxxxxxxk..", ".kkXXXXXXXXXXXXkk.", "kXXXXXXXXXXXXXXXXk"]
    private static let laptopShut = ["kkkkkkkkkkkkkk", "kxxxxxxxxxxxxk", "kkkkkkkkkkkkkk"]

    private static func composeAt(_ pose: Pose, _ look: Look, alert: Bool, laptop: Bool, hairLag: Int) -> [Layer] {
        var pose = pose
        if laptop && [.oops, .pickUp, .bend, .recover, .found, .think, .idea, .spinA, .spinB, .spinC, .spinD].contains(pose) { pose = [.idea, .found].contains(pose) ? .content : .restHands }
        if pose == .pickUp {
            let (back, head) = headLayers(look, .down, .small, 10, 12)
            var shifted = shift([Layer(body(look, sitting: true), 6, 22)] + back + head + [Layer(pencilHand, 28, 30)])
            shifted.insert(Layer(desk, 0, 27), at: 1)
            return shifted + shift([Layer(laptop ? laptopOpen : book, laptop ? 6 : 9, laptop ? 20 : 24)])
        }
        if pose == .dozeA || pose == .dozeB {
            // Head down on the desk, so the desk goes underneath it.
            let (back, head) = headLayers(look, .closed, .small, 7, pose == .dozeA ? 10 : 11)
            var resting = [Layer(body(look, sitting: true), 6, 22), Layer(laptop ? laptopShut : book, 9, 24)] + back + head
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
        case .restHands, .foldArms:
            if pose == .foldArms { headY = 7; eyes = .closed }
            leftArm = true; rightArm = true; leftHand = Layer(hand, 10, 25); rightHand = Layer(hand, 14, 25)
            behind.append(arm(look, (9,22), (11,24), (13,25)))
            behind.append(arm(look, (21,22), (19,24), (15,25)))
        case .blinkB: eyes = .closed; rightHand = Layer(pencilHand, 18, 22)
        case .glanceLeft: eyes = .left
        case .glanceRight: eyes = .right
        case .lookLeft: eyes = .left; sway = -1
        case .lookRight: eyes = .right; sway = 1
        case .bend: headY = 6; rightHand = Layer(hand, 24, 26); eyes = .down
        case .recover: headY = 5; rightHand = Layer(pencilHand, 22, 21)
        case .teaReach: rightHand = Layer(hand, 24, 24)
        case .teaLift: rightHand = nil; front.append(Layer(teacup, 18, 19)); front.append(Layer(hand, 19, 23))
        case .cookieSmall:
            leftHand = nil; leftArm = true; front.append(Layer([".kk.", "klDk", ".kk."], 10, 16))
            front.append(arm(look, (9,22), (10,21), (11,19)))
        case .crumbs: front.append(Layer(["l.l", ".l."], 12, 25))
        case .yawnStart: eyes = .closed; mouth = .open
        case .yawnEnd: leftHand = Layer(hand, 9, 22)
        case .readA, .readB: eyes = .down; rightHand = Layer(hand, pose == .readA ? 12 : 16, 24)
        case .bookmark:
            bookLayer = Layer(turningPage, 9, 23); rightHand = Layer(hand, 17, 23)
            front.append(Layer(["RR", "RR", "RR", "R."], 17, 23))
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
            eyes = .open
            mouth = .smile
        case .oops:
            eyes = .down
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
            rightArm = true; behind.append(arm(look, (21,22), (23,23), (21,22)))
            rightHand = nil
            front.append(Layer(teacup, 20, 18))
            front.append(Layer(hand, 20, 22))
        case .teaSip:
            rightArm = true; behind.append(arm(look, (21,22), (19,21), (16,20)))
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
            eyes = .down
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

        let (hairBack, faceLayers) = headLayers(look, eyes, mouth, 7, headY, lag: hairLag)
        let person = [Layer(body(look, sitting: !standing, leftArm: leftArm, rightArm: rightArm), 6, standing ? 16 : 20)] + hairBack + behind + faceLayers
        // With a laptop the lid hides the book's place; the hands type at its sides.
        var lying = [bookLayer]
        if laptop {
            lying = [Layer(pose == .foldArms ? ["..kkkkkkkkkkkk...", "..kxxxxxxxxxxk...", ".kkxxxxxxxxxxkk..", "kkkkkkkkkkkkkkkkk", "kXXXXXXXXXXXXXXXk"] : laptopOpen, 6, pose == .foldArms ? 22 : 20)]
            let up = pose == .writeB || pose == .blinkB ? 1 : 0
            if let l = leftHand, l.grid == hand, l.x == 7 { leftHand = Layer(hand, 4, 23 + up) }
            if [.turnPage, .bookmark, .readA, .readB].contains(pose) { leftHand = Layer(hand, 4, 24); rightHand = Layer(hand, 18, 24); front.removeAll() }
            if let r = rightHand, r.grid == pencilHand { rightHand = Layer(hand, 21, 24 - up) }
        }
        if laptop { front.removeAll { $0.grid == teacup } }
        var onDesk: [Layer] = []
        if let left = leftHand { onDesk.append(left) }
        if let right = rightHand { onDesk.append(right) }
        onDesk += front
        if look.leftHanded && [.writeA, .writeB, .blink, .blinkB, .readA, .readB].contains(pose) {
            onDesk = onDesk.map { Layer(mirror($0.grid), 32 - $0.x - $0.grid[0].count, $0.y) }
        }
        if let mark = mark { onDesk.append(Layer(mark, mark == question ? 28 : 26, 1)) }
        func move(_ l: Layer) -> Layer { Layer(l.grid, l.x + sway, l.y - rise) }
        // Person, then the desk in front of their lap, then what lies on the desk.
        var on = onDesk.map(move)
        if laptop { let lid = lying[0]; on = on.map { Layer(maskLaptop($0.grid, x: $0.x, y: $0.y, lid: lid), $0.x, $0.y) } }
        return shift(person.map(move)) + [Layer(desk, 0, 27)] + shift(lying) + shift(on)
    }

    static func maskLaptop(_ grid: [String], x: Int, y: Int, lid: Layer) -> [String] {
        let mask = lid.grid.map(Array.init)
        return grid.enumerated().map { j, row in String(row.enumerated().map { i, c in
            let mx = x + i - lid.x, my = y + j - lid.y
            return my >= 0 && my < mask.count && mx >= 0 && mx < mask[my].count && mask[my][mx] != "." ? Character(".") : c
        }) }
    }
    static func heldDrink(_ drink: Drink, tilted: Bool) -> [String] { tiltDrink(drink, step: tilted ? 2 : 0) }
    private static func tiltDrink(_ drink: Drink, step: Int) -> [String] {
        let art = drinkArt[drink.rawValue].map(Array.init)
        if step == 0 { return drinkArt[drink.rawValue] }
        let r = sqrt(3.0) / 2; let cosine = step == 1 ? r : 0.5; let sine = step == 1 ? -0.5 : -r
        let w = art[0].count, h = art.count
        let width = Int(ceil(Double(w)*cosine - Double(h)*sine)), height = Int(ceil(Double(h)*cosine - Double(w)*sine))
        var result: [String] = []
        let centerX = Double(width - 1) / 2.0
        let centerY = Double(height - 1) / 2.0
        let sourceX = Double(w - 1) / 2.0
        let sourceY = Double(h - 1) / 2.0
        for y in 0..<height {
            var row: [Character] = []
            let dy = Double(y) - centerY
            for x in 0..<width {
                let dx = Double(x) - centerX
                let sampleX: Double = cosine * dx + sine * dy + sourceX
                let sampleY: Double = -sine * dx + cosine * dy + sourceY
                let sx = Int(sampleX.rounded(.toNearestOrEven))
                let sy = Int(sampleY.rounded(.toNearestOrEven))
                let inside = sx >= 0 && sx < w && sy >= 0 && sy < h
                row.append(inside ? art[sy][sx] : Character("."))
            }
            result.append(String(row))
        }
        return result
    }
    private static func drinkPosition(_ kind: Drink, step: Int, rotated: [String], lipX: Int, lipY: Int) -> (Int, Int) {
        let source = drinkArt[kind.rawValue], cx = Double(drinkArt[kind.rawValue][0].count-1)/2
        let cy = Double(source.count-1)/2, dx = kind == .icedCoffee ? 5-cx : kind == .beer ? 2.5-cx : 0
        let dy = -cy, r = sqrt(3.0)/2
        let cosine = step == 1 ? r : 0.5, sine = step == 1 ? -0.5 : -r
        let x = cosine*dx-sine*dy+Double(rotated[0].count-1)/2
        let y = sine*dx+cosine*dy+Double(rotated.count-1)/2
        return (lipX-Int(x.rounded(.toNearestOrEven)),lipY-Int(y.rounded(.toNearestOrEven)))
    }
    static func flame(_ alt: Bool) -> [String] { alt ? ["..t.", ".tt.", "tpty", "tyyt", ".pp."] : [".t..", ".tt.", "ytpt", "tyyt", ".pp."] }
    static func drawFlameEyes(left: CGFloat, top: CGFloat, scale: CGFloat, alt: Bool) { draw(layers: [Layer(flame(alt), 20, 12), Layer(flame(!alt), 28, 12)], Look(girl: false, 0, 0, 0, 0, 0, 0), left: left, top: top, scale: scale) }
    static func clockGrid(_ hour: Int, _ minute: Int) -> [String] {
        let center = 15
        var grid = Array(repeating: Array(repeating: Character("."), count: clockSize), count: clockSize)
        for y in 0..<clockSize { for x in 0..<clockSize {
            let radius = (x-center)*(x-center)+(y-center)*(y-center)
            if radius <= 225 { grid[y][x] = radius >= 196 ? "d" : "b" }
        } }
        for tick in 0..<60 {
            let angle = Double(tick) * .pi / 30
            for radius in (tick % 5 == 0 ? 10 : 12)...12 {
                let x = center + Int((sin(angle) * Double(radius)).rounded(.toNearestOrEven))
                let y = center - Int((cos(angle) * Double(radius)).rounded(.toNearestOrEven))
                grid[y][x] = "D"
            }
        }
        func hand(_ angle: Double, _ length: Int) {
            for i in 0...(length * 3) {
                let x = center + Int((sin(angle) * Double(i) / 3).rounded(.toNearestOrEven))
                let y = center - Int((cos(angle) * Double(i) / 3).rounded(.toNearestOrEven))
                grid[y][x] = "k"
            }
        }
        hand((Double(hour % 12) + Double(minute) / 60) * .pi / 6, 7)
        hand(Double(minute) * .pi / 30, 9)
        grid[center][center] = "t"
        return grid.map { String($0) }
    }
    static func drawClock(_ hour: Int, _ minute: Int, left: CGFloat, top: CGFloat, scale: CGFloat) { draw(layers: [Layer(clockGrid(hour, minute), 0, 0)], Look(girl: false, 0, 0, 0, 0, 0, 0), left: left, top: top, scale: scale) }

    /// A friend standing up, with legs since no desk hides them. `leftHand` waves with the
    /// other hand, the one away from a seated friend who would hide it.
    static func visitor(_ look: Look, _ pose: Visiting, alt: Bool, leftHand: Bool = false) -> [Layer] {
        let walking = pose == .walk
        let left = leftHand && (pose == .wave || pose == .cheer)
        let (back, head) = headLayers(look, .open, walking ? .small : .smile, 7, 0)
        var layers = [
            Layer(body(look, sitting: false, leftArm: walking || left, rightArm: walking || !left), 6, 16),
            Layer(legs(look, lifted: walking ? (alt ? 1 : 2) : 0), 6, 27),
        ] + back
        if walking {
            layers.append(arm(look, (9, 18), (alt ? 7 : 10, 22), (alt ? 6 : 11, 25)))
            layers.append(arm(look, (21, 18), (alt ? 22 : 19, 22), (alt ? 23 : 18, 25)))
        }
        if pose == .cheer { layers.append(left ? arm(look, (9,18), (5,20), (4, alt ? 15 : 16)) : arm(look, (21,18), (25,20), (26, alt ? 15 : 16))) }
        else if left { layers.append(arm(look, (9, 18), (5, 15), alt ? (4, 8) : (2, 9))) }
        else if pose == .wave { layers.append(arm(look, (21, 18), (25, 15), alt ? (26, 8) : (28, 9))) }
        return shift(layers + head)
    }

    /// The visitor's arm reaching right to a shoulder; drawn after the pet it taps.
    /// `down` is the tap, the other frame the hand lifted.
    static func reachLayers(_ look: Look, down: Bool) -> [Layer] {
        shift([arm(look, (21, 18), (24, down ? 21 : 20), (29, down ? 21 : 20))])
    }

    private static func shift(_ layers: [Layer]) -> [Layer] { layers.map { Layer($0.grid, $0.x + dx, $0.y) } }

    static func draw(_ pose: Pose, _ look: Look, left: CGFloat, top: CGFloat, scale: CGFloat, alert: Bool = false, lift: Int = 0, decor: Decor? = nil, hairLag: Int = 0) {
        draw(layers: compose(pose, look, alert: alert, lift: lift, decor: decor, hairLag: hairLag), look, left: left, top: top, scale: scale)
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
        NSSize(width: CGFloat(sheetColumns * width) * scale, height: CGFloat((2 * poseRows + 5) * height) * scale)
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
        // Desks: each drink with another bag and sticker, then laptops, the lamp lit and an empty desk.
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
            (.teaHold, girl, Decor(drink: .soju, laptop: true, seed: 29, lit: true), 0),
            (.writeA, boy, Decor(drink: .can, laptop: false, seed: 2, lit: false), 1),
            (.empty, girl, Decor(drink: .beer, laptop: true, seed: 8, lit: false, away: true), 0),
        ]
        for (i, d) in desks.enumerated() {
            let (x, y) = at(row + sheetColumns + i)
            draw(d.0, d.1, left: x, top: y, scale: scale, alert: d.3 > 0, lift: d.3, decor: d.2)
        }
        // Windows: every season, each under another sky.
        for (i, (sky, season)) in [(2, 0), (1, 0), (2, 1), (0, 1), (3, 2), (2, 2), (0, 3), (2, 3)].enumerated() {
            let (x, y) = at(row + 2 * sheetColumns + i)
            drawWindow(40, 34, sky: sky, season: season, left: x + 2 * scale, top: y + 2 * scale, scale: scale)
        }
    }

    static func draw(layers: [Layer], _ look: Look, left: CGFloat, top: CGFloat, scale: CGFloat) {
        let hair = hairColorSet[look.hairColor]
        let top3 = topColorSet[look.topColor]
        var colors = palette
        colors["s"] = color([0xFFE0C8, 0xFFF4EC, 0xD2A17C, 0x83523E][look.skin])
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
