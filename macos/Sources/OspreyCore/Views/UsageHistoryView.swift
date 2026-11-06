import Charts
import SwiftUI

/// Retrospective window: CPU and RAM usage over the retained history with a
/// hover/click scrubber. Selecting a point shows the heaviest processes
/// recorded at that moment - the "what was the laptop stuck on?" view.
public struct UsageHistoryView: View {
    let history: UsageHistoryStore

    @State private var selectedDate: Date?
    @State private var range: TimeRange = .fourHours

    public init(history: UsageHistoryStore) {
        self.history = history
    }

    /// How far back the chart shows. Retention is 12 h; narrowing the view
    /// spreads points out so peaks are easy to scrub to.
    private enum TimeRange: String, CaseIterable, Identifiable {
        case oneHour = "1h", fourHours = "4h", twelveHours = "12h"
        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self {
            case .oneHour: 3_600
            case .fourHours: 14_400
            case .twelveHours: 43_200
            }
        }
    }

    /// Samples within the selected range, anchored to the newest sample so an
    /// idle gap doesn't push everything off the right edge.
    private var visibleSamples: [UsageSample] {
        guard let last = history.samples.last else { return [] }
        let cutoff = last.timestamp.addingTimeInterval(-range.seconds)
        return history.samples.filter { $0.timestamp >= cutoff }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Pinned Header
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().opacity(0.12)

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    if history.samples.count < 2 {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Collecting telemetry data – check back in a few minutes.")
                                .foregroundStyle(Theme.dim)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        chartCard
                        detailPaneCard
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 580, idealWidth: 640, maxWidth: .infinity, minHeight: 440, idealHeight: 520, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Usage History")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Retained Telemetry")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.2))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                }
                Text("Retrospective CPU & RAM trends with point-in-time process forensics")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            // Range pills
            HStack(spacing: 4) {
                ForEach(TimeRange.allCases) { r in
                    Button {
                        range = r
                    } label: {
                        Text(r.rawValue)
                            .font(.system(size: 11, weight: range == r ? .bold : .medium))
                            .foregroundStyle(range == r ? Color.white : Color.gray)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(range == r ? Color.white.opacity(0.12) : Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Export menu
            Menu {
                Button {
                    exportUsageHistory(asJSON: false)
                } label: {
                    Label("Export as CSV (.csv)", systemImage: "tablecells")
                }
                Button {
                    exportUsageHistory(asJSON: true)
                } label: {
                    Label("Export as JSON (.json)", systemImage: "curlybraces")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export…")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        }
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SYSTEM WORKLOAD TIMELINE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.gray)
                Spacer()
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                        Text("CPU").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.gray)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Theme.header).frame(width: 6, height: 6)
                        Text("Memory").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.gray)
                    }
                }
            }

            chart
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var chart: some View {
        Chart {
            ForEach(visibleSamples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Usage", sample.cpuFraction * 100),
                    series: .value("Metric", "CPU")
                )
                .foregroundStyle(Theme.accent)
            }
            ForEach(visibleSamples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Usage", sample.memFraction * 100),
                    series: .value("Metric", "Memory")
                )
                .foregroundStyle(Theme.header)
            }
            if let selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxisLabel("%")
        .chartForegroundStyleScale(["CPU": Theme.accent, "Memory": Theme.header])
        .chartXSelection(value: $selectedDate)
        .frame(minHeight: 220)
    }

    // MARK: - Detail Pane Card

    @ViewBuilder
    private var detailPaneCard: some View {
        let selected = selectedDate.flatMap {
            UsageHistoryMath.nearestSample(in: visibleSamples, to: $0)
        } ?? visibleSamples.last

        if let sample = selected {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gray)
                    Text(sample.timestamp, style: .time)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(sample.timestamp, style: .date)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)

                    Spacer()

                    HStack(spacing: 12) {
                        Text("CPU \(Int((sample.cpuFraction * 100).rounded()))%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.accent)
                        Text("RAM \(Fmt.gigabytes(sample.memUsedBytes))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.header)
                    }
                }

                Divider().opacity(0.1)

                if sample.topProcesses.isEmpty {
                    Text("No process telemetry recorded for this timestamp.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(sample.topProcesses, id: \.pid) { proc in
                            HStack {
                                Text(proc.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.white)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int((proc.cpuFraction * 100).rounded()))% CPU")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 80, alignment: .trailing)
                                Text(Fmt.memoryCompact(proc.memoryBytes))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.dim)
                                    .frame(width: 75, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    private func exportUsageHistory(asJSON: Bool) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "Export Usage History"
        panel.nameFieldStringValue = asJSON ? "osprey_usage_history.json" : "osprey_usage_history.csv"

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            let content: String
            if asJSON {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                content = (try? String(data: encoder.encode(history.samples), encoding: .utf8)) ?? ""
            } else {
                var csv = "Timestamp,CPU_Percent,Memory_Used_MB,Memory_Percent,Top_Processes\n"
                let isoFormatter = ISO8601DateFormatter()
                for s in history.samples {
                    let dateStr = isoFormatter.string(from: s.timestamp)
                    let cpuPct = String(format: "%.1f", s.cpuFraction * 100.0)
                    let memMB = String(format: "%.0f", Double(s.memUsedBytes) / (1024.0 * 1024.0))
                    let memPct = String(format: "%.1f", s.memFraction * 100.0)
                    let topStr = s.topProcesses.prefix(3).map { "\($0.name)(\(Int($0.cpuFraction * 100))%)" }.joined(separator: "; ")
                    csv += "\"\(dateStr)\",\(cpuPct),\(memMB),\(memPct),\"\(topStr)\"\n"
                }
                content = csv
            }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
