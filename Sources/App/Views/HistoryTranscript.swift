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
        private let probe = NSTextField(wrappingLabelWithString: "")
        let toggle = NSButton(title: "Show More", target: nil, action: nil)
        var onToggle: (() -> Void)?
        private var content: HistoryTextContent?
        private var expanded = false
        private var measurements: [CGFloat: Measurement] = [:]
        override var isFlipped: Bool { true }

        struct Measurement {
            let textHeight: CGFloat
            let buttonSize: CGSize
            let showsToggle: Bool
            var height: CGFloat { textHeight + (showsToggle ? Theme.controlSpacing + buttonSize.height : 0) }
        }

        init() {
            super.init(frame: .zero)
            for field in [textField, probe] {
                field.font = .systemFont(ofSize: 14)
                field.isEditable = false
                field.isBezeled = false
                field.drawsBackground = false
                field.cell?.wraps = true
                field.cell?.truncatesLastVisibleLine = true
                field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            textField.isSelectable = true
            probe.maximumNumberOfLines = 7
            toggle.isBordered = false
            toggle.bezelStyle = .inline
            toggle.font = .systemFont(ofSize: 12)
            toggle.contentTintColor = .linkColor
            toggle.target = self
            toggle.action = #selector(toggleExpansion)
            toggle.setAccessibilityIdentifier("history.expand")
            addSubview(textField)
            addSubview(toggle)
        }

        required init?(coder: NSCoder) { nil }

        func configure(content: HistoryTextContent, expanded: Bool) {
            guard self.content != content || self.expanded != expanded else { return }
            self.content = content
            self.expanded = expanded
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor, .paragraphStyle: style
            ]
            textField.maximumNumberOfLines = expanded ? 0 : 6
            textField.attributedStringValue = NSAttributedString(string: expanded ? content.full : content.preview, attributes: attributes)
            probe.attributedStringValue = NSAttributedString(string: content.preview, attributes: attributes)
            toggle.title = expanded ? "Show Less" : "Show More"
            measurements.removeAll(keepingCapacity: true)
            invalidateIntrinsicContentSize()
            needsLayout = true
        }

        func measure(width: CGFloat) -> Measurement {
            if let result = measurements[width] { return result }
            let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
            let textHeight = ceil(textField.cell?.cellSize(forBounds: bounds).height ?? 0)
            let showsToggle = expanded || content?.hasOmittedTail == true ||
                (probe.cell?.cellSize(forBounds: bounds).height ?? 0) > textHeight + 1
            let result = Measurement(textHeight: textHeight, buttonSize: toggle.fittingSize, showsToggle: showsToggle)
            // SwiftUI may probe several widths in a single pass. Keep a small cache.
            if measurements.count >= 8 { measurements.removeAll(keepingCapacity: true) }
            measurements[width] = result
            return result
        }

        override func layout() {
            super.layout()
            let result = measure(width: bounds.width)
            textField.frame = NSRect(x: 0, y: 0, width: bounds.width, height: result.textHeight)
            toggle.isHidden = !result.showsToggle
            toggle.frame = NSRect(x: 0, y: result.textHeight + Theme.controlSpacing,
                                  width: result.buttonSize.width, height: result.buttonSize.height)
        }

        @objc private func toggleExpansion() { onToggle?() }
    }
}
