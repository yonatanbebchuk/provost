import SwiftUI

struct VerifyView: View {
    @Environment(RunSession.self) private var session

    private var totalSteps: Int { session.verifyResult?.stepsRerun ?? session.run.config.steps }
    private var currentStep: Int { session.verifyPoints.last?.step ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Verification run").font(.title2.weight(.semibold))
                        Text("Patched environment · \(session.patch?.id ?? "") · same model, algorithm and seed")
                            .font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("step \(currentStep) / \(totalSteps)")
                        .font(.title3.monospacedDigit().weight(.medium)).foregroundStyle(.secondary)
                }
                TrainingChart(points: session.verifyPoints, totalSteps: totalSteps, liftoff: nil)
                    .frame(height: 230)
                    .padding(.top, 10)
                HStack {
                    ChartLegend(showLiftoff: false)
                    Spacer()
                    if let last = session.verifyPoints.last {
                        Text("gap \(String(format: "%+.2f", last.gap))")
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                if let result = session.verifyResult {
                    BeforeAfterStrip(result: result)
                    Card(title: "Summary") {
                        Text(result.summary).font(.callout)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Before/after numbers land when the re-run finishes.").font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            StageFooter(busyLabel: session.verifyFinished ? "Issuing certificate…" : "Re-verifying · step \(currentStep) / \(totalSteps)") {
                if let result = session.verifyResult {
                    Label(result.verdict.displayName, systemImage: result.verdict == .pass ? "checkmark.seal.fill" : "xmark.seal")
                        .font(.callout.weight(.medium))
                }
            }
        }
    }
}

struct BeforeAfterStrip: View {
    let result: VerifyResult

    var body: some View {
        HStack(spacing: 12) {
            deltaTile("Hack rate", before: result.before.hackRate, after: result.after.hackRate, goodWhenDown: true)
            deltaTile("Pass rate", before: result.before.passRate, after: result.after.passRate, goodWhenDown: false)
            StatTile(label: "Steps re-run", value: "\(result.stepsRerun)", caption: "same seed as the audit run")
            StatTile(label: "Verdict", value: result.verdict.rawValue.capitalized, caption: result.verdict.displayName)
        }
    }

    private func deltaTile(_ label: String, before: Double, after: Double, goodWhenDown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.percent(before))
                    .font(.system(size: 26, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: .secondary)
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                Text(Format.percent(after))
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
            }
            let delta = after - before
            Text(String(format: "%@%.0f pts", delta >= 0 ? "+" : "−", abs(delta) * 100))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
    }
}
