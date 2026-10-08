import SwiftUI

/// How far a raised surface casts its light and shade. Page cards and controls use the
/// Home hero's light and shade at full strength; only the spread shrinks.
enum SoftElevation {
    /// Section cards: half the hero's spread.
    case card
    /// Buttons, fields, pickers, segmented controls, switches and sliders: a quarter.
    case control

    var scale: CGFloat {
        switch self {
        case .card: 0.5
        case .control: 0.25
        }
    }
}

/// The Home hero's raised material for page cards and controls. Light comes from the top
/// left: a highlight up-left and a shade down-right, at the hero's opacities. Pressed
/// surfaces sink into an inset well with the inner shade at the top left.
struct SoftRaisedSurface<S: InsettableShape>: View {
    let shape: S
    var elevation: SoftElevation = .control
    var pressed = false
    var tint: Color? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        let spread = elevation.scale
        // The hero's cast shadows: palette shade at 70% (dark) or 85% (light), white light.
        let shade = Color.black.opacity(dark ? 0.525 : 0.27)
        let light = Color.white.opacity(dark ? 0.09 : 1)
        // Faces sit at the island's mid-tone, like the hero; controls a touch lighter on top.
        let faces: [CGFloat] = switch (elevation, dark) {
        case (.card, false): [0.91, 0.89]
        case (.card, true): [0.19, 0.17]
        case (.control, false): [0.93, 0.89]
        case (.control, true): [0.215, 0.18]
        }
        let rim = Color.white.opacity(dark ? 0.048 : 0.27)
        Group {
            if pressed {
                shape.fill((tint ?? Color(white: dark ? 0.15 : 0.87))
                    .shadow(.inner(color: shade, radius: 12 * spread, x: 7 * spread, y: 9 * spread))
                    .shadow(.inner(color: light, radius: 12 * spread, x: -6 * spread, y: -7 * spread)))
            } else if let tint {
                shape.fill(tint)
                    .overlay {
                        shape.fill(LinearGradient(colors: [.white.opacity(0.07), .black.opacity(0.07)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            } else {
                shape.fill(LinearGradient(colors: faces.map { Color(white: $0) },
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .overlay {
            if !pressed {
                shape.strokeBorder(LinearGradient(colors: [rim, rim.opacity(0)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.035), lineWidth: 0.5)
        }
        // One GPU-rendered layer for the face and its edges. Otherwise each
        // gradient is rasterized on the CPU whenever a lazy row appears.
        // Cast shadows stay outside the group, which would clip them.
        .drawingGroup()
        .background {
            if !pressed {
                SurfaceShadows(shape: shape, shadows: [
                    .init(color: shade, radius: 12 * spread, x: 7 * spread, y: 9 * spread),
                    .init(color: light, radius: 12 * spread, x: -6 * spread, y: -7 * spread),
                ])
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A recessed track for segmented controls, switches and sliders, lit like the Home well.
struct SoftInsetTrack<S: InsettableShape>: View {
    let shape: S
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        shape.fill(Color(white: dark ? 0.14 : 0.85)
            .shadow(.inner(color: .black.opacity(dark ? 0.6 : 0.3), radius: 2.5, x: 1.5, y: 2))
            .shadow(.inner(color: .white.opacity(dark ? 0.08 : 0.9), radius: 2.5, x: -1.5, y: -2)))
            .overlay {
                shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.04), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

enum SoftControl {
    static let height: CGFloat = 28
    static let fieldRadius: CGFloat = 8
    static var fieldShape: RoundedRectangle { RoundedRectangle(cornerRadius: fieldRadius, style: .continuous) }
}

// MARK: Fields

private struct SoftFieldChrome: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .frame(minHeight: SoftControl.height)
            .background { SoftRaisedSurface(shape: SoftControl.fieldShape) }
            .overlay {
                SoftControl.fieldShape
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .opacity(focused ? 1 : 0)
                    .allowsHitTesting(false)
            }
    }
}

private struct SoftField: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .modifier(SoftFieldChrome(focused: focused))
    }
}

extension View {
    /// A raised single-line text or secure field with an accent ring while editing.
    func softField() -> some View { modifier(SoftField()) }

    /// The same chrome for a field that already owns its focus state.
    func softField(focused: Bool) -> some View { modifier(SoftFieldChrome(focused: focused)) }
}

// MARK: Pickers

/// A raised menu picker that replaces the native bezel. The native borderless picker shows
/// the current choice and keeps VoiceOver and keyboard access; a transparent menu over the
/// whole capsule opens the same choices for the pointer.
struct SoftPicker<Value: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Value
    let width: CGFloat
    @ViewBuilder var content: Content

    init(_ title: String, selection: Binding<Value>, width: CGFloat, @ViewBuilder content: () -> Content) {
        self.title = title
        self._selection = selection
        self.width = width
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .allowsHitTesting(false)
                .padding(.trailing, 14)
            Menu {
                Picker(title, selection: $selection) { content }
                    .pickerStyle(.inline)
                    .labelsHidden()
            } label: {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .focusable(false)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 11)
        .frame(width: width, height: SoftControl.height)
        .background { SoftRaisedSurface(shape: Capsule()) }
        .contentShape(Capsule())
    }
}

/// Raised segments on a recessed track; the selected segment slides between choices.
struct SoftSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var width: CGFloat? = nil
    var small = false

    @Namespace private var thumb
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, selection: Binding<Value>, options: [(Value, String)], width: CGFloat? = nil, small: Bool = false) {
        self.title = title
        self._selection = selection
        self.options = options
        self.width = width
        self.small = small
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.0 == selection
                Button {
                    withAnimation(reduceMotion ? nil : SelectionMotion.curve) {
                        selection = option.0
                    }
                } label: {
                    Text(option.1)
                        .font(.system(size: small ? 11 : 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .lineLimit(1)
                        .padding(.horizontal, small ? 9 : 11)
                        .frame(maxWidth: width == nil ? nil : .infinity, maxHeight: .infinity)
                        .background {
                            if selected {
                                SoftRaisedSurface(shape: Capsule())
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.1)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(width: width, height: small ? 22 : SoftControl.height)
        .background { SoftInsetTrack(shape: Capsule()) }
        // The thumb is an object inside the track: its light and shade stay within it.
        .clipShape(Capsule())
        .opacity(isEnabled ? 1 : 0.5)
        .fixedSize(horizontal: width == nil, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: Switches

/// A recessed track with a raised knob, lit from the top left. On fills the track with the
/// system accent so the state never depends on the knob position alone.
struct SoftSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SoftSwitch(configuration: configuration)
    }

    private struct SoftSwitch: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let on = configuration.isOn
            Button {
                withAnimation(reduceMotion ? nil : .timingCurve(0.33, 1, 0.68, 1, duration: 0.2)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack(alignment: on ? .trailing : .leading) {
                    SoftInsetTrack(shape: Capsule())
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85))
                        .padding(1.5)
                        .opacity(on ? 1 : 0)
                    SoftRaisedSurface(shape: Circle())
                        .frame(width: 18, height: 18)
                        .padding(2)
                }
                .frame(width: 38, height: 22)
                // The knob's light and shade stay inside its track.
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.5)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
        }
    }
}

extension ToggleStyle where Self == SoftSwitchStyle {
    static var softSwitch: SoftSwitchStyle { SoftSwitchStyle() }
}

// MARK: Sliders

/// A recessed track with a raised knob; drag, click, use arrow keys or accessibility adjustments.
struct SoftSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    /// Seeking can use a larger keyboard increment without reducing pointer precision.
    var keyboardStep: Double? = nil

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geometry in
            let knob: CGFloat = 18
            let travel = max(1, geometry.size.width - knob)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? min(1, max(0, (value - range.lowerBound) / span)) : 0
            ZStack(alignment: .leading) {
                SoftInsetTrack(shape: Capsule())
                    .frame(height: 8)
                    .padding(.horizontal, knob / 2 - 4)
                SoftRaisedSurface(shape: Circle())
                    .frame(width: knob, height: knob)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard isEnabled else { return }
                focused = true
                let raw = range.lowerBound + Double((drag.location.x - knob / 2) / travel) * (range.upperBound - range.lowerBound)
                set(raw)
            })
        }
        .frame(height: 22)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(0...2))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + step)
            case .decrement: set(value - step)
            @unknown default: break
            }
        }
        .focusable(isEnabled)
        .focused($focused)
        .onMoveCommand { direction in
            switch direction {
            case .left, .down: set(value - (keyboardStep ?? step))
            case .right, .up: set(value + (keyboardStep ?? step))
            @unknown default: break
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .padding(-2)
                .opacity(focused && isEnabled ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    private func set(_ raw: Double) {
        guard isEnabled, raw.isFinite, step > 0 else { return }
        let stepped = range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step
        value = min(max(stepped, range.lowerBound), range.upperBound)
    }
}
