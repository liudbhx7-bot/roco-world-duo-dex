import AVFoundation
import XCTest
@testable import RocoDex

@MainActor
final class DexNarratorTests: XCTestCase {
    func testEveryFormHasItsOwnOfflineRecording() throws {
        let entries = try Catalog().entries
        let locations = try entries.map { entry in
            try XCTUnwrap(DexNarrator.trackURL(for: entry), entry.name)
        }
        XCTAssertEqual(Set(locations).count, entries.count)
        for (entry, url) in zip(entries, locations) {
            let properties = try url.resourceValues(forKeys: [.fileSizeKey])
            XCTAssertGreaterThan(properties.fileSize ?? 0, 2_000, entry.name)
        }
    }

    func testRecordingsContainSpeech() throws {
        let entries = try Catalog().entries
        let samples = entries.enumerated().filter { $0.offset % 97 == 0 || $0.element.id == 8 || $0.offset == entries.count - 1 }
        for (_, entry) in samples {
            let url = try XCTUnwrap(DexNarrator.trackURL(for: entry))
            let track = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let count = AVAudioFrameCount(track.length)
            let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: track.processingFormat, frameCapacity: count))
            try track.read(into: pcm)
            let samples = try XCTUnwrap(pcm.floatChannelData)[0]
            let lead = Int(track.processingFormat.sampleRate * 0.05)
            XCTAssertGreaterThan(Int(pcm.frameLength), lead)
            let backgroundPeak = (0..<lead).reduce(Float.zero) { max($0, abs(samples[$1])) }
            let speechSamples = (lead..<Int(pcm.frameLength)).filter { abs(samples[$0]) > 0.035 }.count
            XCTAssertLessThan(backgroundPeak, 0.004, entry.number)
            XCTAssertGreaterThan(speechSamples, Int(track.processingFormat.sampleRate), entry.number)
        }
    }

    func testNarrationPlaysToCompletion() async throws {
        let water = try XCTUnwrap(Catalog().entries.first { $0.id == 8 })
        let narrator = DexNarrator()
        narrator.speak(water)
        XCTAssertTrue(narrator.isSpeaking)
        let clock = ContinuousClock()
        let start = clock.now
        var maxPeak: Float = -160
        var audibleIntervals = 0
        var route = ""
        var volume: Float = -1
        while narrator.isSpeaking && start.duration(to: clock.now) < .seconds(30) {
            try await Task.sleep(for: .milliseconds(80))
            if let levels = narrator.playbackLevels() {
                if route.isEmpty {
                    let audio = AVAudioSession.sharedInstance()
                    route = audio.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
                    volume = audio.outputVolume
                }
                maxPeak = max(maxPeak, levels.peak)
                if levels.average > -40 { audibleIntervals += 1 }
            }
        }
        print("RocoDex AUDIO_CHECK track=008.m4a zh voice=zf_001 route=\(route) mediaVolume=\(volume) peakDBFS=\(maxPeak) audibleIntervals=\(audibleIntervals)")
        XCTAssertNil(narrator.unavailableMessage)
        XCTAssertFalse(narrator.isSpeaking)
        XCTAssertFalse(route.isEmpty)
        XCTAssertGreaterThan(maxPeak, -30)
        XCTAssertGreaterThan(audibleIntervals, 12)
        XCTAssertGreaterThan(start.duration(to: clock.now), .seconds(3))
    }

    func testReplacingAndStoppingNarration() async throws {
        let entries = try Catalog().entries
        let narrator = DexNarrator()
        narrator.speak(entries[0])
        narrator.speak(entries[1])
        XCTAssertTrue(narrator.isSpeaking)
        narrator.stop()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(narrator.isSpeaking)
        XCTAssertNil(narrator.unavailableMessage)
        XCTAssertNil(narrator.playbackLevels())
    }
}
