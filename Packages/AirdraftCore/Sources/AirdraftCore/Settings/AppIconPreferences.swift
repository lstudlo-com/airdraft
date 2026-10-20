/// The same three artworks are available independently for each appearance.
public enum AppIconStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case pureWave, carvedWave, nightWave

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pureWave: return String(localized: "Pure Wave", bundle: .module)
        case .carvedWave: return String(localized: "Carved Wave", bundle: .module)
        case .nightWave: return String(localized: "Night Wave", bundle: .module)
        }
    }
}

public struct AppIconPreferences: Codable, Equatable, Sendable {
    public var light: AppIconStyle
    public var dark: AppIconStyle

    public init(light: AppIconStyle = .carvedWave, dark: AppIconStyle = .nightWave) {
        self.light = light
        self.dark = dark
    }

    public func icon(isDark: Bool) -> AppIconStyle { isDark ? dark : light }
}
