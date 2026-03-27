import Foundation
import Speech

actor LanguageManager {
    static let shared = LanguageManager()

    func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    func installedLocales() async -> [Locale] {
        await SpeechTranscriber.installedLocales
    }

    func downloadLocale(_ locale: Locale) async throws -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier == locale.identifier }) {
            return true
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) else {
            return true
        }

        try await request.downloadAndInstall()
        return true
    }

    func isInstalled(_ locale: Locale) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains(where: { $0.identifier == locale.identifier })
    }
}
