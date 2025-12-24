// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TextPolish",
  platforms: [
    .macOS(.v13),
  ],
  products: [
    .executable(name: "TextPolish", targets: ["GrammarCorrection"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
  ],
  targets: [
    .executableTarget(
      name: "GrammarCorrection",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      path: "src",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("ApplicationServices"),
        .linkedFramework("Security"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
    .testTarget(
      name: "GrammarCorrectionTests",
      dependencies: ["GrammarCorrection"],
      path: "Tests/GrammarCorrectionTests"
    ),
  ]
)
