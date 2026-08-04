// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "QuasimorphForMacOS",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "quasimorph-macos", targets: ["QuasimorphCLI"])
    ],
    targets: [
        .target(name: "QuasimorphBuilder"),
        .executableTarget(
            name: "QuasimorphCLI",
            dependencies: ["QuasimorphBuilder"]
        ),
        .testTarget(
            name: "QuasimorphBuilderTests",
            dependencies: ["QuasimorphBuilder"]
        )
    ]
)
