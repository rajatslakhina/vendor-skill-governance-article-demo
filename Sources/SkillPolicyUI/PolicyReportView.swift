#if canImport(SwiftUI)
import SwiftUI
import SkillPolicy

/// Live proof of the uncomfortable bit: hold the task and the installed skill
/// set completely still, change only which harness is running, and watch the
/// effective standard flip.
public struct PolicyReportView: View {
    @State private var harnessIndex = 0
    @State private var taskIndex = 0

    private let resolver = SkillResolver()

    public init() {}

    private var harness: HarnessProfile {
        let profiles = HarnessProfile.allProfiles
        guard profiles.indices.contains(harnessIndex) else { return .xcode }
        return profiles[harnessIndex]
    }

    private var task: String {
        let tasks = SampleCatalog.sampleTasks
        guard tasks.indices.contains(taskIndex) else { return "" }
        return tasks[taskIndex]
    }

    private var report: ResolutionReport {
        resolver.resolve(task: task, skills: SampleCatalog.allSkills,
                         harness: harness, pins: SampleCatalog.pins)
    }

    public var body: some View {
        NavigationStack {
            List {
                controls
                gate
                effectiveStandard
                activatedSkills
                findings
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Skill Policy")
        }
    }

    // MARK: - Sections

    private var controls: some View {
        Section("Harness") {
            Picker("Harness", selection: $harnessIndex) {
                ForEach(Array(HarnessProfile.allProfiles.enumerated()), id: \.offset) { index, profile in
                    Text(profile.name).tag(index)
                }
            }
            .pickerStyle(.segmented)

            Picker("Task", selection: $taskIndex) {
                ForEach(Array(SampleCatalog.sampleTasks.enumerated()), id: \.offset) { index, text in
                    Text(shortLabel(for: index)).tag(index)
                }
            }
            Text(task)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var gate: some View {
        let passes = report.passesGate
        return Section {
            HStack(spacing: 12) {
                Image(systemName: passes ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(passes ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(passes ? "Gate passes" : "Gate blocks")
                        .font(.headline)
                    Text(passes
                         ? "Nothing here needs a human before the agent runs."
                         : "\(report.blockingFindings.count) blocking finding(s) need a decision.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var effectiveStandard: some View {
        Section("Effective standard") {
            if report.effectiveRules.isEmpty {
                Text("No rules reach the agent for this task.")
                    .foregroundStyle(.secondary)
            }
            ForEach(report.effectiveRules) { effective in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(effective.subject)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        badge(effective.winningOrigin.displayName, tint: tint(for: effective.winningOrigin))
                    }
                    Text("\(effective.rule.stance.symbol) \(effective.rule.directive)")
                        .font(.callout)
                    ForEach(effective.overrides, id: \.skillID) { overridden in
                        Text("overrides \(overridden.skillID) — \(overridden.reason)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var activatedSkills: some View {
        Section("Activated skills (\(report.activated.count))") {
            ForEach(report.activated) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.skill.name).font(.callout.weight(.medium))
                    HStack(spacing: 6) {
                        badge(entry.skill.origin.displayName, tint: tint(for: entry.skill.origin))
                        badge(entry.portability.label, tint: tint(for: entry.portability))
                        if case .drifted = entry.pinStatus { badge("drifted", tint: .red) }
                        if case .unpinned = entry.pinStatus, entry.skill.origin == .vendor {
                            badge("unpinned", tint: .orange)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var findings: some View {
        Section("Findings (\(report.findings.count))") {
            if report.findings.isEmpty {
                Text("Clean.").foregroundStyle(.secondary)
            }
            ForEach(report.findings) { finding in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: finding.isBlocking ? "octagon.fill" : "info.circle.fill")
                        .foregroundStyle(finding.isBlocking ? .red : .secondary)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(finding.summary).font(.caption)
                }
            }
        }
    }

    // MARK: - Chrome

    private func shortLabel(for index: Int) -> String {
        switch index {
        case 0: return "Test migration + security audit"
        case 1: return "SwiftUI view model refactor"
        default: return "UIKit modernisation + UI test"
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }

    private func tint(for origin: SkillOrigin) -> Color {
        switch origin {
        case .vendor: return .blue
        case .house: return .purple
        case .repo: return .teal
        }
    }

    private func tint(for verdict: PortabilityVerdict) -> Color {
        switch verdict {
        case .portable: return .green
        case .degraded: return .orange
        case .inoperable: return .red
        }
    }
}

#Preview {
    PolicyReportView()
}
#endif
