import SwiftUI

/// The Provost mark: a single pulse on a flat line. Drawn as a path so it tints with
/// `foregroundStyle` and stays crisp at any size. Same geometry as the app icon in `Resources/Assets.xcassets`
/// (120-unit grid, 10-unit stroke); the mark's own box is 96 × 66 of that grid.
struct ProvostMark: Shape {
    static let aspect: CGFloat = 96.0 / 66.0

    func path(in rect: CGRect) -> Path {
        // Fit the 96×66 box into `rect`, preserving aspect, centred.
        let scale = min(rect.width / 96, rect.height / 66)
        let w = 96 * scale, h = 66 * scale
        let ox = rect.minX + (rect.width - w) / 2
        let oy = rect.minY + (rect.height - h) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + (x - 12) * scale, y: oy + (y - 40) * scale)
        }
        var path = Path()
        path.move(to: p(12, 96))
        path.addLine(to: p(37.92, 96))
        path.addLine(to: p(37.92, 40))
        path.addLine(to: p(47.92, 40))
        path.addLine(to: p(82.64, 96))
        path.addLine(to: p(108, 96))
        path.addLine(to: p(108, 106))
        path.addLine(to: p(12, 106))
        path.closeSubpath()
        // The notch between the rise, the fall and the baseline.
        path.move(to: p(47.92, 58.978))
        path.addLine(to: p(70.874, 96))
        path.addLine(to: p(47.92, 96))
        path.closeSubpath()
        return path
    }
}

extension ProvostMark {
    /// Convenience: the mark filled with the current foreground style at a given height.
    static func image(height: CGFloat) -> some View {
        ProvostMark()
            .fill(.foreground, style: FillStyle(eoFill: true))
            .frame(width: height * aspect, height: height)
    }
}

/// Mark + wordmark, baseline-aligned. Used in the sidebar header.
struct BrandLockup: View {
    var size: CGFloat = 17

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.5) {
            ProvostMark.image(height: size * 0.82)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
            Text(AppConfig.productName)
                .font(.system(size: size, weight: .semibold))
                .kerning(-0.2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppConfig.productName)
    }
}

#Preview("Brand") {
    VStack(alignment: .leading, spacing: 24) {
        BrandLockup()
        BrandLockup(size: 32)
        ProvostMark.image(height: 60)
        ProvostMark.image(height: 12)
    }
    .padding(32)
}
