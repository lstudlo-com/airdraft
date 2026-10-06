import AirdraftCore
import Observation
import SwiftUI

@Observable final class SpatialHUDAnimation {
    var motion = SpatialHUDMotion()
}

/// A small software-projected scene. Only this well redraws at display cadence;
/// it neither opens an audio input nor keeps a renderer alive after dismissal.
struct SpatialHUDVisualizer: View {
    let style: HUDStyle
    let levels: [Float]
    let recording: Bool
    var frozenTime: TimeInterval?
    var frozenEnergy: Double?
    @State var animation = SpatialHUDAnimation()
    var reduceMotionOverride: Bool?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60,
                                paused: frozenTime != nil || reduceMotion)) { timeline in
            let target = SpatialHUDMotion.energy(levels: levels, recording: recording)
            let energy = frozenEnergy ?? (frozenTime != nil || reduceMotion ? target : animation.motion.energy)
            let phase = reduceMotion ? 0.65 : frozenTime ?? animation.motion.phase
            Canvas { context, size in
                let scene = SpatialHUDScene(size: size, phase: phase, energy: energy,
                                            recording: recording, highContrast: contrast == .increased)
                if style == .sonic {
                    scene.sonic(in: &context)
                } else {
                    scene.cube(in: &context)
                }
            }
            .onChange(of: timeline.date, initial: true) { _, date in
                guard frozenTime == nil, !reduceMotion else { return }
                animation.motion.advance(to: date.timeIntervalSinceReferenceDate, target: target, recording: recording)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Integrating rotation avoids discontinuities when the microphone level changes.
/// Fast attack and slower release keep consonants crisp without jitter in pauses.
struct SpatialHUDMotion {
    private(set) var phase = 0.65
    private(set) var energy = 0.0
    private var lastTime: TimeInterval?

    static func energy(levels: [Float], recording: Bool) -> Double {
        guard recording else { return 0 }
        let recent = levels.suffix(4).map { $0.isFinite ? min(1, max(0, Double($0))) : 0 }
        guard !recent.isEmpty else { return 0 }
        let rms = sqrt(recent.reduce(0) { $0 + $1 * $1 } / Double(recent.count))
        return min(1, pow(max(0, rms - 0.025) / 0.7, 0.72))
    }

    mutating func advance(to time: TimeInterval, target: Double, recording: Bool) {
        let dt = min(1.0 / 15, max(0, time - (lastTime ?? time)))
        lastTime = time
        let response = target > energy ? 0.055 : 0.20
        energy += (target - energy) * (1 - exp(-dt / response))
        phase += dt * (recording ? 0.55 + 3.8 * energy : 1.15)
    }
}

private struct SpatialHUDScene {
    let size: CGSize
    let phase: Double
    let energy: Double
    let recording: Bool
    let highContrast: Bool

    private struct Point3 {
        var x: Double
        var y: Double
        var z: Double
    }

    private var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    private var unit: Double { min(size.height / 3.8, size.width / 12) }
    private var intensity: Double { recording ? 1 : 0.58 }

    private func rotate(_ point: Point3) -> Point3 {
        let yaw = phase * 0.9
        let pitch = 0.55 + sin(phase * 0.57) * 0.36
        let roll = sin(phase * 0.43) * 0.24
        let x = point.x * cos(yaw) + point.z * sin(yaw)
        let z = -point.x * sin(yaw) + point.z * cos(yaw)
        let y = point.y * cos(pitch) - z * sin(pitch)
        let depth = point.y * sin(pitch) + z * cos(pitch)
        return Point3(x: x * cos(roll) - y * sin(roll),
                      y: x * sin(roll) + y * cos(roll), z: depth)
    }

    private func project(_ point: Point3, scale: Double = 1) -> CGPoint {
        let perspective = 6 / (6 - point.z)
        return CGPoint(x: center.x + point.x * unit * scale * perspective,
                       y: center.y + point.y * unit * scale * perspective)
    }

    private func path(_ points: [CGPoint], closed: Bool = false) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            if closed { path.closeSubpath() }
        }
    }

    private var vertices: [Point3] {
        [Point3(x: -1, y: -1, z: -1), Point3(x: 1, y: -1, z: -1),
         Point3(x: 1, y: 1, z: -1), Point3(x: -1, y: 1, z: -1),
         Point3(x: -1, y: -1, z: 1), Point3(x: 1, y: -1, z: 1),
         Point3(x: 1, y: 1, z: 1), Point3(x: -1, y: 1, z: 1)]
    }

    func cube(in context: inout GraphicsContext) {
        // Fine orbital rails expand with speech, behind the machined cube.
        for ring in 0..<3 {
            let points = (0...64).map { index -> CGPoint in
                let t = Double(index) / 64 * .pi * 2
                let radius = 1.55 + Double(ring) * 0.46 + energy * 0.45
                let p = Point3(x: cos(t) * radius, y: sin(t) * radius * 0.22,
                               z: sin(t) * radius * 0.5)
                return project(rotate(p))
            }
            context.stroke(path(points), with: .color(.white.opacity((0.09 + energy * 0.12) * intensity)),
                           lineWidth: highContrast ? 0.8 : 0.5)
        }
        let points = vertices
        let faces = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3],
                     [1, 2, 6, 5], [0, 1, 5, 4], [3, 7, 6, 2]]
        let normals = [Point3(x: 0, y: 0, z: -1), Point3(x: 0, y: 0, z: 1),
                       Point3(x: -1, y: 0, z: 0), Point3(x: 1, y: 0, z: 0),
                       Point3(x: 0, y: -1, z: 0), Point3(x: 0, y: 1, z: 0)]
        let sorted = faces.indices.sorted { rotate(normals[$0]).z < rotate(normals[$1]).z }
        for index in sorted {
            let normal = normals[index]
            let rotatedNormal = rotate(normal)
            // Slightly separated face plates open on syllables, then settle.
            let separation = energy * 0.20
            let corners = faces[index].map { vertex -> CGPoint in
                let p = points[vertex]
                return project(rotate(Point3(x: p.x + normal.x * separation,
                                             y: p.y + normal.y * separation,
                                             z: p.z + normal.z * separation)), scale: 0.90)
            }
            let face = path(corners, closed: true)
            let light = max(0, -rotatedNormal.x * 0.35 - rotatedNormal.y * 0.65 + rotatedNormal.z * 0.55)
            let silver = 0.22 + light * 0.57
            context.fill(face, with: .linearGradient(
                Gradient(colors: [Color(white: min(1, silver + 0.20)), Color(white: silver * 0.65)]),
                startPoint: CGPoint(x: center.x - 9, y: 0),
                endPoint: CGPoint(x: center.x + 9, y: size.height)))
            context.stroke(face, with: .color(.white.opacity((0.28 + light * 0.48) * intensity)),
                           lineWidth: highContrast ? 0.85 : 0.55)
            // An inset face outline gives the object a visible bevel at HUD scale.
            let centroid = CGPoint(x: corners.map(\.x).reduce(0, +) / 4,
                                   y: corners.map(\.y).reduce(0, +) / 4)
            let inset = corners.map { CGPoint(x: centroid.x + ($0.x - centroid.x) * 0.70,
                                              y: centroid.y + ($0.y - centroid.y) * 0.70) }
            context.stroke(path(inset, closed: true), with: .color(.white.opacity(0.13 * intensity)), lineWidth: 0.4)
        }
        // Two balanced traces connect the floating object to the audio field.
        for side in [-1.0, 1.0] {
            let trace = (0...30).map { index -> CGPoint in
                let t = Double(index) / 30
                let envelope = sin(t * .pi)
                return CGPoint(x: center.x + side * (14 + t * 22),
                               y: center.y + sin(t * 9 - phase * 3) * envelope * energy * 3)
            }
            context.stroke(path(trace), with: .color(.white.opacity((0.20 + energy * 0.48) * intensity)), lineWidth: 0.75)
        }
    }

    func sonic(in context: inout GraphicsContext) {
        let corners = vertices.map { project(rotate($0), scale: 0.93 + energy * 0.08) }
        let edges = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6),
                     (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
        for (a, b) in edges {
            context.stroke(path([corners[a], corners[b]]),
                           with: .color(.white.opacity(highContrast ? 0.65 : 0.24)), lineWidth: 0.5)
        }
        // Braided ribbons form a travelling interference pattern, not fake FFT bands.
        // Their excursion is driven only by the measured short-term input level.
        for strand in 0..<7 {
            let offset = Double(strand - 3)
            let points = (0...80).map { index -> CGPoint in
                let t = Double(index) / 80
                let envelope = pow(sin(t * .pi), 1.4)
                let carrier = sin(t * 12.5 - phase * 3.1 + offset * 0.38)
                let overtone = sin(t * 23 + phase * 1.7 + offset * 0.63) * 0.25
                let amplitude = 0.35 + energy * 6.2
                return CGPoint(x: 6 + t * (size.width - 12),
                               y: center.y + envelope * ((carrier + overtone) * amplitude + offset * 0.38))
            }
            let curve = path(points)
            let opacity = (0.30 + (1 - abs(offset) / 4) * 0.58) * intensity
            if strand == 3 && !highContrast {
                var glow = context
                glow.addFilter(.blur(radius: 1.5))
                glow.stroke(curve, with: .color(.white.opacity(energy * 0.25)), lineWidth: 2.5)
            }
            context.stroke(curve, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.06), .white.opacity(opacity), .white.opacity(0.06)]),
                startPoint: CGPoint(x: 6, y: 0), endPoint: CGPoint(x: size.width - 6, y: 0)),
                lineWidth: strand == 3 ? 0.9 : 0.5)
        }
    }
}
