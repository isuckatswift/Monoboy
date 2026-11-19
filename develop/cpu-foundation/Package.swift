
 // swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Monoboy",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "MonoboyCore",
            targets: ["MonoboyCore"]
        )
    ],
    targets: [
        .target(
            name: "MonoboyCore"
        ),
        .testTarget(
            name: "MonoboyCoreTests",
            dependencies: ["MonoboyCore"]
        )
    ]
)
