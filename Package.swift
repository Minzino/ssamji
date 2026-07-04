// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ssamji",
    platforms: [.macOS("15.4")],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Ssamji",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/Ssamji",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
