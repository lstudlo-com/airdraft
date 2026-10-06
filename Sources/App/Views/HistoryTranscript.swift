import AppKit
import SwiftUI

/// Native selectable text with bounded collapsed layout. The expansion control
/// participates in the first size proposal, with no geometry-to-State feedback.
struct HistoryTranscript: NSViewRepresentable {
    let content: HistoryTextContent
    @Binding var expanded: Bool

    func makeNSView(context: Context) -> BackingView { BackingView() }

    func updateNSView(_ view: BackingView, context: Context) {
        view.configure(content: content, expanded: expanded)
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
            let toggle = NSButton(title: expanded ? "Show Less" : "Show More", target: self, action: #selector(toggleExpansion))
            Self.configureToggle(toggle)
            toggle.isHidden = !showsToggle
            addSubview(toggle)
            createdToggle = toggle
            return toggle
        }

        func configure(content: HistoryTextContent, expanded: Bool) {
            guard self.content != content || self.expanded != expanded else { return }
            self.content = content
            self.expanded = expanded
            textField.maximumNumberOfLines = expanded ? 0 : 6
            textField.attributedStringValue = NSAttributedString(string: expanded ? content.full : content.preview,
                                                                 attributes: Self.attributes)
            createdToggle?.title = expanded ? "Show Less" : "Show More"
            lastMeasurement = nil
            invalidateIntrinsicContentSize()
            needsLayout = true
        }

        func measure(width: CGFloat) -> Measurement {
            if let lastMeasurement, lastMeasurement.width == width { return lastMeasurement.result }
            guard let content else { return Measurement(textHeight: 0, buttonSize: .zero, showsToggle: false) }
            let measured = Self.measure(content, expanded: expanded, width: width)
            let result = Measurement(textHeight: measured.textHeight, buttonSize: Self.toggleSize(expanded: expanded),
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
                toggle.frame = NSRect(x: 0, y: result.textHeight + Theme.controlSpacing,
                                      width: result.buttonSize.width, height: result.buttonSize.height)
            } else {
                createdToggle?.isHidden = true
            }
        }

        @objc private func toggleExpansion() { onToggle?() }

        // MARK: Shared measurement

        private static let attributes: [NSAttributedString.Key: Any] = {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            return [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        }()

        private static func configureLabel(_ field: NSTextField) {
            field.font = .systemFont(ofSize: 14)
            field.isEditable = false
            field.isBezeled = false
            field.drawsBackground = false
            field.cell?.wraps = true
            field.cell?.truncatesLastVisibleLine = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        private static func configureToggle(_ toggle: NSButton) {
            toggle.isBordered = false
            toggle.bezelStyle = .inline
            toggle.font = .systemFont(ofSize: 12)
            toggle.contentTintColor = .linkColor
            toggle.setAccessibilityIdentifier("history.expand")
        }

        private static let measuringField: NSTextField = {
            let field = NSTextField(wrappingLabelWithString: "")
            configureLabel(field)
            return field
        }()

        private static var toggleSizes: [Bool: CGSize] = [:]

        private static func toggleSize(expanded: Bool) -> CGSize {
            if let size = toggleSizes[expanded] { return size }
            let toggle = NSButton(title: expanded ? "Show Less" : "Show More", target: nil, action: nil)
            configureToggle(toggle)
            toggleSizes[expanded] = toggle.fittingSize
            return toggle.fittingSize
        }

        private struct Key: Hashable {
            let text: String
            let expanded: Bool
            let width: CGFloat
        }

        /// Lazy rows are recreated whenever they scroll back into view. Text and
        /// width determine the result, so measurements outlive the views.
        private static var measurements: [Key: (textHeight: CGFloat, showsToggle: Bool)] = [:]

        private static func textHeight(_ text: String, lines: Int, width: CGFloat) -> CGFloat {
            let field = measuringField
            field.maximumNumberOfLines = lines
            field.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
            let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
            return ceil(field.cell?.cellSize(forBounds: bounds).height ?? 0)
        }

        /// Six unconstrained lines; anything shorter cannot have a seventh.
        private static let sixLineHeight = textHeight((1...6).map(String.init).joined(separator: "\n"), lines: 0, width: 10_000)

        private static func measure(_ content: HistoryTextContent, expanded: Bool, width: CGFloat) -> (textHeight: CGFloat, showsToggle: Bool) {
            let key = Key(text: expanded ? content.full : content.preview, expanded: expanded, width: width)
            if let result = measurements[key] { return result }
            let height = textHeight(key.text, lines: expanded ? 0 : 6, width: width)
            let showsToggle = expanded || content.hasOmittedTail ||
                (height + 1 >= sixLineHeight && textHeight(content.preview, lines: 7, width: width) > height + 1)
            if measurements.count >= 1_000 { measurements.removeAll(keepingCapacity: true) }
            measurements[key] = (height, showsToggle)
            return (height, showsToggle)
        }
    }
}
