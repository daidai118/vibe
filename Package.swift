// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vibe",
    platforms: [
        // Process Tap API(单应用音频接管)需要 macOS 14.4+
        .macOS("14.4")
    ],
    targets: [
        .executableTarget(
            name: "Vibe",
            path: "Sources/Vibe"
        )
    ]
)
