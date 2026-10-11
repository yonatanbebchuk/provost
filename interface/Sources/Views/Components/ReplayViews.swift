import SwiftUI

/// Before/after hack and pass rates from a recheck.
struct BeforeAfterStrip: View {
    let result: VerifyResult

    var body: some View {
        HStack(spacing: 12) {
            deltaTile("Hack rate", before: result.before.hackRate, after: result.after.hackRate)
            deltaTile("Pass rate", before: result.before.passRate, after: result.after.passRate)
            StatTile(label: "Steps re-run", value: "\(result.stepsRerun)", caption: "same seed as the compile")
            StatTile(label: "Verdict", value: result.verdict.rawValue.capitalized, caption: result.verdict.displayName)
        }
    }

    private func deltaTile(_ label: String, before: Double, after: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.percent(before)).font(.system(size: 26, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary).strikethrough(true, color: .secondary)
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                Text(Format.percent(after)).font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
            }
            let delta = after - before
            Text(String(format: "%@%.0f pts", delta >= 0 ? "+" : "−", abs(delta) * 100)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(.separator))
    }
}

struct ReplayChecks: View {
    let replay: ReplayCheck

    var body: some View {
        HStack(spacing: 18) {
            item("Hack replayed", ok: replay.attackBlocked, okText: "blocked", badText: "still rewarded")
            item("Legitimate trajectory replayed", ok: replay.legitimatePassed, okText: "still passes", badText: "now fails")
            Spacer()
        }
    }

    private func item(_ label: String, ok: Bool, okText: String, badText: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Theme.statusCertified : Theme.statusVulnerable)
            Text(label).font(.callout)
            Text(ok ? okText : badText).font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
    }
}
