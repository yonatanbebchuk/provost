// ARCHIVED. The adversarial training curve (proxy reward vs held-out score, liftoff marker) measures
// a training simulation, not the rollouts a compile produces. It leaves the compile page and is kept
// here for the Monitor process, where watching reward diverge during real training is the point.
import SwiftUI
import Charts

/// Proxy reward vs true score over steps. Monochrome until liftoff, when the accent appears.
struct TrainingChart: View {
    var points: [TrainingPoint]
    var totalSteps: Int
    var liftoff: LiftoffEvent?

    private var lastStep: Int { points.last?.step ?? 0 }

    var body: some View {
        Chart {
            if let liftoff, lastStep >= liftoff.step {
                RectangleMark(xStart: .value("Step", liftoff.step), xEnd: .value("Step", max(lastStep, liftoff.step + 1)))
                    .foregroundStyle(Theme.liftoff.opacity(0.07))
                RuleMark(x: .value("Liftoff", liftoff.step))
                    .foregroundStyle(Theme.liftoff)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 4) {
                        Text("Liftoff · \(liftoff.step)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.liftoff)
                            .padding(.leading, 4)
                    }
            }
            ForEach(points, id: \.step) { p in
                LineMark(x: .value("Step", p.step), y: .value("Score", p.proxyReward), series: .value("Series", "Proxy reward"))
                    .foregroundStyle(Color.primary)
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                LineMark(x: .value("Step", p.step), y: .value("Score", p.trueScore), series: .value("Series", "True score"))
                    .foregroundStyle(Color.secondary)
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [5, 3]))
            }
            if let liftoff, let p = points.first(where: { $0.step == liftoff.step }) {
                PointMark(x: .value("Step", p.step), y: .value("Score", p.proxyReward))
                    .foregroundStyle(Theme.liftoff)
                    .symbolSize(70)
            }
        }
        .chartXScale(domain: 0...max(totalSteps, 10))
        .chartYScale(domain: 0...1)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7)) {
                AxisGridLine().foregroundStyle(.quaternary)
                AxisTick()
                AxisValueLabel().font(.caption.monospacedDigit())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1]) {
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel().font(.caption.monospacedDigit())
            }
        }
        .chartXAxisLabel("step", alignment: .trailing)
        .chartLegend(.hidden)
    }
}

struct ChartLegend: View {
    var showLiftoff: Bool

    var body: some View {
        HStack(spacing: 18) {
            legendItem(dashed: false, color: .primary, label: "Proxy reward", detail: "what the environment pays out")
            legendItem(dashed: true, color: .secondary, label: "True score", detail: "held-out oracle")
            if showLiftoff {
                HStack(spacing: 6) {
                    Circle().fill(Theme.liftoff).frame(width: 8, height: 8)
                    Text("Liftoff").font(.caption.weight(.semibold)).foregroundStyle(Theme.liftoff)
                }
            }
        }
    }

    private func legendItem(dashed: Bool, color: Color, label: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 22, y: 0)) }
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, dash: dashed ? [4, 3] : []))
                .frame(width: 22, height: 2)
            Text(label).font(.caption.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}


/// ARCHIVED with the chart: the liftoff callout belongs to the training curve.
struct LiftoffBanner: View {
    let liftoff: LiftoffEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "arrow.up.right.circle.fill").font(.title3).foregroundStyle(Theme.liftoff)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Liftoff at step \(liftoff.step)").font(.body.weight(.semibold))
                    Text("·").foregroundStyle(.tertiary)
                    Text("matched").foregroundStyle(.secondary)
                    Text(liftoff.failureMode.rawValue).font(.body.monospaced())
                    Text("·").foregroundStyle(.tertiary)
                    Text("confidence \(Format.score(liftoff.confidence))").foregroundStyle(.secondary)
                }
                Text(liftoff.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.liftoff.opacity(0.09), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.liftoff.opacity(0.5)))
    }
}
