import AppKit

final class HelpWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "사용 설명서 · 공부 친구"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 560, height: 360)
        let tabs = NSTabView(frame: NSRect(x: 12, y: 12, width: 796, height: 536))
        tabs.autoresizingMask = [.width, .height]
        for (heading, body) in HelpWindow.sections() {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            let text = NSTextView()
            text.isEditable = false
            text.font = .systemFont(ofSize: 15)
            text.textContainerInset = NSSize(width: 16, height: 16)
            text.string = body
            text.isVerticallyResizable = true
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            scroll.documentView = text
            let tab = NSTabViewItem(identifier: heading)
            tab.label = heading
            tab.view = scroll
            tabs.addTabViewItem(tab)
        }
        contentView?.addSubview(tabs)
        center()
    }
    override func cancelOperation(_ sender: Any?) { close() }

    static func sections() -> [(String, String)] {
        guard let url = Bundle.main.url(forResource: "help", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "## ").filter { !$0.isEmpty }.compactMap { part in
            guard let newline = part.firstIndex(of: "\n") else { return nil }
            return (String(part[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines), String(part[part.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
