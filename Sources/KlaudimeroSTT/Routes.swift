import Vapor
import Foundation

func routes(_ app: Application) throws {
    app.get("health") { req async throws -> HealthResponse in
        let supported = await LanguageManager.shared.supportedLocales()
        let installed = await LanguageManager.shared.installedLocales()
        return HealthResponse(
            status: "ok",
            version: "1.0.0",
            supportedLocales: supported.map(\.identifier).sorted(),
            installedLocales: installed.map(\.identifier).sorted()
        )
    }

    app.get("languages") { req async throws -> LanguagesResponse in
        let supported = await LanguageManager.shared.supportedLocales()
        let installed = await LanguageManager.shared.installedLocales()
        return LanguagesResponse(
            supported: supported.map(\.identifier).sorted(),
            installed: installed.map(\.identifier).sorted()
        )
    }

    app.post("languages", "download") { req async throws -> DownloadResponse in
        let body = try req.content.decode(DownloadRequest.self)
        let locale = Locale(identifier: body.locale)

        let supported = await LanguageManager.shared.supportedLocales()
        guard supported.contains(where: { $0.identifier == locale.identifier }) else {
            throw Abort(.badRequest, reason: "Locale '\(body.locale)' is not supported")
        }

        do {
            _ = try await LanguageManager.shared.downloadLocale(locale)
            return DownloadResponse(locale: body.locale, status: "installed")
        } catch {
            throw Abort(.internalServerError, reason: "Download failed: \(error)")
        }
    }

    app.on(.POST, "transcribe", body: .collect(maxSize: "50mb")) { req async throws -> TranscribeResponse in
        let startTime = DispatchTime.now()

        // Extract file from multipart upload
        guard let file = try? req.content.decode(FileUpload.self).file else {
            throw Abort(.badRequest, reason: "No file provided. Send multipart/form-data with a 'file' field.")
        }

        // Optional language hint
        let languageHint: Locale?
        if let lang = try? req.content.decode(LanguageHintUpload.self).language, !lang.isEmpty {
            languageHint = Locale(identifier: lang)
        } else {
            languageHint = nil
        }

        // Write uploaded file to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("klaudimero-stt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let filename = file.filename.isEmpty ? "audio.oga" : file.filename
        let inputPath = tempDir.appendingPathComponent(filename)
        try Data(buffer: file.data).write(to: inputPath)

        // Convert to compatible format if needed
        let compatiblePath: URL
        do {
            compatiblePath = try AudioConverter.ensureCompatible(inputPath)
        } catch {
            throw Abort(.badRequest, reason: "\(error)")
        }

        // Transcribe
        let result: TranscriptionResult
        do {
            result = try await TranscriptionService.transcribe(
                fileURL: compatiblePath,
                localeHint: languageHint
            )
        } catch let error as TranscriptionError {
            switch error {
            case .noSpeechDetected:
                throw Abort(.unprocessableEntity, reason: error.description)
            case .localeNotInstalled:
                throw Abort(.serviceUnavailable, reason: error.description)
            case .localeNotSupported:
                throw Abort(.badRequest, reason: error.description)
            case .audioFileError:
                throw Abort(.badRequest, reason: error.description)
            case .analysisError:
                throw Abort(.internalServerError, reason: error.description)
            }
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
        let elapsedMs = Int(elapsed / 1_000_000)

        return TranscribeResponse(
            text: result.text,
            language: result.locale,
            durationSeconds: nil,
            processingTimeMs: elapsedMs
        )
    }
}

// Multipart decode helpers
private struct FileUpload: Content {
    let file: File
}

private struct LanguageHintUpload: Content {
    let language: String?
}
