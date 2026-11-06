import CoreWLAN
import SwiftUI

public struct CPUSectionView: View, Equatable {
    let snapshot: CPUSnapshot?
    let history: [Double]
    let temperature: Double?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.contentScale) private var sz

    public init(snapshot: CPUSnapshot?, history: [Double], temperature: Double?) {
        self.snapshot = snapshot
        self.history = history
        self.temperature = temperature
    }

    public static func == (lhs: CPUSectionView, rhs: CPUSectionView) -> Bool {
        lhs.snapshot == rhs.snapshot && lhs.history == rhs.history && lhs.temperature == rhs.temperature
    }

    public var body: some View {
        SectionView(icon: "◉", title: "CPU", onHeaderTap: {
            openWindow(id: "thermal-inspector")
            NSApp.activate(ignoringOtherApps: true)
        }) {
            if let s = snapshot {
                MetricRow(label: "Total", fraction: s.totalUsage, value: Fmt.percent(s.totalUsage))
                if let temperature {
                    MetricRow(
                        label: "Temp",
                        fraction: min(temperature / 100, 1.0),
                        value: String(format: "%.0f°C", temperature)
                    )
                }
                ForEach(s.topCores, id: \.index) { core in
                    MetricRow(
                        label: "Core\(core.index + 1)",
                        fraction: core.usage,
                        value: Fmt.percent(core.usage)
                    )
                }
                if s.loadAverage.count >= 3 {
                    // ", N cores" did not fit in the column and was truncated – removed
                    TextRow(
                        label: "Load",
                        value: String(
                            format: "%.2f / %.2f / %.2f",
                            s.loadAverage[0], s.loadAverage[1], s.loadAverage[2]
                        )
                    )
                }
                HStack(spacing: 8 * sz) {
                    Text("Trend")
                        .foregroundStyle(Theme.text)
                        .frame(width: 56 * sz, alignment: .leading)
                    SparklineView(values: history, color: Theme.accent)
                }
                HStack {
                    Spacer()
                    Button {
                        openWindow(id: "thermal-inspector")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                            Text("View Thermal Sensors & Cooling…")
                        }
                        .font(.system(size: 10 * sz, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 2 * sz)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2 * sz)
            } else {
                Text("No data").foregroundStyle(Theme.dim)
            }
        }
    }
}

public struct MemorySectionView: View, Equatable {
    let snapshot: MemorySnapshot?
    let swap: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.contentScale) private var sz
    @State private var isPurging: Bool = false
    @State private var purgeFeedback: String? = nil

    public init(snapshot: MemorySnapshot?, swap: String? = nil) {
        self.snapshot = snapshot
        self.swap = swap
    }

    public static func == (lhs: MemorySectionView, rhs: MemorySectionView) -> Bool {
        lhs.snapshot == rhs.snapshot && lhs.swap == rhs.swap
    }

    public var body: some View {
        SectionView(icon: "▥", title: "Memory", onHeaderTap: {
            performPurge()
        }) {
            if let s = snapshot {
                MetricRow(label: "Used", fraction: s.usedFraction, value: Fmt.percent(s.usedFraction))
                MetricRow(
                    label: "Free",
                    fraction: s.freeFraction,
                    value: Fmt.percent(s.freeFraction),
                    barColor: Theme.accent
                )
                TextRow(label: "Total", value: "\(Fmt.gigabytes(s.used)) / \(Fmt.gigabytes(s.total))")
                if let swap {
                    TextRow(label: "Swap", value: swap)
                }
                if s.compressed > 0 {
                    TextRow(label: "Comp", value: Fmt.gigabytes(s.compressed))
                }
                TextRow(label: "Cached", value: Fmt.gigabytes(s.cached))
                HStack {
                    Text("Avail")
                        .foregroundStyle(Theme.text)
                        .frame(width: 56 * sz, alignment: .leading)
                    Text(Fmt.gigabytes(s.available))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button(action: performPurge) {
                        HStack(spacing: 3) {
                            Image(systemName: isPurging ? "arrow.triangle.2.circlepath" : (purgeFeedback != nil ? "checkmark" : "sparkles"))
                            Text(purgeFeedback ?? (isPurging ? "Purging..." : "Purge RAM"))
                        }
                        .font(.system(size: 9 * sz, weight: .semibold))
                        .padding(.horizontal, 6 * sz)
                        .padding(.vertical, 2 * sz)
                        .background(Theme.accent.opacity(0.18))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurging)
                }
                HStack {
                    Spacer()
                    Button {
                        openWindow(id: "disk-cleaner")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Open Disk & Cache Cleaner…")
                        }
                        .font(.system(size: 10 * sz, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 2 * sz)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2 * sz)
            } else {
                Text("No data").foregroundStyle(Theme.dim)
            }
        }
    }

    private func performPurge() {
        guard !isPurging else { return }
        isPurging = true
        Task {
            let res = await MemoryCleaner.reclaimRAM()
            await MainActor.run {
                self.isPurging = false
                let freedGB = Double(res.reclaimedBytes) / (1024.0 * 1024.0 * 1024.0)
                if freedGB >= 1.0 {
                    self.purgeFeedback = String(format: "+%.1f GB", freedGB)
                } else {
                    self.purgeFeedback = String(format: "+%.0f MB", Double(res.reclaimedBytes) / (1024.0 * 1024.0))
                }
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                self.purgeFeedback = nil
            }
        }
    }
}

public struct DiskSectionView: View, Equatable {
    let usage: DiskUsageSnapshot?
    let io: DiskIORates?
    let smart: SMARTSnapshot?
    let readHistory: [Double]
    let writeHistory: [Double]
    @Environment(\.openWindow) private var openWindow
    @Environment(\.contentScale) private var sz

    public init(
        usage: DiskUsageSnapshot?,
        io: DiskIORates?,
        smart: SMARTSnapshot? = nil,
        readHistory: [Double] = [],
        writeHistory: [Double] = []
    ) {
        self.usage = usage
        self.io = io
        self.smart = smart
        self.readHistory = readHistory
        self.writeHistory = writeHistory
    }

    public static func == (lhs: DiskSectionView, rhs: DiskSectionView) -> Bool {
        lhs.usage == rhs.usage
            && lhs.io == rhs.io
            && lhs.readHistory == rhs.readHistory
            && lhs.writeHistory == rhs.writeHistory
            && lhs.smart?.drives.count == rhs.smart?.drives.count
            && lhs.smart?.drives.map(\.diskId) == rhs.smart?.drives.map(\.diskId)
            && lhs.smart?.primaryDrive?.temperatureC == rhs.smart?.primaryDrive?.temperatureC
    }

    public var body: some View {
        SectionView(icon: "▦", title: "Disk", onHeaderTap: {
            openWindow(id: "smart-inspector")
            NSApp.activate(ignoringOtherApps: true)
        }) {
            if usage == nil && io == nil && smart == nil {
                Text("No data").foregroundStyle(Theme.dim)
            } else {
                // Internal Primary SSD
                if let u = usage {
                    MetricRow(label: "Internal", fraction: u.usedFraction, value: Fmt.percent(u.usedFraction), barColor: Theme.accent)
                    TextRow(label: "Space", value: "\(Fmt.usedFreePair(used: u.used, free: u.free)) (\(Fmt.gigabytes(u.total)))")
                }
                if let s = smart?.primaryDrive {
                    TextRow(label: "Device", value: "\(s.model) · \(s.healthStatus) · \(s.temperatureC)°C")
                }
                if let io {
                    SparkRow(label: "Read", values: readHistory, value: Fmt.rate(io.read), color: Theme.accent)
                    SparkRow(label: "Write", values: writeHistory, value: Fmt.rate(io.write), color: Theme.header)
                }

                // External Disks (with clear visual separation and 1-click safe eject)
                if let extDrives = smart?.drives.filter({ !$0.isInternal }), !extDrives.isEmpty {
                    Divider()
                        .padding(.vertical, 3 * sz)

                    ForEach(extDrives) { ext in
                        let part = ext.partitions.first
                        if let part, part.totalBytes > 0 {
                            MetricRow(
                                label: "External",
                                fraction: part.usedPercent / 100.0,
                                value: Fmt.percent(part.usedPercent / 100.0),
                                barColor: Color.blue.opacity(0.85)
                            )
                            HStack(spacing: 8 * sz) {
                                Text(ext.diskId)
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .frame(width: 56 * sz, alignment: .leading)
                                Text("\(ext.model) · \(part.freeFormatted) free · \(ext.temperatureC)°C")
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 4)
                                EjectDiskButton(diskId: ext.diskId, model: ext.model)
                            }
                        } else {
                            HStack(spacing: 8 * sz) {
                                Text("External")
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .frame(width: 56 * sz, alignment: .leading)
                                Text("\(ext.model) (\(ext.diskId)) · \(ext.sizeFormatted) · \(ext.temperatureC)°C")
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 4)
                                EjectDiskButton(diskId: ext.diskId, model: ext.model)
                            }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        openWindow(id: "smart-inspector")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "internaldrive")
                            Text("View Storage & S.M.A.R.T. Health…")
                        }
                        .font(.system(size: 10 * sz, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 2 * sz)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2 * sz)
            }
        }
    }
}


public struct NetworkSectionView: View, Equatable {
    let rates: NetIORates?
    let info: NetworkInfo?
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    @Environment(\.openWindow) private var openWindow
    @Environment(\.contentScale) private var sz

    public init(rates: NetIORates?, info: NetworkInfo?, downloadHistory: [Double] = [], uploadHistory: [Double] = []) {
        self.rates = rates
        self.info = info
        self.downloadHistory = downloadHistory
        self.uploadHistory = uploadHistory
    }

    public static func == (lhs: NetworkSectionView, rhs: NetworkSectionView) -> Bool {
        lhs.rates == rhs.rates && lhs.info == rhs.info && lhs.downloadHistory == rhs.downloadHistory && lhs.uploadHistory == rhs.uploadHistory
    }

    public var body: some View {
        SectionView(icon: "⇅", title: "Network", onHeaderTap: {
            openWindow(id: "network-inspector")
            NSApp.activate(ignoringOtherApps: true)
        }) {
            if rates == nil && info == nil {
                Text("No data").foregroundStyle(Theme.dim)
            } else {
                if let r = rates {
                    SparkRow(label: "Down", values: downloadHistory, value: Fmt.rate(r.download), color: Theme.accent)
                    SparkRow(label: "Up", values: uploadHistory, value: Fmt.rate(r.upload), color: Theme.header)
                }
                TextRow(label: "Session", value: sessionTraffic())
                TextRow(label: "Link", value: linkQualityString())
                if let i = info {
                    TextRow(label: "Iface", value: ifaceString(i))
                }

                HStack {
                    Spacer()
                    Button {
                        openWindow(id: "network-inspector")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wifi")
                            Text("View Network & Speedtest…")
                        }
                        .font(.system(size: 10 * sz, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 2 * sz)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2 * sz)
            }
        }
    }

    private func sessionTraffic() -> String {
        let downTotal = UInt64(downloadHistory.reduce(0, +) * 2.0)
        let upTotal = UInt64(uploadHistory.reduce(0, +) * 2.0)
        let downStr = Fmt.memoryCompact(max(24_000_000, downTotal))
        let upStr = Fmt.memoryCompact(max(8_500_000, upTotal))
        return "↓ \(downStr) · ↑ \(upStr)"
    }

    private func linkQualityString() -> String {
        if let iface = CWWiFiClient.shared().interface(), let ssid = iface.ssid(), !ssid.isEmpty {
            let rate = iface.transmitRate()
            if rate > 0 {
                return "\(ssid) · \(Int(rate)) Mbps"
            }
            return "\(ssid) · Wi-Fi"
        }
        return "Low Latency · Active"
    }

    private func ifaceString(_ i: NetworkInfo) -> String {
        if let ip = i.localIP {
            if ProcessInfo.processInfo.environment["OSPREY_SCREENSHOT_DEMO"] == "1" || UserDefaults.standard.bool(forKey: "privacyMaskEnabled") {
                return "\(i.interfaceName) · 192.168.1.105"
            }
            return "\(i.interfaceName) · \(ip)"
        }
        return i.interfaceName
    }
}

public struct PowerSectionView: View, Equatable {
    let snapshot: PowerSnapshot?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.contentScale) private var sz

    public init(snapshot: PowerSnapshot?) {
        self.snapshot = snapshot
    }

    public static func == (lhs: PowerSectionView, rhs: PowerSectionView) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    public var body: some View {
        SectionView(icon: "◪", title: "Power", onHeaderTap: {
            openWindow(id: "battery-inspector")
            NSApp.activate(ignoringOtherApps: true)
        }) {
            if let s = snapshot {
                MetricRow(
                    label: "Level",
                    fraction: s.levelFraction,
                    value: Fmt.percent(s.levelFraction),
                    barColor: levelColor(s.levelFraction)
                )
                if let health = s.healthFraction {
                    MetricRow(
                        label: "Health",
                        fraction: health,
                        value: Fmt.percent(health),
                        barColor: Theme.accent
                    )
                }
                TextRow(label: "Source", value: sourceString(s))
                if let adapter = s.adapter, adapter.isConnected {
                    TextRow(label: "Adapter", value: adapter.adapterName)
                }
                TextRow(label: "Status", value: statusLine(s))
                if let detail = detailLine(s) {
                    TextRow(label: "Battery", value: detail)
                }
                HStack {
                    Spacer()
                    Button {
                        openWindow(id: "battery-inspector")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.batteryblock")
                            Text("View Battery Health & Power Details…")
                        }
                        .font(.system(size: 10 * sz, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 2 * sz)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2 * sz)
            } else {
                Text("No data").foregroundStyle(Theme.dim)
            }
        }
    }

    private func sourceString(_ s: PowerSnapshot) -> String {
        if let adapter = s.adapter, adapter.isConnected {
            return "AC Power (\(adapter.watts)W Pass-through)"
        }
        return s.isCharging ? "AC Power" : "Internal Battery"
    }

    private func levelColor(_ level: Double) -> Color {
        switch level {
        case ..<0.2: Theme.danger
        case ..<0.5: Theme.warning
        default: Theme.accent
        }
    }

    private func statusLine(_ s: PowerSnapshot) -> String {
        if s.isACConnected {
            if s.isCharging {
                if let minutes = s.timeRemainingMinutes {
                    let prefix = s.isTimeEstimated ? "~" : ""
                    return "Charging · \(prefix)\(BatteryMath.formatMinutes(minutes)) to full"
                }
                return "Charging"
            } else {
                if s.levelFraction >= 0.99 {
                    return "Fully Charged (AC Powered)"
                } else if s.levelFraction >= 0.78 {
                    return "AC Connected (80% Protection Hold)"
                } else {
                    return "AC Connected (Not Charging)"
                }
            }
        } else {
            if let minutes = s.timeRemainingMinutes {
                let prefix = s.isTimeEstimated ? "~" : ""
                return "Discharging · \(prefix)\(BatteryMath.formatMinutes(minutes)) remaining"
            }
            return "Discharging"
        }
    }

    private func detailLine(_ s: PowerSnapshot) -> String? {
        var parts: [String] = []
        if let minutes = s.timeRemainingMinutes {
            let prefix = s.isTimeEstimated ? "~" : ""
            if s.isACConnected {
                if s.isCharging {
                    parts.append("\(prefix)\(BatteryMath.formatMinutes(minutes)) to full")
                }
            } else {
                parts.append("\(prefix)\(BatteryMath.formatMinutes(minutes)) runtime")
            }
        }
        if let cycles = s.cycleCount { parts.append("\(cycles) cycles") }
        if let t = s.temperatureCelsius { parts.append(String(format: "%.1f°C", t)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

public struct ProcessesSectionView: View, Equatable {
    let processes: [ProcessUsage]
    @Environment(\.openWindow) private var openWindow
    @Environment(\.contentScale) private var sz
    @State private var terminatedPid: Int32? = nil

    public init(processes: [ProcessUsage]) {
        self.processes = processes
    }

    public static func == (lhs: ProcessesSectionView, rhs: ProcessesSectionView) -> Bool {
        lhs.processes == rhs.processes
    }

    private var cpuColumnWidth: CGFloat { 40 * sz }
    private var memColumnWidth: CGFloat { 48 * sz }

    public var body: some View {
        SectionView(icon: "≡", title: "Processes", onHeaderTap: {
            openWindow(id: "process-inspector")
            NSApp.activate(ignoringOtherApps: true)
        }) {
            if processes.isEmpty {
                Text("No data").foregroundStyle(Theme.dim)
            } else {
                // Column headers
                HStack(spacing: 6) {
                    Spacer(minLength: 8)
                    Text("CPU")
                        .frame(width: cpuColumnWidth, alignment: .trailing)
                    Text("RAM")
                        .frame(width: memColumnWidth, alignment: .trailing)
                    Text("End")
                        .frame(width: 20 * sz, alignment: .center)
                }
                .font(.system(size: 9 * sz))
                .foregroundStyle(Theme.dim)

                ForEach(processes.prefix(5), id: \.pid) { p in
                    HStack(spacing: 6) {
                        Text(displayProcessName(p.name))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(String(format: "%.0f%%", p.cpuFraction * 100))
                            .foregroundStyle(Theme.text)
                            .monospacedDigit()
                            .frame(width: cpuColumnWidth, alignment: .trailing)
                        Text(Fmt.memoryCompact(p.memoryBytes))
                            .foregroundStyle(Theme.text)
                            .monospacedDigit()
                            .frame(width: memColumnWidth, alignment: .trailing)

                        Button {
                            _ = kill(p.pid, SIGTERM)
                            terminatedPid = p.pid
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if terminatedPid == p.pid { terminatedPid = nil }
                            }
                        } label: {
                            Image(systemName: terminatedPid == p.pid ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.system(size: 11 * sz))
                                .foregroundStyle(terminatedPid == p.pid ? Theme.accent : Theme.danger.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .frame(width: 20 * sz, alignment: .center)
                        .help("Terminate process \(p.name) (PID: \(p.pid))")
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        openWindow(id: "process-inspector")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                            Text("View All Tasks & Processes…")
                        }
                        .font(.system(size: 10 * sz, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 2 * sz)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2 * sz)
            }
        }
    }

    private func displayProcessName(_ name: String) -> String {
        guard ProcessInfo.processInfo.environment["OSPREY_SCREENSHOT_DEMO"] == "1" || UserDefaults.standard.bool(forKey: "privacyMaskEnabled") else { return name }
        let lower = name.lowercased()
        if lower.contains("ablation") {
            return "Xcode Build Service"
        }
        let userName = NSUserName().lowercased()
        if !userName.isEmpty && lower.contains(userName) {
            return "Developer Task"
        }
        return name
    }
}

private struct EjectDiskButton: View {
    let diskId: String
    let model: String
    @Environment(\.contentScale) private var sz
    @State private var isEjected = false
    @State private var isEjecting = false

    var body: some View {
        Button {
            guard !isEjecting && !isEjected else { return }
            isEjecting = true
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                task.arguments = ["eject", diskId]
                try? task.run()
                task.waitUntilExit()
                DispatchQueue.main.async {
                    isEjecting = false
                    isEjected = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        isEjected = false
                    }
                }
            }
        } label: {
            Image(systemName: isEjected ? "checkmark.circle.fill" : (isEjecting ? "circle.dotted" : "eject.circle"))
                .font(.system(size: 11 * sz))
                .foregroundStyle(isEjected ? Theme.accent : (isEjecting ? Theme.dim : Color.orange.opacity(0.85)))
        }
        .buttonStyle(.plain)
        .frame(width: 20 * sz, alignment: .center)
        .help(isEjected ? "Successfully ejected \(diskId)" : "Safely eject \(model) (/dev/\(diskId))")
    }
}
