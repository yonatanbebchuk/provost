import SwiftUI

/// One slide: eyebrow, title, optional subtitle, optional visual. Title only; the script never shows.
struct PitchSlideView: View {
    let slide: PitchSlide
    /// Pieces of a step-revealed visual showing so far (see `PitchSlide.buildCount`).
    var build: Int = 0

    var body: some View {
        GeometryReader { geo in
            let titleSize = min(60, max(28, geo.size.width * 0.057))
            VStack(alignment: .leading, spacing: 0) {
                if let eyebrow = slide.eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 13, weight: .medium)).kerning(1.1)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 22)
                }
                if slide.logo {
                    BrandLockup(size: titleSize)
                } else {
                    Text(slide.title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .kerning(-titleSize * 0.025)
                        .lineSpacing(titleSize * 0.06)
                        .frame(maxWidth: titleSize * (slide.isWideTitle ? 12.1 : 8.8), alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subtitle = slide.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: min(20, max(15, geo.size.width * 0.019))))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 560, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 26)
                }
                if slide.visual != nil {
                    visual
                        .padding(.top, 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, geo.size.width * 0.069)
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch slide.visual {
        case .names: NamesVisual(names: slide.names ?? [])
        case .faces: FacesVisual(people: slide.people ?? [])
        case .timeline: TimelineVisual(ticks: slide.timeline ?? [], chart: slide.chart, revealed: slide.revealsByStep ? build : nil)
        case .chart: ChartVisual(chart: slide.chart, revealed: slide.revealsByStep ? build > 0 : nil)
        case .ring: RingVisual(stat: slide.ring ?? .init(percent: 0, caption: ""))
        case .reachDo: ReachDoVisual()
        case .diagram: DiagramVisual()
        case .waffle: WaffleVisual(spec: slide.waffle ?? .init(cells: 1000, columns: 50, lit: 250), heroes: slide.heroes ?? [])
        case .team: TeamVisual(lines: slide.team ?? [])
        case nil: EmptyView()
        }
    }
}
