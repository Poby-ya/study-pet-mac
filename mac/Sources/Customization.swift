import AppKit
import CoreFoundation
final class Customization: Equatable {
    struct Choice { var enabled: Bool; var value: Int; var locked = false }
    struct Category { var key: String; var title: String; var group: String; var optional: Bool; var legacy: Int; var art: [[String:Any]]; var count: Int { legacy + art.count + 1 } }
    static let categories: [Category] = {
        guard let url=Bundle.main.url(forResource:"customization",withExtension:"json"),let data=try? Data(contentsOf:url),let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let slots=obj["slots"] as? [[String:Any]] else { fatalError("Missing customization catalog") }
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
        var grid=art["grid"] as! [String];if key == "lamp" && !lit {grid=grid.map{$0.replacingOccurrences(of:"Y",with:"w")}}
        if key == "prop" && value(key) == 7 {grid=Self.digital(grid,clock,compact:true)}
        return [Sprites.Layer(grid,x+(art["x"] as! Int),y+(art["y"] as! Int))]
    }
    func headLayers(_ x: Int,_ y: Int) -> [Sprites.Layer] { ["hair","head","hat","ear","neck","badge"].flatMap{layers($0,x,y)} }
    func legacyLook(_ look: Look) -> Look {
        var hair=value("hair");if hair>=8 {hair=Self.categories.first{$0.key == "hair"}!.art.first{$0["id"] as? Int == hair}!["base"] as! Int};let top=value("top")<9 ? value("top") : 0
        var e=Array(look.extra.prefix(7));e[0]=on("head") && value("head")==1 ? "2" : on("ear") && value("ear")==1 ? "3" : "0";e[2]=on("hat") && value("hat")<=2 ? Character(String(value("hat"))) : "0";e[5]=on("documentSticker") ? Character(String(min(3,value("documentSticker")))) : "0"
        let mask=(look.additions & 1) | (on("deskStickers") || on("documentSticker") ? 2 : 0) | (on("hat") ? 4 : 0)
        return Look(girl:look.girl,hair,look.hairColor,top,look.topColor,look.bottom,look.ribbon).withExtras(String(e)+String(mask)).withCustomization(self)
    }
    static let digits="111/101/101/101/111 010/110/010/010/111 111/001/111/100/111 111/001/111/001/111 101/101/111/001/001 111/100/111/001/111 111/100/111/101/111 111/001/010/010/010 111/101/111/101/111 111/101/111/001/111".split(separator:" ").map{$0.split(separator:"/").map{Array($0)}}
    static func digital(_ source: [String],_ date: Date,compact: Bool=false) -> [String] { var rows=source.map{Array($0)};let parts=Calendar.current.dateComponents([.hour,.minute],from:date);let text=String(format:"%02d%02d",parts.hour ?? 0,parts.minute ?? 0).map{Int(String($0))!};for n in 0..<4 {for y in 0..<(compact ? 3 : 5) {for x in 0..<(compact ? 2 : 3) {let xx=(compact ? (n%2)*3 : 7+n*4)+x,yy=(compact ? 1+(n/2)*4 : 6)+y;if yy<rows.count && xx<rows[yy].count {rows[yy][xx]=digits[text[n]][compact ? y*2 : y][compact ? x*2 : x] == "1" ? "Y" : "G"}}}};return rows.map{String($0)} }
    func drawClock(_ look: Look,_ x: CGFloat,_ y: CGFloat,_ scale: CGFloat,_ date: Date) {let parts=Calendar.current.dateComponents([.hour,.minute],from:date);let art=layers("clock");if art.isEmpty {Sprites.drawClock(parts.hour ?? 0,parts.minute ?? 0,left:x,top:y,scale:scale);return};let grid=value("clock")==2 ? Self.digital(art[0].grid,date) : art[0].grid;Sprites.draw(layers:[Sprites.Layer(grid,0,0)],look,left:x,top:y,scale:scale);if value("clock")==1 {Sprites.drawClock(parts.hour ?? 0,parts.minute ?? 0,left:x,top:y,scale:scale)}}
    func drawRoom(_ look: Look,_ rect: NSRect,_ date: Date,preview: Bool=true) {let scale=max(1,min(rect.width/112,rect.height/62).rounded(.down)),x=rect.minX+(rect.width-112*scale)/2,y=rect.minY;if preview {Sprites.color(0xECE4D5).setFill();rect.fill();Sprites.drawWindow(98,52,sky:PetWindow.skyAt(date),season:PetWindow.seasonAt(date),left:x+7*scale,top:y+5*scale,scale:scale,scene:0)};for key in ["window","wall","hangingPlant","lights"] {let dx=key == "wall" ? -17 : key == "hangingPlant" ? 99 : 0,dy=key == "wall" ? 10 : key == "hangingPlant" ? 1 : 0;var art=layers(key);let hour=Calendar.current.component(.hour,from:date);if key == "lights" && hour>=6 && hour<18 {art=art.map{Sprites.Layer($0.grid.map{$0.replacingOccurrences(of:"Y",with:"w")},$0.x,$0.y)}};Sprites.draw(layers:art,look,left:x+CGFloat(dx)*scale,top:y+CGFloat(dy)*scale,scale:scale)};if preview && on("floor") {Sprites.color(0xECD7AE).setFill();NSRect(x:rect.minX,y:rect.maxY-12,width:rect.width,height:12).fill()};if preview {drawClock(look,x+4*scale,y+5*scale,scale,date)}}
}
