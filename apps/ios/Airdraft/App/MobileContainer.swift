import AirdraftCore
import Foundation
import Observation
import os

/// Owns the app's stores and engines. Data lives in the app's own container,
/// in the same layout as the Mac app's Application Support folder.
@MainActor
@Observable
final class MobileContainer {
    let settings: AppSettings
    let mobile: MobileSettings
    let profiles: ProfileStore
    let dictionary: DictionaryStore
    let history: HistoryStore?
    let historyError: String?
    let factory: EngineFactory
    let downloads: ModelDownloadStore
    let dictation: MobileDictation
    let controller: DictationController
    let transcribe: TranscribeController

    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "container")

    init(defaults: UserDefaults = .standard, directory: URL = AppSettings.supportDirectory) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let firstLaunch = defaults.data(forKey: "settings.asr") == nil
        settings = AppSettings(defaults: defaults)
        if firstLaunch {
            // A new iPhone setup starts with the speech recognition built into
            // iOS, which needs no download, and refinement off until chosen.
            settings.asr.select(.apple)
            settings.llm.select(.none)
        }
        mobile = MobileSettings(defaults: defaults)
        profiles = ProfileStore(directory: directory)
        dictionary = DictionaryStore(directory: directory)
        do {
            history = try HistoryStore(directory: directory)
            historyError = nil
        } catch {
            history = nil
            historyError = error.localizedDescription
            Self.log.error("history unavailable: \(error.localizedDescription, privacy: .public)")
        }
        factory = EngineFactory(status: EngineStatus())
        downloads = ModelDownloadStore()
        let recorder = AudioRecorder()
        dictation = MobileDictation(settings: settings, profiles: profiles, dictionary: dictionary,
                                    factory: factory, history: history, recorder: recorder)
        controller = DictationController(dictation: dictation, recorder: recorder, settings: settings,
                                         mobile: mobile, factory: factory)
        transcribe = TranscribeController(history: history, factory: factory, directory: directory, speech: settings.asr,
                                          defaults: defaults)
        // One input at a time: dictation and its keyboard session, or a long recording.
        let controller = self.controller, transcribe = self.transcribe, dictation = self.dictation
        transcribe.dictationHoldsMicrophone = { [weak controller, weak dictation] in
            controller?.isSessionActive == true || (dictation.map { $0.phase != .idle } ?? false)
        }
        controller.otherCaptureActive = { [weak transcribe] in transcribe?.isRecording == true }
        Self.excludeModelsFromBackup()
    }

    /// Downloaded models can be downloaded again; keep them out of iCloud backups.
    private static func excludeModelsFromBackup() {
        var root = LocalModels.root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }
}
