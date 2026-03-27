import Vapor

let env = try Environment.detect()
let app = try Application(env)

defer { app.shutdown() }

let port = Int(Environment.get("STT_PORT") ?? "8586") ?? 8586
app.http.server.configuration.hostname = "0.0.0.0"
app.http.server.configuration.port = port

try routes(app)

app.logger.info("klaudimero-stt starting on port \(port)")
try app.run()
