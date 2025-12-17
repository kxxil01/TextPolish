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
  targets: [
    .executableTarget(
      name: "GrammarCorrection",
      path: "src",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("ApplicationServices"),
        .linkedFramework("Security"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
  ]
)
