// swift-tools-version:5.9
// Kök dizinden `swift run levha-lint <dosya.json>` çalışsın diye ince sarmalayıcı.
// Asıl paket: Tools/levha-lint
import PackageDescription

let package = Package(
    name: "Levha",
    dependencies: [.package(path: "Tools/levha-lint")],
    targets: []
)
