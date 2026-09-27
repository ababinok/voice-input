import Foundation
import WhisperKit

actor SpeechEngine {
    static let model = "openai_whisper-large-v3-v20240930_626MB"
    // Whisper uses this as a style example, not as an instruction or output prefix.
    private static let punctuationExample = "Добрый день! Как дела? Если будет время, позвони мне, пожалуйста. Всё готово: можно начинать."
    private var pipe: WhisperKit?
    static var storage: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceInput", isDirectory: true)
    }
    func prepare(progress: @escaping @Sendable (String, Double?) -> Void) async throws {
        if pipe != nil { return }
        let base = Self.storage
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let marker = base.appendingPathComponent("model-path.txt")
        let folder: URL
        if let saved = try? String(contentsOf: marker, encoding: .utf8), FileManager.default.fileExists(atPath: saved) {
            folder = URL(fileURLWithPath: saved)
        } else {
            progress("Скачиваю модель…", 0)
            folder = try await WhisperKit.download(variant: Self.model, downloadBase: base) { status in
                progress("Скачиваю модель…", status.fractionCompleted)
            }
        }
        progress("Подготавливаю модель… Первый запуск может занять несколько минут.", nil)
        let loaded = try await WhisperKit(WhisperKitConfig(
            modelFolder: folder.path, tokenizerFolder: base,
            verbose: false, prewarm: true, load: true, download: false
        ))
        try folder.path.write(to: marker, atomically: true, encoding: .utf8)
        pipe = loaded
    }
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let pipe else { throw AppError.message("Модель ещё не готова.") }
        try Task.checkCancellation()
        guard let tokenizer = pipe.tokenizer else {
            throw AppError.message("Словарь модели ещё не готов.")
        }
        let promptTokens = tokenizer.encode(text: " " + Self.punctuationExample).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        // WhisperKit 1.0 samples during prompt prefill. Keep EOS suppressed until
        // the first audio token, otherwise a complete example can end decoding early.
        pipe.textDecoder.logitsFilters = [SuppressBlankFilter(
            specialTokens: tokenizer.specialTokens, // start-of-previous + example + start-of-transcript/language/task/timestamp.
            sampleBegin: promptTokens.count + 5
        )]
        defer { pipe.textDecoder.logitsFilters = [] }
        let options = DecodingOptions(language: "ru", temperatureFallbackCount: 2,
                                      detectLanguage: false, skipSpecialTokens: true,
                                      promptTokens: promptTokens,
                                      // WhisperKit 1.0 checks this at the first context token,
                                      // before speech decoding; it can reject a valid style prompt.
                                      firstTokenLogProbThreshold: nil,
                                      concurrentWorkerCount: 1, chunkingStrategy: .vad)
        let result = try await pipe.transcribe(audioArray: samples, decodeOptions: options, callback: { _ in
            !Task.isCancelled
        })
        try Task.checkCancellation()
        return result.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
