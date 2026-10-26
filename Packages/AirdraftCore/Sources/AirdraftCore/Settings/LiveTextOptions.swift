import Foundation

/// How the recording window's live-text card looks (AD-108). Display only:
/// the preview source, cadence and the final transcript are unchanged.
public struct LiveTextOptions: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Translucent smoked glass over the desktop.
        case glass
        /// An opaque dark card.
        case solid
        /// Frosted light glass with dark text.
        case frost
        /// A wide, centered caption bar.
        case subtitle
        /// Shadowed text without a card.
        case bare
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .glass: return String(localized: "Glass", bundle: .module)
            case .solid: return String(localized: "Solid", bundle: .module)
            case .frost: return String(localized: "Frost", bundle: .module)
            case .subtitle: return String(localized: "Subtitle", bundle: .module)
            case .bare: return String(localized: "Text Only", bundle: .module)
            }
        }
    }

    public enum TextSize: String, Codable, CaseIterable, Sendable, Identifiable {
        case small, medium, large
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .small: return String(localized: "Small", bundle: .module)
            case .medium: return String(localized: "Medium", bundle: .module)
            case .large: return String(localized: "Large", bundle: .module)
            }
        }
        /// Points; the recording window keeps fixed sizes outside the app's text scale.
        public var points: Double {
            switch self {
            case .small: return 11.5
            case .medium: return 12.5
            case .large: return 14.5
            }
        }
    }

    /// How newly recognized words enter the live text. Display only.
    public enum Reveal: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Words fade in.
        case fade
        /// Words rise into place as they fade in.
        case rise
        /// Words come into focus from a blur.
        case focus
        /// Words grow from small with a slight overshoot.
        case pop
        /// Letters appear one after another.
        case typewriter
        /// Letters arc up and settle, one after another.
        case wave
        /// Words light up, then cool to the normal color.
        case glow
        /// Words appear at once.
        case none
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .fade: return String(localized: "Fade", bundle: .module)
            case .rise: return String(localized: "Rise", bundle: .module)
            case .focus: return String(localized: "Focus", bundle: .module)
            case .pop: return String(localized: "Pop", bundle: .module)
            case .typewriter: return String(localized: "Typewriter", bundle: .module)
            case .wave: return String(localized: "Wave", bundle: .module)
            case .glow: return String(localized: "Glow", bundle: .module)
            case .none: return String(localized: "RevealNone", defaultValue: "None", bundle: .module)
            }
        }

        /// Moving effects fall back to a fade under Reduce Motion.
        public var isSpatial: Bool { self == .rise || self == .pop || self == .wave }

        /// Seconds one letter takes to settle.
        public var duration: TimeInterval {
            switch self {
            case .fade: return 0.35
            case .rise: return 0.45
            case .focus: return 0.5
            case .pop: return 0.42
            case .typewriter: return 0.06
            case .wave: return 0.55
            case .glow: return 0.9
            case .none: return 0
            }
        }

        /// Seconds between consecutive letters of one update.
        public var stagger: TimeInterval {
            switch self {
            case .fade, .focus: return 0.012
            case .rise, .glow: return 0.016
            case .pop: return 0.022
            case .typewriter: return 0.035
            case .wave: return 0.03
            case .none: return 0
            }
        }

        /// The longest a whole update may take to start every letter, so a
        /// long phrase never trails far behind speech.
        public var maximumSpread: TimeInterval { self == .typewriter ? 1.1 : 0.7 }
    }

    public static let lineRange = 1...4

    public var style: Style
    /// Newest lines kept readable; older text fades out above them.
    public var lines: Int { didSet { lines = Self.clampedLines(lines) } }
    public var textSize: TextSize
    public var reveal: Reveal

    public init(style: Style = .glass, lines: Int = 2, textSize: TextSize = .medium, reveal: Reveal = .fade) {
        self.style = style
        self.lines = Self.clampedLines(lines)
        self.textSize = textSize
        self.reveal = reveal
    }

    /// Missing or unknown fields fall back to their defaults so a newer or
    /// older saved value never resets the others.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LiveTextOptions()
        style = (try? container.decodeIfPresent(Style.self, forKey: .style)) ?? defaults.style
        lines = Self.clampedLines((try? container.decodeIfPresent(Int.self, forKey: .lines)) ?? defaults.lines)
        textSize = (try? container.decodeIfPresent(TextSize.self, forKey: .textSize)) ?? defaults.textSize
        reveal = (try? container.decodeIfPresent(Reveal.self, forKey: .reveal)) ?? defaults.reveal
    }

    private enum CodingKeys: String, CodingKey { case style, lines, textSize, reveal }

    static func clampedLines(_ value: Int) -> Int {
        min(max(value, lineRange.lowerBound), lineRange.upperBound)
    }
}
