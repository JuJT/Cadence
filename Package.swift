// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cadence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CadenceCore", targets: ["CadenceCore"])],
    targets: [
        .target(name: "CadenceCore", path: "Sources/CadenceCore"),
        .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore"], path: "Tests/CadenceCoreTests")
    ]
)
