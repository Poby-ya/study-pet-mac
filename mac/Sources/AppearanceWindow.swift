import AppKit
private final class AppearanceContent: NSView { override var isFlipped: Bool { true } }
final class AppearanceWindow: NSWindow, NSWindowDelegate {
    private var values: [Int]
    private var custom: Customization
    private var selected: Look
    private var applied=false
    private var ribbon: Int
    private var baseLocks: [Int:Bool]=[:]
    private var group="character"
    private let preview=NSImageView()
    private let body=AppearanceContent()
    private let scroll=NSScrollView()
    init(_ look: Look) {
        values=[look.hair,look.hairColor,look.top,look.topColor,look.bottom,look.ribbon,0,look.skin,0,look.sleeve,look.leftHanded ? 1 : 0,0,look.bag,look.girl ? 1 : 0]
        custom=(look.customization ?? Customization.legacy(look)).copy();selected=look;ribbon=look.additions & 1
        let saved=Array(Settings.get("appearanceLocks"));if look.customization == nil {for (key,index) in [("hair",0),("top",2),("hat",8),("documentSticker",11),("deskStickers",11)] {custom.slots[key]!.locked=saved.count>index && saved[index] == "1"}};for i in [1,3,4,5,9,12] {baseLocks[i]=i<saved.count && saved[i] == "1"}
        let height=min(640,(NSScreen.main?.visibleFrame.height ?? 760)-50)
        super.init(contentRect:NSRect(x:0,y:0,width:528,height:height),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        title="꾸미기";isReleasedWhenClosed=false;delegate=self;let root=AppearanceContent(frame:NSRect(x:0,y:0,width:528,height:height));contentView=root
        let tabs=NSSegmentedControl(labels:["캐릭터","책상","교실"],trackingMode:.selectOne,target:self,action:#selector(tabChanged(_:)));tabs.selectedSegment=0;tabs.frame=NSRect(x:16,y:12,width:496,height:30);root.addSubview(tabs)
        scroll.frame=NSRect(x:0,y:50,width:528,height:height-260);scroll.hasVerticalScroller=true;scroll.documentView=body;root.addSubview(scroll)
        preview.frame=NSRect(x:20,y:height-202,width:468,height:150);root.addSubview(preview)
        for (title,x,action) in [("랜덤 뽑기",20,#selector(roll)),("적용",330,#selector(apply)),("취소",425,#selector(cancel))] {let b=NSButton(title:title,target:self,action:action);b.frame=NSRect(x:CGFloat(x),y:height-42,width:90,height:30);root.addSubview(b);if title == "적용" {b.keyEquivalent="\r"};if title == "취소" {b.keyEquivalent="\u{1b}"}}
        rebuild();center()
    }
    required init?(coder: NSCoder) {fatalError("not used")}
    @objc private func tabChanged(_ sender: NSSegmentedControl) {group=["character","desk","classroom"][sender.selectedSegment];rebuild()}
    private func rebuild() {
        body.subviews.forEach{$0.removeFromSuperview()};var y: CGFloat=10
        func label(_ title: String) {let l=NSTextField(labelWithString:title);l.frame=NSRect(x:20,y:y,width:480,height:25);body.addSubview(l);y+=30}
        func toggle(_ title: String,_ index: Int,_ labels: [String]) {let l=NSTextField(labelWithString:title);l.frame=NSRect(x:20,y:y,width:75,height:24);body.addSubview(l);let t: NSSegmentedControl
            if index == 7 {let colors=[0xFFF4EC,0xFFE0C8,0xD2A17C,0x83523E];let images=colors.map { color in NSImage(size:NSSize(width:35,height:18),flipped:true){rect in Sprites.color(color).setFill();rect.fill();return true}};t=NSSegmentedControl(images:images,trackingMode:.selectOne,target:self,action:#selector(toggleChanged(_:)));t.selectedSegment=[1,0,2,3].firstIndex(of:values[index]) ?? 0}
            else {t=NSSegmentedControl(labels:labels,trackingMode:.selectOne,target:self,action:#selector(toggleChanged(_:)));t.selectedSegment=values[index]};t.tag=index;t.frame=NSRect(x:105,y:y-3,width:380,height:30);body.addSubview(t);y+=38
        }
        func check(_ title: String,_ key: String,_ on: Bool,_ action: Selector) {let b=NSButton(checkboxWithTitle:title,target:self,action:action);b.identifier=NSUserInterfaceItemIdentifier(key);b.state=on ? .on : .off;b.frame=NSRect(x:20,y:y,width:470,height:25);body.addSubview(b);y+=27}
        if group == "character" {toggle("캐릭터",13,["남자","여자"]);toggle("쓰는 손",10,["오른손","왼손"]);toggle("피부색",7,["","","",""])}
        label("추가할 것을 선택하세요.")
        for s in Customization.categories where s.group == group && s.optional {check(s.title,s.key,custom.on(s.key),#selector(addChanged(_:)))}
        if group == "character" {check("리본","ribbon",ribbon != 0,#selector(addChanged(_:)))}
        label("고정할 것을 선택하세요.")
        for s in Customization.categories where s.group == group && custom.on(s.key) {check(s.title,s.key,custom.slots[s.key]!.locked,#selector(lockChanged(_:)))}
        let bases: [(Int,String)] = group == "character" ? [(1,"머리색"),(3,"상의 색"),(4,"하의"),(5,"리본 색"),(9,"소매")] : group == "desk" ? [(12,"가방 색")] : []
        for (i,title) in bases where i != 5 || ribbon != 0 {check(title,String(i),baseLocks[i] ?? false,#selector(baseLockChanged(_:)))}
        body.frame=NSRect(x:0,y:0,width:508,height:y+10);changed()
    }
    @objc private func toggleChanged(_ sender: NSSegmentedControl) {values[sender.tag]=sender.tag == 7 ? [1,0,2,3][sender.selectedSegment] : sender.selectedSegment;if values[13]==0 && values[4]>=4 {values[4]=0};changed()}
    @objc private func addChanged(_ sender: NSButton) {let key=sender.identifier!.rawValue;if key == "ribbon" {ribbon=sender.state == .on ? 1 : 0}else{custom.slots[key]!.enabled=sender.state == .on;let s=Customization.categories.first{$0.key == key}!;if custom.on(key) && custom.value(key)==0 && s.legacy==0 && key != "deskStickers" {custom.slots[key]!.value=1}};rebuild()}
    @objc private func lockChanged(_ sender: NSButton) {custom.slots[sender.identifier!.rawValue]!.locked=sender.state == .on}
    @objc private func baseLockChanged(_ sender: NSButton) {baseLocks[Int(sender.identifier!.rawValue)!]=sender.state == .on}
    private func read() -> Look {let extra="0"+String(values[7])+"0"+String(values[9])+String(values[10])+"0"+String(values[12])+String(ribbon);return custom.legacyLook(Look(girl:values[13]==1,values[0],values[1],values[2],values[3],values[4],values[5]).withExtras(extra))}
    private func changed() {let look=read(),isRoom=group == "classroom",roomCustom=custom;preview.image=NSImage(size:NSSize(width:468,height:150),flipped:true){_ in if isRoom {roomCustom.drawRoom(look,NSRect(x:8,y:4,width:452,height:140),Date())}else{for (i,pose) in [Sprites.Pose.writeA,.dozeA,.waveA].enumerated(){if i==0 && roomCustom.on("lamp") {Sprites.drawLampGlow(left:20,top:24,scale:2,lamp:roomCustom.value("lamp"))};Sprites.draw(pose,look,left:CGFloat(20+i*156),top:24,scale:2,decor:Sprites.Decor(seed:7,lit:i==0));if i==0 && roomCustom.on("lamp") {Sprites.drawLampPool(left:20,top:24,scale:2)}}};return true}}
    @objc private func roll() {custom.roll(group);let counts=[8,5,9,10,values[13]==1 ? 8 : 4,6,0,4,0,4,0,4,4];for i in (group == "character" ? [1,3,4,5,9] : group == "desk" ? [12] : []) where baseLocks[i] != true && (i != 5 || ribbon != 0) {values[i]=Int.random(in:0..<counts[i])};changed()}
    @objc private func apply() {do {try Settings.set("appearanceLocks",(0..<14).map{baseLocks[$0] == true ? "1" : "0"}.joined());selected=read();applied=true;NSApp.stopModal()}catch{let a=NSAlert();a.messageText="설정을 저장하지 못했어요.";a.informativeText=error.localizedDescription;a.runModal()}}
    func windowShouldClose(_ sender: NSWindow) -> Bool {NSApp.stopModal();return true}
    @objc private func cancel() {NSApp.stopModal()}
    static func choose(_ look: Look) -> Look? {let window=AppearanceWindow(look);NSApp.activate(ignoringOtherApps:true);NSApp.runModal(for:window);window.orderOut(nil);return window.applied ? window.selected : nil}
}
