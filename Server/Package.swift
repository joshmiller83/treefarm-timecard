// swift-tools-version: 6.0
// The Tree Farm Time Card server: Vapor 4 + Fluent on SQLite. It depends on
// TreeFarmKit for the data model and sync protocol, so the app and the server
// can't drift apart.
import PackageDescription

let package = Package(
    name: "TreeFarmServer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Run", targets: ["Run"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.2"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.9.0"),
        .package(path: "../Packages/TreeFarmKit"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "TreeFarmKit", package: "TreeFarmKit"),
            ]
        ),
        .executableTarget(name: "Run", dependencies: [.target(name: "App")]),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
    ]
)
