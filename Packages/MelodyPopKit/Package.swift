// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MelodyPopKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MelodyPopKit", targets: ["MelodyPopKit"])
    ],
    targets: [
        .target(name: "MelodyPopKit"),
        .testTarget(name: "MelodyPopKitTests", dependencies: ["MelodyPopKit"])
    ]
)
