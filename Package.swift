// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingTranscriber",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MeetingTranscriber", targets: ["MeetingTranscriber"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingTranscriber",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/MeetingTranscriber",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
