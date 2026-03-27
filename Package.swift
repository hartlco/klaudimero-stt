// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KlaudimeroSTT",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
    ],
    targets: [
        .executableTarget(
            name: "KlaudimeroSTT",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/KlaudimeroSTT"
        ),
        .executableTarget(
            name: "TranscribeWorker",
            path: "Sources/TranscribeWorker"
        ),
    ]
)
