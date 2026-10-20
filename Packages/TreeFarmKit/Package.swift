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
        // Fakes for the watch link (a scripted WatchConnectivity, an in-memory outbox store).
        // Test targets link it (TreeFarmKit's, the iPhone app's and the watch app's); apps never do.
        .library(name: "TreeFarmKitTestSupport", targets: ["TreeFarmKitTestSupport"]),
    ],
    targets: [
        .target(name: "TreeFarmKit"),
        .target(name: "TreeFarmKitTestSupport", dependencies: ["TreeFarmKit"]),
        .testTarget(name: "TreeFarmKitTests", dependencies: ["TreeFarmKit", "TreeFarmKitTestSupport"]),
    ]
)
