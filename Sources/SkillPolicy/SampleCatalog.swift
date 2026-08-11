/// A worked example: Apple's seven Xcode 27 skills, plus the house and repo
/// skills a team would realistically layer on top of them.
///
/// The rule text is paraphrased and deliberately opinionated — the point of
/// the catalog is to make the *collisions* concrete, not to reproduce Apple's
/// wording. Capability requirements follow the real split: knowledge-driven
/// skills only read and edit source, tool-driven ones reach for Xcode.
public enum SampleCatalog {

    // MARK: - Vendor: shipped in Xcode 27, exported to ~/.agents/skills

    public static let swiftUIBestPractices = AgentSkill(
        id: "apple.swiftui-best-practices",
        name: "SwiftUI best practices",
        origin: .vendor,
        version: "27.0",
        activationKeywords: ["swiftui", "view model", "state"],
        requiredCapabilities: [.readSource, .editSource],
        rules: [
            SkillRule(
                subject: "swiftui.state-ownership",
                stance: .require,
                directive: "Model view state with @Observable classes owned by the view."
            ),
            SkillRule(
                subject: "swiftui.view-decomposition",
                stance: .prefer,
                directive: "Extract subviews once a body exceeds roughly one screen."
            )
        ]
    )

    public static let swiftUIAPIAdoption = AgentSkill(
        id: "apple.swiftui-api-adoption",
        name: "SwiftUI API adoption guide (2027)",
        origin: .vendor,
        version: "27.0",
        activationKeywords: ["api adoption", "ios 27", "deprecated"],
        requiredCapabilities: [.readSource, .editSource],
        rules: [
            SkillRule(
                subject: "swiftui.navigation",
                stance: .require,
                directive: "Replace NavigationView with NavigationStack and value-based destinations."
            )
        ]
    )

    public static let uiKitModernization = AgentSkill(
        id: "apple.uikit-modernization",
        name: "UIKit modernisation",
        origin: .vendor,
        version: "27.0",
        activationKeywords: ["uikit", "view controller", "storyboard"],
        requiredCapabilities: [.readSource, .editSource],
        rules: [
            SkillRule(
                subject: "uikit.layout",
                stance: .require,
                directive: "Drive layout from Auto Layout anchors, never from frame math in layoutSubviews."
            )
        ]
    )

    public static let xctestMigration = AgentSkill(
        id: "apple.xctest-to-swift-testing",
        name: "XCTest to Swift Testing migration",
        origin: .vendor,
        version: "27.0",
        activationKeywords: ["xctest", "swift testing", "test suite"],
        requiredCapabilities: [.readSource, .editSource],
        rules: [
            SkillRule(
                subject: "testing.framework",
                stance: .require,
                directive: "Port XCTestCase subclasses to @Test functions with #expect."
            )
        ]
    )

    public static let deviceInteractionTesting = AgentSkill(
        id: "apple.device-interaction-testing",
        name: "Device interaction testing",
        origin: .vendor,
        version: "27.0",
        activationKeywords: ["device interaction", "ui test", "simulator"],
        requiredCapabilities: [.readSource, .runDeviceInteractionTests],
        rules: [
            SkillRule(
                subject: "testing.ui-verification",
                stance: .require,
                directive: "Assert against accessibility identifiers, never against on-screen strings."
            )
        ]
    )

    public static let cBoundsSafety = AgentSkill(
        id: "apple.c-bounds-safety",
        name: "C bounds safety",
        origin: .vendor,
        version: "27.0",
        activationKeywords: ["bounds safety", "unsafe pointer", "c interop"],
        requiredCapabilities: [.readSource, .editSource],
        rules: [
            SkillRule(
                subject: "interop.pointer-safety",
                stance: .require,
                directive: "Carry an explicit count with every imported pointer; annotate with __counted_by."
            )
        ]
    )

    public static let securitySettingsAudit = AgentSkill(
        id: "apple.xcode-security-audit",
        name: "Xcode security settings audit",
        origin: .vendor,
        version: "27.0",
        activationKeywords: ["security audit", "build settings", "hardened"],
        requiredCapabilities: [.readBuildSettings, .writeBuildSettings],
        rules: [
            SkillRule(
                subject: "build.hardening",
                stance: .require,
                directive: "Enable stack protectors and library validation on every shipping target."
            )
        ]
    )

    // MARK: - House and repo: the conventions you actually own

    public static let houseSwiftUIArchitecture = AgentSkill(
        id: "house.swiftui-architecture",
        name: "House SwiftUI architecture",
        origin: .house,
        version: "4.2.0",
        activationKeywords: ["swiftui", "view model", "feature module"],
        requiredCapabilities: [.readSource, .editSource],
        rules: [
            SkillRule(
                subject: "swiftui.state-ownership",
                stance: .forbid,
                directive: "No @Observable view models. Views render a ViewState value produced by a feature actor."
            )
        ]
    )

    public static let houseConcurrencyPolicy = AgentSkill(
        id: "house.concurrency-policy",
        name: "House concurrency policy",
        origin: .house,
        version: "2.1.0",
        activationKeywords: ["concurrency", "actor", "sendable"],
        requiredCapabilities: [.readSource, .editSource],
        rules: [
            SkillRule(
                subject: "concurrency.isolation",
                stance: .forbid,
                directive: "@unchecked Sendable requires a written justification in the ADR log."
            )
        ]
    )

    /// The interesting one. It outranks Apple's migration skill, but it is
    /// tool-driven — it flips a build setting as part of the freeze — so
    /// outside Xcode it cannot run, and the vendor rule it was written to
    /// suppress is what the model actually gets.
    public static let repoTestFrameworkFreeze = AgentSkill(
        id: "repo.test-framework-freeze",
        name: "Checkout test-framework freeze",
        origin: .repo,
        version: "1.3.0",
        activationKeywords: ["xctest", "checkout", "test suite"],
        requiredCapabilities: [.writeBuildSettings],
        rules: [
            SkillRule(
                subject: "testing.framework",
                stance: .forbid,
                directive: "Do not move checkout tests off XCTest until the flake rate is under 1% for two weeks."
            )
        ]
    )

    /// All ten skills an agent would find installed.
    public static let allSkills: [AgentSkill] = [
        swiftUIBestPractices,
        swiftUIAPIAdoption,
        uiKitModernization,
        xctestMigration,
        deviceInteractionTesting,
        cBoundsSafety,
        securitySettingsAudit,
        houseSwiftUIArchitecture,
        houseConcurrencyPolicy,
        repoTestFrameworkFreeze
    ]

    /// The ledger a team would commit: five vendor skills pinned honestly, one
    /// pinned at a digest Xcode has since changed underneath them, and one
    /// never pinned at all.
    public static let pins: [SkillPin] = [
        SkillPin(
            skillID: swiftUIBestPractices.id,
            version: "26.4",
            digest: SkillDigest.hash("apple.swiftui-best-practices@26.4")
        ),
        .pinning(swiftUIAPIAdoption),
        .pinning(uiKitModernization),
        .pinning(xctestMigration),
        .pinning(deviceInteractionTesting),
        .pinning(securitySettingsAudit)
        // apple.c-bounds-safety is deliberately absent.
    ]

    /// Tasks worth watching resolve differently across harnesses.
    public static let sampleTasks: [String] = [
        "Migrate the checkout XCTest suite to Swift Testing and run the security audit on build settings",
        "Refactor the profile SwiftUI view model ahead of the iOS 27 API adoption pass",
        "Modernise the legacy UIKit settings view controller and add a device interaction ui test"
    ]
}
