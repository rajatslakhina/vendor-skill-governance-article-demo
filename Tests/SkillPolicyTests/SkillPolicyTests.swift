import XCTest
@testable import SkillPolicy

final class SkillPolicyTests: XCTestCase {

    private let resolver = SkillResolver()

    // MARK: - Activation

    func testActivationMatchesWholeTokensOnly() {
        let skill = AgentSkill(
            id: "t.state", name: "State", origin: .house, version: "1.0",
            activationKeywords: ["state"], requiredCapabilities: [.readSource], rules: []
        )
        let hit = resolver.resolve(task: "Fix the state restoration bug", skills: [skill], harness: .xcode)
        XCTAssertEqual(hit.activated.count, 1)

        let miss = resolver.resolve(task: "Read the statement parser", skills: [skill], harness: .xcode)
        XCTAssertTrue(miss.activated.isEmpty, "`state` must not match inside `statement`")
    }

    func testMultiWordKeywordsAndPunctuationSurvivesNormalization() {
        let skill = AgentSkill(
            id: "t.multi", name: "Multi", origin: .house, version: "1.0",
            activationKeywords: ["build settings"], requiredCapabilities: [], rules: []
        )
        let report = resolver.resolve(task: "Audit the build-settings, please.", skills: [skill], harness: .claudeCode)
        XCTAssertEqual(report.activated.first?.matchedKeywords, ["build settings"])
    }

    func testEmptyKeywordNeverActivates() {
        let skill = AgentSkill(
            id: "t.empty", name: "Empty", origin: .house, version: "1.0",
            activationKeywords: ["", "   "], requiredCapabilities: [], rules: []
        )
        XCTAssertTrue(resolver.resolve(task: "anything at all", skills: [skill], harness: .xcode).activated.isEmpty)
    }

    func testEmptyCatalogResolvesCleanly() {
        let report = resolver.resolve(task: "Do something", skills: [], harness: .xcode)
        XCTAssertTrue(report.activated.isEmpty)
        XCTAssertTrue(report.effectiveRules.isEmpty)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertTrue(report.passesGate)
    }

    // MARK: - Portability

    func testPortabilityClassification() {
        XCTAssertEqual(resolver.verdict(for: SampleCatalog.swiftUIBestPractices, in: .claudeCode), .portable)
        XCTAssertEqual(
            resolver.verdict(for: SampleCatalog.deviceInteractionTesting, in: .claudeCode),
            .degraded(missing: [.runDeviceInteractionTests])
        )
        XCTAssertEqual(
            resolver.verdict(for: SampleCatalog.securitySettingsAudit, in: .claudeCode),
            .inoperable(missing: [.readBuildSettings, .writeBuildSettings])
        )
    }

    func testSkillWithNoCapabilityRequirementIsPortableEverywhere() {
        let skill = AgentSkill(
            id: "t.free", name: "Free", origin: .vendor, version: "1.0",
            activationKeywords: ["free"], requiredCapabilities: [], rules: []
        )
        for harness in HarnessProfile.allProfiles {
            XCTAssertEqual(resolver.verdict(for: skill, in: harness), .portable)
        }
    }

    // MARK: - Conflicts

    func testRequireVersusForbidIsAHardConflict() {
        let report = resolver.resolve(
            task: "Refactor the profile swiftui view model",
            skills: [SampleCatalog.swiftUIBestPractices, SampleCatalog.houseSwiftUIArchitecture],
            harness: .claudeCode
        )
        let conflict = report.conflicts.first { $0.subject == "swiftui.state-ownership" }
        XCTAssertEqual(conflict?.severity, .hard)
        XCTAssertEqual(conflict?.participants, ["apple.swiftui-best-practices", "house.swiftui-architecture"])
    }

    func testPreferVersusRequireIsOnlyASoftConflict() {
        let a = AgentSkill(
            id: "t.a", name: "A", origin: .vendor, version: "1.0", activationKeywords: ["topic"],
            requiredCapabilities: [], rules: [SkillRule(subject: "s", stance: .prefer, directive: "lean this way")]
        )
        let b = AgentSkill(
            id: "t.b", name: "B", origin: .house, version: "1.0", activationKeywords: ["topic"],
            requiredCapabilities: [], rules: [SkillRule(subject: "s", stance: .require, directive: "do this")]
        )
        let report = resolver.resolve(task: "the topic", skills: [a, b], harness: .xcode)
        XCTAssertEqual(report.conflicts.first?.severity, .soft)
        XCTAssertFalse(report.findings.contains { if case .hardConflict = $0 { return true }; return false })
    }

    func testIdenticalRulesAreAgreementNotConflict() {
        let rule = SkillRule(subject: "s", stance: .require, directive: "same text")
        let a = AgentSkill(id: "t.a", name: "A", origin: .vendor, version: "1.0",
                           activationKeywords: ["topic"], requiredCapabilities: [], rules: [rule])
        let b = AgentSkill(id: "t.b", name: "B", origin: .house, version: "1.0",
                           activationKeywords: ["topic"], requiredCapabilities: [], rules: [rule])
        XCTAssertTrue(resolver.resolve(task: "the topic", skills: [a, b], harness: .xcode).conflicts.isEmpty)
    }

    // MARK: - Precedence

    func testRepoOutranksHouseOutranksVendor() {
        let make: (String, SkillOrigin) -> AgentSkill = { id, origin in
            AgentSkill(id: id, name: id, origin: origin, version: "1.0", activationKeywords: ["topic"],
                       requiredCapabilities: [], rules: [SkillRule(subject: "s", stance: .require, directive: id)])
        }
        let report = resolver.resolve(
            task: "the topic",
            skills: [make("v", .vendor), make("h", .house), make("r", .repo)],
            harness: .xcode
        )
        let effective = report.effectiveRules.first
        XCTAssertEqual(effective?.winningSkillID, "r")
        XCTAssertEqual(effective?.overrides.map(\.skillID), ["h", "v"])
    }

    // MARK: - The headline behaviour

    func testSameTaskAndSameSkillsProduceADifferentStandardPerHarness() {
        let task = SampleCatalog.sampleTasks[0]

        let inXcode = resolver.resolve(task: task, skills: SampleCatalog.allSkills,
                                       harness: .xcode, pins: SampleCatalog.pins)
        let inClaude = resolver.resolve(task: task, skills: SampleCatalog.allSkills,
                                        harness: .claudeCode, pins: SampleCatalog.pins)

        let xcodeRule = inXcode.effectiveRules.first { $0.subject == "testing.framework" }
        let claudeRule = inClaude.effectiveRules.first { $0.subject == "testing.framework" }

        XCTAssertEqual(xcodeRule?.winningSkillID, "repo.test-framework-freeze")
        XCTAssertEqual(xcodeRule?.rule.stance, .forbid)

        XCTAssertEqual(claudeRule?.winningSkillID, "apple.xctest-to-swift-testing")
        XCTAssertEqual(claudeRule?.rule.stance, .require)

        XCTAssertNotEqual(xcodeRule?.rule, claudeRule?.rule,
                          "Same task, same catalog, opposite instruction — that is the whole point.")
    }

    func testInoperableHigherAuthoritySkillRaisesAYieldFinding() {
        let report = resolver.resolve(task: SampleCatalog.sampleTasks[0], skills: SampleCatalog.allSkills,
                                      harness: .claudeCode, pins: SampleCatalog.pins)
        let yielded = report.findings.contains {
            $0 == .precedenceYielded(
                subject: "testing.framework",
                inoperableSkillID: "repo.test-framework-freeze",
                appliedInsteadSkillID: "apple.xctest-to-swift-testing"
            )
        }
        XCTAssertTrue(yielded)
        XCTAssertFalse(report.passesGate, "A yield is a blocking finding")
    }

    func testInoperableSkillsNeverWinASubject() {
        let report = resolver.resolve(task: SampleCatalog.sampleTasks[0], skills: SampleCatalog.allSkills,
                                      harness: .claudeCode, pins: SampleCatalog.pins)
        let winners = Set(report.effectiveRules.map(\.winningSkillID))
        let inoperable = report.activated.filter { !$0.portability.isOperative }.map(\.skill.id)
        XCTAssertFalse(inoperable.isEmpty, "The fixture must actually contain an inoperable skill")
        for id in inoperable {
            XCTAssertFalse(winners.contains(id), "\(id) cannot run yet won a subject")
        }
    }

    // MARK: - Pins

    func testDriftedVendorPinIsDetectedAndBlocks() {
        let report = resolver.resolve(task: "Refactor the swiftui view model", skills: SampleCatalog.allSkills,
                                      harness: .claudeCode, pins: SampleCatalog.pins)
        let drifted = report.findings.contains {
            if case .vendorSkillDrifted(let id, _, _) = $0 { return id == "apple.swiftui-best-practices" }
            return false
        }
        XCTAssertTrue(drifted)
        XCTAssertFalse(report.passesGate)
    }

    func testUnpinnedVendorSkillIsReportedButDoesNotBlock() {
        let report = resolver.resolve(task: "Review the c interop layer for bounds safety",
                                      skills: SampleCatalog.allSkills, harness: .claudeCode,
                                      pins: SampleCatalog.pins)
        XCTAssertTrue(report.findings.contains(.vendorSkillUnpinned(skillID: "apple.c-bounds-safety", version: "27.0")))
        XCTAssertTrue(report.passesGate)
    }

    func testMatchingPinIsClean() {
        let report = resolver.resolve(task: "Migrate the xctest suite", skills: [SampleCatalog.xctestMigration],
                                      harness: .xcode, pins: [.pinning(SampleCatalog.xctestMigration)])
        XCTAssertEqual(report.activated.first?.pinStatus, .pinned)
    }

    // MARK: - Digest

    func testDigestIsStableAcrossCallsAndSensitiveToRuleText() {
        let skill = SampleCatalog.xctestMigration
        XCTAssertEqual(skill.contentDigest, skill.contentDigest)
        XCTAssertEqual(skill.contentDigest.count, 16)

        let edited = AgentSkill(
            id: skill.id, name: skill.name, origin: skill.origin, version: skill.version,
            activationKeywords: skill.activationKeywords, requiredCapabilities: skill.requiredCapabilities,
            rules: [SkillRule(subject: "testing.framework", stance: .require, directive: "Port them, but slowly.")]
        )
        XCTAssertNotEqual(skill.contentDigest, edited.contentDigest)
    }

    func testDigestIgnoresKeywordOrdering() {
        let a = AgentSkill(id: "x", name: "X", origin: .house, version: "1.0",
                           activationKeywords: ["b", "a"], requiredCapabilities: [], rules: [])
        let b = AgentSkill(id: "x", name: "X", origin: .house, version: "1.0",
                           activationKeywords: ["a", "b"], requiredCapabilities: [], rules: [])
        XCTAssertEqual(a.contentDigest, b.contentDigest)
    }

    func testKnownDigestVector() {
        XCTAssertEqual(SkillDigest.hash(""), "cbf29ce484222325")
        XCTAssertEqual(SkillDigest.hash("a"), "af63dc4c8601ec8c")
    }

    // MARK: - Determinism

    func testReportIsDeterministic() {
        let first = resolver.resolve(task: SampleCatalog.sampleTasks[0], skills: SampleCatalog.allSkills,
                                     harness: .claudeCode, pins: SampleCatalog.pins)
        let second = resolver.resolve(task: SampleCatalog.sampleTasks[0], skills: SampleCatalog.allSkills.reversed(),
                                      harness: .claudeCode, pins: SampleCatalog.pins)
        XCTAssertEqual(first.activated.map(\.id), second.activated.map(\.id))
        XCTAssertEqual(first.effectiveRules, second.effectiveRules)
        XCTAssertEqual(first.findings, second.findings)
    }
}
