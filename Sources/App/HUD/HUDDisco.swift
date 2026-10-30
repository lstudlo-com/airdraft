import AirdraftCore
import Foundation
import SwiftUI

/// Speech moves a continuous palette. Silence holds its position; a smoothed
/// syllable accent adds color without random jumps or flashing the capsule.
struct HUDDiscoMotion {
    private(set) var frame = HUDDiscoFrame()
    private var lastTime: TimeInterval?

    mutating func advance(to time: TimeInterval, target: Double,
                          intensity: Double = AppSettings.defaultDiscoIntensity) {
        guard time.isFinite else { return }
        let dt = min(1.0 / 15, max(0, time - (lastTime ?? time)))
        lastTime = time
        frame.intensity = AppSettings.clampedDiscoIntensity(intensity)
        let input = target.isFinite ? min(1, max(0, target)) : 0
        let onset = min(1, max(0, input - frame.energy) * 2.4)
        let response = input > frame.energy ? 0.065 : 0.32
        frame.energy += (input - frame.energy) * (1 - exp(-dt / response))
        let accentResponse = onset > frame.accent ? 0.045 : 0.24
        frame.accent += (onset - frame.accent) * (1 - exp(-dt / accentResponse))
        frame.travel = (frame.travel + dt * max(0, frame.energy - 0.045)
                        * (0.10 + 0.10 * frame.accent) * frame.scaled(0.45, 1, 2)).truncatingRemainder(dividingBy: 1)
    }
}

/// Captured with geometry during delivery, so color cannot keep travelling
/// while the final HUD fades. Static previews and Reduce Motion use level only.
struct HUDDiscoFrame: Equatable {
    var travel = 0.0
    var energy = 0.0
    var accent = 0.0
    /// Settings > Appearance > Disco intensity. Low stays pastel, narrow and slow;
    /// high saturates sooner, purifies the pigments, spreads more of the ring across
    /// the artwork and travels faster. The default reproduces the original palette.
    var intensity = AppSettings.defaultDiscoIntensity

    static func still(energy: Double, intensity: Double = AppSettings.defaultDiscoIntensity) -> Self {
        Self(energy: energy.isFinite ? min(1, max(0, energy)) : 0,
             intensity: AppSettings.clampedDiscoIntensity(intensity))
    }

    /// `standard` at the default intensity, interpolated towards `gentle` at 0
    /// and `vivid` at 1.
    func scaled(_ gentle: Double, _ standard: Double, _ vivid: Double) -> Double {
        let value = AppSettings.clampedDiscoIntensity(intensity)
        let midpoint = AppSettings.defaultDiscoIntensity
        return value < midpoint
            ? gentle + (standard - gentle) * value / midpoint
            : standard + (vivid - standard) * (value - midpoint) / (1 - midpoint)
    }

    func color(at position: Double, shade: Double = 1) -> Color {
        let rgb = components(at: position, shade: shade)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    func components(at position: Double, shade: Double = 1) -> RGB {
        let energy = energy.isFinite ? min(1, max(0, energy)) : 0
        let accent = accent.isFinite ? min(1, max(0, accent)) : 0
        let coordinate = travel + position * scaled(0.16, 0.32, 0.56) + energy * 0.12 + accent * scaled(0.03, 0.05, 0.09)
        let wrapped = coordinate.isFinite ? coordinate - floor(coordinate) : 0
        let stop = wrapped * Double(Self.palette.count)
        let index = Int(stop)
        let fraction = stop - Double(index)
        // Smooth the stop boundaries, including the mint-to-ice seam.
        let blend = fraction * fraction * (3 - 2 * fraction)
        let pigment = Self.palette[index].mixed(with: Self.palette[(index + 1) % Self.palette.count], amount: blend)
            .purified(by: scaled(1, 1, 1.3))
        let gain = scaled(0.45, 1, 1.45)
        let saturation = min(scaled(0.42, 0.94, 1), scaled(0.04, 0.08, 0.14) + energy * 0.78 * gain + accent * 0.16 * gain)
        let light = (0.84 + energy * 0.12 + accent * 0.04) * min(1, max(0, shade.isFinite ? shade : 1))
        return RGB(red: 0.96, green: 0.97, blue: 1)
            .mixed(with: pigment, amount: saturation).scaled(by: light)
    }

    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        func mixed(with other: Self, amount: Double) -> Self {
            Self(red: red + (other.red - red) * amount,
                 green: green + (other.green - green) * amount,
                 blue: blue + (other.blue - blue) * amount)
        }

        func scaled(by value: Double) -> Self {
            Self(red: red * value, green: green * value, blue: blue * value)
        }

        /// Moves each channel away from their mean, keeping the hue.
        func purified(by amount: Double) -> Self {
            guard amount != 1 else { return self }
            let mean = (red + green + blue) / 3
            func channel(_ value: Double) -> Double { min(1, max(0, mean + (value - mean) * amount)) }
            return Self(red: channel(red), green: channel(green), blue: channel(blue))
        }
    }

    // Luminous ice, sapphire, amethyst, coral, amber and mint. Neighbouring
    // elements sample a short band of this ring, preserving a coherent material.
    private static let palette = [
        RGB(red: 0.30, green: 0.88, blue: 1.00),
        RGB(red: 0.42, green: 0.53, blue: 1.00),
        RGB(red: 0.82, green: 0.40, blue: 1.00),
        RGB(red: 1.00, green: 0.40, blue: 0.65),
        RGB(red: 1.00, green: 0.73, blue: 0.34),
        RGB(red: 0.34, green: 0.96, blue: 0.70),
    ]
}
