// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillPolicy",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SkillPolicy", targets: ["SkillPolicy"]),
        .library(name: "SkillPolicyUI", targets: ["SkillPolicyUI"])
    ],
    targets: [
        .target(name: "SkillPolicy"),
        .target(name: "SkillPolicyUI", dependencies: ["SkillPolicy"]),
        .testTarget(name: "SkillPolicyTests", dependencies: ["SkillPolicy"])
    ]
)
