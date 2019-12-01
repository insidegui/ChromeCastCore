// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "ChromeCastCore",
    platforms: [
        .macOS(.v10_12),
    ],
    products: [
        .library(name: "ChromeCastCore", targets: ["ChromeCastCore", "CASTV2PlatformReader"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMajor(from: "1.7.0"))
    ],
    targets: [
        .target(
            name: "ChromeCastCore",
            dependencies: ["SwiftProtobuf", "CASTV2PlatformReader"],
            path: "ChromeCastCore",
            exclude: ["PlatformReader.swift"]
        ),
        .target(name: "CASTV2PlatformReader", path: "CASTV2PlatformReader")
    ],
    swiftLanguageVersions: [.v4]
)
