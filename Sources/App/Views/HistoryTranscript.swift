import AppKit
import SwiftUI

/// Native selectable text with bounded collapsed layout. The expansion control
/// participates in the first size proposal, with no geometry-to-State feedback.
struct HistoryTranscript: NSViewRepresentable {
    let content: HistoryTextContent
    @Binding var expanded: Bool

    func makeNSView(context: Context) -> BackingView { BackingView() }

    func updateNSView(_ view: BackingView, context: Context) {
        view.configure(content: content, expanded: expanded, scale: context.environment.textScale)
        view.onToggle = { expanded.toggle() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BackingView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.measure(width: width).height)
    }

    final class BackingView: NSView {
        let textField = NSTextField(wrappingLabelWithString: "")
        var onToggle: (() -> Void)?
        private var content: HistoryTextContent?
        private var expanded = false
        private var scale: CGFloat = 1
        private var createdToggle: NSButton?
        private var lastMeasurement: (width: CGFloat, result: Measurement)?
        /// Before the first layout an accessed toggle starts visible, as a native control would.
        private var showsToggle = true
        override var isFlipped: Bool { true }

        struct Measurement {
            let textHeight: CGFloat
            let buttonSize: CGSize
            let showsToggle: Bool
            var height: CGFloat { textHeight + (showsToggle ? Theme.controlSpacing + buttonSize.height : 0) }
        }

        init() {
            super.init(frame: .zero)
            Self.configureLabel(textField)
            // AppKit views no longer clip by default. Keep text and native
            // selection inside the measured area, clear of the card controls.
            textField.clipsToBounds = true
            textField.isSelectable = true
            addSubview(textField)
        }

        required init?(coder: NSCoder) { nil }

        /// Created on first use: most cards fit in six lines and never need it.
        var toggle: NSButton {
            if let createdToggle { return createdToggle }
            let toggle = NSButton(title: expanded ? String(localized: "Show Less") : String(localized: "Show More"), target: self, action: #selector(toggleExpansion))
            Self.configureToggle(toggle, scale: scale)
            toggle.isHidden = !showsToggle
            addSubview(toggle)
            createdToggle = toggle
            return toggle
        }

        func configure(content: HistoryTextContent, expanded: Bool, scale: CGFloat = 1) {
            guard self.content != content || self.expanded != expanded || self.scale != scale else { return }
            self.content = content
            self.expanded = expanded
            if self.scale != scale, let createdToggle { Self.configureToggle(createdToggle, scale: scale) }
            self.scale = scale
            textField.font = TextStyle.transcript.nsFont(scale: scale)
            textField.maximumNumberOfLines = expanded ? 0 : 6
            let text = expanded ? content.full : content.preview
            textField.attributedStringValue = NSAttributedString(string: text, attributes: Self.attributes(scale: scale, text: text))
            createdToggle?.title = expanded ? String(localized: "Show Less") : String(localized: "Show More")
            lastMeasurement = nil
            invalidateIntrinsicContentSize()
            needsLayout = true
        }

        func measure(width: CGFloat) -> Measurement {
            if let lastMeasurement, lastMeasurement.width == width { return lastMeasurement.result }
            guard let content else { return Measurement(textHeight: 0, buttonSize: .zero, showsToggle: false) }
            let measured = Self.measure(content, expanded: expanded, width: width, scale: scale)
            let result = Measurement(textHeight: measured.textHeight, buttonSize: Self.toggleSize(expanded: expanded, scale: scale),
                                     showsToggle: measured.showsToggle)
            lastMeasurement = (width, result)
            return result
        }

        override func layout() {
            super.layout()
            let result = measure(width: bounds.width)
            showsToggle = result.showsToggle
            textField.frame = NSRect(x: 0, y: 0, width: bounds.width, height: result.textHeight)
            if result.showsToggle {
                toggle.isHidden = false
                // At the interface's leading edge, like the card actions below it.
                let x = userInterfaceLayoutDirection == .rightToLeft ? bounds.width - result.buttonSize.width : 0
                toggle.frame = NSRect(x: x, y: result.textHeight + Theme.controlSpacing,
                                      width: result.buttonSize.width, height: result.buttonSize.height)
            } else {
                createdToggle?.isHidden = true
            }
        }

        @objc private func toggleExpansion() { onToggle?() }

        // MARK: Shared measurement

        /// Natural alignment by the transcript's own direction: an English dictation stays
        /// left aligned in a right-to-left interface, and an Arabic one right aligned in English.
        private static func attributes(scale: CGFloat, text: String) -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.baseWritingDirection = WritingDirection.paragraphDirection(of: text)
            style.alignment = switch style.baseWritingDirection {
            case .leftToRight: .left
            case .rightToLeft: .right
            default: .natural
            }
            style.lineSpacing = 3
            return [.font: TextStyle.transcript.nsFont(scale: scale), .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        }

        private static func configureLabel(_ field: NSTextField) {
            field.font = TextStyle.transcript.nsFont(scale: 1)
            field.isEditable = false
            field.isBezeled = false
            field.drawsBackground = false
            field.cell?.wraps = true
            field.cell?.truncatesLastVisibleLine = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        private static func configureToggle(_ toggle: NSButton, scale: CGFloat) {
            toggle.isBordered = false
            toggle.bezelStyle = .inline
            toggle.font = TextStyle.detail.nsFont(scale: scale)
            toggle.contentTintColor = .linkColor
            toggle.setAccessibilityIdentifier("history.expand")
        }

        private static let measuringField: NSTextField = {
            let field = NSTextField(wrappingLabelWithString: "")
            configureLabel(field)
            return field
        }()

        private struct ToggleKey: Hashable {
            let expanded: Bool
            let scale: CGFloat
        }

        private static var toggleSizes: [ToggleKey: CGSize] = [:]

        private static func toggleSize(expanded: Bool, scale: CGFloat) -> CGSize {
            let key = ToggleKey(expanded: expanded, scale: scale)
            if let size = toggleSizes[key] { return size }
            let toggle = NSButton(title: expanded ? String(localized: "Show Less") : String(localized: "Show More"), target: nil, action: nil)
            configureToggle(toggle, scale: scale)
            toggleSizes[key] = toggle.fittingSize
            return toggle.fittingSize
        }

        private struct Key: Hashable {
            let text: String
            let expanded: Bool
            let width: CGFloat
            let scale: CGFloat
        }

        /// Lazy rows are recreated whenever they scroll back into view. Text and
        /// width determine the result, so measurements outlive the views.
        private static var measurements: [Key: (textHeight: CGFloat, showsToggle: Bool)] = [:]

        private static func textHeight(_ text: String, lines: Int, width: CGFloat, scale: CGFloat) -> CGFloat {
            let field = measuringField
            field.font = TextStyle.transcript.nsFont(scale: scale)
            field.maximumNumberOfLines = lines
            field.attributedStringValue = NSAttributedString(string: text, attributes: attributes(scale: scale, text: text))
            let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
            return ceil(field.cell?.cellSize(forBounds: bounds).height ?? 0)
        }

        /// Six unconstrained lines at each text size; anything shorter cannot have a seventh.
        private static var sixLineHeights: [CGFloat: CGFloat] = [:]

        private static func sixLineHeight(scale: CGFloat) -> CGFloat {
            if let height = sixLineHeights[scale] { return height }
            let height = textHeight((1...6).map(String.init).joined(separator: "\n"), lines: 0, width: 10_000, scale: scale)
            sixLineHeights[scale] = height
            return height
        }

        private static func measure(_ content: HistoryTextContent, expanded: Bool, width: CGFloat, scale: CGFloat) -> (textHeight: CGFloat, showsToggle: Bool) {
            let key = Key(text: expanded ? content.full : content.preview, expanded: expanded, width: width, scale: scale)
            if let result = measurements[key] { return result }
            let height = textHeight(key.text, lines: expanded ? 0 : 6, width: width, scale: scale)
            let showsToggle = expanded || content.hasOmittedTail ||
                (height + 1 >= sixLineHeight(scale: scale) && textHeight(content.preview, lines: 7, width: width, scale: scale) > height + 1)
            if measurements.count >= 1_000 { measurements.removeAll(keepingCapacity: true) }
            measurements[key] = (height, showsToggle)
            return (height, showsToggle)
        }
    }
}
