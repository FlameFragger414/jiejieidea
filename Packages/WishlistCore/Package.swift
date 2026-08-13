// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "WishlistCore",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(name: "WishlistCore", targets: ["WishlistCore"])
  ],
  targets: [
    .target(name: "WishlistCore"),
    .testTarget(name: "WishlistCoreTests", dependencies: ["WishlistCore"]),
  ],
  swiftLanguageModes: [.v6]
)
