import Foundation
import Speech
import AVFoundation

enum TranscriptionError: Error, CustomStringConvertible {
    case localeNotSupported(String)
    case localeNotInstalled(String)
    case noSpeechDetected
    case audioFileError(String)
    case analysisError(String)

    var description: String {
        switch self {
        case .localeNotSupported(let locale):
            return "Locale '\(locale)' is not supported by SpeechTranscriber"
        case .localeNotInstalled(let locale):
            return "Language model for '\(locale)' is not installed. POST /languages/download to install it."
        case .noSpeechDetected:
            return "No speech detected in audio"
        case .audioFileError(let reason):
            return "Failed to open audio file: \(reason)"
        case .analysisError(let reason):
            return "Analysis failed: \(reason)"
        }
    }
}

struct TranscriptionResult: Sendable {
    let text: String
    let locale: String?
}

enum TranscriptionService {
    static func transcribe(fileURL: URL, localeHint: Locale? = nil) async throws -> TranscriptionResult {
        let locale = localeHint ?? .autoupdatingCurrent

        if let hint = localeHint {
            let supported = await SpeechTranscriber.supportedLocales
            guard supported.contains(where: { $0.identifier == hint.identifier }) else {
                throw TranscriptionError.localeNotSupported(hint.identifier)
            }
            guard await LanguageManager.shared.isInstalled(hint) else {
                throw TranscriptionError.localeNotInstalled(hint.identifier)
            }
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw TranscriptionError.audioFileError("\(error)")
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let lastText = LastText()

        // Collect results concurrently — progressive results stream during analysis
        let resultTask = Task.detached {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !text.isEmpty {
                    lastText.set(text)
                }
            }
        }

        // Run analysis
        _ = try await analyzer.analyzeSequence(from: audioFile)

        // The progressive results stream doesn't terminate on its own after analysis.
        // Give it a moment for final results to flush, then cancel.
        try await Task.sleep(for: .milliseconds(500))
        resultTask.cancel()

        let fullText = lastText.get()
        guard !fullText.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }

        return TranscriptionResult(text: fullText, locale: locale.identifier)
    }
}

final class LastText: @unchecked Sendable {
    private let lock = NSLock()
    private var _text: String = ""

    func set(_ text: String) {
        lock.lock()
        _text = text
        lock.unlock()
    }

    func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return _text
    }
}
