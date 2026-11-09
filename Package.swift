// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MornLiveUtil",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "MornLiveUtil", swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")])]
)
