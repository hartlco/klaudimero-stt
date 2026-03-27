import Foundation
import Vapor

// SpeechAnalyzer requires the main thread's RunLoop for Core Audio callbacks.
// Start Vapor on a background thread, keep main free with dispatchMain().

let env = try Environment.detect()
let app = try Application(env)

let port = Int(Environment.get("STT_PORT") ?? "8586") ?? 8586
app.http.server.configuration.hostname = "0.0.0.0"
app.http.server.configuration.port = port

try routes(app)

app.logger.info("klaudimero-stt starting on port \(port)")

DispatchQueue.global().async {
    do {
        try app.run()
    } catch {
        fatalError("Vapor server failed: \(error)")
    }
}

dispatchMain()
