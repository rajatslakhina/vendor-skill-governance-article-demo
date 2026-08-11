# SkillPolicy

**Xcode 27 ships seven agent skills. `xcrun agent skills export` drops them into `~/.agents/skills`, where Claude Code, Codex and Cursor read them. That makes Apple a contributor to your coding standard — one whose commits nobody on your team reviews.**

`SkillPolicy` is a small, runnable library that treats an installed skill set the way you'd treat any other dependency: resolve it, check what can actually run, decide which rule wins each subject, and produce an audit trail you can read in review.

Article: (added after publish)

---

## The result worth looking at

One task. One catalog of ten installed skills. Two harnesses. **Opposite instructions.**

> Task: *"Migrate the checkout XCTest suite to Swift Testing and run the security audit on build settings"*

| | Xcode 27 | Claude Code |
|---|---|---|
| Activated skills | 3 | 3 |
| Effective rule on `testing.framework` | **MUST NOT** move checkout tests off XCTest | **MUST** port XCTestCase to `@Test` |
| Winning skill | `repo.test-framework-freeze` | `apple.xctest-to-swift-testing` |
| Conflicts detected | 1 (hard) | **0** |
| Blocking findings | 1 | 1 |

The repo's freeze rule outranks Apple's migration rule. But the freeze skill is tool-driven — it flips a build setting — and Claude Code grants no build-settings capability, so it is `inoperable` there. It cannot run, so it cannot win, so the vendor rule underneath it is what the model actually receives.

Note the conflict count. It doesn't get resolved in Claude Code. It stops being detectable, because one side of it left the room.

## The load-bearing decision

**Precedence is computed over the skills that can run, not over the skills that are installed.**

Letting an inoperable skill "win" a subject would suppress the vendor rule that is genuinely reaching the model — a standard nobody chose, applied in a harness nobody checked. So the resolver ranks only operative skills, and raises a blocking `precedenceYielded` finding whenever a higher-authority skill was outranked into silence by a missing capability.

```swift
public enum PortabilityVerdict: Sendable, Equatable {
    case portable
    case degraded(missing: [HarnessCapability])
    case inoperable(missing: [HarnessCapability])

    public var isOperative: Bool {
        if case .inoperable = self { return false }
        return true
    }
}
```

```swift
// A vendor skill you did not write, pinned by content, checked before it runs.
public enum PinStatus: Sendable, Equatable {
    case pinned
    case unpinned
    case drifted(expected: String, actual: String)
}
```

Digests are hand-rolled FNV-1a, deliberately **not** `Hasher` — `Hasher` is seeded per process, so a pin written today would "drift" tomorrow for no reason at all.

## What's in it

- `AgentSkill` — id, origin (`vendor` / `house` / `repo`), version, activation keywords, required capabilities, and typed `SkillRule`s keyed by `subject`.
- `HarnessProfile` — what a given harness actually grants. Ships `.xcode`, `.claudeCode`, `.ciAgent`.
- `SkillResolver` — activation, portability, conflict detection, precedence resolution, governance findings, and a CI-shaped `passesGate`.
- `SkillDigest` / `SkillPin` — deterministic content addressing and drift detection for skills you don't own.
- `SampleCatalog` — Apple's seven Xcode 27 skills plus two house skills and one repo skill, wired so the collisions are real.
- `SkillPolicyUI` — a SwiftUI report view: pick a harness, pick a task, watch the effective standard change.

## How to run it

```bash
git clone https://github.com/rajatslakhina/vendor-skill-governance-article-demo.git
cd vendor-skill-governance-article-demo
swift test              # library + tests, no Xcode needed
open Demo.xcodeproj     # pick any Simulator, press Run
```

`Demo.xcodeproj` consumes the library through a local Swift package reference (`relativePath = .`), so there is no second repository to fetch and no package resolution step.

## Verification status

Verified in this run:

- `swift build` — clean (Swift 6.0.3, `swift-tools-version: 6.0`).
- `swift test` — **20 tests, 0 failures**, covering activation boundaries, portability classification, hard/soft/no-conflict cases, precedence ordering, the cross-harness divergence above, inoperable-skill suppression, pin drift, digest determinism against known FNV-1a vectors, and report determinism under input reordering.
- `Demo.xcodeproj/project.pbxproj` — brace/paren balance checked, all 20 object ids defined, no dangling references, and byte-identical (modulo module name and bundle id) to a project file previously confirmed to build and launch on Simulator.

**Not verified in this run:** the app was **not** launched on a Simulator, so this repo contains **no** screenshots. The run that produced it was an unattended scheduled task, and screen-control approval cannot be granted while nobody is present to approve it. Rather than fake a screenshot, the gap is recorded here. The `Demo/Screenshots/` directory is intentionally empty apart from a placeholder note.

## License

MIT.
