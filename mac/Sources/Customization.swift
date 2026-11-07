import AppKit
import CoreFoundation
final class Customization: Equatable {
    struct Choice { var enabled: Bool; var value: Int; var locked = false }
    struct Category { var key: String; var title: String; var group: String; var optional: Bool; var legacy: Int; var art: [[String:Any]]; var count: Int { legacy + art.count + 1 } }
    /// Shared/customization.json: all the art, colours, poses and routines.
    static let root: [String:Any] = {
        guard let url=Bundle.main.url(forResource:"customization",withExtension:"json"),let data=try? Data(contentsOf:url),let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any] ,obj["slots"] is [[String:Any]] else { fatalError("Missing customization catalog") }
        return obj
    }()
    private static let baseArt = root["baseArt"] as! [String:[String]]
    static func artwork(_ key: String) -> [String] { baseArt[key]! }
    static var baseArtNames: [String] { Array(baseArt.keys) }
    static let categories: [Category] = {
        let slots=root["slots"] as! [[String:Any]]
        return slots.map { Category(key:$0["key"] as! String,title:$0["title"] as! String,group:$0["group"] as! String,optional:$0["optional"] as! Bool,legacy:$0["legacy"] as! Int,art:$0["variants"] as! [[String:Any]]) }
    }()
    var slots: [String:Choice] = [:]
    static func legacy(_ look: Look) -> Customization {
        let c=Customization();for s in categories { c.slots[s.key]=Choice(enabled: !s.optional || s.key == "lamp",value:0) }
        c.slots["hair"]!.value=look.hair;c.slots["top"]!.value=look.top
        c.slots["hat"]=Choice(enabled:look.additions & 4 != 0 && look.hat>0,value:max(1,look.hat))
        c.slots["documentSticker"]=Choice(enabled:look.additions & 2 != 0 && look.sticker>0,value:max(1,look.sticker))
        c.slots["deskStickers"]!.enabled=look.additions & 2 != 0
        c.slots["head"]=Choice(enabled:look.accessory == 2,value:1);c.slots["ear"]=Choice(enabled:look.accessory == 3,value:1)
        return c
    }
    static func parse(_ raw: Any?, _ look: Look) -> Customization {
        let c=legacy(look);var obj=raw
        if let text=raw as? String,let data=text.data(using:.utf8){obj=try? JSONSerialization.jsonObject(with:data)}
        guard let root=obj as? [String:Any],root["version"] as? Int == 1,let values=root["slots"] as? [String:Any] else { return c }
        for s in categories { if let v=values[s.key] as? [String:Any],let n=v["value"] as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),Double(n.intValue)==n.doubleValue,(0..<s.count).contains(n.intValue),let enabled=v["enabled"] as? Bool {c.slots[s.key]=Choice(enabled: !s.optional || enabled,value:n.intValue,locked:v["locked"] as? Bool ?? false)} }
        return c
    }
    func copy() -> Customization {let c=Customization();c.slots=slots;return c}
    func data(shared: Bool=false) -> [String:Any] { var result: [String:Any]=[:];for s in Self.categories where !shared || s.group != "classroom" {let v=slots[s.key]!;var entry: [String:Any]=["enabled":v.enabled,"value":v.value];if !shared{entry["locked"]=v.locked};result[s.key]=entry};return ["version":1,"slots":result] }
    var json: String {String(data:try! JSONSerialization.data(withJSONObject:data(),options:.sortedKeys),encoding:.utf8)!}
    static func ==(a: Customization,b: Customization) -> Bool {a.json == b.json}
    func on(_ key: String) -> Bool { slots[key]!.enabled }
    func value(_ key: String) -> Int { slots[key]!.value }
    func roll(_ group: String) { for s in Self.categories where s.group == group { if on(s.key) && !slots[s.key]!.locked { let minValue=s.optional && s.key != "lamp" && s.key != "deskStickers" ? 1 : 0;slots[s.key]!.value=Int.random(in:minValue..<s.count) } } }
    func layers(_ key: String,_ x: Int=0,_ y: Int=0,lit: Bool=true,clock: Date=Date()) -> [Sprites.Layer] {
        guard on(key),let s=Self.categories.first(where:{$0.key == key}),let art=s.art.first(where:{$0["id"] as? Int == value(key)}) else {return []}
        var grid=art["grid"] as! [String];if key == "clock" && value(key)==1 {grid=Self.swing(grid,clock)};if key == "lamp" && !lit {grid=grid.map{$0.replacingOccurrences(of:"Y",with:"w")}}
        if key == "prop" && value(key) == 7 {grid=Self.digital(grid,clock,compact:true)}
        return [Sprites.Layer(grid,x+(art["x"] as! Int),y+(art["y"] as! Int))]
    }
    func headLayers(_ x: Int,_ y: Int) -> [Sprites.Layer] { ["head","hat","ear","neck","badge"].flatMap{layers($0,x,y)} }
    func legacyLook(_ look: Look) -> Look {
        var hair=value("hair");if hair>=8 {hair=Self.categories.first{$0.key == "hair"}!.art.first{$0["id"] as? Int == hair}!["base"] as! Int};let top=value("top")<9 ? value("top") : 0
        var e=Array(look.extra.prefix(7));e[0]=on("head") && value("head")==1 ? "2" : on("ear") && value("ear")==1 ? "3" : "0";e[2]=on("hat") && value("hat")<=2 ? Character(String(value("hat"))) : "0";e[5]=on("documentSticker") ? Character(String(min(3,value("documentSticker")))) : "0"
        let mask=(look.additions & 1) | (on("deskStickers") || on("documentSticker") ? 2 : 0) | (on("hat") ? 4 : 0)
        return Look(girl:look.girl,hair,look.hairColor,top,look.topColor,look.bottom,look.ribbon).withExtras(String(e)+String(mask)).withCustomization(self)
    }
    static func swing(_ source: [String],_ date: Date) -> [String] {
        var rows=source.map{Array($0)}
        let second=Calendar.current.component(.second,from:date)
        let fraction=date.timeIntervalSince1970-floor(date.timeIntervalSince1970)
        let dx=Int(floor(sin((Double(second)+fraction)*Double.pi)*2+0.5))
        for y in 29..<39 {for x in 11..<20 {rows[y][x]="k"}}
        for y in 29...35 {let x=15+Int(floor(Double(dx)*Double(y-29)/6.0+0.5));rows[y][x]="y"}
        for y in 34..<38 {for x in (13+dx)..<(18+dx) {rows[y][x]="p"}}
        rows[34][14+dx]="Y"
        return rows.map{String($0)}
    }
    static let digits="111/101/101/101/111 010/110/010/010/111 111/001/111/100/111 111/001/111/001/111 101/101/111/001/001 111/100/111/001/111 111/100/111/101/111 111/001/010/010/010 111/101/111/101/111 111/101/111/001/111".split(separator:" ").map{$0.split(separator:"/").map{Array($0)}}
    static func digital(_ source: [String],_ date: Date,compact: Bool=false) -> [String] { var rows=source.map{Array($0)};let parts=Calendar.current.dateComponents([.hour,.minute],from:date);let text=String(format:"%02d%02d",parts.hour ?? 0,parts.minute ?? 0).map{Int(String($0))!};for n in 0..<4 {for y in 0..<(compact ? 3 : 5) {for x in 0..<(compact ? 2 : 3) {let xx=(compact ? 1+(n%2)*3 : 7+n*4)+x,yy=(compact ? 1+(n/2)*4 : 6)+y;if yy<rows.count && xx<rows[yy].count {rows[yy][xx]=digits[text[n]][compact ? y*2 : y][compact ? x*2 : x] == "1" ? "Y" : compact ? "G" : "1"}}}};return rows.map{String($0)} }

    static func resize(_ grid: [String],_ w: Int,_ h: Int) -> [String] {
        let rows=grid.map{Array($0)}
        return (0..<h).map { y in String((0..<w).map{x in rows[y*rows.count/h][x*rows[0].count/w]}) }
    }
    static func drawFloor(_ rect: NSRect,_ scale: CGFloat,_ light: Bool) {
        Sprites.color(light ? 0xEFDCB9 : 0xDEC7A5).setFill();rect.fill()
        let seams=NSBezierPath();seams.lineWidth=1
        var row=0
        while CGFloat(row)*8*scale<rect.height {
            let y=rect.minY+CGFloat(row)*8*scale
            seams.move(to:NSPoint(x:rect.minX,y:y));seams.line(to:NSPoint(x:rect.maxX,y:y))
            var x=rect.minX+CGFloat(row%2==0 ? 12 : 28)*scale
            while x<rect.maxX {seams.move(to:NSPoint(x:x,y:y));seams.line(to:NSPoint(x:x,y:min(rect.maxY,y+8*scale)));x+=40*scale}
            row+=1
        }
        Sprites.color(light ? 0xDCC6A2 : 0xC8AF8F).setStroke();seams.stroke()
        Sprites.color(0x936F4F).setFill();NSRect(x:rect.minX,y:rect.minY-2*scale,width:rect.width,height:2*scale).fill()
        Sprites.color(0xC29D74).setFill();NSRect(x:rect.minX,y:rect.minY-2*scale,width:rect.width,height:scale).fill()
    }
    func drawClock(_ look: Look,_ x: CGFloat,_ y: CGFloat,_ scale: CGFloat,_ date: Date) {
        let parts=Calendar.current.dateComponents([.hour,.minute],from:date),art=layers("clock",clock:date)
        if art.isEmpty {Sprites.drawClock(parts.hour ?? 0,parts.minute ?? 0,left:x,top:y,scale:scale);return}
        let grid=value("clock")==2 ? Self.digital(art[0].grid,date) : art[0].grid
        Sprites.draw(layers:[Sprites.Layer(grid,0,0)],look,left:x,top:y,scale:scale)
        if value("clock")==1 {let face=Self.resize(Sprites.clockGrid(parts.hour ?? 0,parts.minute ?? 0),19,19);Sprites.draw(layers:[Sprites.Layer(face,6,5)],look,left:x,top:y,scale:scale)}
    }
    func drawRoom(_ look: Look,_ rect: NSRect,_ date: Date,preview: Bool=true) {
        if preview {
            let scale=max(1,min(rect.width/226,rect.height/70).rounded(.down)),x=rect.minX+(rect.width-226*scale)/2,y=rect.minY
            Sprites.color(0xEFE7D8).setFill();rect.fill()
            Self.drawFloor(NSRect(x:rect.minX,y:y+58*scale,width:rect.width,height:max(0,rect.maxY-y-58*scale)),scale,on("floor"))
            Sprites.color(0xA87452).setFill();NSRect(x:x+51*scale,y:y,width:124*scale,height:14*scale).fill()
            Sprites.color(0x3F5C4E).setFill();NSRect(x:x+53*scale,y:y+2*scale,width:120*scale,height:10*scale).fill()
            Sprites.color(0xEEEBD5).setFill();NSRect(x:x+90*scale,y:y+7*scale,width:46*scale,height:2*scale).fill()
            Sprites.drawWindow(98,32,sky:PetWindow.skyAt(date),season:PetWindow.seasonAt(date),left:x+64*scale,top:y+18*scale,scale:scale)
            drawRoom(look,NSRect(x:x+64*scale,y:y+18*scale,width:98*scale,height:32*scale),date,preview:false)
            drawClock(look,x+16*scale,y+18*scale,max(1,scale/2),date)
            for i in 0..<3 {Sprites.draw(i==1 ? .writeA : .empty,look,left:x+CGFloat(20+i*70)*scale,top:y+32*scale,scale:scale,decor:Sprites.Decor(seed:7,away:i != 1))}
            return
        }
        let unit=max(1,min(rect.width/98,rect.height/32).rounded(.down))
        for key in ["window","wall","hangingPlant","lights"] {
            guard let layer=layers(key).first else {continue}
            var grid=layer.grid,x=rect.minX,y=rect.minY
            if key == "window" || key == "lights" {
                grid=Self.resize(grid,Int(rect.width/unit)+14,key == "window" ? Int(rect.height/unit)+6 : 10)
                x-=7*unit;y-=3*unit
            }
            if key == "wall" {x=rect.maxX+8*unit;y+=24*unit}
            if key == "hangingPlant" {x=rect.maxX-4*unit;y+=2*unit}
            if key == "lights" {for row in grid.indices {let cells=Array(grid[row]);for col in cells.indices where cells[col] == "Y" && (col==0 || cells[col-1] != "Y") && (row==0 || Array(grid[row-1])[col] != "Y") {
                NSColor(calibratedRed:1,green:214.0/255,blue:100.0/255,alpha:26.0/255).setFill()
                NSRect(x:x+CGFloat(col-3)*unit,y:y+CGFloat(row-3)*unit,width:9*unit,height:9*unit).fill(using:.sourceOver)
                NSColor(calibratedRed:1,green:226.0/255,blue:142.0/255,alpha:62.0/255).setFill()
                NSRect(x:x+CGFloat(col-1)*unit,y:y+CGFloat(row-1)*unit,width:5*unit,height:5*unit).fill(using:.sourceOver)
            }}}
            Sprites.draw(layers:[Sprites.Layer(grid,0,0)],look,left:x,top:y,scale:unit)
        }
    }
}
