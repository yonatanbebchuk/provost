import SwiftUI

// Each visual animates once when its slide appears, from a visible resting state, over 1–2 s.
// Reduce Motion jumps to the end state.

/// Rows that wrap, for names.
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + rowSpacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width == .infinity ? maxX : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width { x = 0; y += rowHeight + rowSpacing; rowHeight = 0 }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Text whose number animates: `value` is interpolated and formatted on every frame.
struct CountingNumber: ViewModifier, Animatable {
    nonisolated(unsafe) var value: Double
    var format: (Int) -> String

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text(format(Int(value.rounded())))
    }
}

// MARK: names

struct NamesVisual: View {
    let names: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        FlowLayout(spacing: 28, rowSpacing: 12) {
            ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                Text(name)
                    .font(.system(size: 16, weight: .medium))
                    .opacity(shown ? 1 : 0.25)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.15 + Double(i) * 0.12), value: shown)
            }
        }
        .onAppear { shown = true }
    }
}

// MARK: faces

/// The people in a wrapped row, a small round photo (or initials) to the left of each name.
struct FacesVisual: View {
    let people: [PitchSlide.Person]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        FlowLayout(spacing: 28, rowSpacing: 14) {
            ForEach(Array(people.enumerated()), id: \.offset) { i, person in
                HStack(spacing: 9) {
                    face(person)
                    Text(person.name).font(.system(size: 16, weight: .medium))
                }
                .opacity(shown ? 1 : 0.25)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.15 + Double(i) * 0.12), value: shown)
            }
        }
        .onAppear { shown = true }
    }

    @ViewBuilder
    private func face(_ person: PitchSlide.Person) -> some View {
        if let url = PitchDeck.faceURL(for: person), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: 30, height: 30).clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
        } else {
            ZStack {
                Circle().fill(Color.primary.opacity(0.08))
                Text(person.initials).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 30, height: 30)
        }
    }
}

// MARK: timeline + compute chart

/// A rail with ticks. `revealed` nil: the ticks rise in one by one when the slide appears;
/// otherwise only the first `revealed` ticks show, each rising in as `→` reveals it.
struct TimelineVisual: View {
    let ticks: [PitchSlide.TimelineTick]
    let chart: PitchSlide.ComputeShareChart?
    var revealed: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private func isShown(_ i: Int) -> Bool { revealed.map { i < $0 } ?? shown }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            GeometryReader { geo in
                let slot = geo.size.width / CGFloat(max(1, ticks.count))
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.separator).frame(height: 1).offset(y: 10)
                    ForEach(Array(ticks.enumerated()), id: \.offset) { i, tick in
                        VStack(alignment: .leading, spacing: 10) {
                            Circle().fill(Color.primary).frame(width: 10, height: 10).padding(.top, 5.5)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tick.name).font(.system(size: 16, weight: .medium))
                                Text(tick.product).font(.system(size: 13)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(width: slot - 24, alignment: .leading)
                        }
                        .offset(x: CGFloat(i) * slot, y: isShown(i) ? 0 : 8)
                        .opacity(isShown(i) ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(revealed == nil ? 0.4 + Double(i) * 0.55 : 0),
                                   value: isShown(i))
                    }
                }
            }
            .frame(height: 110)
            if let chart {
                ComputeShareChartView(chart: chart, shown: shown)
            }
        }
        .onAppear { shown = true }
    }
}

/// The compute-share chart on its own. `revealed` nil: it rises when the slide appears; false:
/// hidden until `→`; true: rising.
struct ChartVisual: View {
    let chart: PitchSlide.ComputeShareChart?
    var revealed: Bool? = nil
    @State private var shown = false

    var body: some View {
        if let chart {
            ComputeShareChartView(chart: chart, shown: revealed ?? shown)
                .opacity((revealed ?? shown) ? 1 : 0)
                .onAppear { shown = true }
        }
    }
}

/// Stacked bars, one per quarter, normalised to 100 %. The highlighted series is drawn in the
/// foreground colour; the others in two greys. Bars rise from the baseline when the slide appears.
struct ComputeShareChartView: View {
    let chart: PitchSlide.ComputeShareChart
    var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func shade(_ series: PitchSlide.ComputeShareChart.Series, index: Int) -> Color {
        if series.highlight == true { return .primary }
        return index == 0 ? Color.primary.opacity(0.28) : Color.primary.opacity(0.10)
    }

    private func label(_ series: PitchSlide.ComputeShareChart.Series, index: Int) -> Color {
        if series.highlight == true { return Theme.windowBackground }
        return index == 0 ? .primary : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text(chart.title).font(.system(size: 13, weight: .semibold))
                ForEach(Array(chart.series.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(shade(s, index: i)).frame(width: 10, height: 10)
                        Text(s.name).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            GeometryReader { geo in
                let n = max(1, chart.quarters.count)
                let gap: CGFloat = max(6, geo.size.width * 0.012)
                let barWidth = (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                let labelHeight: CGFloat = 18
                let barHeight = geo.size.height - labelHeight
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(0..<n, id: \.self) { q in
                        let total = chart.series.reduce(0) { $0 + ($1.values.indices.contains(q) ? $1.values[q] : 0) }
                        VStack(spacing: 4) {
                            VStack(spacing: 1) {
                                // Drawn top-down: the last series sits on top of the stack.
                                ForEach(Array(chart.series.enumerated().reversed()), id: \.offset) { i, s in
                                    let v = s.values.indices.contains(q) ? s.values[q] : 0
                                    let h = total > 0 ? barHeight * v / total : 0
                                    ZStack {
                                        Rectangle().fill(shade(s, index: i))
                                        if h >= 15 {
                                            Text("\(Int(v.rounded()))%")
                                                .font(.system(size: 10.5, weight: s.highlight == true ? .semibold : .regular).monospacedDigit())
                                                .foregroundStyle(label(s, index: i))
                                        }
                                    }
                                    .frame(height: max(0, h - 1))
                                }
                            }
                            .frame(width: barWidth, height: barHeight, alignment: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .scaleEffect(y: shown ? 1 : 0.04, anchor: .bottom)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.3 + Double(q) * 0.06), value: shown)
                            Text(chart.quarters[q])
                                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .frame(width: barWidth + gap, height: labelHeight - 4)
                        }
                    }
                }
            }
            .frame(height: 230)
            if let source = chart.source {
                Text("Source: \(source)").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: ring

struct RingVisual: View {
    let stat: PitchSlide.RingStat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress / 100)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .modifier(CountingNumber(value: progress) { "\($0)%" })
                    .font(.system(size: 54, weight: .semibold).monospacedDigit())
                    .kerning(-1.5)
                    .frame(height: 54, alignment: .leading)
                Text(stat.caption)
                    .font(.system(size: 16)).foregroundStyle(.secondary)
                    .frame(maxWidth: 380, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if reduceMotion { progress = Double(stat.percent) }
            else { withAnimation(.easeOut(duration: 1.4).delay(0.2)) { progress = Double(stat.percent) } }
        }
    }
}

// MARK: reach → do

struct ReachDoVisual: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(28, max(18, geo.size.width * 0.027))
            HStack(spacing: 22) {
                box("What the model can reach", size: size)
                Text("→").font(.system(size: size, weight: .medium)).foregroundStyle(.secondary)
                box("What the model can do", size: size)
            }
        }
        .frame(height: 80)
    }

    private func box(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .medium)).kerning(-size * 0.01)
            .padding(.horizontal, 22).padding(.vertical, 16)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
    }
}

// MARK: diagram

/// The architecture: an environment with an adversary inside and a canary key; an adversary outside
/// joined by a channel; three tracked exits leaving the environment's right edge. Drawn on a
/// 720 × 230 grid and scaled to the width available.
struct DiagramVisual: View {
    var body: some View {
        GeometryReader { geo in
            let scale = min(1, geo.size.width / 720)
            Canvas { context, _ in
                func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
                    Path(roundedRect: CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale), cornerRadius: radius * scale)
                }
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
                func text(_ s: String, _ x: CGFloat, _ y: CGFloat, muted: Bool = false, anchor: UnitPoint = .center) {
                    var t = Text(s).font(.system(size: 13 * scale))
                    t = t.foregroundColor(muted ? Color.secondary : Color.primary)
                    context.draw(t, at: p(x, y), anchor: anchor)
                }
                let line2 = Color.primary.opacity(0.22)
                let panel = Theme.cardBackground
                // environment
                context.stroke(r(200, 30, 320, 170, 12), with: .color(line2), lineWidth: 1.5 * scale)
                text("environment", 216, 50, muted: true, anchor: .leading)
                // adversary inside
                let inside = r(236, 80, 130, 70, 8)
                context.fill(inside, with: .color(panel))
                context.stroke(inside, with: .color(.primary), lineWidth: 1 * scale)
                text("adversary", 301, 106); text("inside", 301, 124, muted: true)
                // canary
                let canary = r(400, 80, 96, 70, 8)
                context.fill(canary, with: .color(panel))
                context.stroke(canary, with: .color(line2), lineWidth: 1 * scale)
                text("canary", 448, 106); text("key", 448, 124, muted: true)
                // adversary outside
                let outside = r(40, 80, 120, 70, 8)
                context.fill(outside, with: .color(panel))
                context.stroke(outside, with: .color(.primary), lineWidth: 1 * scale)
                text("adversary", 100, 106); text("outside", 100, 124, muted: true)
                // channel
                var channel = Path()
                channel.move(to: p(160, 115)); channel.addLine(to: p(236, 115))
                context.stroke(channel, with: .color(.primary), style: StrokeStyle(lineWidth: 1.5 * scale, dash: [4 * scale, 3 * scale]))
                text("channel", 198, 101, muted: true)
                // tracked exits
                for (y, label) in [(70, "tracked exit · package proxy"), (115, "tracked exit · network"), (160, "tracked exit · grader")] {
                    var exit = Path()
                    exit.move(to: p(520, CGFloat(y))); exit.addLine(to: p(680, CGFloat(y)))
                    context.stroke(exit, with: .color(Theme.liftoff), lineWidth: 1.5 * scale)
                    context.fill(Path(ellipseIn: CGRect(x: (680 - 4) * scale, y: (CGFloat(y) - 4) * scale, width: 8 * scale, height: 8 * scale)), with: .color(Theme.liftoff))
                    text(label, 600, CGFloat(y) - 12, muted: true)
                }
            }
            .frame(width: 720 * scale, height: 230 * scale)
        }
        .frame(height: 230)
    }
}

// MARK: waffle + hero numbers

struct WaffleVisual: View {
    let spec: PitchSlide.WaffleSpec
    let heroes: [PitchSlide.HeroNumber]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false
    @State private var counted = false

    /// Fixed pseudo-random order: cell i lights at rank (i × 7919) mod cells.
    private var order: [Int] {
        (0..<spec.cells).sorted { ($0 * 7919) % spec.cells < ($1 * 7919) % spec.cells }
    }

    var body: some View {
        let rank = order
        VStack(alignment: .leading, spacing: 28) {
            GeometryReader { geo in
                let columns = max(1, spec.columns)
                let rows = Int(ceil(Double(spec.cells) / Double(columns)))
                let gap: CGFloat = 3
                let cell = (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                TimelineView(.animation(minimumInterval: 1 / 30, paused: finished || reduceMotion)) { context in
                    let t = context.date.timeIntervalSince(start)
                    let progress = reduceMotion ? 1 : min(1, max(0, (t - 0.3) / 1.5))
                    let lit = Int((Double(spec.lit) * progress).rounded())
                    Canvas { ctx, _ in
                        for i in 0..<spec.cells {
                            let x = CGFloat(i % columns) * (cell + gap)
                            let y = CGFloat(i / columns) * (cell + gap)
                            let hot = i < rank.count && rank[i] < lit
                            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: cell, height: cell), cornerRadius: 1),
                                     with: .color(hot ? Theme.liftoff : Color.primary.opacity(0.16)))
                        }
                    }
                    .frame(height: CGFloat(rows) * cell + gap * CGFloat(rows - 1))
                }
            }
            .frame(maxWidth: 720)
            .frame(height: waffleHeight)
            HeroRow(heroes: heroes, counted: counted)
        }
        .onAppear {
            start = Date()
            Task {
                try? await Task.sleep(for: .seconds(2.2))
                finished = true
            }
            if !reduceMotion { withAnimation(.easeOut(duration: 2.2).delay(0.9)) { counted = true } }
        }
    }

    /// Height for a 720-wide grid, so the layout is stable before GeometryReader resolves.
    private var waffleHeight: CGFloat {
        let columns = CGFloat(max(1, spec.columns))
        let rows = ceil(CGFloat(spec.cells) / columns)
        let cell = (720 - 3 * (columns - 1)) / columns
        return rows * cell + 3 * (rows - 1)
    }
}

/// Big numbers with a caption each. A hero with `countTo` counts up from 0 once `counted` turns
/// true (the waffle drives it); on its own it counts when it appears.
struct HeroRow: View {
    let heroes: [PitchSlide.HeroNumber]
    var counted: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ownCount = false

    private var isCounted: Bool { counted ?? ownCount }

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            ForEach(Array(heroes.enumerated()), id: \.offset) { _, hero in
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if let target = hero.countTo {
                            Color.clear.modifier(CountingNumber(value: isCounted || reduceMotion ? Double(target) : 0) {
                                "$" + $0.formatted(.number.grouping(.automatic))
                            })
                            .frame(height: 44, alignment: .leading)
                        } else {
                            Text(hero.value)
                        }
                    }
                    .font(.system(size: 42, weight: .semibold).monospacedDigit()).kerning(-1.2)
                    .foregroundStyle(hero.accent == true ? Theme.liftoff : .primary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    Text(hero.caption).font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: 240, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            guard counted == nil, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.2).delay(0.4)) { ownCount = true }
        }
    }
}

// MARK: numbered lines

struct LinesVisual: View {
    let lines: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text("\(i + 1)").font(.system(size: 18, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(line).font(.system(size: 26, weight: .medium)).kerning(-0.3)
                }
                .opacity(shown ? 1 : 0.25)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.2 + Double(i) * 0.35), value: shown)
            }
        }
        .onAppear { shown = true }
    }
}

// MARK: team

struct TeamVisual: View {
    let lines: [PitchSlide.TeamLine]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                (Text(line.name).fontWeight(.semibold) + Text(" · " + line.clause).foregroundColor(.secondary))
                    .font(.system(size: 18))
                    .opacity(shown ? 1 : 0.25)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.15 + Double(i) * 0.2), value: shown)
            }
        }
        .onAppear { shown = true }
    }
}
