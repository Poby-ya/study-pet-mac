import AppKit

let app = NSApplication.shared
let arguments = CommandLine.arguments
if arguments.count == 4 && arguments[1] == "--release-probe" { exit(ReleaseChannel.probe(arguments[2], expected: arguments[3])) }
if arguments.count > 1 && arguments[1] == "--selftest" {
    exit(SelfTest.run(outDir: arguments.count > 2 ? arguments[2] : nil, invite: arguments.count > 3 ? arguments[3] : nil))
}

// The menu bar never shows (the app lives in the status bar), but without an Edit menu
// ⌘V can't paste the invite code into a text field.
let mainMenu = NSMenu()
let editItem = NSMenuItem()
let edit = NSMenu(title: "편집")
edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
edit.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
editItem.submenu = edit
mainMenu.addItem(editItem)
app.mainMenu = mainMenu

// The installer stops a running copy with SIGTERM (an AppleScript "quit" would ask the
// friend for permission); quit properly, so the open segment is saved and friends see "off".
signal(SIGTERM, SIG_IGN)
let terminateSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminateSignal.setEventHandler { NSApp.terminate(nil) }
terminateSignal.resume()

app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
