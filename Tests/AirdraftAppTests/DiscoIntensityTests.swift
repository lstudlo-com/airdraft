import AirdraftCore
import XCTest

/// Settings > Appearance > Disco intensity scales the shared palette: the default
/// keeps the original colors, low stays gentle and high turns vivid and extreme.
final class DiscoIntensityTests: XCTestCase {
    private func chroma(_ rgb: HUDDiscoFrame.RGB) -> Double {
        max(rgb.red, rgb.green, rgb.blue) - min(rgb.red, rgb.green, rgb.blue)
    }

    /// How far a color without accent has left the neutral silver it starts from.
    /// Chroma alone can dip at low saturation, where a warm pigment first cancels
    /// the silver's faint blue.
    private func departure(_ rgb: HUDDiscoFrame.RGB, energy: Double) -> Double {
        let light = 0.84 + energy * 0.12
        return ((rgb.red - 0.96 * light) * (rgb.red - 0.96 * light) + (rgb.green - 0.97 * light) * (rgb.green - 0.97 * light)
                + (rgb.blue - light) * (rgb.blue - light)).squareRoot()
    }

    /// The default intensity reproduces the original formula; more intensity saturates
    /// more at every level and phase, and every value stays a valid color.
    func testDefaultKeepsTheOriginalPaletteAndIntensityRaisesSaturation() {
        let palette = [
            HUDDiscoFrame.RGB(red: 0.30, green: 0.88, blue: 1.00),
            HUDDiscoFrame.RGB(red: 0.42, green: 0.53, blue: 1.00),
            HUDDiscoFrame.RGB(red: 0.82, green: 0.40, blue: 1.00),
            HUDDiscoFrame.RGB(red: 1.00, green: 0.40, blue: 0.65),
            HUDDiscoFrame.RGB(red: 1.00, green: 0.73, blue: 0.34),
            HUDDiscoFrame.RGB(red: 0.34, green: 0.96, blue: 0.70),
        ]
        func original(travel: Double, energy: Double, accent: Double, position: Double) -> HUDDiscoFrame.RGB {
            let coordinate = travel + position * 0.32 + energy * 0.12 + accent * 0.05
            let scaled = (coordinate - floor(coordinate)) * Double(palette.count)
            let index = Int(scaled)
            let fraction = scaled - Double(index)
            let blend = fraction * fraction * (3 - 2 * fraction)
            let pigment = palette[index].mixed(with: palette[(index + 1) % palette.count], amount: blend)
            let saturation = min(0.94, 0.08 + energy * 0.78 + accent * 0.16)
            return HUDDiscoFrame.RGB(red: 0.96, green: 0.97, blue: 1).mixed(with: pigment, amount: saturation)
                .scaled(by: 0.84 + energy * 0.12 + accent * 0.04)
        }
        for energy in stride(from: 0.0, through: 1.0, by: 0.25) {
            for travel in stride(from: 0.0, to: 1.0, by: 0.1) {
                let frame = HUDDiscoFrame(travel: travel, energy: energy, accent: 0.3)
                XCTAssertEqual(frame.components(at: 0.4), original(travel: travel, energy: energy, accent: 0.3, position: 0.4))
                var previous = -1.0
                for intensity in [0, 0.25, 0.5, 0.75, 1] {
                    // No accent and the first element: the hue stays put, so only saturation moves.
                    let rgb = HUDDiscoFrame(travel: travel, energy: energy, intensity: intensity).components(at: 0)
                    XCTAssertTrue([rgb.red, rgb.green, rgb.blue].allSatisfy { (0...1).contains($0) })
                    XCTAssertGreaterThanOrEqual(departure(rgb, energy: energy), previous - 1e-9, "intensity \(intensity), energy \(energy)")
                    previous = departure(rgb, energy: energy)
                }
            }
        }
        let gentle = HUDDiscoFrame(energy: 1, intensity: 0).components(at: 0)
        let vivid = HUDDiscoFrame(energy: 1, intensity: 1).components(at: 0)
        XCTAssertLessThan(chroma(gentle), 0.35, "Gentle stays pastel even when shouting")
        XCTAssertGreaterThan(chroma(vivid), chroma(HUDDiscoFrame(energy: 1).components(at: 0)) + 0.1)
        XCTAssertEqual(HUDDiscoFrame.still(energy: 0.5, intensity: 7).intensity, 1)
        XCTAssertEqual(HUDDiscoFrame.still(energy: 0.5, intensity: .nan).intensity, AppSettings.defaultDiscoIntensity)
    }

    /// Higher intensity moves the color bands faster while speaking; silence still holds them.
    func testIntensityScalesColorTravelAndSilenceStillHolds() {
        func travel(intensity: Double, target: Double) -> Double {
            var motion = HUDDiscoMotion()
            for step in 0...120 { motion.advance(to: Double(step) / 60, target: target, intensity: intensity) }
            XCTAssertEqual(motion.frame.intensity, intensity)
            return motion.frame.travel
        }
        let gentle = travel(intensity: 0, target: 0.8)
        let standard = travel(intensity: 0.5, target: 0.8)
        let vivid = travel(intensity: 1, target: 0.8)
        XCTAssertLessThan(gentle, standard)
        XCTAssertLessThan(standard, vivid)
        XCTAssertEqual(travel(intensity: 1, target: 0), 0, "Silence never cycles color")
    }
}
