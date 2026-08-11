/// Where a skill came from, and therefore who is allowed to change it.
///
/// The distinction that matters is not "official vs. unofficial" — it is
/// *ownership*. A `.vendor` skill is a dependency: it arrives with the
/// toolchain, it changes when Apple decides, and nobody on your team reviews
/// the diff. A `.house` or `.repo` skill is yours.
public enum SkillOrigin: String, Sendable, Codable, CaseIterable {
    /// Shipped inside Xcode 27, exported with `xcrun agent skills export`.
    case vendor
    /// Written by your org, applied across every repository.
    case house
    /// Written for this specific repository.
    case repo

    public var displayName: String {
        switch self {
        case .vendor: return "Vendor"
        case .house: return "House"
        case .repo: return "Repo"
        }
    }
}

/// A capability a skill needs from whatever harness is executing it.
///
/// Some skills never touch anything but source text, which is why they behave
/// identically wherever they run. Others want the project model, and a harness
/// that cannot offer it turns them into dead weight without announcing it.
public enum HarnessCapability: String, Sendable, Codable, CaseIterable, Comparable {
    case readSource
    case editSource
    case readBuildSettings
    case writeBuildSettings
    case runDeviceInteractionTests

    public var displayName: String {
        switch self {
        case .readSource: return "read source"
        case .editSource: return "edit source"
        case .readBuildSettings: return "read build settings"
        case .writeBuildSettings: return "write build settings"
        case .runDeviceInteractionTests: return "drive a device/simulator"
        }
    }

    public static func < (lhs: HarnessCapability, rhs: HarnessCapability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A harness the team actually runs agents in, and what it can do.
public struct HarnessProfile: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let granted: Set<HarnessCapability>

    public init(id: String, name: String, granted: Set<HarnessCapability>) {
        self.id = id
        self.name = name
        self.granted = granted
    }

    /// Full-fat: the skills were written against this, so everything works.
    public static let xcode = HarnessProfile(
        id: "xcode",
        name: "Xcode 27",
        granted: Set(HarnessCapability.allCases)
    )

    /// Reads `~/.agents/skills` and edits files. No project-model access.
    public static let claudeCode = HarnessProfile(
        id: "claude-code",
        name: "Claude Code",
        granted: [.readSource, .editSource]
    )

    /// Source access plus a simulator, but no build-settings surface.
    public static let ciAgent = HarnessProfile(
        id: "ci-agent",
        name: "CI agent",
        granted: [.readSource, .runDeviceInteractionTests]
    )

    public static let allProfiles: [HarnessProfile] = [.xcode, .claudeCode, .ciAgent]
}

/// How hard a rule pushes.
public enum Stance: String, Sendable, Codable {
    case require
    case forbid
    case prefer

    public var symbol: String {
        switch self {
        case .require: return "MUST"
        case .forbid: return "MUST NOT"
        case .prefer: return "SHOULD"
        }
    }
}

/// One normative directive, keyed by the topic it governs.
///
/// `subject` is the load-bearing field. Two skills only collide if they are
/// talking about the same thing, and free-text prose cannot tell you that.
public struct SkillRule: Sendable, Codable, Hashable {
    public let subject: String
    public let stance: Stance
    public let directive: String

    public init(subject: String, stance: Stance, directive: String) {
        self.subject = subject
        self.stance = stance
        self.directive = directive
    }
}

/// A skill as the resolver sees it: an identity, a trigger, a capability
/// requirement, and the rules it will inject into the agent's context.
public struct AgentSkill: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let origin: SkillOrigin
    public let version: String
    public let activationKeywords: Set<String>
    public let requiredCapabilities: Set<HarnessCapability>
    public let rules: [SkillRule]

    public init(
        id: String,
        name: String,
        origin: SkillOrigin,
        version: String,
        activationKeywords: Set<String>,
        requiredCapabilities: Set<HarnessCapability>,
        rules: [SkillRule]
    ) {
        self.id = id
        self.name = name
        self.origin = origin
        self.version = version
        self.activationKeywords = activationKeywords
        self.requiredCapabilities = requiredCapabilities
        self.rules = rules
    }

    /// Content address over everything that changes the skill's behaviour.
    ///
    /// Deliberately FNV-1a and not `Hasher`: `Hasher` is seeded per process,
    /// so a pin written today would "drift" tomorrow for no reason at all.
    public var contentDigest: String {
        var canonical = "\(id)|\(origin.rawValue)|\(version)"
        canonical += "|" + activationKeywords.sorted().joined(separator: ",")
        canonical += "|" + requiredCapabilities.map(\.rawValue).sorted().joined(separator: ",")
        let ordered = rules.sorted { lhs, rhs in
            (lhs.subject, lhs.stance.rawValue, lhs.directive)
                < (rhs.subject, rhs.stance.rawValue, rhs.directive)
        }
        for rule in ordered {
            canonical += "|\(rule.subject)~\(rule.stance.rawValue)~\(rule.directive)"
        }
        return SkillDigest.hash(canonical)
    }
}
