/// Deterministic, process-independent content addressing.
///
/// A pin is a promise that the bytes you reviewed are the bytes that ran.
/// `Hasher` cannot make that promise across two launches, let alone across two
/// machines, so this is a hand-rolled FNV-1a instead.
public enum SkillDigest {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    /// 64-bit FNV-1a over the UTF-8 bytes, rendered as 16 lowercase hex digits.
    public static func hash(_ input: String) -> String {
        var value = offsetBasis
        for byte in input.utf8 {
            value ^= UInt64(byte)
            value = value &* prime
        }
        return hex(value)
    }

    static func hex(_ value: UInt64) -> String {
        let digits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7",
                                   "8", "9", "a", "b", "c", "d", "e", "f"]
        var out = ""
        out.reserveCapacity(16)
        var shift = 60
        while shift >= 0 {
            let nibble = Int(truncatingIfNeeded: (value >> UInt64(shift)) & 0xF)
            // nibble is masked to 0...15, so this index is always in bounds.
            out.append(digits[nibble])
            shift -= 4
        }
        return out
    }
}

/// A recorded, reviewed version of a skill.
public struct SkillPin: Sendable, Equatable {
    public let skillID: String
    public let version: String
    public let digest: String

    public init(skillID: String, version: String, digest: String) {
        self.skillID = skillID
        self.version = version
        self.digest = digest
    }

    /// Convenience: pin a skill exactly as it stands right now.
    public static func pinning(_ skill: AgentSkill) -> SkillPin {
        SkillPin(skillID: skill.id, version: skill.version, digest: skill.contentDigest)
    }
}

/// What the pin ledger says about a skill that is about to run.
public enum PinStatus: Sendable, Equatable {
    case pinned
    case unpinned
    case drifted(expected: String, actual: String)
}
