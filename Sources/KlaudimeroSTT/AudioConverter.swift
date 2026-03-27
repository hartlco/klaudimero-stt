import Foundation

enum AudioConversionError: Error, CustomStringConvertible {
    case ffmpegNotFound
    case conversionFailed(String)

    var description: String {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found. Install with: brew install ffmpeg"
        case .conversionFailed(let reason):
            return "Audio conversion failed: \(reason)"
        }
    }
}

struct AudioConverter {
    private static let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
    private static let ffmpegFallbackPath = "/usr/local/bin/ffmpeg"

    /// File extensions that Core Audio can handle natively (no conversion needed).
    private static let nativeExtensions: Set<String> = [
        "wav", "aiff", "aif", "caf", "m4a", "mp3", "aac", "mp4", "mov"
    ]

    /// Returns the path to ffmpeg, or nil if not found.
    private static func findFFmpeg() -> String? {
        if FileManager.default.fileExists(atPath: ffmpegPath) {
            return ffmpegPath
        }
        if FileManager.default.fileExists(atPath: ffmpegFallbackPath) {
            return ffmpegFallbackPath
        }
        return nil
    }

    /// Converts an audio file to WAV format suitable for SpeechAnalyzer.
    /// Returns the original path if no conversion is needed, or a new temp path if converted.
    static func ensureCompatible(_ inputPath: URL) throws -> URL {
        let ext = inputPath.pathExtension.lowercased()

        // OGA/OGG (Telegram voice) and other non-native formats need conversion
        if nativeExtensions.contains(ext) {
            return inputPath
        }

        guard let ffmpeg = findFFmpeg() else {
            throw AudioConversionError.ffmpegNotFound
        }

        let outputPath = inputPath
            .deletingPathExtension()
            .appendingPathExtension("wav")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-i", inputPath.path,
            "-ar", "16000",     // 16kHz sample rate (good for speech)
            "-ac", "1",         // mono
            "-f", "wav",
            "-y",               // overwrite
            outputPath.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown error"
            throw AudioConversionError.conversionFailed(stderr)
        }

        return outputPath
    }
}
