// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeCell",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FreeCellCore", targets: ["FreeCellCore"]),
               .executable(name: "FreeCell", targets: ["FreeCellApp"])],
    targets: [
        .target(name: "FreeCellCore"),
        .target(name: "FreeCellPresentation", dependencies: ["FreeCellCore"]),
        .executableTarget(name: "FreeCellApp", dependencies: ["FreeCellCore", "FreeCellPresentation"],
                          resources: [.copy("Resources/Cards"), .copy("Resources/AppIcon.png"), .copy("Resources/Icon-Attribution.txt")]),
        .executableTarget(name: "FreeCellChecks", dependencies: ["FreeCellCore", "FreeCellPresentation"], path: "Tests/FreeCellCoreTests")
    ]
)
