import Combine
import SwiftUI

// MARK: - Measured widget height

/// Publishes the widget's measured natural (content-fitting) height so the
/// desktop window and the resize handles work with real numbers instead of
/// hard-coded estimates. Updated from `SpreadVStack` layout passes.
@MainActor
public final class WidgetGeometry: ObservableObject {
    public static let shared = WidgetGeometry()

    /// Height (pt) the widget needs to show everything without clipping,
    /// per 1.0 of content scale (multiply by the zoom to get points).
    /// 0 until the first layout pass has run.
    @Published public private(set) var naturalHeight: CGFloat = 0

    private init() {}

    /// Called from layout code; the state change is deferred to the next
    /// main-loop turn so a layout pass never mutates observed state in place.
    nonisolated static func report(_ height: CGFloat, tolerance: CGFloat = 1.5) {
        let rounded = (height * 2).rounded(.up) / 2
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let geometry = WidgetGeometry.shared
                // Ignore sub-point jitter from text metrics at different
                // scales, so fit-to-size can't oscillate.
                if abs(geometry.naturalHeight - rounded) >= tolerance {
                    geometry.naturalHeight = rounded
                }
            }
        }
    }
}

// MARK: - SpreadVStack

/// Vertical stack that never shrinks below its children's ideal heights and
/// spreads any extra height it is offered:
///
/// * `.gaps` – extra height is shared evenly by the gaps between children,
///   at most `maxGapGrowth` per gap; whatever is left goes into the last gap
///   (used inside a section: lines breathe a little, the last line – the
///   action link – lands on the bottom edge instead of lines drifting apart).
/// * `.children` – extra height is shared evenly by the children
///   (used for the grid rows: every row grows by the same amount).
///
/// The first `pinnedCount` children keep a fixed gap (`pinnedSpacing`) after
/// them and never receive extra height, so a title bar or a section header
/// stays snug to what follows it.
struct SpreadVStack: Layout {
    enum Distribution { case gaps, children }

    var spacing: CGFloat
    var pinnedCount: Int = 0
    var pinnedSpacing: CGFloat? = nil
    var distribution: Distribution = .gaps
    /// `.gaps` only: cap on how much a single gap may grow.
    var maxGapGrowth: CGFloat = .infinity
    /// When set, every sizing pass with a concrete width publishes
    /// natural height + this padding to `WidgetGeometry`. (A plain value,
    /// not a closure: a closure as the last init parameter would swallow the
    /// trailing `{ ... }` content builder.)
    var reportsNaturalHeight: CGFloat? = nil
    /// Content scale the subviews are laid out at; the report is divided by
    /// it so `WidgetGeometry` holds a scale-independent height.
    var reportScale: CGFloat = 1
    /// Minimum change (in unscaled points) worth publishing.
    var reportTolerance: CGFloat = 1.5

    private func gap(after index: Int) -> CGFloat {
        index < pinnedCount ? (pinnedSpacing ?? spacing) : spacing
    }

    private func idealHeights(_ subviews: Subviews, width: CGFloat?) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
    }

    private func naturalHeight(of heights: [CGFloat]) -> CGFloat {
        guard !heights.isEmpty else { return 0 }
        var total = heights.reduce(0, +)
        for index in 0..<(heights.count - 1) { total += gap(after: index) }
        return total
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let natural = naturalHeight(of: idealHeights(subviews, width: width))
        if let padding = reportsNaturalHeight, let width, width > 0 {
            WidgetGeometry.report((natural + padding) / max(reportScale, 0.01), tolerance: reportTolerance)
        }

        let resolvedWidth = width
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max()
            ?? 0
        var height = natural
        if let proposed = proposal.height, proposed.isFinite {
            height = max(natural, proposed)
        }
        return CGSize(width: resolvedWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let heights = idealHeights(subviews, width: bounds.width)
        let extra = max(0, bounds.height - naturalHeight(of: heights))
        let count = subviews.count
        let flexibleGaps = max(0, count - 1 - pinnedCount)
        let flexibleChildren = max(0, count - pinnedCount)

        // .gaps: even growth per flexible gap (capped), remainder to the last gap.
        var perGap: CGFloat = 0
        var lastGapBonus: CGFloat = 0
        if distribution == .gaps, flexibleGaps > 0 {
            perGap = min(extra / CGFloat(flexibleGaps), maxGapGrowth)
            lastGapBonus = extra - perGap * CGFloat(flexibleGaps)
        }

        var y = bounds.minY
        for index in 0..<count {
            var height = heights[index]
            if distribution == .children, index >= pinnedCount, flexibleChildren > 0 {
                height += extra / CGFloat(flexibleChildren)
            }
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height
            if index < count - 1 {
                y += gap(after: index)
                if distribution == .gaps, index >= pinnedCount {
                    y += perGap
                    if index == count - 2 { y += lastGapBonus }
                }
            }
        }
    }
}
