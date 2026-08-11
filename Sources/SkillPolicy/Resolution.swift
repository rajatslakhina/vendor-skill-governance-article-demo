/// Whether a skill can actually do its job in the harness that loaded it.
public enum PortabilityVerdict: Sendable, Equatable {
    /// Every capability the skill needs is granted here.
    case portable
    /// Some capabilities are missing. The skill runs, partially.
    case degraded(missing: [HarnessCapability])
    /// Every capability the skill needs is missing. It cannot act at all.
    case inoperable(missing: [HarnessCapability])

    /// Can this skill's rules actually reach the agent's behaviour?
    public var isOperative: Bool {
        if case .inoperable = self { return false }
        return true
    }

    public var missing: [HarnessCapability] {
        switch self {
        case .portable: return []
        case .degraded(let missing), .inoperable(let missing): return missing
        }
    }

    public var label: String {
        switch self {
        case .portable: return "portable"
        case .degraded: return "degraded"
        case .inoperable: return "inoperable"
        }
    }
}

/// A skill that matched the task, plus everything governance needs to know
/// about it before its rules are allowed to count.
public struct ActivatedSkill: Sendable, Identifiable, Equatable {
    public let skill: AgentSkill
    public let matchedKeywords: [String]
    public let portability: PortabilityVerdict
    public let pinStatus: PinStatus

    public var id: String { skill.id }

    public init(
        skill: AgentSkill,
        matchedKeywords: [String],
        portability: PortabilityVerdict,
        pinStatus: PinStatus
    ) {
        self.skill = skill
        self.matchedKeywords = matchedKeywords
        self.portability = portability
        self.pinStatus = pinStatus
    }
}

/// How badly two rules disagree.
public enum ConflictSeverity: String, Sendable, Equatable {
    /// One skill requires what another forbids. No agent can satisfy both.
    case hard
    /// The rules pull in different directions but are not mutually exclusive.
    case soft
}

/// Two or more operative skills issuing different guidance on one subject.
public struct RuleConflict: Sendable, Equatable, Identifiable {
    public let subject: String
    public let severity: ConflictSeverity
    public let participants: [String]

    public var id: String { subject }

    public init(subject: String, severity: ConflictSeverity, participants: [String]) {
        self.subject = subject
        self.severity = severity
        self.participants = participants
    }
}

/// A rule that lost, and the reason it lost.
public struct OverriddenRule: Sendable, Equatable {
    public let skillID: String
    public let origin: SkillOrigin
    public let rule: SkillRule
    public let reason: String

    public init(skillID: String, origin: SkillOrigin, rule: SkillRule, reason: String) {
        self.skillID = skillID
        self.origin = origin
        self.rule = rule
        self.reason = reason
    }
}

/// The single rule the agent should actually follow for one subject, with the
/// full trail of what it beat and why.
public struct EffectiveRule: Sendable, Equatable, Identifiable {
    public let subject: String
    public let rule: SkillRule
    public let winningSkillID: String
    public let winningOrigin: SkillOrigin
    public let overrides: [OverriddenRule]

    public var id: String { subject }

    public init(
        subject: String,
        rule: SkillRule,
        winningSkillID: String,
        winningOrigin: SkillOrigin,
        overrides: [OverriddenRule]
    ) {
        self.subject = subject
        self.rule = rule
        self.winningSkillID = winningSkillID
        self.winningOrigin = winningOrigin
        self.overrides = overrides
    }
}

/// Something a human should look at before this agent run is trusted.
public enum GovernanceFinding: Sendable, Equatable, Identifiable {
    case vendorSkillUnpinned(skillID: String, version: String)
    case vendorSkillDrifted(skillID: String, expected: String, actual: String)
    case skillDegraded(skillID: String, missing: [HarnessCapability])
    case skillInoperable(skillID: String, missing: [HarnessCapability])
    case hardConflict(subject: String, winner: String, losers: [String])
    case precedenceYielded(subject: String, inoperableSkillID: String, appliedInsteadSkillID: String)

    public var id: String { summary }

    /// Blocking findings are the ones worth failing a CI gate over.
    public var isBlocking: Bool {
        switch self {
        case .vendorSkillDrifted, .hardConflict, .precedenceYielded:
            return true
        case .vendorSkillUnpinned, .skillDegraded, .skillInoperable:
            return false
        }
    }

    public var summary: String {
        switch self {
        case .vendorSkillUnpinned(let skillID, let version):
            return "\(skillID) @ \(version) is a vendor skill with no pin recorded"
        case .vendorSkillDrifted(let skillID, let expected, let actual):
            return "\(skillID) drifted from its pin (\(expected) → \(actual))"
        case .skillDegraded(let skillID, let missing):
            return "\(skillID) is degraded here — missing \(missing.map(\.displayName).joined(separator: ", "))"
        case .skillInoperable(let skillID, let missing):
            return "\(skillID) cannot run here — missing \(missing.map(\.displayName).joined(separator: ", "))"
        case .hardConflict(let subject, let winner, let losers):
            return "\(subject): \(winner) overrides \(losers.joined(separator: ", ")) on a require/forbid conflict"
        case .precedenceYielded(let subject, let inoperableSkillID, let appliedInsteadSkillID):
            return "\(subject): \(inoperableSkillID) outranks but cannot run here, so \(appliedInsteadSkillID) applies instead"
        }
    }
}

/// Everything the resolver decided, in a form you can print in review.
public struct ResolutionReport: Sendable, Equatable {
    public let task: String
    public let harnessName: String
    public let activated: [ActivatedSkill]
    public let conflicts: [RuleConflict]
    public let effectiveRules: [EffectiveRule]
    public let findings: [GovernanceFinding]

    public init(
        task: String,
        harnessName: String,
        activated: [ActivatedSkill],
        conflicts: [RuleConflict],
        effectiveRules: [EffectiveRule],
        findings: [GovernanceFinding]
    ) {
        self.task = task
        self.harnessName = harnessName
        self.activated = activated
        self.conflicts = conflicts
        self.effectiveRules = effectiveRules
        self.findings = findings
    }

    public var blockingFindings: [GovernanceFinding] { findings.filter(\.isBlocking) }

    /// The CI answer: would you let this agent run unattended?
    public var passesGate: Bool { blockingFindings.isEmpty }
}
