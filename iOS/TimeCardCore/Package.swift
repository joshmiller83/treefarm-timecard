// swift-tools-version: 6.0
// TimeCardCore is everything in the iPhone app that isn't UI: the local store,
// the sync engine, the API client and sign-in. It builds for macOS too, so all of
// it is tested with `swift test` and no simulator.
import PackageDescription

let package = Package(
    name: "TimeCardCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TimeCardCore", targets: ["TimeCardCore"]),
    ],
    dependencies: [
        .package(path: "../../Packages/TreeFarmKit"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "TimeCardCore",
            dependencies: [
                .product(name: "TreeFarmKit", package: "TreeFarmKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "TimeCardCoreTests", dependencies: ["TimeCardCore"]),
    ]
)
