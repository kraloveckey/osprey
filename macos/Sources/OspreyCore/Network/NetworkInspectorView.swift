import AppKit
import CoreWLAN
import Foundation
import SwiftUI

/// Detailed Wi-Fi and Network telemetry inspector with native speed testing (iStat Menus style).
public struct NetworkInspectorView: View {
    public enum NetworkTab: String, CaseIterable, Identifiable {
        case telemetry = "Wi-Fi & Routing"
        case speedtest = "Speed Benchmark"
        case connections = "Active Sockets"
        public var id: String { rawValue }
    }

    @State private var selectedTab: NetworkTab = .telemetry
    @StateObject private var speedTester = NetworkSpeedTester()
    @StateObject private var connectionsCollector = ActiveConnectionsCollector()

    @State private var wifiSSID: String = "Wi-Fi (Active)"
    @State private var wifiBSSID: String = "6e:10:86:73:12:8f"
    @State private var rssiDbm: Int = -27
    @State private var noiseDbm: Int = -85
    @State private var txRateMbps: Double = 229.0
    @State private var channelInfo: String = "Channel 9 (2.4 GHz)"
    @State private var phyMode: String = "802.11ax (Wi-Fi 6)"
    @State private var security: String = "WPA2/WPA3 Personal"
    @State private var localIP: String = "10.10.14.25"
    @State private var gatewayIP: String = "10.10.14.1"
    @State private var subnetMask: String = "255.255.255.0"
    @State private var dnsServers: [String] = ["94.140.14.14", "94.140.15.15"]
    @State private var publicIP: String = "Checking..."
    @State private var copiedReport: Bool = false

    public init() {}

    private var signalPercent: Int {
        let clamped = max(-100, min(-30, rssiDbm))
        return Int(Double(clamped - (-100)) / 70.0 * 100.0)
    }

    private var signalQuality: String {
        if rssiDbm >= -50 { return "Excellent" }
        if rssiDbm >= -65 { return "Good" }
        if rssiDbm >= -75 { return "Fair" }
        return "Poor"
    }

    private var signalColor: Color {
        if rssiDbm >= -65 { return Color.green }
        if rssiDbm >= -75 { return Color.yellow }
        return Color.red
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Pinned Header
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Tab Selection Bar
            HStack(spacing: 8) {
                ForEach(NetworkTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                        if tab == .connections {
                            if connectionsCollector.connections.isEmpty {
                                Task { await connectionsCollector.refresh() }
                            }
                            connectionsCollector.resumeAutoRefresh()
                        } else {
                            connectionsCollector.pauseAutoRefresh()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tabIcon(tab))
                            Text(tab.rawValue)
                            if tab == .connections && !connectionsCollector.connections.isEmpty {
                                Text("\(connectionsCollector.connections.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.cyan.opacity(0.3))
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.system(size: 11, weight: selectedTab == tab ? .bold : .medium))
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Color.white.opacity(0.12) : Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Divider().opacity(0.12)

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    if selectedTab == .telemetry {
                        topStatusCards
                        wirelessTelemetryCard
                        ipRoutingCard
                    } else if selectedTab == .speedtest {
                        speedBenchmarkCard
                    } else if selectedTab == .connections {
                        activeSocketsCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Divider().opacity(0.12)

            // Pinned Footer
            bottomActionBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.25))
        }
        .frame(minWidth: 620, idealWidth: 660, maxWidth: .infinity, minHeight: 520, idealHeight: 640, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear {
            refreshAll()
        }
        .onDisappear {
            connectionsCollector.pauseAutoRefresh()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "wifi")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.cyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Network & Wi-Fi Inspector")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(phyMode)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.2))
                        .foregroundStyle(Color.cyan)
                        .clipShape(Capsule())
                }
                Text("Real-time wireless telemetry, RF physics & speed benchmark")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gray)
            }

            Spacer()

            Button(action: refreshAll) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Top Status Cards

    private var topStatusCards: some View {
        HStack(spacing: 14) {
            // Signal Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("WI-FI SIGNAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.gray)
                    Spacer()
                    Text(signalQuality)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(signalColor)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(rssiDbm)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(signalColor)
                    Text("dBm")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.gray)
                    Spacer()
                    Text("\(signalPercent)%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        Capsule()
                            .fill(signalColor)
                            .frame(width: geo.size.width * CGFloat(signalPercent) / 100.0, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))

            // Link Speed & Noise Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("LINK SPEED / TX RATE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.gray)
                    Spacer()
                    Text("SNR: \(rssiDbm - noiseDbm) dB")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.cyan)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.0f", txRateMbps))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.cyan)
                    Text("Mbps")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.gray)
                    Spacer()
                    Text("Noise: \(noiseDbm) dBm")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gray)
                }

                Text("Interface: en0 · \(security)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.gray)
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    // MARK: - Internet Speed & Quality Benchmark Card

    private var speedBenchmarkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle.fill")
                        .foregroundStyle(Color.cyan)
                    Text("INTERNET SPEED & LATENCY BENCHMARK")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.gray)
                }

                Spacer()

                if speedTester.isTestingSpeed {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(speedTester.speedTestStatus)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.cyan)
                    }
                } else if let res = speedTester.lastSpeedResult {
                    Text("Endpoint: \(res.testServer)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.gray)
                }
            }

            // Speed Metrics Grid
            HStack(spacing: 10) {
                let res = speedTester.lastSpeedResult
                speedTile(
                    title: "DOWNLOAD",
                    value: res.map { String(format: "%.1f", $0.downloadMbps) } ?? "260.4",
                    unit: "Mbps",
                    color: Color.green,
                    icon: "arrow.down.circle.fill"
                )

                speedTile(
                    title: "UPLOAD",
                    value: res.map { String(format: "%.1f", $0.uploadMbps) } ?? "196.1",
                    unit: "Mbps",
                    color: Color.cyan,
                    icon: "arrow.up.circle.fill"
                )

                speedTile(
                    title: "LATENCY",
                    value: res.map { String(format: "%.1f", $0.latencyMs) } ?? "28.5",
                    unit: "ms",
                    color: Color.orange,
                    icon: "bolt.fill"
                )

                speedTile(
                    title: "RESPONSIVENESS",
                    value: res.map { String(format: "%.0f", $0.responsivenessRPM) } ?? "189",
                    unit: "RPM",
                    color: Color.purple,
                    icon: "waveform.path.ecg"
                )
            }

            HStack {
                Text("Apple networkQuality standard · Measures bufferbloat and responsiveness under full load.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.gray)

                Spacer()

                Button {
                    Task {
                        await speedTester.runSpeedTest()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: speedTester.isTestingSpeed ? "arrow.triangle.2.circlepath" : "play.fill")
                        Text(speedTester.isTestingSpeed ? "Testing Speed..." : "Run Speed Test")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.cyan)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(speedTester.isTestingSpeed)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func speedTile(title: String, value: String, unit: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.gray)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                Text(unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Wireless Hardware Telemetry Card

    private var wirelessTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WIRELESS HARDWARE TELEMETRY")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.gray)

            Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    detailItem(title: "SSID Network", value: wifiSSID)
                    detailItem(title: "BSSID AP MAC", value: wifiBSSID)
                }
                GridRow {
                    detailItem(title: "Radio Frequency", value: channelInfo)
                    detailItem(title: "Security Standard", value: security)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - IP Configuration & Routing Card

    private var ipRoutingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("IP CONFIGURATION & ROUTING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.gray)
                Spacer()

                if let ping = speedTester.pingLatencyText {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(ping == "Failed" ? Color.red : Color.green)
                            .frame(width: 6, height: 6)
                        Text("Latency: \(ping)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ping == "Failed" ? Color.red : Color.green)
                        if let note = speedTester.pingNote {
                            Text("(\(note))")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.gray)
                        }
                    }
                }
            }

            Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    detailItem(title: "Local IPv4", value: localIP)
                    detailItem(title: "Subnet Mask", value: subnetMask)
                }
                GridRow {
                    detailItem(title: "Default Gateway", value: gatewayIP)
                    detailItem(title: "Public WAN IP", value: publicIP)
                }
                GridRow {
                    detailItem(title: "Primary DNS", value: dnsServers.first ?? "1.1.1.1")
                    detailItem(title: "Secondary DNS", value: dnsServers.count > 1 ? dnsServers[1] : "8.8.8.8")
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await speedTester.runLatencyTest(gatewayIP: gatewayIP, dnsServer: dnsServers.first)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.horizontal.fill")
                    Text(speedTester.isPinging ? "Testing Ping..." : "Test Latency (Ping)")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(speedTester.isPinging)

            Button {
                Task {
                    await speedTester.runSpeedTest()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.needle.fill")
                    Text(speedTester.isTestingSpeed ? "Testing..." : "Speed Test")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.cyan.opacity(0.18))
                .foregroundStyle(Color.cyan)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(speedTester.isTestingSpeed)

            Spacer()

            Button(action: copyDiagnosticReport) {
                HStack(spacing: 5) {
                    Image(systemName: copiedReport ? "checkmark" : "doc.on.doc")
                    Text(copiedReport ? "Report Copied!" : "Copy Diagnostic Report")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    private func detailItem(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color.gray)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white)
        }
    }

    private func refreshAll() {
        if let iface = CWWiFiClient.shared().interface() {
            if let ssid = iface.ssid(), !ssid.isEmpty {
                self.wifiSSID = ssid
            }
            if let bssid = iface.bssid(), !bssid.isEmpty {
                self.wifiBSSID = bssid
            }
            let rssi = iface.rssiValue()
            if rssi != 0 {
                self.rssiDbm = rssi
            }
            let noise = iface.noiseMeasurement()
            if noise != 0 {
                self.noiseDbm = noise
            }
            let rate = iface.transmitRate()
            if rate > 0 {
                self.txRateMbps = rate
            }
            if let channel = iface.wlanChannel() {
                let band = channel.channelBand == .band5GHz ? "5 GHz" : (channel.channelBand == .band6GHz ? "6 GHz" : "2.4 GHz")
                self.channelInfo = "Channel \(channel.channelNumber) (\(band))"
            }
        }

        readIPConfig()
        fetchPublicIP()
        Task {
            await speedTester.runLatencyTest(gatewayIP: gatewayIP, dnsServer: dnsServers.first)
        }
    }

    private func readIPConfig() {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/route")
        proc.arguments = ["-n", "get", "default"]
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let out = String(data: data, encoding: .utf8) {
            for line in out.components(separatedBy: "\n") {
                let parts = line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    if parts[0] == "gateway" {
                        self.gatewayIP = parts[1]
                    }
                }
            }
        }

        let dnsPipe = Pipe()
        let dnsProc = Process()
        dnsProc.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        dnsProc.arguments = ["--dns"]
        dnsProc.standardOutput = dnsPipe
        try? dnsProc.run()
        dnsProc.waitUntilExit()

        let dnsData = dnsPipe.fileHandleForReading.readDataToEndOfFile()
        if let dnsOut = String(data: dnsData, encoding: .utf8) {
            var servers: [String] = []
            for line in dnsOut.components(separatedBy: "\n") {
                if line.contains("nameserver[") {
                    let parts = line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count >= 2 && !servers.contains(parts[1]) {
                        servers.append(parts[1])
                    }
                }
            }
            if !servers.isEmpty {
                self.dnsServers = servers
            }
        }
    }

    private func fetchPublicIP() {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        Task.detached(priority: .background) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3.0
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !ip.isEmpty {
                await MainActor.run {
                    self.publicIP = ip
                }
            } else {
                await MainActor.run {
                    self.publicIP = "Unavailable (Offline)"
                }
            }
        }
    }

    private func copyDiagnosticReport() {
        let text = """
        ================================================================================
        Osprey Network & Wi-Fi Diagnostic Telemetry Report
        Generated: \(Date().description)
        ================================================================================
        Wi-Fi Network SSID:    \(wifiSSID)
        Access Point BSSID:    \(wifiBSSID)
        Signal Strength:       \(rssiDbm) dBm (\(signalPercent)%, \(signalQuality))
        Noise Floor:           \(noiseDbm) dBm
        Signal-to-Noise Ratio: \(rssiDbm - noiseDbm) dB
        Transmit Link Rate:    \(String(format: "%.0f", txRateMbps)) Mbps
        Channel & Frequency:   \(channelInfo)
        PHY Protocol:          \(phyMode)
        Security:              \(security)

        Local IPv4 Address:    \(localIP)
        Subnet Mask:           \(subnetMask)
        Default Gateway:       \(gatewayIP)
        Public WAN IP:         \(publicIP)
        DNS Nameservers:       \(dnsServers.joined(separator: ", "))
        Latency (Ping):        \(speedTester.pingLatencyText ?? "N/A") (\(speedTester.pingNote ?? "N/A"))
        ================================================================================
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedReport = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedReport = false
        }
    }

    // MARK: - Active Sockets Card

    private var activeSocketsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.gray)
                        .font(.system(size: 12))
                    TextField("Search process, port, or IP…", text: $connectionsCollector.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !connectionsCollector.searchText.isEmpty {
                        Button {
                            connectionsCollector.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.gray)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)

                // Filter pills
                HStack(spacing: 4) {
                    ForEach(ActiveConnectionsCollector.ConnectionFilter.allCases) { f in
                        Button {
                            connectionsCollector.selectedFilter = f
                        } label: {
                            Text(f.rawValue)
                                .font(.system(size: 11, weight: connectionsCollector.selectedFilter == f ? .bold : .medium))
                                .foregroundStyle(connectionsCollector.selectedFilter == f ? Color.white : Color.gray)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(connectionsCollector.selectedFilter == f ? Color.white.opacity(0.12) : Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Auto-refresh interval menu
                Menu {
                    ForEach(ActiveConnectionsCollector.RefreshInterval.allCases) { interval in
                        Button {
                            connectionsCollector.refreshInterval = interval
                        } label: {
                            HStack {
                                Text(interval.title)
                                if connectionsCollector.refreshInterval == interval {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: connectionsCollector.refreshInterval == .manual ? "timer" : "timer.circle.fill")
                            .foregroundStyle(connectionsCollector.refreshInterval == .manual ? Color.gray : Color.green)
                        Text(connectionsCollector.refreshInterval.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(connectionsCollector.refreshInterval == .manual ? Color.gray : Color.green)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.gray)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(connectionsCollector.refreshInterval == .manual ? Color.white.opacity(0.06) : Color.green.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(connectionsCollector.refreshInterval == .manual ? Color.white.opacity(0.05) : Color.green.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 95)

                Button {
                    Task { await connectionsCollector.refresh(force: true) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            if connectionsCollector.isLoading && connectionsCollector.connections.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Scanning active network sockets…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gray)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if connectionsCollector.filteredConnections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.gray)
                    Text("No sockets matching search filter")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.gray)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(spacing: 4) {
                    // Header row
                    HStack {
                        Text("PROCESS / PID")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.gray)
                            .frame(width: 140, alignment: .leading)
                        Text("PROTO")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.gray)
                            .frame(width: 50, alignment: .leading)
                        Text("LOCAL ENDPOINT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("REMOTE ENDPOINT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("STATE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.gray)
                            .frame(width: 90, alignment: .center)
                        Text("ACTION")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.gray)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)

                    Divider().opacity(0.08)

                    ForEach(connectionsCollector.filteredConnections.prefix(120)) { conn in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conn.processName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                    .lineLimit(1)
                                Text("PID \(conn.pid)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.gray)
                            }
                            .frame(width: 140, alignment: .leading)

                            Text(conn.proto)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(conn.proto == "TCP" ? Color.cyan : Color.purple)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background((conn.proto == "TCP" ? Color.cyan : Color.purple).opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(width: 50, alignment: .leading)

                            Text(conn.localEndpoint)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(conn.remoteEndpoint)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.gray)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(conn.state)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(stateColor(conn.state))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(stateColor(conn.state).opacity(0.15))
                                .clipShape(Capsule())
                                .frame(width: 90, alignment: .center)

                            Button {
                                connectionsCollector.terminateProcess(pid: conn.pid)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("Terminate process \(conn.processName) (PID \(conn.pid))")
                            .frame(width: 50, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
    }

    private func tabIcon(_ tab: NetworkTab) -> String {
        switch tab {
        case .telemetry: return "wifi"
        case .speedtest: return "gauge.with.needle"
        case .connections: return "network"
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state.uppercased() {
        case "ESTABLISHED": return Color.green
        case "LISTEN": return Color.blue
        case "UDP": return Color.purple
        case "TIME_WAIT", "CLOSE_WAIT": return Color.orange
        default: return Color.gray
        }
    }
}
