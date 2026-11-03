// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PennsKit",
    platforms: [.macOS(.v26), .iOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "PennsKit", targets: ["PennsKit"]),
    ],
    targets: [
        .target(name: "PennsKit"),
        .testTarget(name: "PennsKitTests", dependencies: ["PennsKit"]),
    ]
)
