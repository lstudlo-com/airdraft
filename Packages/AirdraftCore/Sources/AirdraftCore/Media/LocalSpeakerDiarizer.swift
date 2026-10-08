import Foundation
import Darwin
import SpeakerKit

public enum LocalSpeakerDiarizer {
    public static var folder: URL { LocalModels.root.appendingPathComponent("speakerkit-coreml", isDirectory: true) }
    public static let modelPaths = [
        "speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc",
        "speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc"
    ]
    public static var isInstalled: Bool {
        !FileManager.default.fileExists(atPath: folder.appendingPathComponent(LocalModels.incompleteMarker).path) &&
        modelPaths.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }
    private static var availableMemory: UInt64 {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(statistics.free_count + statistics.inactive_count) * UInt64(vm_kernel_page_size)
    }
    public static func identify(url: URL, duration: Double, progress: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerInterval] {
        guard isInstalled else { throw MediaError.missingSpeakerModel }
        guard duration <= MediaConfiguration.maximumDuration else { throw MediaError.tooLong }
        // Whole-session clustering preserves identities. Bound concurrency and fail before allocating
        // when the conservative audio + model working-set allowance cannot fit.
        let required = UInt64(duration * 16_000 * 4 * 4) + 1_500_000_000
        guard availableMemory > required else { throw MediaError.insufficientMemory }
        try Task.checkCancellation()
        let config = PyannoteConfig(modelFolder: folder.path, download: false, verbose: false,
                                    concurrentSegmenterWorkers: 1, concurrentEmbedderWorkers: 2)
        let kit = try await SpeakerKit(config)
        do {
            let samples = try MediaAudioWindow.read(url, from: 0, maximumSeconds: duration)
            try Task.checkCancellation()
            let result = try await kit.diarize(audioArray: samples,
                options: PyannoteDiarizationOptions(useExclusiveReconciliation: false),
                progressCallback: { progress($0.fractionCompleted) })
            try Task.checkCancellation()
            let intervals = result.segments.map { segment in
                SpeakerInterval(start: Double(segment.startTime), end: Double(segment.endTime),
                    speaker: segment.speaker.speakerId.map { String($0 + 1) } ?? SpeakerInterval.unassigned)
            }
            await kit.unloadModels()
            return intervals
        } catch {
            await kit.unloadModels()
            throw error
        }
    }
}
