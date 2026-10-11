import SwiftUI

/// The re-run on the hardened environment: the patch and its learning scope, the curve as it
/// arrives, then the before/after rates and the replay checks from the recheck result.
struct VerifyView: View {
    @Environment(DemoStore.self) private var store
    @Environment(RunSession.self) private var session

    private var hack: Trajectory? { session.hacks.first { $0.id == session.checkedHackId } }
    private var patch: Patch? { hack.flatMap { session.patches[$0.id] } }
    private var result: VerifyResult? { hack.flatMap { session.checks[$0.id] } }
    private var total: Int { result?.stepsRerun ?? session.run.config.steps }
    private var running: Bool { !session.checking.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Verify").font(.title2.weight(.semibold))
                        Text(result == nil ? "hardened environment · re-running \(total) steps" : "hardened environment · \(total) steps re-run")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        if running {
                            ProgressView().controlSize(.small)
                            Text("step \(session.checkPoints.last?.step ?? 0) / \(total)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        } else if result == nil {
                            Text("hardening…").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if let patch, let hack { patchCards(patch, hack: hack) }
                    Card(title: "Re-run · reward against held-out score") {
                        TrainingChart(points: session.checkPoints, totalSteps: total, liftoff: nil)
                            .frame(height: 150)
                    }
                    if let result {
                        BeforeAfterStrip(result: result)
                        if let replay = result.replay { ReplayChecks(replay: replay) }
                        Text(result.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack(spacing: 12) {
                Button("← Rollouts") { session.page = .result }.buttonStyle(MonoSecondaryButtonStyle())
                Spacer()
                if store.pitch.isDemo {
                    Button("Continue pitch →") { store.leaveDemo(toNextSlide: true) }.buttonStyle(MonoProminentButtonStyle())
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func patchCards(_ patch: Patch, hack: Trajectory) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Card(title: "Patch") {
                if let notes = patch.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notes, id: \.self) { note in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Color.primary).frame(width: 5, height: 5).padding(.top, 1)
                                Text(note).font(.callout).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.changes(for: hack, in: session.environment)) { change in
                            ChangeRow(change: change, environment: session.environment, showPart: true)
                        }
                    }
                }
                Text(patch.rationale).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Card(title: "Learning scope") {
                scope("May read", patch.learningScope.allow)
                scope("May not read", patch.learningScope.deny)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func scope(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Text(item).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }
}
