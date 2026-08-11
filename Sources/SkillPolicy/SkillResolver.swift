/// Decides which skills apply to a task, which of them can actually run in
/// this harness, and which single rule wins each subject.
///
/// The design decision worth arguing about: **precedence is computed over the
/// skills that can run, not over the skills that are installed.** A repo skill
/// outranks a vendor skill on paper, but if the repo skill needs a capability
/// this harness does not grant, it cannot influence anything — and letting it
/// "win" a subject would silently suppress the vendor rule that *is* going to
/// reach the model. That is a standard nobody chose, applied in a harness
/// nobody checked.
public struct SkillResolver: Sendable {
    /// Highest authority first.
    public let precedence: [SkillOrigin]

    public init(precedence: [SkillOrigin] = [.repo, .house, .vendor]) {
        self.precedence = precedence
    }

    public func resolve(
        task: String,
        skills: [AgentSkill],
        harness: HarnessProfile,
        pins: [SkillPin] = []
    ) -> ResolutionReport {
        let haystack = Self.normalized(task)
        let pinsByID = Dictionary(pins.map { ($0.skillID, $0) }, uniquingKeysWith: { first, _ in first })

        // 1. Activation — which skills does this task's wording pull in?
        var activated: [ActivatedSkill] = []
        for skill in skills {
            let matched = skill.activationKeywords
                .filter { !$0.trimmedIsEmpty }
                .filter { haystack.contains(Self.normalized($0)) }
                .sorted()
            guard !matched.isEmpty else { continue }

            activated.append(
                ActivatedSkill(
                    skill: skill,
                    matchedKeywords: matched,
                    portability: verdict(for: skill, in: harness),
                    pinStatus: pinStatus(for: skill, pins: pinsByID)
                )
            )
        }
        activated.sort { lhs, rhs in
            let l = rank(lhs.skill.origin), r = rank(rhs.skill.origin)
            return l == r ? lhs.skill.id < rhs.skill.id : l < r
        }

        // 2. Only operative skills get a vote on the effective standard.
        let operative = activated.filter { $0.portability.isOperative }
        let conflicts = detectConflicts(in: operative)
        let (effective, yieldFindings) = resolveRules(operative: operative, activated: activated)

        // 3. Findings, in a stable order so diffs of the report are readable.
        var findings: [GovernanceFinding] = []
        for entry in activated {
            switch entry.pinStatus {
            case .unpinned where entry.skill.origin == .vendor:
                findings.append(.vendorSkillUnpinned(skillID: entry.skill.id, version: entry.skill.version))
            case .drifted(let expected, let actual):
                findings.append(.vendorSkillDrifted(skillID: entry.skill.id, expected: expected, actual: actual))
            default:
                break
            }
            switch entry.portability {
            case .degraded(let missing):
                findings.append(.skillDegraded(skillID: entry.skill.id, missing: missing))
            case .inoperable(let missing):
                findings.append(.skillInoperable(skillID: entry.skill.id, missing: missing))
            case .portable:
                break
            }
        }
        for conflict in conflicts where conflict.severity == .hard {
            guard let winner = effective.first(where: { $0.subject == conflict.subject }) else { continue }
            let losers = winner.overrides.map(\.skillID)
            guard !losers.isEmpty else { continue }
            findings.append(.hardConflict(subject: conflict.subject, winner: winner.winningSkillID, losers: losers))
        }
        findings.append(contentsOf: yieldFindings)

        return ResolutionReport(
            task: task,
            harnessName: harness.name,
            activated: activated,
            conflicts: conflicts,
            effectiveRules: effective,
            findings: findings
        )
    }

    // MARK: - Portability

    func verdict(for skill: AgentSkill, in harness: HarnessProfile) -> PortabilityVerdict {
        let missing = skill.requiredCapabilities.subtracting(harness.granted).sorted()
        if missing.isEmpty { return .portable }
        if missing.count == skill.requiredCapabilities.count { return .inoperable(missing: missing) }
        return .degraded(missing: missing)
    }

    private func pinStatus(for skill: AgentSkill, pins: [String: SkillPin]) -> PinStatus {
        guard let pin = pins[skill.id] else { return .unpinned }
        let actual = skill.contentDigest
        return pin.digest == actual ? .pinned : .drifted(expected: pin.digest, actual: actual)
    }

    // MARK: - Conflicts

    private func detectConflicts(in operative: [ActivatedSkill]) -> [RuleConflict] {
        var bySubject: [String: [(id: String, rule: SkillRule)]] = [:]
        for entry in operative {
            for rule in entry.skill.rules {
                bySubject[rule.subject, default: []].append((entry.skill.id, rule))
            }
        }

        var conflicts: [RuleConflict] = []
        for (subject, entries) in bySubject where entries.count > 1 {
            var severity: ConflictSeverity?
            for i in entries.indices {
                for j in entries.indices where j > i {
                    let a = entries[i].rule, b = entries[j].rule
                    if a.stance == b.stance && a.directive == b.directive { continue }
                    let pair: Set<Stance> = [a.stance, b.stance]
                    if pair == [.require, .forbid] {
                        severity = .hard
                    } else if severity == nil {
                        severity = .soft
                    }
                }
            }
            guard let severity else { continue }
            conflicts.append(
                RuleConflict(
                    subject: subject,
                    severity: severity,
                    participants: entries.map(\.id).sorted()
                )
            )
        }
        return conflicts.sorted { $0.subject < $1.subject }
    }

    // MARK: - Precedence

    private func resolveRules(
        operative: [ActivatedSkill],
        activated: [ActivatedSkill]
    ) -> ([EffectiveRule], [GovernanceFinding]) {
        var bySubject: [String: [(entry: ActivatedSkill, rule: SkillRule)]] = [:]
        for entry in operative {
            for rule in entry.skill.rules {
                bySubject[rule.subject, default: []].append((entry, rule))
            }
        }

        let inoperable = activated.filter { !$0.portability.isOperative }
        var effective: [EffectiveRule] = []
        var yields: [GovernanceFinding] = []

        for (subject, candidates) in bySubject {
            let ordered = candidates.sorted { lhs, rhs in
                let l = rank(lhs.entry.skill.origin), r = rank(rhs.entry.skill.origin)
                return l == r ? lhs.entry.skill.id < rhs.entry.skill.id : l < r
            }
            guard let winner = ordered.first else { continue }

            let overrides = ordered.dropFirst().map { loser in
                OverriddenRule(
                    skillID: loser.entry.skill.id,
                    origin: loser.entry.skill.origin,
                    rule: loser.rule,
                    reason: "\(winner.entry.skill.origin.displayName.lowercased()) outranks \(loser.entry.skill.origin.displayName.lowercased())"
                )
            }

            effective.append(
                EffectiveRule(
                    subject: subject,
                    rule: winner.rule,
                    winningSkillID: winner.entry.skill.id,
                    winningOrigin: winner.entry.skill.origin,
                    overrides: Array(overrides)
                )
            )

            // The quiet failure: a higher-authority skill exists, carries a rule
            // on this exact subject, and cannot run — so a rule the team never
            // ratified is what the model will actually see.
            for blocked in inoperable where blocked.skill.rules.contains(where: { $0.subject == subject }) {
                guard rank(blocked.skill.origin) < rank(winner.entry.skill.origin) else { continue }
                yields.append(
                    .precedenceYielded(
                        subject: subject,
                        inoperableSkillID: blocked.skill.id,
                        appliedInsteadSkillID: winner.entry.skill.id
                    )
                )
            }
        }

        return (effective.sorted { $0.subject < $1.subject }, yields.sorted { $0.summary < $1.summary })
    }

    func rank(_ origin: SkillOrigin) -> Int {
        precedence.firstIndex(of: origin) ?? precedence.count
    }

    // MARK: - Text matching

    /// Lowercase, strip punctuation, pad with spaces so `contains` is a
    /// whole-token match and multi-word keywords still work.
    static func normalized(_ text: String) -> String {
        var out = " "
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                out.append(character)
            } else if out.last != " " {
                out.append(" ")
            }
        }
        if out.last != " " { out.append(" ") }
        return out
    }
}

extension String {
    var trimmedIsEmpty: Bool {
        !contains { $0.isLetter || $0.isNumber }
    }
}
