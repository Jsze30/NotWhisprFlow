import AVFoundation
import Foundation

/// Plays a short click sample with optional pitch shift. One engine, two
/// player nodes so press and release can overlap without cutting each other off.
final class ClickPlayer {
    private let engine = AVAudioEngine()
    private let pressNode = AVAudioPlayerNode()
    private let releaseNode = AVAudioPlayerNode()
    private let pressPitch = AVAudioUnitTimePitch()
    private let releasePitch = AVAudioUnitTimePitch()
    private var buffer: AVAudioPCMBuffer?

    init?(url: URL, pressVolume: Float, releaseVolume: Float,
          pressPitchCents: Float, releasePitchCents: Float) {
        guard let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do { try file.read(into: buf) } catch { return nil }
        buffer = buf

        pressNode.volume = pressVolume
        releaseNode.volume = releaseVolume
        pressPitch.pitch = pressPitchCents      // 100 cents = 1 semitone
        releasePitch.pitch = releasePitchCents

        engine.attach(pressNode)
        engine.attach(releaseNode)
        engine.attach(pressPitch)
        engine.attach(releasePitch)

        let format = file.processingFormat
        engine.connect(pressNode, to: pressPitch, format: format)
        engine.connect(pressPitch, to: engine.mainMixerNode, format: format)
        engine.connect(releaseNode, to: releasePitch, format: format)
        engine.connect(releasePitch, to: engine.mainMixerNode, format: format)

        do { try engine.start() } catch { return nil }
    }

    func playPress() { schedule(on: pressNode) }
    func playRelease() { schedule(on: releaseNode) }

    private func schedule(on node: AVAudioPlayerNode) {
        guard let buffer else { return }
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        node.play()
    }
}
