#if DEBUG
import AirdraftCore
import AppKit
import SwiftUI

@MainActor
enum HistoryVerification {
    static func run() throws {
        try verifySnapshots()
        verifyTextLayout()
        verifyTextClipping()
    }

    private static func verifySnapshots() throws {
        let history = try HistoryStore(inMemory: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12))!
        var records: [DictationRecord] = []
        for index in 0..<405 {
            records.append(try history.save(DictationRecord(
                createdAt: now.addingTimeInterval(-Double(index) * 600), mode: "Clean", family: "general",
                rawTranscript: "um record \(index)", refinedText: "record \(index)", finalText: "record \(index)",
                asrEngine: "fixture", audioSeconds: 1, asrMs: 1, llmMs: 1, inserted: true)))
        }
        func prepare(_ records: [DictationRecord], previous: HistorySnapshot = .empty) -> HistorySnapshot {
            HistorySnapshot.prepare(records, history: history, appendingTo: previous, calendar: calendar, now: now)
        }
        let first = prepare(try history.recent(limit: 200))
        let second = prepare(try history.recent(limit: 200, offset: 200), previous: first)
        let all = prepare(try history.recent(limit: 200, offset: 400), previous: second)
        precondition(first.entries.count == 200 && second.entries.count == 400 && all.entries.count == 405)
        precondition(all.entries.map(\.id) == records.compactMap(\.id), "Pagination changed record order")
        precondition(all.entries.map(\.heading) == prepare(records).entries.map(\.heading), "Append duplicated a day heading")
        precondition(all.entries.first?.heading == "Today")
        precondition(all.entries.contains { $0.heading == "Yesterday" })
        precondition(all.firstVisibleID(in: [records[399].id!, -1, records[398].id!]) == records[398].id)
        precondition(all.firstVisibleID(in: []) == nil && all.firstVisibleID(in: [-1]) == nil)
        let filtered = prepare(try history.recent(query: "record 40"))
        precondition(filtered.entries.count == 6 && filtered.entries.allSatisfy { $0.finalText.full.contains("record 40") })
        let deleted = filtered.entries[0].id
        try history.delete(id: deleted)
        let refreshed = prepare(try history.recent(query: "record 40"))
        precondition(refreshed.indexByID[deleted] == nil && refreshed.entries.count == 5)
        let nextDay = HistorySnapshot.prepare([records[0]], history: history, calendar: calendar,
                                              now: now.addingTimeInterval(86_400))
        precondition(nextDay.entries.first?.heading == "Yesterday", "Cached relative dates must refresh")
        print("PASS: History pagination, day boundaries, search, deletion and visible-ID lookup")
    }

    private static func verifyTextLayout() {
        let view = HistoryTranscript.BackingView()
        let short = HistoryTextContent("  A short transcript.\n")
        view.configure(content: short, expanded: false)
        let shortSize = view.measure(width: 430)
        precondition(!shortSize.showsToggle && short.full == "A short transcript.")
        for text in [String(repeating: "A long dictation should scroll smoothly. ", count: 2000),
                     String(repeating: "中文測試與 emoji 👨‍👩‍👧‍👦 café e\u{301}。\n", count: 2000)] {
            let content = HistoryTextContent(text)
            precondition(content.hasOmittedTail && content.preview.count == 2048)
            precondition(content.full == text.trimmingCharacters(in: .whitespacesAndNewlines))
            view.configure(content: content, expanded: false)
            for width in [CGFloat(300), 430, 510] {
                let size = view.measure(width: width)
                precondition(size.showsToggle && size.textHeight < 200, "Collapsed text must stay within six lines")
                precondition(view.textField.stringValue == content.preview, "Collapsed shaping must be bounded")
            }
            let collapsed = view.measure(width: 430)
            view.configure(content: content, expanded: true)
            precondition(view.textField.stringValue == content.full, "Expansion must preserve every character")
            precondition(view.measure(width: 430).height > collapsed.height && view.toggle.title == "Show Less")
            view.configure(content: short, expanded: false)
            precondition(!view.measure(width: 430).showsToggle, "Switching transcript must invalidate cached sizing")
        }
        let sixLines = HistoryTextContent((1...6).map { "Line \($0)" }.joined(separator: "\n"))
        view.configure(content: sixLines, expanded: false)
        precondition(!view.measure(width: 430).showsToggle, "Exactly six lines must not offer expansion")
        view.configure(content: HistoryTextContent(sixLines.full + "\nSeventh line"), expanded: false)
        precondition(view.measure(width: 430).showsToggle, "The seventh line must offer expansion")
        var toggled = false
        view.onToggle = { toggled = true }
        view.toggle.performClick(nil)
        precondition(toggled, "Native expansion button must deliver its action")
        view.configure(content: short, expanded: false)
        view.frame = NSRect(x: 0, y: 0, width: 430, height: view.measure(width: 430).height)
        view.layoutSubtreeIfNeeded()
        precondition(view.toggle.isHidden && view.textField.isSelectable && !view.textField.isEditable)
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.textField.selectText(nil)
        precondition(view.textField.currentEditor()?.selectedRange.length == short.full.utf16.count,
                     "Transcript must support native text selection")
        window.makeFirstResponder(nil)
        window.orderOut(nil)
        verifyHostedExpansion()
        print("PASS: Bounded multilingual text, six-line boundary, expansion, native selection and cache invalidation")
    }

    private static func verifyTextClipping() {
        let paragraph = "長篇逐字稿包含中文、English、emoji 🎙️ 與多個段落。收合後，文字必須留在預覽區域內，讓展開、版本切換與操作按鈕保持可讀。"
        let content = HistoryTextContent(String(repeating: paragraph + "\n\n", count: 40))
        let view = HistoryTranscript.BackingView()
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 550, height: 400))
        canvas.addSubview(view)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.orderOut(nil) }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            window.makeKeyAndOrderFront(nil)
            for width in [CGFloat(300), 430, 510] {
                // Exercise initial display, collapse, and a transcript-version change.
                for expanded in [false, true, false] {
                    view.configure(content: content, expanded: expanded)
                    let size = view.measure(width: width)
                    view.frame = NSRect(x: 20, y: 20, width: width, height: size.height)
                    view.layoutSubtreeIfNeeded()
                    let field = view.textField
                    let visible = field.visibleRect
                    precondition(field.bounds.insetBy(dx: -0.5, dy: -0.5).contains(visible),
                                 "Transcript drawing escaped its text area: \(visible) outside \(field.bounds)")
                    precondition(field.frame.maxY + Theme.controlSpacing <= view.toggle.frame.minY,
                                 "Transcript must leave the expansion control clear")
                    if !expanded {
                        field.selectText(nil)
                        guard let editor = field.currentEditor() else {
                            preconditionFailure("Long transcript must support native selection")
                        }
                        let selectionArea = editor.convert(editor.visibleRect, to: field)
                        precondition(field.bounds.insetBy(dx: -0.5, dy: -0.5).contains(selectionArea),
                                     "Native selection escaped the collapsed text area")
                        window.makeFirstResponder(nil)
                    }
                }
                view.configure(content: HistoryTextContent("Short original transcript."), expanded: false)
                view.frame.size.height = view.measure(width: width).height
                view.layoutSubtreeIfNeeded()
                precondition(view.toggle.isHidden && view.textField.frame.height < 30,
                             "Switching to a short version must reset the collapsed layout")
            }
        }
        print("PASS: Transcript drawing and native selection stay clear of controls in both appearances")
    }

    private static func verifyHostedExpansion() {
        struct Fixture: View {
            @Bindable var state: HistoryCardState
            let content: HistoryTextContent
            var body: some View { HistoryTranscript(content: content, expanded: $state.expanded) }
        }
        let state = HistoryCardState()
        let content = HistoryTextContent(String(repeating: "Expand the complete transcript. ", count: 100))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        func mount() -> HistoryTranscript.BackingView {
            let host = NSHostingView(rootView: Fixture(state: state, content: content))
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            func transcript(in view: NSView) -> HistoryTranscript.BackingView? {
                (view as? HistoryTranscript.BackingView) ?? view.subviews.compactMap { transcript(in: $0) }.first
            }
            return transcript(in: host)!
        }
        let first = mount()
        first.toggle.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        precondition(state.expanded && first.textField.stringValue == content.full,
                     "Hosted expansion: state=\(state.expanded), lines=\(first.textField.maximumNumberOfLines)")
        let remounted = mount()
        precondition(remounted.textField.maximumNumberOfLines == 0, "Expansion must survive row recreation")
        remounted.toggle.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        precondition(!state.expanded && remounted.textField.maximumNumberOfLines == 6)
    }
}
#endif
