import Darwin
import Foundation
import UserNotifications

public struct AdvisorySnapshot: Sendable {
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let swapUsedFormatted: String
    public let uptimeDays: Double
    public let uptimeFormatted: String
    public let shouldReboot: Bool
    public let level: String // "optimal", "warning", "critical"
    public let score: Int
    public let summary: String
    public let triggers: [String]

    public init(
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64,
        swapUsedFormatted: String,
        uptimeDays: Double,
        uptimeFormatted: String,
        shouldReboot: Bool,
        level: String,
        score: Int,
        summary: String,
        triggers: [String]
    ) {
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedFormatted = swapUsedFormatted
        self.uptimeDays = uptimeDays
        self.uptimeFormatted = uptimeFormatted
        self.shouldReboot = shouldReboot
        self.level = level
        self.score = score
        self.summary = summary
        self.triggers = triggers
    }
}

public final class AdvisoryCollector: @unchecked Sendable {
    public init() {}

    public func sample() -> AdvisorySnapshot {
        // 1. Swap Usage via sysctl vm.swapusage
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var swapUsedBytes: UInt64 = 0
        var swapTotalBytes: UInt64 = 0

        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            swapUsedBytes = UInt64(swap.xsu_used)
            swapTotalBytes = UInt64(swap.xsu_total)
        }

        // 2. System Uptime via sysctl kern.boottime
        var bootTime = timeval()
        var bootSize = MemoryLayout<timeval>.size
        var uptimeSecs: Double = 0

        if sysctlbyname("kern.boottime", &bootTime, &bootSize, nil, 0) == 0 {
            let now = Date().timeIntervalSince1970
            uptimeSecs = max(0, now - Double(bootTime.tv_sec))
        }

        let uptimeDays = uptimeSecs / 86400.0
        let days = Int(uptimeDays)
        let hours = Int((uptimeSecs.truncatingRemainder(dividingBy: 86400.0)) / 3600.0)
        let uptimeFormatted = "\(days)d \(hours)h"

        let swapGB = Double(swapUsedBytes) / 1_073_741_824.0
        let swapUsedFormatted = String(format: "%.1f GB", swapGB)

        var triggers: [String] = []
        var score: Int = 100
        var level = "optimal"
        var shouldReboot = false

        // Triggers evaluation
        if swapGB >= 12.0 {
            triggers.append("Excessive SSD swap paging (\(swapUsedFormatted) active)")
            score -= 40
            level = "critical"
            shouldReboot = true
        } else if swapGB >= 8.0 {
            triggers.append("Heavy memory pressure & swap accumulation (\(swapUsedFormatted))")
            score -= 25
            if level != "critical" { level = "warning" }
            shouldReboot = true
        } else if swapGB >= 4.0 {
            triggers.append("Moderate swap usage (\(swapUsedFormatted))")
            score -= 10
            if level == "optimal" { level = "warning" }
        }

        if uptimeDays >= 14.0 {
            triggers.append("Prolonged kernel uptime (\(days) days without restart)")
            score -= 20
            if level != "critical" { level = "warning" }
            shouldReboot = true
        } else if uptimeDays >= 7.0 {
            triggers.append("Elevated kernel uptime (\(days) days)")
            score -= 10
        }

        score = max(0, min(100, score))

        let summary: String
        if level == "critical" {
            summary = "Reboot Recommended: High SSD swap wear (\(swapUsedFormatted)) after \(uptimeFormatted) uptime."
        } else if level == "warning" {
            summary = "Advisory: Elevated swap accumulation (\(swapUsedFormatted)). Consider restarting soon."
        } else {
            summary = "All systems optimal. Memory and kernel caches operating normally."
        }

        return AdvisorySnapshot(
            swapUsedBytes: swapUsedBytes,
            swapTotalBytes: swapTotalBytes,
            swapUsedFormatted: swapUsedFormatted,
            uptimeDays: uptimeDays,
            uptimeFormatted: uptimeFormatted,
            shouldReboot: shouldReboot,
            level: level,
            score: score,
            summary: summary,
            triggers: triggers
        )
    }

    public static func sendNativeNotification(title: String = "Osprey Advisory", body: String) {
        guard !UserDefaults.standard.bool(forKey: "dndSilenceAlerts") else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "osprey-advisory-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request, withCompletionHandler: nil)
        }
    }
}
