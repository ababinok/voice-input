import AVFoundation
import Foundation

// The audio callback never touches MainActor/UI state.
final class SampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var level: Float = 0
    private var peak: Float = 0
    private var active = true
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        let values = Array(UnsafeBufferPointer(start: channel, count: count))
        let rms = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 } / Float(count))
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        // Bound memory to 30 minutes. Controller stops at this limit.
        if samples.count + count <= 16_000 * 60 * 30 { samples.append(contentsOf: values) }
        level = rms; peak = max(peak, rms)
    }
    func meter() -> Float { lock.lock(); defer { lock.unlock() }; return level }
    func take() -> (samples: [Float], peak: Float) {
        lock.lock(); defer { lock.unlock() }
        active = false
        let result = (samples, peak)
        samples = []; level = 0; peak = 0
        return result
    }
}

@MainActor
final class Recorder {
    private var engine: AVAudioEngine?
    private var collector: SampleCollector?
    private var observer: NSObjectProtocol?
    var onDeviceChange: (() -> Void)?
    var level: Float { collector?.meter() ?? 0 }

    func start() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw AppError.message("Микрофон недоступен. Проверьте устройство ввода в настройках звука.")
        }
        let collector = SampleCollector()
        self.collector = collector
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / inputFormat.sampleRate) + 32)
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if error == nil { collector.append(converted) }
        }
        do { try engine.start() }
        catch { input.removeTap(onBus: 0); self.collector = nil; throw error }
        self.engine = engine
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onDeviceChange?() }
        }
    }
    func stop() -> (samples: [Float], peak: Float) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        let result = collector?.take() ?? ([], 0)
        collector = nil
        return result
    }
}
