// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "InkrailCore", targets: ["InkrailCore"])]
var targets: [Target] = [
    .target(name: "InkrailCore"),
    .testTarget(name: "InkrailCoreTests", dependencies: ["InkrailCore"])
]
#if os(macOS)
products.append(.executable(name: "Inkrail", targets: ["Inkrail"]))
targets.append(.executableTarget(
    name: "Inkrail",
    dependencies: ["InkrailCore"],
    resources: [.process("Resources")],
    linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("AVFoundation")]
))
#endif

let package = Package(
    name: "Inkrail",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets,
    swiftLanguageVersions: [.v5]
)
