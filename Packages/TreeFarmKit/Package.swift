// swift-tools-version: 6.0
// TreeFarmKit holds everything the app and the server agree on: the data model,
// the time and tree rules, and the sync protocol. It has no dependencies and
// builds on macOS, iOS and Linux so the rules are tested once and used everywhere.
import PackageDescription

let package = Package(
    name: "TreeFarmKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "TreeFarmKit", targets: ["TreeFarmKit"]),
    ],
    targets: [
        .target(name: "TreeFarmKit"),
        .testTarget(name: "TreeFarmKitTests", dependencies: ["TreeFarmKit"]),
    ]
)
