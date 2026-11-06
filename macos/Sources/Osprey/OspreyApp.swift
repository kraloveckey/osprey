import AppKit
import Combine
import OspreyCore
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct OspreyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(WidgetSettings.positionLockedKey) private var positionLocked = false
    @AppStorage(WidgetSettings.widgetVisibleKey) private var widgetVisible = true
    @AppStorage(WidgetSettings.alwaysOnTopKey) private var alwaysOnTop = false
    @AppStorage(WidgetSettings.widgetColumnsKey) private var widgetColumns = WidgetSettings.defaultColumns
    @AppStorage(WidgetSettings.widgetWidthKey) private var widgetWidth = WidgetSettings.defaultWidth
    @AppStorage(WidgetSettings.widgetScaleKey) private var widgetScale = WidgetSettings.defaultScale

    // Settings: opacity
    @AppStorage(WidgetSettings.backgroundOpacityKey)
    private var backgroundOpacity = WidgetSettings.defaultOpacity

    // Settings: refresh rate
    @AppStorage(WidgetSettings.refreshIntervalKey)
    private var refreshInterval = WidgetSettings.defaultRefreshInterval

    // Settings: font
    @AppStorage(WidgetSettings.fontSizeKey)
    private var fontSize = WidgetSettings.defaultFontSize
    @AppStorage(WidgetSettings.fontStyleKey)
    private var fontStyle = WidgetSettings.defaultFontStyle.rawValue

    // Settings: menu bar metrics
    @AppStorage(WidgetSettings.menuBarShowCPUKey)     private var menuBarShowCPU     = WidgetSettings.defaultMenuBarShowCPU
    @AppStorage(WidgetSettings.menuBarShowMemoryKey)  private var menuBarShowMemory  = WidgetSettings.defaultMenuBarShowMemory
    @AppStorage(WidgetSettings.menuBarShowTempKey)    private var menuBarShowTemp    = WidgetSettings.defaultMenuBarShowTemp
    @AppStorage(WidgetSettings.menuBarShowNetworkKey) private var menuBarShowNetwork = WidgetSettings.defaultMenuBarShowNetwork
    @AppStorage(WidgetSettings.menuBarShowDiskKey)    private var menuBarShowDisk    = WidgetSettings.defaultMenuBarShowDisk

    // Settings: section visibility
    @AppStorage(WidgetSettings.showHeaderKey)    private var showHeader    = true
    @AppStorage(WidgetSettings.showCPUKey)       private var showCPU       = true
    @AppStorage(WidgetSettings.showMemoryKey)    private var showMemory    = true
    @AppStorage(WidgetSettings.showDiskKey)      private var showDisk      = true
    @AppStorage(WidgetSettings.showPowerKey)     private var showPower     = true
    @AppStorage(WidgetSettings.showNetworkKey)   private var showNetwork   = true
    @AppStorage(WidgetSettings.showProcessesKey) private var showProcesses = true
    @AppStorage(WidgetSettings.autoCheckUpdatesKey) private var autoCheckUpdates = WidgetSettings.defaultAutoCheckUpdates
    @AppStorage(WidgetSettings.batterySaverModeKey) private var batterySaverMode = WidgetSettings.defaultBatterySaverMode

    @State private var availableUpdateVersion: String? = nil

    /// Monochrome template glyph: stylized Osprey falcon wings silhouette.
    /// macOS automatically tints template images for light/dark menu bars.
    private static let menuBarIcon: NSImage = {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            // Falcon wings and body silhouette
            path.move(to: NSPoint(x: 1, y: 11))
            path.curve(to: NSPoint(x: 9, y: 15), controlPoint1: NSPoint(x: 4, y: 14), controlPoint2: NSPoint(x: 7, y: 15))
            path.curve(to: NSPoint(x: 17, y: 11), controlPoint1: NSPoint(x: 11, y: 15), controlPoint2: NSPoint(x: 14, y: 14))
            path.curve(to: NSPoint(x: 12, y: 6), controlPoint1: NSPoint(x: 15, y: 9), controlPoint2: NSPoint(x: 13, y: 7))
            path.curve(to: NSPoint(x: 9, y: 1), controlPoint1: NSPoint(x: 11, y: 4), controlPoint2: NSPoint(x: 9.5, y: 2))
            path.curve(to: NSPoint(x: 6, y: 6), controlPoint1: NSPoint(x: 8.5, y: 2), controlPoint2: NSPoint(x: 7, y: 4))
            path.curve(to: NSPoint(x: 1, y: 11), controlPoint1: NSPoint(x: 5, y: 7), controlPoint2: NSPoint(x: 3, y: 9))
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            if let newVer = availableUpdateVersion {
                OpenUpdateAvailableButton(version: newVer)
                Divider()
            }

            if let adv = appDelegate.store.advisory {
                if adv.shouldReboot {
                    Button {
                        promptRebootAlert(advisory: adv)
                    } label: {
                        // MenuBarExtra can discard a Label's SF Symbol when it
                        // bridges the button into an NSMenuItem. Keep the warning
                        // glyph in the title so it is always visible.
                        Text("⚠️ Reboot Recommended (\(adv.swapUsedFormatted) Swap)")
                    }
                } else {
                    Button {
                        AdvisoryCollector.sendNativeNotification(
                            title: "Osprey Telemetry",
                            body: "All systems running optimally. Swap: \(adv.swapUsedFormatted)."
                        )
                    } label: {
                        Label("System State: Optimal (\(adv.uptimeFormatted))", systemImage: "checkmark.circle.fill")
                    }
                }
            }
            if let power = appDelegate.store.power {
                OpenBatteryInspectorMenuButton(power: power)
            }
            if let drives = appDelegate.store.smart?.drives, !drives.isEmpty {
                ForEach(drives) { drive in
                    OpenSmartInspectorDriveButton(drive: drive)
                }
            } else if let drive = appDelegate.store.smart?.primaryDrive {
                OpenSmartInspectorDriveButton(drive: drive)
            }

            Divider()

            Toggle("Lock position", isOn: $positionLocked)
            Toggle("Pin on top of other windows", isOn: Binding(
                get: { widgetVisible && alwaysOnTop },
                set: { newVal in
                    alwaysOnTop = newVal
                    if newVal {
                        widgetVisible = true
                    }
                }
            ))
            Toggle("Show on desktop", isOn: Binding(
                get: { widgetVisible },
                set: { newVal in
                    widgetVisible = newVal
                    if !newVal {
                        alwaysOnTop = false
                    }
                }
            ))

            Divider()

            // System & Hardware Inspectors (Alphabetical)
            OpenBatteryInspectorButton()
            OpenNetworkInspectorButton()
            OpenProcessInspectorButton()
            OpenSmartInspectorButton()
            OpenThermalInspectorButton()
            OpenUsageHistoryButton()

            Divider()

            // System Maintenance & Cleaning (Alphabetical)
            Button("Activity Monitor") {
                AppLauncher.openActivityMonitor()
            }
            OpenDiskCleanerButton()
            OpenPurgeMemoryButton()

            Divider()

            Menu("Settings") {
                OpenAlertSettingsButton()
                Toggle("Battery saver mode", isOn: $batterySaverMode)
                Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
                Picker("Font size", selection: $fontSize) {
                    Text("Small").tag(11.0)
                    Text("Medium").tag(12.0)
                    Text("Large").tag(14.0)
                    Text("Extra Large").tag(16.0)
                }
                Picker("Widget zoom", selection: Binding<Double>(
                    get: { widgetScale },
                    set: { newScale in
                        let oldScale = widgetScale
                        widgetScale = newScale
                        let ratio = newScale / max(0.1, oldScale)
                        widgetWidth = WidgetSettings.clampWidth(widgetWidth * ratio, columns: widgetColumns, scale: newScale)
                    }
                )) {
                    Text("75%").tag(0.75)
                    Text("85%").tag(0.85)
                    Text("90%").tag(0.90)
                    Text("100% (Default)").tag(1.00)
                    Text("110%").tag(1.10)
                    Text("120%").tag(1.20)
                    Text("125%").tag(1.25)
                }
                Picker("Font style", selection: $fontStyle) {
                    Text("Monospaced").tag(WidgetSettings.FontStyle.monospaced.rawValue)
                    Text("System").tag(WidgetSettings.FontStyle.system.rawValue)
                }
                Picker("Widget layout", selection: Binding(
                    get: { widgetColumns },
                    set: { newCols in
                        widgetColumns = newCols
                        if newCols == 3 && widgetWidth < 920 {
                            widgetWidth = WidgetSettings.defaultWideWidth
                        } else if newCols == 2 && widgetWidth > 820 {
                            widgetWidth = WidgetSettings.defaultWidth
                        }
                    }
                )) {
                    Text("2 Columns (Standard 2×3)").tag(2)
                    Text("3 Columns (Wide 3×2)").tag(3)
                }
                LaunchAtLoginToggle()
                Menu("Menu bar metrics") {
                    Toggle("CPU",             isOn: $menuBarShowCPU)
                    Toggle("CPU temperature", isOn: $menuBarShowTemp)
                    Toggle("Disk",            isOn: $menuBarShowDisk)
                    Toggle("Memory",          isOn: $menuBarShowMemory)
                    Toggle("Network",         isOn: $menuBarShowNetwork)
                }
                Picker("Opacity", selection: $backgroundOpacity) {
                    Text("100%").tag(1.0)
                    Text("92%").tag(0.92)
                    Text("85%").tag(0.85)
                    Text("70%").tag(0.7)
                }
                Picker("Refresh rate", selection: $refreshInterval) {
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("5 s").tag(5.0)
                }
                Menu("Widget sections") {
                    Toggle("CPU",       isOn: $showCPU)
                    Toggle("Disk",      isOn: $showDisk)
                    Toggle("Header",    isOn: $showHeader)
                    Toggle("Memory",    isOn: $showMemory)
                    Toggle("Network",   isOn: $showNetwork)
                    Toggle("Power",     isOn: $showPower)
                    Toggle("Processes", isOn: $showProcesses)
                }
            }

            Divider()

            OpenSoftwareUpdateButton()
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OspreyNewUpdateDetected"))) { notif in
                    if let ver = notif.object as? String {
                        self.availableUpdateVersion = ver
                    }
                }
            Button("Report an Issue…") {
                NSWorkspace.shared.open(UpdateChecker.issuesPageURL)
            }
            Button("Osprey \(CoreInfo.version) – GitHub") {
                NSWorkspace.shared.open(UpdateChecker.repoPageURL)
            }

            Divider()

            Button("Quit Osprey") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            MenuBarLabel(store: appDelegate.store, icon: Self.menuBarIcon)
        }

        Window("Storage Health & S.M.A.R.T. Inspector", id: "smart-inspector") {
            SMARTInspectorView(store: appDelegate.store)
        }
        .defaultSize(width: 780, height: 600)

        Window("Network & Wi-Fi Inspector", id: "network-inspector") {
            NetworkInspectorView()
        }
        .defaultSize(width: 580, height: 480)

        Window("Thermal Sensors & Cooling", id: "thermal-inspector") {
            ThermalInspectorView(store: appDelegate.store)
        }
        .defaultSize(width: 640, height: 490)

        Window("Disk Space & Cache Cleaner", id: "disk-cleaner") {
            DiskSpaceAnalyzerView(store: appDelegate.store)
        }
        .defaultSize(width: 640, height: 600)

        Window("Battery Health & Power Telemetry", id: "battery-inspector") {
            BatteryInspectorView(store: appDelegate.store)
        }
        .defaultSize(width: 720, height: 640)

        Window("Alert Channels & Thresholds", id: "alert-settings") {
            AlertSettingsView()
        }
        .defaultSize(width: 620, height: 640)

        Window("Usage History", id: "usage-history") {
            UsageHistoryView(history: appDelegate.usageHistory)
        }
        .defaultSize(width: 640, height: 420)

        Window("Software Update", id: "software-update") {
            UpdateView()
        }
        .defaultSize(width: 600, height: 540)

        Window("Process Activity & Task Manager", id: "process-inspector") {
            ProcessInspectorView(store: appDelegate.store)
        }
        .defaultSize(width: 740, height: 540)
    }
}

/// Alert button in menu bar dropdown when a software update is available.
private struct OpenUpdateAvailableButton: View {
    let version: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("✨ New Update Available: v\(version)") {
            openWindow(id: "software-update")
            activateWindow(titlePrefix: "Software Update")
            NotificationCenter.default.post(name: NSNotification.Name("TriggerCheckForUpdates"), object: nil)
        }
    }
}

/// Opens the Software Update window.
private struct OpenSoftwareUpdateButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Check for Updates…") {
            openWindow(id: "software-update")
            activateWindow(titlePrefix: "Software Update")
            NotificationCenter.default.post(name: NSNotification.Name("TriggerCheckForUpdates"), object: nil)
        }
    }
}

/// Helper to ensure only the target inspector window comes to front
private func activateWindow(titlePrefix: String) {
    if NSApp.activationPolicy() != .regular {
        NSApp.setActivationPolicy(.regular)
    }
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        if let win = NSApp.windows.first(where: { !($0 is DesktopWindow) && $0.title.hasPrefix(titlePrefix) }) {
            win.makeKeyAndOrderFront(nil)
        }
    }
}

private func promptRebootAlert(advisory: AdvisorySnapshot) {
    let alert = NSAlert()
    alert.messageText = "Reboot Recommended to Protect SSD Lifespan"
    alert.informativeText = "Your Mac has accumulated \(advisory.swapUsedFormatted) of swap memory after \(advisory.uptimeFormatted) of uptime.\n\nHeavy swap paging causes continuous NAND write cycles on your internal SSD and degrades system responsiveness.\n\nWould you like to restart your Mac now, or open Activity Monitor to inspect memory hogs?"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Restart Mac Now")
    alert.addButton(withTitle: "Open Activity Monitor")
    alert.addButton(withTitle: "Dismiss")

    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        let script = "tell application \"System Events\" to restart"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    } else if response == .alertSecondButtonReturn {
        AppLauncher.openActivityMonitor()
    }
}

/// Opens the Storage S.M.A.R.T. Inspector window when clicking the drive in menu bar.
private struct OpenSmartInspectorDriveButton: View {
    let drive: SMARTDriveInfo
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("💾 \(drive.model): \(drive.healthStatus) \(drive.healthPercent)% · \(drive.temperatureC)°C") {
            openWindow(id: "smart-inspector")
            NotificationCenter.default.post(name: NSNotification.Name("SelectSMARTDrive"), object: drive.diskId)
            activateWindow(titlePrefix: "Storage Health")
        }
    }
}

/// Opens the Battery Inspector window when clicking battery status in the menu bar.
private struct OpenBatteryInspectorMenuButton: View {
    let power: PowerSnapshot
    @Environment(\.openWindow) private var openWindow

    private var labelText: String {
        let percent = Int(round(power.levelFraction * 100))
        let icon: String = power.isCharging ? "⚡️" : (power.isACConnected ? "🔌" : "🔋")
        let status: String
        if power.isACConnected {
            status = power.isCharging ? "Charging" : "AC Connected (Hold)"
        } else {
            if let mins = power.timeRemainingMinutes, mins > 0 {
                let prefix = power.isTimeEstimated ? "~" : ""
                status = "\(prefix)\(BatteryMath.formatMinutes(mins)) left"
            } else {
                status = "Discharging"
            }
        }
        let tempStr = power.temperatureCelsius.map { String(format: "%.0f°C", $0) } ?? "29°C"
        let healthStr = power.healthFraction.map { Fmt.percent($0) } ?? "100%"

        return "\(icon) Battery: \(percent)% · \(status) · \(healthStr) Health · \(tempStr)"
    }

    var body: some View {
        Button(labelText) {
            openWindow(id: "battery-inspector")
            activateWindow(titlePrefix: "Battery Health")
        }
    }
}

/// Triggers 1-click RAM reclamation.
private struct OpenPurgeMemoryButton: View {
    @State private var isPurging = false

    var body: some View {
        Button(isPurging ? "Purging Inactive Memory..." : "Purge Inactive RAM…") {
            isPurging = true
            Task {
                let res = await MemoryCleaner.reclaimRAM()
                await MainActor.run {
                    isPurging = false
                    let freedMB = Double(res.reclaimedBytes) / (1024.0 * 1024.0)
                    AdvisoryCollector.sendNativeNotification(
                        title: "RAM Reclaimed Successfully",
                        body: String(format: "Freed %.0f MB of inactive file caches and memory buffers.", freedMB)
                    )
                }
            }
        }
        .disabled(isPurging)
    }
}

/// Opens the Process Activity & Task Manager window.
private struct OpenProcessInspectorButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Process Activity & Task Manager…") {
            openWindow(id: "process-inspector")
            activateWindow(titlePrefix: "Process Activity")
        }
    }
}

/// Opens the Network & Wi-Fi Inspector window.
private struct OpenNetworkInspectorButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Network & Wi-Fi Inspector…") {
            openWindow(id: "network-inspector")
            activateWindow(titlePrefix: "Network")
        }
    }
}

/// Opens the Thermal Sensors & Cooling window.
private struct OpenThermalInspectorButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Thermal Sensors & Cooling…") {
            openWindow(id: "thermal-inspector")
            activateWindow(titlePrefix: "Thermal Sensors")
        }
    }
}

/// Opens the Disk Space & Cache Cleaner window.
private struct OpenDiskCleanerButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Disk Space & Cache Cleaner…") {
            openWindow(id: "disk-cleaner")
            activateWindow(titlePrefix: "Disk Space")
        }
    }
}

/// Opens the Storage S.M.A.R.T. Inspector window.
private struct OpenSmartInspectorButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Storage SMART Inspector…") {
            openWindow(id: "smart-inspector")
            activateWindow(titlePrefix: "Storage Health")
        }
    }
}

/// Opens the Battery Health & Power Telemetry Inspector window.
private struct OpenBatteryInspectorButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Battery & Power Inspector…") {
            openWindow(id: "battery-inspector")
            activateWindow(titlePrefix: "Battery Health")
        }
    }
}

/// Opens the Alert Channels & Webhooks window.
private struct OpenAlertSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Alert Settings…") {
            openWindow(id: "alert-settings")
            activateWindow(titlePrefix: "Alert Channels")
        }
    }
}

/// Opens the Usage History window.
private struct OpenUsageHistoryButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Usage History…") {
            openWindow(id: "usage-history")
            activateWindow(titlePrefix: "Usage History")
        }
    }
}


/// Menu bar label: shows live metric text when any metric toggle is on and
/// data is available, otherwise the static template icon.
private struct MenuBarLabel: View {
    let store: MetricsStore
    let icon: NSImage

    @AppStorage(WidgetSettings.menuBarShowCPUKey)     private var showCPU     = WidgetSettings.defaultMenuBarShowCPU
    @AppStorage(WidgetSettings.menuBarShowMemoryKey)  private var showMemory  = WidgetSettings.defaultMenuBarShowMemory
    @AppStorage(WidgetSettings.menuBarShowTempKey)    private var showTemp    = WidgetSettings.defaultMenuBarShowTemp
    @AppStorage(WidgetSettings.menuBarShowNetworkKey) private var showNetwork = WidgetSettings.defaultMenuBarShowNetwork
    @AppStorage(WidgetSettings.menuBarShowDiskKey)    private var showDisk    = WidgetSettings.defaultMenuBarShowDisk

    var body: some View {
        let values = MenuBarValues(
            cpuFraction: store.cpu?.totalUsage,
            memFraction: store.memory?.usedFraction,
            temperatureC: store.cpuTemperature,
            netDownBytesPerSec: store.netRates?.download,
            netUpBytesPerSec: store.netRates?.upload,
            diskReadBytesPerSec: store.diskIO?.read,
            diskWriteBytesPerSec: store.diskIO?.write
        )
        let metrics = MenuBarText.metrics(values) { kind in
            switch kind {
            case .cpu:     return showCPU
            case .memory:  return showMemory
            case .temp:    return showTemp
            case .network: return showNetwork
            case .disk:    return showDisk
            }
        }
        Image(nsImage: metrics.isEmpty ? icon : Self.image(for: metrics))
    }

    private static func image(for metrics: [MenuBarMetric]) -> NSImage {
        let labelFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        let stackFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

        func attrs(_ font: NSFont) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: NSColor.black]
        }

        let cells = metrics.map { metric -> (top: NSAttributedString, bottom: NSAttributedString, topFont: NSFont, bottomFont: NSFont, width: CGFloat) in
            let topFont = metric.stacked ? stackFont : labelFont
            let bottomFont = metric.stacked ? stackFont : valueFont
            let top = NSAttributedString(string: metric.label, attributes: attrs(topFont))
            let bottom = NSAttributedString(string: metric.value, attributes: attrs(bottomFont))
            return (top, bottom, topFont, bottomFont, ceil(max(top.size().width, bottom.size().width)))
        }

        let columnGap: CGFloat = 16
        let rowGap: CGFloat = 3
        let vPad: CGFloat = 2
        let bottomCap = cells.map { $0.bottomFont.capHeight }.max() ?? valueFont.capHeight
        let topCap = cells.map { $0.topFont.capHeight }.max() ?? labelFont.capHeight
        let width = cells.reduce(0) { $0 + $1.width } + columnGap * CGFloat(max(0, cells.count - 1))
        let height = ceil(bottomCap + rowGap + topCap + vPad * 2)
        let bottomBaseline = vPad
        let topBaseline = bottomCap + rowGap + vPad

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for cell in cells {
                cell.bottom.draw(at: NSPoint(x: x, y: bottomBaseline + cell.bottomFont.descender))
                cell.top.draw(at: NSPoint(x: x, y: topBaseline + cell.topFont.descender))
                x += cell.width + columnGap
            }
            return true
        }
        image.isTemplate = true

        let thickness = NSStatusBar.system.thickness
        if height > thickness {
            image.size = NSSize(width: width * thickness / height, height: thickness)
        }
        return image
    }
}

/// "Launch at login" menu item backed by SMAppService.
private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    enabled = newValue
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
        ))
    }
}

private var isDraggingAllowed: Bool {
    !UserDefaults.standard.bool(forKey: WidgetSettings.positionLockedKey)
}

/// Identifies user-facing secondary inspector windows with a title bar (excluding status bar menus, popovers, and desktop HUD).
private func isInspectorWindow(_ win: NSWindow) -> Bool {
    guard !(win is DesktopWindow) else { return false }
    guard win.styleMask.contains(.titled) else { return false }
    guard !win.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    guard win.canBecomeKey else { return false }
    return win.isVisible || win.isMiniaturized
}

final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless desktop-level window: never steals focus,
/// draggable from anywhere (unless position is locked).
final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.type == .leftMouseDown, isDraggingAllowed {
            performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var window: DesktopWindow?
    let store = MetricsStore()
    let usageHistory = UsageHistoryStore(persistence: .init())
    private var updateTimer: Timer?
    private var geometryObserver: AnyCancellable?
    private var isLiveResizing = false

    private var lastRefreshInterval: Double = UserDefaults.standard.object(
        forKey: WidgetSettings.refreshIntervalKey
    ) as? Double ?? WidgetSettings.defaultRefreshInterval

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let idx = CommandLine.arguments.firstIndex(of: "--notify") {
            let title = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : "Osprey Advisory"
            let body = CommandLine.arguments.indices.contains(idx + 2) ? CommandLine.arguments[idx + 2] : "System notification"
            AdvisoryCollector.sendNativeNotification(title: title, body: body)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
            return
        }

        NSApp.setActivationPolicy(.accessory) // Menu bar only, no Dock clutter
        NSWindow.allowsAutomaticWindowTabbing = false

        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.register()
        }


        store.start()
        usageHistory.start(reading: store)

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        scheduleAutomaticUpdateCheck()

        let window = DesktopWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Window layer: desktopIconWindow + 1 (Desktop wallpaper level) by default
        let isAlwaysOnTop = UserDefaults.standard.bool(forKey: WidgetSettings.alwaysOnTopKey)
        window.level = isAlwaysOnTop
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false // Clean crisp rounded card, zero outer fuzzy box/lines

        let hostingView = WidgetHostingView(rootView: WidgetRootView(store: store))
        // The window size is owned by syncWindowSize() (stored width/height +
        // measured content height). No hosting-view window constraints, so
        // AppKit and SwiftUI never fight over the frame.
        hostingView.sizingOptions = []
        window.contentView = hostingView

        window.center()
        window.setFrameAutosaveName("OspreyWidgetWindow")

        self.window = window
        if WidgetSettings.isVisible(in: .standard) {
            window.orderFrontRegardless()
        }

        syncWindowSize()

        // Follow the widget's measured content height: rows appearing or
        // disappearing, zoom, font or preset changes all re-measure it.
        geometryObserver = WidgetGeometry.shared.$naturalHeight
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.syncWindowSize() }
            }

        // Bottom/corner resizing uses a composited preview rather than
        // rebuilding the complete SwiftUI hierarchy for every mouse event.
        // Resize the native window synchronously to keep that preview under
        // the pointer, then do one real layout when the drag ends.
        NotificationCenter.default.addObserver(
            forName: .ospreyWidgetLiveResize,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let value = notification.object as? NSValue else { return }
            MainActor.assumeIsolated {
                self?.isLiveResizing = true
                self?.applyLiveWindowSize(value.sizeValue)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .ospreyWidgetLiveResizeEnded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLiveResizing = false
                self?.syncWindowSize()
            }
        }

        // Keep inspector windows manageable: elevate while Osprey is active, revert to normal when switching to other apps
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let win = notification.object as? NSWindow else { return }
            if isInspectorWindow(win) {
                let isFloating = UserDefaults.standard.bool(forKey: WidgetSettings.alwaysOnTopKey)
                win.level = isFloating ? .floating : .normal
                MainActor.assumeIsolated {
                    self?.updateDockVisibility()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDockVisibility()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.updateDockVisibility()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDockVisibility()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDockVisibility()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenInspectorWindow"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                MainActor.assumeIsolated {
                    self?.updateDockVisibility()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            for win in NSApp.windows where !(win is DesktopWindow) {
                win.level = .normal
            }
        }

        // Support inter-process opening of inspector windows
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.kraloveckey.osprey.open"),
            object: nil,
            queue: .main
        ) { notification in
            if let id = notification.object as? String {
                NotificationCenter.default.post(name: NSNotification.Name("OpenInspectorWindow"), object: id)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.kraloveckey.osprey.smartTab"),
            object: nil,
            queue: .main
        ) { notification in
            if let tab = notification.object as? String {
                NotificationCenter.default.post(name: NSNotification.Name("SwitchSMARTTab"), object: tab)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.kraloveckey.osprey.selectDrive"),
            object: nil,
            queue: .main
        ) { notification in
            if let diskId = notification.object as? String {
                NotificationCenter.default.post(name: NSNotification.Name("SelectSMARTDrive"), object: diskId)
            }
        }

        // Automatic detection when external SSD is plugged in or unplugged
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.refreshDiskUsage()
                self?.store.refreshAdvisory()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.refreshDiskUsage()
                self?.store.refreshAdvisory()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncWindowSize()
                self?.restartStoreIfIntervalChanged()
                self?.reconcileVisibility()
                self?.reconcileWindowLevel()
            }
        }
    }

    func updateDockVisibility() {
        let hasOpenInspectors = NSApp.windows.contains { isInspectorWindow($0) }
        let targetPolicy: NSApplication.ActivationPolicy = hasOpenInspectors ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            let wasActive = NSApp.isActive
            NSApp.setActivationPolicy(targetPolicy)
            if targetPolicy == .regular {
                NSApp.activate(ignoringOtherApps: true)
            } else if wasActive {
                // Changing an active app from `.regular` to `.accessory`
                // makes AppKit activate the previous regular app. If that app
                // is Finder, its last window suddenly covers the desktop
                // widget after an inspector closes. Re-activate Osprey while
                // keeping it accessory-only: the Dock icon disappears without
                // pulling another application's windows to the foreground.
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.async {
                    guard !NSApp.windows.contains(where: isInspectorWindow) else { return }
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        var restoredAny = false
        for win in NSApp.windows where isInspectorWindow(win) && win.isMiniaturized {
            win.deminiaturize(nil)
            restoredAny = true
        }
        if !restoredAny {
            if let inspector = NSApp.windows.first(where: { isInspectorWindow($0) && $0.isVisible }) {
                inspector.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    /// Sizes the desktop window from the stored width/height settings and the
    /// widget's measured content height (`WidgetGeometry.naturalHeight`).
    /// The top-left corner stays put; the window grows/shrinks downward.
    private func syncWindowSize() {
        guard window != nil, !isLiveResizing else { return }

        let defaults = UserDefaults.standard
        let scale = defaults.object(forKey: WidgetSettings.widgetScaleKey) as? Double
            ?? WidgetSettings.defaultScale
        let cols = defaults.integer(forKey: WidgetSettings.widgetColumnsKey)
        let effectiveCols = cols > 0 ? cols : WidgetSettings.defaultColumns

        let storedWidth = defaults.object(forKey: WidgetSettings.widgetWidthKey) as? Double
            ?? (effectiveCols == 3 ? WidgetSettings.defaultWideWidth * scale : WidgetSettings.defaultWidth * scale)
        let targetWidth = WidgetSettings.clampWidth(storedWidth, columns: effectiveCols, scale: scale)

        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }

            // Read inside the async hop: @Published emits on willSet, so the
            // new natural height is only visible once the setter has finished.
            // naturalHeight is per unit of zoom.
            // The widget is always exactly as tall as its content; size
            // changes go through the zoom. Until the first layout pass has
            // measured the content, keep the current height.
            let natural = ceil(Double(WidgetGeometry.shared.naturalHeight) * scale)
            let targetHeight = natural > 0
                ? max(natural, WidgetSettings.minHeight)
                : Double(window.frame.height)

            let widthChanged = abs(window.frame.width - targetWidth) > 0.5
            let heightChanged = abs(window.frame.height - targetHeight) > 0.5
            guard widthChanged || heightChanged else { return }

            let current = window.frame
            var newFrame = NSRect(
                x: current.minX,
                y: current.maxY - targetHeight,
                width: targetWidth,
                height: targetHeight
            )
            // Growing downward must not push the bottom (and the resize
            // handle) off the screen: slide the window up instead.
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                if newFrame.minY < visible.minY {
                    newFrame.origin.y = visible.minY
                }
                if newFrame.maxY > visible.maxY {
                    newFrame.origin.y = max(visible.minY, visible.maxY - newFrame.height)
                }
            }
            window.setFrame(newFrame, display: true, animate: false)
        }
    }

    /// Applies the inexpensive preview size while preserving the widget's
    /// top-left anchor. The final persisted dimensions still go through
    /// `syncWindowSize()` after the gesture ends.
    private func applyLiveWindowSize(_ size: NSSize) {
        guard let window, size.width.isFinite, size.height.isFinite else { return }

        let current = window.frame
        let targetWidth = max(1, size.width)
        let targetHeight = max(1, size.height)
        var newFrame = NSRect(
            x: current.minX,
            y: current.maxY - targetHeight,
            width: targetWidth,
            height: targetHeight
        )

        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            if newFrame.minY < visible.minY {
                newFrame.origin.y = visible.minY
            }
            if newFrame.maxY > visible.maxY {
                newFrame.origin.y = max(visible.minY, visible.maxY - newFrame.height)
            }
        }

        window.setFrame(newFrame, display: true, animate: false)
    }

    private func restartStoreIfIntervalChanged() {
        let current = UserDefaults.standard.object(forKey: WidgetSettings.refreshIntervalKey) as? Double
            ?? WidgetSettings.defaultRefreshInterval
        guard current != lastRefreshInterval else { return }
        lastRefreshInterval = current
        store.start()
    }

    private func reconcileVisibility() {
        guard let window else { return }
        let shouldBeVisible = WidgetSettings.isVisible(in: .standard)
        if shouldBeVisible, !window.isVisible {
            window.orderFrontRegardless()
        } else if !shouldBeVisible, window.isVisible {
            window.orderOut(nil)
            if UserDefaults.standard.bool(forKey: WidgetSettings.alwaysOnTopKey) {
                UserDefaults.standard.set(false, forKey: WidgetSettings.alwaysOnTopKey)
            }
        }
    }

    private func reconcileWindowLevel() {
        guard let window else { return }
        let isAlwaysOnTop = UserDefaults.standard.bool(forKey: WidgetSettings.alwaysOnTopKey)
        let targetLevel = isAlwaysOnTop
            ? NSWindow.Level.floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        if window.level != targetLevel {
            window.level = targetLevel
        }
    }

    // MARK: - Software Updates Background Check

    private func scheduleAutomaticUpdateCheck() {
        guard UserDefaults.standard.bool(forKey: WidgetSettings.autoCheckUpdatesKey) else { return }
        // Initial check 15 seconds after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.checkUpdateInBackground()
        }
        // Daily periodic check every 24 hours
        updateTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkUpdateInBackground()
            }
        }
    }

    private func checkUpdateInBackground() {
        guard UserDefaults.standard.bool(forKey: WidgetSettings.autoCheckUpdatesKey) else { return }
        Task {
            let res = await UpdateChecker.checkLatestRelease()
            if let update = res.update, update.isNewer {
                await MainActor.run {
                    NotificationCenter.default.post(name: NSNotification.Name("OspreyNewUpdateDetected"), object: update.version)
                    sendUpdateNotification(version: update.version)
                }
            }
        }
    }

    private func sendUpdateNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "Osprey Update Available"
        content.body = "A new version (v\(version)) is available. Click to review release notes and install."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "osprey-update-\(version)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("OpenInspectorWindow"), object: "software-update")
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
        updateTimer = nil
        store.stop()
        usageHistory.stop()
    }
}
