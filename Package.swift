// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "OverviewCore", targets: ["OverviewCore"]),
]

var targets: [Target] = [
    // Scanning, tree model and chart geometry. Foundation only, so it also
    // builds and tests on Linux.
    .target(name: "OverviewCore"),
    .testTarget(name: "OverviewCoreTests", dependencies: ["OverviewCore"]),
]

#if os(macOS)
products.append(.executable(name: "Overview", targets: ["Overview"]))
targets.append(.executableTarget(name: "Overview", dependencies: ["OverviewCore"]))
#endif

let package = Package(
    name: "Overview",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
