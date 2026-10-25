// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CursorBeacon",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "CursorBeacon", path: "Sources/CursorBeacon")
    ]
)
