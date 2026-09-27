// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "VoiceInput", targets: ["VoiceInput"])],
    dependencies: [.package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.0.0")],
    targets: [
        .target(name: "VoiceInputCore"),
        .executableTarget(name: "VoiceInput", dependencies: ["VoiceInputCore", .product(name: "WhisperKit", package: "argmax-oss-swift")])
    ]
)
