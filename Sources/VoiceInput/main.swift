import AppKit
import WhisperKit

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--benchmark-audio" {
    let audioPath = CommandLine.arguments[2]
    Task {
        do {
            let engine = SpeechEngine()
            let started = Date()
            try await engine.prepare { message, _ in fputs(message + "\n", stderr) }
            let prepared = Date()
            let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioPath)
            let inference = Date()
            let text = try await engine.transcribe(audio)
            let report: [String: Any] = ["audioSeconds": Double(audio.count) / 16000,
                                       "preparationSeconds": prepared.timeIntervalSince(started),
                                       "transcriptionSeconds": Date().timeIntervalSince(inference), "text": text]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            exit(0)
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    dispatchMain()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
