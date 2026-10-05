import XCTest
import AVFoundation
@testable import AirdraftCore

final class MeetingCaptureTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Airdraft-MeetingTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func testSeparateChannelsCommonClockGapsTailAndCleanup() throws {
        let root = try directory(); let history = try HistoryStore(directory: root)
        let writer = try MeetingAudioWriter(directory: root, microphone: true)
        try writer.append(Array(repeating: 0.8, count: 16_000), track: .microphone, at: 0)
        try writer.append(Array(repeating: 0.2, count: 8_000), track: .system, at: 0.5)
        try writer.append(Array(repeating: -0.4, count: 16_000), track: .system, at: 2)
        try writer.append(Array(repeating: 0.7, count: 4_000), track: .microphone, at: 2.75)
        // Duplicate/late buffers may not overwrite already accepted audio.
        try writer.append(Array(repeating: -1, count: 8_000), track: .system, at: 2)
        let draft = try writer.finish()
        XCTAssertEqual(writer.duration, 3, accuracy: 0.0001)
        let asset = try MeetingAudioStore.recover(draft, directory: root, history: history, interrupted: false)
        let url = try XCTUnwrap(history.audioURL(for: asset))
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.processingFormat.channelCount, 2)
        XCTAssertEqual(asset.source, .meeting); XCTAssertEqual(asset.duration, 3, accuracy: 0.0001)
        XCTAssertTrue(asset.captureIssue?.contains("gap") == true)
        let samples = try MediaAudioWindow.read(url, from: 0)
        XCTAssertEqual(samples.count, 48_000)
        XCTAssertEqual(samples[100], 0.4, accuracy: 0.001)
        XCTAssertEqual(samples[10_000], 0.5, accuracy: 0.001)
        XCTAssertEqual(samples[20_000], 0, accuracy: 0.001)
        XCTAssertEqual(samples[33_000], -0.2, accuracy: 0.001)
        XCTAssertEqual(samples[47_900], 0.15, accuracy: 0.001) // Last quarter-second survived finalization.
        XCTAssertEqual(try MeetingAudioStore.drafts(in: root).count, 0)
        _ = try history.createDocument(asset: asset, title: "Meeting", configuration: .init())
        try history.deleteHistoryKeepingAudio()
        XCTAssertNotNil(history.audioURL(for: asset))
        try history.pruneAudio(olderThan: Date().addingTimeInterval(10_000))
        XCTAssertNotNil(history.audioURL(for: asset))
        try history.deleteAllAudio()
        XCTAssertNil(history.audioURL(for: asset))
    }
    func testInterruptedWriterRecoversWithoutHeaderOrTranscriptAndIdempotentAdoption() throws {
        let root = try directory(); let history = try HistoryStore(directory: root)
        do {
            let writer = try MeetingAudioWriter(directory: root, microphone: true)
            try writer.append(Array(repeating: 0.3, count: 32_000), track: .system, at: 0)
            // Intentionally omit finish, like a process interruption.
        }
        let draft = try XCTUnwrap(MeetingAudioStore.drafts(in: root).first)
        let asset = try MeetingAudioStore.recover(draft, directory: root, history: history, interrupted: true)
        XCTAssertEqual(asset.id, draft.id)
        XCTAssertTrue(asset.captureIssue?.contains("Recovered") == true)
        XCTAssertTrue(asset.captureIssue?.contains("No microphone") == true)
        let repeated = try MeetingAudioStore.recover(draft, directory: root, history: history, interrupted: true)
        XCTAssertEqual(repeated.id, asset.id)
        XCTAssertEqual(try history.recordings().entries.count, 1)
        XCTAssertEqual(try history.documents().count, 0)
    }
    func testUnreadableDraftDoesNotHideOtherRecoverableMeetings() throws {
        let root = try directory()
        let valid = try MeetingAudioWriter(directory: root, microphone: false)
        let broken = try MeetingAudioWriter(directory: root, microphone: false)
        let json = root.appendingPathComponent("MeetingStaging/\(broken.id)/session.json")
        try Data("broken".utf8).write(to: json)
        let scan = try MeetingAudioStore.scanDrafts(in: root)
        XCTAssertEqual(scan.unreadable, 1)
        XCTAssertEqual(scan.drafts.map(\.id), [valid.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: json.path))
    }

    func testLimitsEmptyAndUnsafeFilesFailWithoutRemovingExternalData() throws {
        let root = try directory(); let history = try HistoryStore(directory: root)
        let writer = try MeetingAudioWriter(directory: root, microphone: true)
        XCTAssertThrowsError(try writer.append([1], track: .system, at: .nan))
        XCTAssertThrowsError(try writer.append([1], track: .system, at: 7201))
        XCTAssertThrowsError(try writer.append([.infinity], track: .system, at: 0))
        XCTAssertThrowsError(try writer.finish())
        try MeetingAudioStore.discardEmpty(id: writer.id, directory: root)
        XCTAssertTrue(try MeetingAudioStore.drafts(in: root).isEmpty)
        let target = root.appendingPathComponent("external"); try Data("keep".utf8).write(to: target)
        let second = try MeetingAudioWriter(directory: root, microphone: false)
        let draft = try XCTUnwrap(MeetingAudioStore.drafts(in: root).first)
        let pcm = root.appendingPathComponent("MeetingStaging/\(second.id)/system.pcm")
        try FileManager.default.removeItem(at: pcm)
        try FileManager.default.createSymbolicLink(at: pcm, withDestinationURL: target)
        XCTAssertThrowsError(try MeetingAudioStore.recover(draft, directory: root, history: history, interrupted: true))
        try MeetingAudioStore.removeDrafts(in: root)
        XCTAssertEqual(try String(contentsOf: target), "keep")
    }
    func testNativeStereo48kBuffersResampleWithoutAnOutputDevice() throws {
        let root = try directory()
        let capture = try MeetingCaptureSession(directory: root, microphone: true, onStatus: { _ in }, onFailure: { _ in })
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        pcm.frameLength = 4800
        pcm.floatChannelData![0].initialize(repeating: 0.2, count: 4800)
        pcm.floatChannelData![1].initialize(repeating: 0.6, count: 4800)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
            refcon: nil, formatDescription: format.formatDescription, sampleCount: 4800, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample), noErr)
        let buffer = try XCTUnwrap(sample)
        XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(buffer, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: pcm.audioBufferList), noErr)
        var all: [Float] = []
        for _ in 0..<10 { all += try capture.normalize(buffer, track: .microphone) }
        all += try capture.finishConversion(.microphone)
        print("MEETING_CONVERTED_WITH_TAIL frames=\(all.count)")
        XCTAssertEqual(all.count, 16_000, accuracy: 2)
        XCTAssertEqual(all[1000], 0.4, accuracy: 0.01)
    }

    func testTwoHourCaptureAndExportStayBounded() throws {
        let root = try directory(); let history = try HistoryStore(directory: root)
        let writer = try MeetingAudioWriter(directory: root, microphone: true)
        let buffer = Array(repeating: Float(0.1), count: 16_000)
        for seconds in 0..<7200 {
            try writer.append(buffer, track: .system, at: Double(seconds))
            try writer.append(buffer, track: .microphone, at: Double(seconds))
        }
        let draft = try writer.finish()
        let asset = try MeetingAudioStore.recover(draft, directory: root, history: history, interrupted: false)
        XCTAssertEqual(asset.duration, 7200, accuracy: 0.001)
        let tail = try MediaAudioWindow.read(try XCTUnwrap(history.audioURL(for: asset)), from: 7199)
        XCTAssertEqual(tail.count, 16000); XCTAssertEqual(tail.last ?? 0, 0.1, accuracy: 0.001)
    }
}
