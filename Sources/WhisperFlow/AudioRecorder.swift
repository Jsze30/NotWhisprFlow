import AVFoundation
import Foundation

final class AudioRecorder {
    /// Called on main with a normalized 0...1 level (perceptual sqrt curve) ~every audio buffer.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var pcmAccumulator = Data()
    private let targetSampleRate: Double = 16_000
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat!
    private let queue = DispatchQueue(label: "whisperflow.recorder")

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )
    }

    func start() throws {
        pcmAccumulator.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, inputFormat: inputFormat)
        }
        engine.prepare()
        try engine.start()
    }

    func stop(completion: @escaping (Data?) -> Void) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        queue.async { [weak self] in
            guard let self else { completion(nil); return }
            let wav = Self.wrapInWavHeader(pcm: self.pcmAccumulator, sampleRate: Int(self.targetSampleRate))
            completion(wav)
        }
    }

    private func process(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = targetSampleRate / inputFormat.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else { return }

        var error: NSError?
        var supplied = false
        converter.convert(to: outBuffer, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil { return }

        let frameCount = Int(outBuffer.frameLength)
        guard frameCount > 0, let channelData = outBuffer.int16ChannelData else { return }
        let byteCount = frameCount * MemoryLayout<Int16>.size
        let bytes = Data(bytes: channelData[0], count: byteCount)
        queue.async { [weak self] in
            self?.pcmAccumulator.append(bytes)
        }

        var peak: Int32 = 0
        let samples = channelData[0]
        for i in 0..<frameCount {
            let v = Int32(samples[i])
            let a = v < 0 ? -v : v
            if a > peak { peak = a }
        }
        let normalized = Float(peak) / 32767.0
        let level = sqrtf(max(0, min(1, normalized)))
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(level)
        }
    }

    /// Wraps raw 16-bit mono PCM in a minimal WAV container.
    private static func wrapInWavHeader(pcm: Data, sampleRate: Int) -> Data {
        var header = Data()
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm.count)
        let totalSize = 36 + dataSize

        header.append("RIFF".data(using: .ascii)!)
        header.append(uint32: totalSize)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(uint32: 16)              // PCM chunk size
        header.append(uint16: 1)               // PCM format
        header.append(uint16: channels)
        header.append(uint32: UInt32(sampleRate))
        header.append(uint32: byteRate)
        header.append(uint16: blockAlign)
        header.append(uint16: bitsPerSample)
        header.append("data".data(using: .ascii)!)
        header.append(uint32: dataSize)
        header.append(pcm)
        return header
    }
}

private extension Data {
    mutating func append(uint32 value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    mutating func append(uint16 value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
