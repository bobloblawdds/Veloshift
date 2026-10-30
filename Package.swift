// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Veloshift", platforms: [.macOS(.v14)], products: [.executable(name: "Veloshift", targets: ["Velox"])], targets: [.target(name: "VeloxCore"), .executableTarget(name: "Velox", dependencies: ["VeloxCore"]), .executableTarget(name: "VeloxChecks", dependencies: ["VeloxCore"], path: "Tests/VeloxChecks")])
