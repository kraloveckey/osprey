import AppKit
import SwiftUI

/// Widget section: "● CPU ························" header + content lines.
/// Clicking the header title opens Activity Monitor; the tap area is limited
/// to the icon + title so window dragging from the rest of the section works.
public struct SectionView<Content: View>: View {
    @Environment(\.contentScale) private var sz
    let icon: String
    let title: String
    var onHeaderTap: (() -> Void)? = nil
    @ViewBuilder let content: Content

    public init(icon: String, title: String, onHeaderTap: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.onHeaderTap = onHeaderTap
        self.content = content()
    }

    public var body: some View {
        // Lines keep a 2 pt gap at natural size. When the widget is taller
        // than its content each gap grows by at most 6 pt (the header stays
        // snug) and the rest goes above the last line, so the action link
        // sits on the bottom edge of the cell and every column ends level.
        SpreadVStack(spacing: 2 * sz, pinnedCount: 1, distribution: .gaps, maxGapGrowth: 6 * sz) {
            HStack(spacing: 6 * sz) {
                HStack(spacing: 6 * sz) {
                    Text(icon).foregroundStyle(Theme.header)
                    Text(title).bold().foregroundStyle(Theme.header)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let onHeaderTap {
                        onHeaderTap()
                    } else {
                        Self.openActivityMonitor()
                    }
                }
                .help(onHeaderTap != nil ? "Open \(title) Details" : "Open Activity Monitor")
                DottedLine()
            }
            content
        }
    }

    static func openActivityMonitor() {
        AppLauncher.openActivityMonitor()
    }
}

public enum AppLauncher {
    public static func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error {
                NSLog("osprey: failed to open Activity Monitor: \(error.localizedDescription)")
            }
        }
    }
}


/// Dotted filler line in the section header.
struct DottedLine: View {
    @Environment(\.contentScale) private var sz

    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(Theme.dim.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
        }
        .frame(height: 10 * sz)
    }
}

/// Row with "label – bar – value" layout.
struct MetricRow: View, Equatable {
    let label: String
    let fraction: Double
    let value: String
    var barColor: Color?
    @Environment(\.contentScale) private var sz

    static func == (lhs: MetricRow, rhs: MetricRow) -> Bool {
        lhs.label == rhs.label && lhs.fraction == rhs.fraction && lhs.value == rhs.value && lhs.barColor == rhs.barColor
    }

    init(label: String, fraction: Double, value: String, barColor: Color? = nil) {
        self.label = label
        self.fraction = fraction
        self.value = value
        self.barColor = barColor
    }

    var body: some View {
        // lineLimit(1) everywhere: a wrapped row changes the widget height
        HStack(spacing: 8 * sz) {
            Text(label)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(width: 56 * sz, alignment: .leading)
            BarView(fraction: fraction, color: barColor).equatable()
            Text(value)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(width: 56 * sz, alignment: .trailing)
        }
    }
}

/// Row with "label – text" layout, no bar.
struct TextRow: View {
    let label: String
    let value: String
    @Environment(\.contentScale) private var sz

    var body: some View {
        HStack(spacing: 8 * sz) {
            Text(label)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(width: 56 * sz, alignment: .leading)
            Text(value)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}

/// Row with a label, a sparkline of recent history, and a trailing value.
struct SparkRow: View, Equatable {
    let label: String
    let values: [Double]
    let value: String
    let color: Color
    @Environment(\.contentScale) private var sz

    static func == (lhs: SparkRow, rhs: SparkRow) -> Bool {
        lhs.label == rhs.label && lhs.values == rhs.values && lhs.value == rhs.value && lhs.color == rhs.color
    }

    var body: some View {
        HStack(spacing: 8 * sz) {
            Text(label)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(width: 56 * sz, alignment: .leading)
            SparklineView(values: values, color: color).equatable()
            Text(value)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 56 * sz, alignment: .trailing)
        }
    }
}
