import AVFoundation
import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit

public struct MeetingAudioSource: Identifiable, Sendable, Hashable {
    public let id: Int32
    public let name: String
    public init(id: Int32, name: String) { self.id = id; self.name = name }
}
public struct MeetingCaptureStatus: Sendable {
    public let duration: Double
    public let microphoneLevel: Float
    public let systemLevel: Float
    public let microphoneReceived: Bool
    public let systemReceived: Bool
}

public protocol MeetingCapturing: AnyObject, Sendable {
    var id: String { get }
    func start(applicationID: Int32?, microphoneID: String?, includeMicrophone: Bool, microphoneChannel: Int?) async throws
    func stop(reason: String?) async throws -> MeetingDraft
}

/// Captures only audio outputs. No screen frames are retained and no output device is opened.
/// Delegate and file writes share one bounded serial queue; UI receives throttled snapshots.
public final class MeetingCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, MeetingCapturing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Airdraft.meeting.capture", qos: .userInitiated)
    private let writer: MeetingAudioWriter
    private let onStatus: @Sendable (MeetingCaptureStatus) -> Void
    private let onFailure: @Sendable (String) -> Void
    public var id: String { writer.id }
    private var stream: SCStream?
    private var accepting = false
    private var origin = 0.0
    private var lastStatus = 0.0
    private var levels: [MeetingTrack: Float] = [:]
    private var lastReceived: [MeetingTrack: Double] = [:]
    private var inputEnds: [MeetingTrack: Double] = [:]
    private var outputOffsets: [MeetingTrack: Double] = [:]
    private var expectedFrames: [MeetingTrack: Double] = [:]
    private var convertedFrames: [MeetingTrack: Int] = [:]
    private var converters: [MeetingTrack: AVAudioConverter] = [:]
    private var formats: [MeetingTrack: AVAudioFormat] = [:]
    private var failed = false
    private var microphoneChannel: Int?
    public init(directory: URL, microphone: Bool,
                onStatus: @escaping @Sendable (MeetingCaptureStatus) -> Void,
                onFailure: @escaping @Sendable (String) -> Void) throws {
        writer = try MeetingAudioWriter(directory: directory, microphone: microphone)
        self.onStatus = onStatus; self.onFailure = onFailure
    }
    public static func sources() async throws -> [MeetingAudioSource] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.applications.filter {
            $0.processID != ProcessInfo.processInfo.processIdentifier && !$0.applicationName.isEmpty &&
            NSRunningApplication(processIdentifier: $0.processID)?.activationPolicy == .regular
        }
            .map { MeetingAudioSource(id: $0.processID, name: $0.applicationName) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func start(applicationID: Int32?, microphoneID: String?, includeMicrophone: Bool, microphoneChannel: Int? = nil) async throws {
        self.microphoneChannel = microphoneChannel
        if includeMicrophone {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { throw MeetingError.permission }
            if let microphoneID, !AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices.contains(where: { $0.uniqueID == microphoneID }) {
                throw RecordingPrerequisiteError("The selected microphone is unavailable. Choose a connected microphone in the sidebar.")
            }
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw MeetingError.noDisplay }
        let filter: SCContentFilter
        if let applicationID {
            guard let app = content.applications.first(where: { $0.processID == applicationID }) else { throw MeetingError.sourceGone }
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        } else {
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        }
        try Task.checkCancellation()
        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false; config.queueDepth = 3
        config.capturesAudio = true; config.sampleRate = 16_000; config.channelCount = 1
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = includeMicrophone
        config.microphoneCaptureDeviceID = microphoneID
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        if includeMicrophone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        self.stream = stream
        queue.sync { origin = CMClockGetTime(CMClockGetHostTimeClock()).seconds; accepting = true }
        do { try await stream.startCapture() }
        catch { queue.sync { accepting = false }; self.stream = nil; throw error }
    }
    /// Stop callbacks first, then drain their queue and flush the final samples.
    public func stop(reason: String? = nil) async throws -> MeetingDraft {
        var stopIssue = reason
        if let stream {
            do { try await stream.stopCapture() }
            catch { stopIssue = reason ?? "System capture stopped unexpectedly. The saved tail may be incomplete." }
        }
        stream = nil
        let finalIssue = stopIssue
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.accepting = false
                do {
                    try self.flushConverters()
                    continuation.resume(returning: try self.writer.finish(reason: finalIssue))
                }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.report("System audio capture was interrupted: " + error.localizedDescription) }
    }
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard accepting, !failed, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer), type == .audio || type == .microphone else { return }
        let track: MeetingTrack = type == .microphone ? .microphone : .system
        do {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard timestamp.isFinite else { throw MeetingError.invalidClock }
            guard CMClockGetTime(CMClockGetHostTimeClock()).seconds - timestamp < 5 else {
                throw RecordingPrerequisiteError("Audio capture fell behind. Recording stopped; the saved audio can be recovered from Meetings.")
            }
            let offset = timestamp - origin
            guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { throw MediaError.invalidAudio }
            let format = AVAudioFormat(cmAudioFormatDescription: description)
            if let previous = inputEnds[track], abs(offset - previous) > 0.02 || formats[track] != format {
                try flushConverter(track)
                converters[track] = nil; formats[track] = nil; outputOffsets[track] = offset
            }
            if outputOffsets[track] == nil { outputOffsets[track] = offset }
            inputEnds[track] = offset + Double(CMSampleBufferGetNumSamples(sampleBuffer)) / format.sampleRate
            let samples = try normalize(sampleBuffer, track: track)
            if !samples.isEmpty {
                try writer.append(samples, track: track, at: outputOffsets[track] ?? offset)
                outputOffsets[track, default: offset] += Double(samples.count) / 16_000
                lastReceived[track] = timestamp
                levels[track] = AudioLevel.meter(samples)
            }
            if timestamp - lastStatus > 0.2 {
                lastStatus = timestamp
                let microphoneFresh = timestamp - (lastReceived[.microphone] ?? 0) < 3
                let systemFresh = timestamp - (lastReceived[.system] ?? 0) < 3
                onStatus(MeetingCaptureStatus(duration: writer.duration, microphoneLevel: microphoneFresh ? levels[.microphone] ?? 0 : 0,
                    systemLevel: systemFresh ? levels[.system] ?? 0 : 0, microphoneReceived: microphoneFresh, systemReceived: systemFresh))
            }
        } catch { report(error.localizedDescription) }
    }
    func finishConversion(_ track: MeetingTrack) throws -> [Float] {
        guard let converter = converters[track] else { return [] }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        var result: [Float] = []
        for _ in 0..<8 {
            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in state.pointee = .endOfStream; return nil }
            if status == .error { throw error ?? MediaError.invalidAudio }
            result += UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))
            if status == .endOfStream || output.frameLength == 0 { break }
        }
        let remaining = max(0, Int((expectedFrames[track] ?? 0).rounded()) - (convertedFrames[track] ?? 0))
        guard result.count >= remaining else { throw MediaError.invalidAudio }
        // AVAudioConverter may append filter padding; retain only the source timeline.
        return Array(result.prefix(remaining))
    }
    private func flushConverter(_ track: MeetingTrack) throws {
        let values = try finishConversion(track)
        if !values.isEmpty {
            let offset = outputOffsets[track] ?? writer.end(of: track)
            try writer.append(values, track: track, at: offset)
            outputOffsets[track] = offset + Double(values.count) / 16_000
        }
    }
    private func flushConverters() throws { for track in MeetingTrack.allCases { try flushConverter(track) } }
    private func report(_ message: String) {
        guard !failed else { return }
        failed = true; onFailure(message)
    }
    func normalize(_ sample: CMSampleBuffer, track: MeetingTrack) throws -> [Float] {
        guard let description = CMSampleBufferGetFormatDescription(sample) else { throw MediaError.invalidAudio }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard format.sampleRate > 0, format.channelCount > 0, format.channelCount <= 8 else { throw MediaError.invalidAudio }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0, frames <= Int(format.sampleRate * 5),
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { throw MediaError.invalidAudio }
        input.frameLength = AVAudioFrameCount(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: input.mutableAudioBufferList) == noErr else { throw MediaError.invalidAudio }
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: input.frameLength)!
        mono.frameLength = input.frameLength
        let selected = track == .microphone ? microphoneChannel : nil
        if let selected, !(0..<Int(format.channelCount)).contains(selected) { throw MediaError.invalidAudio }
        let channels = selected.map { [$0] } ?? Array(0..<Int(format.channelCount))
        for frame in 0..<frames {
            var value: Float = 0
            for channel in channels {
                let bufferIndex = format.isInterleaved ? 0 : channel
                let sampleIndex = format.isInterleaved ? frame * Int(format.channelCount) + channel : frame
                switch format.commonFormat {
                case .pcmFormatFloat32: value += input.floatChannelData![bufferIndex][sampleIndex]
                case .pcmFormatInt16: value += Float(input.int16ChannelData![bufferIndex][sampleIndex]) / 32768
                case .pcmFormatInt32: value += Float(input.int32ChannelData![bufferIndex][sampleIndex]) / 2147483648
                case .pcmFormatFloat64:
                    let buffers = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
                    value += Float(buffers[bufferIndex].mData!.assumingMemoryBound(to: Double.self)[sampleIndex])
                default: throw MediaError.invalidAudio
                }
            }
            mono.floatChannelData![0][frame] = value / Float(channels.count)
        }
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        if formats[track] != format {
            if formats[track] != nil { try writer.note("\(track == .microphone ? "Microphone" : "App audio") format changed during recording.") }
            guard let converter = AVAudioConverter(from: monoFormat, to: outputFormat) else { throw MediaError.invalidAudio }
            converter.primeMethod = .none
            converters[track] = converter; formats[track] = format
            expectedFrames[track] = 0; convertedFrames[track] = 0
        }
        expectedFrames[track, default: 0] += Double(frames) * 16_000 / format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(frames) * 16_000 / format.sampleRate) + 32)
        let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)!
        var supplied = false
        var error: NSError?
        let status = converters[track]!.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return mono
        }
        if status == .error { throw error ?? MediaError.invalidAudio }
        convertedFrames[track, default: 0] += Int(output.frameLength)
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
