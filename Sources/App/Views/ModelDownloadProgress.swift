import AirdraftCore
import SwiftUI

/// Shared by Models and first-run setup, including stages without a measurable total.
struct ModelDownloadProgress: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: ModelDownloader.Progress

    var body: some View {
        if let fraction = progress.fraction, fraction > 0 {
            MeasuredDownloadProgress(progress: progress)
                .animation(reduceMotion ? nil : .linear(duration: 0.2), value: fraction)
        } else {
            DownloadProgressLabel(progress: progress, showsActivity: true)
        }
    }
}

/// Interpolate only between received values, with no timer that guesses ahead.
/// The label and fill share the same value so coarse provider callbacks stay legible.
private struct MeasuredDownloadProgress: View, Animatable {
    var progress: ModelDownloader.Progress

    var animatableData: Double {
        get { progress.fraction ?? 0 }
        set { progress.fraction = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress.fraction ?? 0)
                .progressViewStyle(DownloadProgressStyle())
                .accessibilityLabel("Model download")
                .accessibilityValue(progress.detail)
            DownloadProgressLabel(progress: progress, showsActivity: false)
        }
    }
}

private struct DownloadProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.2))
                Capsule().fill(.tint)
                    .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 4)
    }
}

private struct DownloadProgressLabel: View {
    let progress: ModelDownloader.Progress
    let showsActivity: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showsActivity {
                ProgressView().controlSize(.mini).accessibilityHidden(true)
            }
            if !progress.detail.isEmpty {
                Text(progress.detail).monospacedDigit().fixedSize()
            }
            Text(progress.currentFile).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .help([progress.detail, progress.currentFile].filter { !$0.isEmpty }.joined(separator: " · "))
    }
}
