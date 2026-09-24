// swift-tools-version:5.9
import PackageDescription

// The app's data layer as a standalone package. The Xcode app target compiles
// these same files directly; this manifest exists so the logic can be built and
// tested without Xcode — including on Linux CI.
let package = Package(
    name: "GymLoggerCore",
    products: [
        .library(name: "GymLoggerCore", targets: ["GymLoggerCore"])
    ],
    targets: [
        .target(name: "GymLoggerCore", path: "GymLogger/Core"),
        .testTarget(name: "GymLoggerCoreTests", dependencies: ["GymLoggerCore"], path: "Tests/CoreTests"),
    ]
)
