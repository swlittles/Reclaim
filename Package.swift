// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Reclaim", platforms: [.macOS(.v13)],
    products: [.library(name: "ReclaimCore", targets: ["ReclaimCore"]), .executable(name: "Reclaim", targets: ["Reclaim"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [.target(name: "ReclaimCore"),
              .executableTarget(name: "Reclaim", dependencies: ["ReclaimCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
              .executableTarget(name: "ReclaimCoreTests", dependencies: ["ReclaimCore"], path: "Tests/ReclaimCoreTests")])
