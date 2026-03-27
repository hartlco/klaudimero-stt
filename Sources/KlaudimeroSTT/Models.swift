import Vapor

struct TranscribeResponse: Content {
    let text: String
    let language: String?
    let durationSeconds: Double?
    let processingTimeMs: Int
}

struct HealthResponse: Content {
    let status: String
    let version: String
    let supportedLocales: [String]
    let installedLocales: [String]
}

struct LanguagesResponse: Content {
    let supported: [String]
    let installed: [String]
}

struct DownloadRequest: Content {
    let locale: String
}

struct DownloadResponse: Content {
    let locale: String
    let status: String
}

struct ErrorResponse: Content {
    let error: String
}
