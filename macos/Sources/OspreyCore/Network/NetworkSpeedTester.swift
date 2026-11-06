import Foundation

/// Result of an Apple networkQuality speed and bufferbloat test.
public struct SpeedTestResult: Codable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let latencyMs: Double
    public let responsivenessRPM: Double
    public let testServer: String
    public let timestamp: Date

    public var responsivenessGrade: String {
        if responsivenessRPM >= 400 { return "Ultra-Responsive" }
        if responsivenessRPM >= 200 { return "High Quality" }
        if responsivenessRPM >= 100 { return "Medium" }
        return "Bufferbloat Prone"
    }
}

/// Executes network latency pings and high-speed throughput benchmarks.
@MainActor
public final class NetworkSpeedTester: ObservableObject {
    @Published public var isTestingSpeed: Bool = false
    @Published public var isPinging: Bool = false
    @Published public var lastSpeedResult: SpeedTestResult? = nil
    @Published public var pingLatencyText: String? = nil
    @Published public var pingNote: String? = nil
    @Published public var speedTestStatus: String = ""

    public init() {}

    // MARK: - Multi-Tier Ping Latency Test

    public func runLatencyTest(gatewayIP: String, dnsServer: String?) async {
        guard !isPinging else { return }
        self.isPinging = true
        self.pingLatencyText = "Measuring..."
        self.pingNote = nil

        let result = await Task.detached(priority: .userInitiated) { () -> (Double, String) in
            // 1. Try Gateway ICMP
            let cleanGW = gatewayIP.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanGW.isEmpty && cleanGW != "Detecting..." {
                if let gwPing = Self.pingHost(cleanGW, timeoutSec: 1) {
                    return (gwPing, "Direct Gateway (\(cleanGW))")
                }
            }

            // 2. Try Primary DNS or Cloudflare 1.1.1.1
            let dnsTarget = (dnsServer?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "1.1.1.1"
            if let dnsPing = Self.pingHost(dnsTarget, timeoutSec: 1) {
                return (dnsPing, "DNS \(dnsTarget) · Gateway ICMP Filtered")
            }

            // 3. Try Google 8.8.8.8
            if let gPing = Self.pingHost("8.8.8.8", timeoutSec: 1) {
                return (gPing, "DNS 8.8.8.8 · Local ICMP Filtered")
            }

            // 4. Fallback: HTTP/2 RTT to Apple / Cloudflare
            let start = DispatchTime.now()
            if let url = URL(string: "https://www.apple.com"),
               let (_, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                let end = DispatchTime.now()
                let ms = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
                return (ms, "HTTP/2 CDN Handshake")
            }

            return (0.0, "Network Offline or Blocked")
        }.value

        if result.0 > 0 {
            self.pingLatencyText = String(format: "%.1f ms", result.0)
            self.pingNote = result.1
        } else {
            self.pingLatencyText = "Failed"
            self.pingNote = result.1
        }
        self.isPinging = false
    }

    // MARK: - Native Apple networkQuality Speedtest

    public func runSpeedTest() async {
        guard !isTestingSpeed else { return }
        self.isTestingSpeed = true
        self.speedTestStatus = "Measuring download, upload & bufferbloat..."

        let res = await Task.detached(priority: .userInitiated) { () -> SpeedTestResult? in
            let path = "/usr/bin/networkQuality"
            guard FileManager.default.isExecutableFile(atPath: path) else {
                return nil
            }

            let pipe = Pipe()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            // Limit to 6 seconds for fast responsive UX
            proc.arguments = ["-c", "-M", "6"]
            proc.standardOutput = pipe

            do {
                try proc.run()
                proc.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }

                let dlBps = (json["dl_throughput"] as? Double) ?? 0.0
                let ulBps = (json["ul_throughput"] as? Double) ?? 0.0
                let rttMs = (json["base_rtt"] as? Double) ?? 0.0
                let respRPM = (json["responsiveness"] as? Double) ?? 0.0
                let endpoint = (json["test_endpoint"] as? String) ?? "Apple Edge CDN"

                return SpeedTestResult(
                    downloadMbps: dlBps / 1_000_000.0,
                    uploadMbps: ulBps / 1_000_000.0,
                    latencyMs: rttMs,
                    responsivenessRPM: respRPM,
                    testServer: endpoint,
                    timestamp: Date()
                )
            } catch {
                return nil
            }
        }.value

        if let res {
            self.lastSpeedResult = res
            self.speedTestStatus = "Test Complete"
        } else {
            self.speedTestStatus = "Speed test unavailable"
        }
        self.isTestingSpeed = false
    }

    // MARK: - Internal Ping Runner

    nonisolated private static func pingHost(_ host: String, timeoutSec: Int) -> Double? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ping")
        proc.arguments = ["-c", "1", "-t", "\(timeoutSec)", host]
        proc.standardOutput = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let out = String(data: data, encoding: .utf8) else { return nil }

            if let range = out.range(of: "time=") {
                let sub = out[range.upperBound...]
                if let end = sub.range(of: " ms") {
                    return Double(sub[..<end.lowerBound].trimmingCharacters(in: .whitespaces))
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
