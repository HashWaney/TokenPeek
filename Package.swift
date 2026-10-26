// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenPeek",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TokenPeek", targets: ["TokenPeek"])
    ],
    targets: [
        .executableTarget(name: "TokenPeek"),
        .testTarget(name: "TokenPeekTests", dependencies: ["TokenPeek"])
    ],
    swiftLanguageModes: [.v5]
)
