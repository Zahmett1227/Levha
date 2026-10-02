// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "levha-lint",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "levha-lint", targets: ["levha-lint"]),
        .library(name: "LevhaSema", targets: ["LevhaSema"]),
    ],
    targets: [
        .target(name: "LevhaSema"),
        .executableTarget(name: "levha-lint", dependencies: ["LevhaSema"]),
        .testTarget(name: "LevhaSemaTests", dependencies: ["LevhaSema"]),
    ]
)
