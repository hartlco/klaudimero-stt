import Foundation
import Speech
import AVFoundation

func runTranscription() async {
    guard CommandLine.arguments.count >= 2 else {
        fputs("Usage: transcribe-worker <audio-file> [locale]\n", stderr)
        fflush(stderr)
        exit(1)
    }

    let filePath = CommandLine.arguments[1]
    let localeId = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : nil
    let locale = localeId.map { Locale(identifier: $0) } ?? .autoupdatingCurrent

    let fileURL = URL(fileURLWithPath: filePath)

    if let localeId = localeId {
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier == locale.identifier }) else {
            fputs("Locale '\(localeId)' not supported\n", stderr)
            fflush(stderr)
            exit(2)
        }

        let installed = await SpeechTranscriber.installedLocales
        guard installed.contains(where: { $0.identifier == locale.identifier }) else {
            fputs("Locale '\(localeId)' not installed\n", stderr)
            fflush(stderr)
            exit(3)
        }
    }

    do {
        let audioFile = try AVAudioFile(forReading: fileURL)

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let lastText = LastText()

        // Collect results concurrently
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

        // Give results a moment to flush, then cancel the stream
        // (progressiveTranscription results stream may not terminate on its own)
        try await Task.sleep(for: .milliseconds(500))
        resultTask.cancel()

        let text = lastText.get()
        if text.isEmpty {
            fputs("no speech detected\n", stderr)
            fflush(stderr)
            exit(4)
        }

        print(text)
        fflush(stdout)
        exit(0)
    } catch {
        fputs("Analysis error: \(error)\n", stderr)
        fflush(stderr)
        exit(5)
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

fputs("Worker starting...\n", stderr)
fflush(stderr)

Task { @MainActor in
    await runTranscription()
}
RunLoop.main.run()
