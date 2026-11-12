// Used by the Verify page to plot proxy reward against the held-out score across the recheck.
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
