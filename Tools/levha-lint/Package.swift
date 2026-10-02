// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "levha-lint",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "levha-lint", targets: ["levha-lint"]),
        .library(name: "LevhaSema", targets: ["LevhaSema"]),
        .library(name: "LevhaCekirdek", targets: ["LevhaCekirdek"]),
    ],
    targets: [
        // Şema modelleri + lint kuralları (uygulama da derler).
        .target(name: "LevhaSema"),
        // Saf fonksiyonlar: zamanlayıcı, tohumlu rastgele (uygulama da derler).
        .target(name: "LevhaCekirdek"),
        .executableTarget(name: "levha-lint", dependencies: ["LevhaSema"]),
        .testTarget(name: "LevhaSemaTests", dependencies: ["LevhaSema"]),
        .testTarget(name: "LevhaCekirdekTests", dependencies: ["LevhaCekirdek"]),
    ]
)
