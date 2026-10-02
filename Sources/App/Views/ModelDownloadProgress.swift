import AirdraftCore
import SwiftUI

/// Shared by Models and first-run setup, including stages without a measurable total.
struct ModelDownloadProgress: View {
    let progress: ModelDownloader.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .accessibilityLabel("Model download")
                    .accessibilityValue(progress.detail)
            }
            HStack(spacing: 6) {
                if progress.fraction == nil { ProgressView().controlSize(.mini) }
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
}
