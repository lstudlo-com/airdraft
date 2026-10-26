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

    public static let lineRange = 1...4

    public var style: Style
    /// Newest lines kept readable; older text fades out above them.
    public var lines: Int { didSet { lines = Self.clampedLines(lines) } }
    public var textSize: TextSize

    public init(style: Style = .glass, lines: Int = 2, textSize: TextSize = .medium) {
        self.style = style
        self.lines = Self.clampedLines(lines)
        self.textSize = textSize
    }

    /// Missing or unknown fields fall back to their defaults so a newer or
    /// older saved value never resets the others.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LiveTextOptions()
        style = (try? container.decodeIfPresent(Style.self, forKey: .style)) ?? defaults.style
        lines = Self.clampedLines((try? container.decodeIfPresent(Int.self, forKey: .lines)) ?? defaults.lines)
        textSize = (try? container.decodeIfPresent(TextSize.self, forKey: .textSize)) ?? defaults.textSize
    }

    private enum CodingKeys: String, CodingKey { case style, lines, textSize }

    static func clampedLines(_ value: Int) -> Int {
        min(max(value, lineRange.lowerBound), lineRange.upperBound)
    }
}
