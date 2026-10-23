#if DEBUG
import AirdraftCore
import AppKit
import SwiftUI

/// `--render-window a11y-audit <dir>`: walks the actual accessibility tree of every
/// page, overlay, onboarding step and the License sheet in its own windows, at the
/// Default and Larger text sizes. Every interactive element must expose a role and a
/// non-empty name; unnamed images must be hidden; custom controls must expose state.
/// It writes one tree dump per surface for manual review and exits nonzero on a
/// violation. It reads only its own windows and never enables VoiceOver.
@MainActor
enum AccessibilityAudit {
    private final class SilentWindow: NSWindow {
        override func noResponder(for eventSelector: Selector) {}
    }

    struct Node {
        let role: String
        let subrole: String
        let label: String
        let title: String
        let value: String
        let help: String
        let placeholder: String
        let identifier: String
        let enabled: Bool
        let selected: Bool
        let depth: Int
        let frame: CGRect

        var name: String { [label, title].first { !$0.isEmpty } ?? "" }
        var line: String {
            let parts = [role + (subrole.isEmpty ? "" : "/\(subrole)"), "name=\(name.debugDescription)",
                         !label.isEmpty && !title.isEmpty && label != title ? "title=\(title.debugDescription)" : nil,
                         value.isEmpty ? nil : "value=\(value.debugDescription)",
                         help.isEmpty ? nil : "help=\(help.debugDescription)",
                         placeholder.isEmpty ? nil : "placeholder=\(placeholder.debugDescription)",
                         identifier.isEmpty ? nil : "id=\(identifier)",
                         enabled ? nil : "disabled", selected ? "selected" : nil,
                         frame.isNull || frame.isInfinite ? nil
                            : "@\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"]
            return String(repeating: "  ", count: depth) + parts.compactMap { $0 }.joined(separator: " ")
        }
    }

    /// Roles that VoiceOver users operate; each needs a spoken name.
    static let interactiveRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXPopUpButton", "AXMenuButton",
        "AXTextField", "AXTextArea", "AXIncrementor", "AXLink", "AXDisclosureTriangle", "AXComboBox",
        "AXSegmentedControl", "AXSwitch", "AXToggle",
    ]

    static func run(to directory: URL) {
        setbuf(stdout, nil)
        precondition(LocalE2E.isActive && RenderMode.isActive, "Use --e2e-local with --render-window a11y-audit")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let container = PreviewData.container
        container.navigation.sidebarCollapsed = false
        var violations: [String] = []
        var surfaces = 0
        for size in [TextSizePreference.standard, .larger] {
            func audit<V: View>(_ name: String, _ root: V, height: CGFloat = 720,
                                expect: ([Node]) -> [String] = { _ in [] }) {
                let window = show(root.environment(container).textSize(size), height: height)
                let nodes = tree(window)
                surfaces += 1
                let file = directory.appendingPathComponent("\(name)-\(size.rawValue).txt")
                try? nodes.map(\.line).joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
                violations += (check(nodes) + expect(nodes)).map { "\(name) [\(size.rawValue)]: \($0)" }
                window.orderOut(nil)
                window.contentView = nil
                pump()
            }
            for page in Page.allCases {
                container.navigation.page = page
                audit("page-\(page.rawValue)", MainWindowView(), expect: { expectations(for: page, $0) })
            }
            container.navigation.page = .home
            audit("overlay-microphone", MainWindowView(previewOverlay: .microphone, microphoneRenderLevel: 0.4))
            audit("overlay-account", MainWindowView(previewOverlay: .account))
            container.navigation.sidebarCollapsed = true
            audit("sidebar-collapsed", MainWindowView())
            container.navigation.sidebarCollapsed = false
            for step in OnboardingProgress.Step.allCases {
                container.settings.onboarding.present()
                container.settings.onboarding.move(to: step)
                audit("onboarding-\(step.rawValue)", MainWindowView())
            }
            container.settings.onboarding.dismiss()
            audit("license", LicenseView(), height: 420)
            // The transcript editor with its Recent names and Summarize menus (AD-086).
            let llm = container.settings.llm
            container.settings.llm.select(.openAICompatible)
            try? container.history?.rememberSpeakerNames(["Morgan Lee", "林語晴"])
            audit("media-editor", MediaDocumentEditor(initial: MediaPreview.document), height: 580, expect: { nodes in
                ["Recent names for Speaker 1", "Summarize"].filter { label in !nodes.contains { $0.line.contains(label) } }
                    .map { "missing \($0)" }
            })
            container.settings.llm = llm
        }
        let report = directory.appendingPathComponent("violations.txt")
        try? violations.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
        for violation in violations { print("A11Y_VIOLATION \(violation)") }
        precondition(violations.isEmpty, "\(violations.count) accessibility violation(s); see \(report.path)")
        print("A11Y_AUDIT_PASS surfaces=\(surfaces) sizes=default,larger dumps=\(directory.path)")
    }

    /// Specific labels and states this audit introduced, checked on the real tree.
    static func expectations(for page: Page, _ nodes: [Node]) -> [String] {
        var problems: [String] = []
        let headings = nodes.filter { $0.role == "AXHeading" }
        if !headings.contains(where: { $0.name == page.title }) { problems.append("page title is not a heading") }
        switch page {
        case .home:
            let period = String(localized: "Statistics period")
            if !nodes.contains(where: { $0.role == "AXMenuButton" && $0.name == period && !$0.value.isEmpty }) {
                problems.append("the period filter must be a menu button named \(period) with its choice as value")
            }
        case .configuration:
            if headings.count < 6 { problems.append("Settings sections must be headings (found \(headings.count))") }
            guard let picker = nodes.firstIndex(where: { $0.identifier == "settings.textSize" }) else {
                problems.append("missing Text size picker"); break
            }
            let options = nodes[(picker + 1)...].prefix { $0.depth > nodes[picker].depth }.filter { $0.role == "AXButton" }
            let selected = String(localized: "Selected")
            if options.count != TextSizePreference.allCases.count || options.filter({ $0.value == selected }).count != 1 {
                problems.append("Text size options must expose exactly one Selected value: \(options.map(\.line))")
            }
        case .history:
            let entries = nodes.filter { $0.role == "AXGroup" && $0.identifier.hasPrefix("history.entry.") }
            if entries.isEmpty || entries.contains(where: { $0.name.isEmpty }) {
                problems.append("History cards must be named groups so their actions have context")
            }
        default: break
        }
        return problems
    }

    /// Rules applied to one surface's tree.
    static func check(_ nodes: [Node]) -> [String] {
        var problems: [String] = []
        for node in nodes {
            let describe = node.line.trimmingCharacters(in: .whitespaces)
            // Native scroll bar parts are named by AppKit's scroll bar itself.
            let scrollerPart = ["AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage"].contains(node.subrole)
            if interactiveRoles.contains(node.role), !scrollerPart {
                // A placeholder disappears once text is entered; fields need their own name.
                let spoken = node.name
                if spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    problems.append("unnamed control: \(describe)")
                }
                // SwiftUI falls back to an SF Symbol's description when a label holds only an image.
                if ["Chevron", "Up and down", "Ellipsis"].contains(where: { node.label.contains($0) || node.title.contains($0) }) {
                    problems.append("symbol name used as a control name: \(describe)")
                }
            }
            if node.role == "AXImage", node.name.isEmpty {
                problems.append("unnamed image is not hidden: \(describe)")
            }
            if ["AXSlider", "AXCheckBox", "AXSwitch", "AXToggle"].contains(node.role), node.value.isEmpty {
                problems.append("control without a value: \(describe)")
            }
            if node.role == "AXUnknown" || node.role.isEmpty {
                problems.append("element without a role: \(describe)")
            }
        }
        return problems
    }

    static func tree(_ window: NSWindow) -> [Node] {
        var nodes: [Node] = []
        /// Modern NSAccessibility properties, or the legacy attribute API that some
        /// AppKit elements (outline rows) still implement instead.
        let legacy: [String: String] = [
            "accessibilityRole": "AXRole", "accessibilitySubrole": "AXSubrole", "accessibilityLabel": "AXDescription",
            "accessibilityTitle": "AXTitle", "accessibilityValue": "AXValue", "accessibilityHelp": "AXHelp",
            "accessibilityPlaceholderValue": "AXPlaceholderValue", "accessibilityIdentifier": "AXIdentifier",
            "isAccessibilityEnabled": "AXEnabled", "isAccessibilitySelected": "AXSelected",
            "accessibilityChildren": "AXChildren", "accessibilityRows": "AXRows",
        ]
        func attribute(_ object: NSObject, _ key: String) -> Any? {
            if object.responds(to: NSSelectorFromString(key)) { return object.value(forKey: key) }
            guard let name = legacy[key],
                  object.responds(to: #selector(NSObject.accessibilityAttributeNames)),
                  object.accessibilityAttributeNames().contains(NSAccessibility.Attribute(rawValue: name)) else { return nil }
            return object.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: name))
        }
        func string(_ object: NSObject, _ key: String) -> String {
            let raw = attribute(object, key)
            if let text = raw as? String { return text }
            if let attributed = raw as? NSAttributedString { return attributed.string }
            if let number = raw as? NSNumber { return number.stringValue }
            return ""
        }
        func bool(_ object: NSObject, _ key: String, default fallback: Bool) -> Bool {
            attribute(object, key) as? Bool ?? fallback
        }
        func walk(_ object: Any, depth: Int) {
            guard let item = object as? NSObject else { return }
            let role = string(item, "accessibilityRole")
            if !(item is NSWindow), !role.isEmpty {
                let frame = (item.responds(to: NSSelectorFromString("accessibilityFrame"))
                    ? (item.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue : nil) ?? .zero
                nodes.append(Node(role: role, subrole: string(item, "accessibilitySubrole"),
                                  label: string(item, "accessibilityLabel"), title: string(item, "accessibilityTitle"),
                                  value: string(item, "accessibilityValue"), help: string(item, "accessibilityHelp"),
                                  placeholder: string(item, "accessibilityPlaceholderValue"),
                                  identifier: string(item, "accessibilityIdentifier"),
                                  enabled: bool(item, "isAccessibilityEnabled", default: true),
                                  selected: bool(item, "isAccessibilitySelected", default: false),
                                  depth: depth, frame: frame))
            }
            var children = attribute(item, "accessibilityChildren") as? [Any] ?? []
            // Native tables and outlines may expose their rows only through AXRows.
            if children.isEmpty { children = attribute(item, "accessibilityRows") as? [Any] ?? [] }
            for child in children { walk(child, depth: depth + 1) }
        }
        walk(window, depth: 0)
        return nodes
    }

    private static func show<V: View>(_ root: V, height: CGFloat) -> NSWindow {
        let window = SilentWindow(contentRect: NSRect(x: 150, y: 70, width: Theme.windowWidth, height: height),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Airdraft accessibility audit"
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: root.frame(width: Theme.windowWidth, height: height)
            .background(Color(nsColor: .windowBackgroundColor)))
        window.makeKeyAndOrderFront(nil)
        pump()
        return window
    }

    private static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.4)) }
}
#endif
