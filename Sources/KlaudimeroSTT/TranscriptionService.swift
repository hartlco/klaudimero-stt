import Foundation
import Speech
import AVFoundation

enum TranscriptionError: Error, CustomStringConvertible {
    case localeNotSupported(String)
    case localeNotInstalled(String)
    case noSpeechDetected
    case audioFileError(String)

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
        }
    }
}

struct TranscriptionResult: Sendable {
    let text: String
    let locale: String?
}

struct TranscriptionService {
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

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw TranscriptionError.audioFileError("\(error)")
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Collect results concurrently while the analyzer processes the audio
        async let _ = try analyzer.analyzeSequence(from: audioFile)

        var segments: [String] = []
        for try await result in transcriber.results {
            if result.isFinal {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !text.isEmpty {
                    segments.append(text)
                }
            }
        }

        let fullText = segments.joined(separator: " ")
        guard !fullText.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }

        return TranscriptionResult(text: fullText, locale: locale.identifier)
    }
}
