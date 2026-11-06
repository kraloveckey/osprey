import AppKit
import Foundation

public extension Notification.Name {
    /// Carries an `NSValue(size:)` while the widget is being proportionally resized.
    static let ospreyWidgetLiveResize = Notification.Name("OspreyWidgetLiveResize")

    /// Ends the native live-resize session after the final scale is persisted.
    static let ospreyWidgetLiveResizeEnded = Notification.Name("OspreyWidgetLiveResizeEnded")
}

/// Shared widget settings (UserDefaults keys and bounds).
public enum WidgetSettings {
    // MARK: - Position / size

    /// Pins the widget: blocks both dragging and resizing.
    public static let positionLockedKey = "positionLocked"

    /// User-adjustable widget width (points).
    public static let widgetWidthKey = "widgetWidth"

    /// Dynamic minimum width that prevents text truncation across active columns.
    public static func minWidth(for columns: Int, scale: Double = defaultScale) -> Double {
        let minColWidth: Double = 320.0
        let spacing: Double = columns == 3 ? 40.0 : 20.0
        let padding: Double = 28.0
        return (Double(columns) * minColWidth + spacing + padding) * scale
    }

    public static let maxWidth: Double = 4000
    public static let defaultWidth: Double = 744
    public static let defaultWideWidth: Double = 1130

    public static func clampWidth(_ width: Double, columns: Int = defaultColumns, scale: Double = defaultScale) -> Double {
        let minAllowed = minWidth(for: columns, scale: scale)
        let screenMax = screenMaxWidth()
        let effectiveMax = min(maxWidth, max(minAllowed, screenMax))
        return min(max(width, minAllowed), effectiveMax)
    }

    /// Legacy key: the height is no longer stored – the widget is always
    /// exactly as tall as its content (`WidgetGeometry.naturalHeight`), and
    /// vertical resizing changes the zoom. Kept so presets can clear it.
    public static let widgetHeightKey = "widgetHeight"

    /// Absolute lower bound used before the first layout measurement exists.
    public static let minHeight: Double = 120

    /// Largest width the widget may take on the current screen.
    public static func screenMaxWidth() -> Double {
        (NSScreen.main?.visibleFrame.width).map { Double($0) - 32 } ?? 1440
    }

    /// Largest height the widget may take on the current screen.
    public static func screenMaxHeight() -> Double {
        (NSScreen.main?.visibleFrame.height).map { Double($0) - 32 } ?? 1200
    }

    // MARK: - Zoom and scale

    /// Zoom (0.70 to 2.00, default 1.0): set by the −/+ buttons, the menu,
    /// and by dragging the widget's bottom edge or corner.
    public static let widgetScaleKey = "widgetScale"
    public static let defaultScale: Double = 1.0
    public static let minScale: Double = 0.70
    public static let maxScale: Double = 2.00

    public static func clampScale(_ scale: Double) -> Double {
        min(max(scale, minScale), maxScale)
    }

    /// Number of grid columns: 2 (standard vertical 2×3) or 3 (wide 3×2).
    public static let widgetColumnsKey = "widgetColumns"
    public static let defaultColumns: Int = 2


    // MARK: - Background opacity

    public static let backgroundOpacityKey = "backgroundOpacity"
    public static let defaultOpacity: Double = 0.92

    /// Clamps opacity to the allowed range [0.3, 1.0].
    public static func clampOpacity(_ opacity: Double) -> Double {
        min(max(opacity, 0.3), 1.0)
    }

    // MARK: - Refresh rate

    public static let refreshIntervalKey = "refreshInterval"
    public static let defaultRefreshInterval: Double = 2.0

    // MARK: - Font

    /// Base font size in points. Picker offers 11 / 12 / 14 / 16.
    public static let fontSizeKey = "fontSize"
    public static let defaultFontSize: Double = 12

    /// Clamps the font size to the supported range [11, 16].
    public static func clampFontSize(_ size: Double) -> Double {
        min(max(size, 11), 16)
    }

    /// Font design: monospaced (aligned columns) or the native system face.
    public enum FontStyle: String {
        case monospaced
        case system
    }

    public static let fontStyleKey = "fontStyle"

    /// Default font style: the native system face reads more like a first-party
    /// macOS widget; users who prefer aligned columns can switch to monospaced.
    public static let defaultFontStyle: FontStyle = .system

    /// Resolves a stored raw value into a `FontStyle`, defaulting to
    /// `defaultFontStyle` for absent or unrecognized values.
    public static func resolveFontStyle(_ raw: String?) -> FontStyle {
        raw.flatMap(FontStyle.init(rawValue:)) ?? defaultFontStyle
    }

    // MARK: - Menu bar metrics

    /// Live metrics shown as text in the menu bar. All on by default so the menu
    /// bar shows a full readout out of the box; a metric with no data (e.g.
    /// battery temperature on a desktop Mac) is simply omitted from the text.
    public static let menuBarShowCPUKey     = "menuBarShowCPU"
    public static let menuBarShowMemoryKey  = "menuBarShowMemory"
    public static let menuBarShowTempKey    = "menuBarShowTemp"
    public static let menuBarShowNetworkKey = "menuBarShowNetwork"
    public static let menuBarShowDiskKey    = "menuBarShowDisk"

    // CPU/Memory/Temp on by default (the built-in readout); the rest are
    // opt-in so the menu bar stays compact until the user asks for more.
    // Network/Disk each show both directions stacked in one column.
    public static let defaultMenuBarShowCPU     = true
    public static let defaultMenuBarShowMemory  = true
    public static let defaultMenuBarShowTemp    = true
    public static let defaultMenuBarShowNetwork = false
    public static let defaultMenuBarShowDisk    = false

    // MARK: - Section visibility

    public static let showHeaderKey    = "showHeader"
    public static let showCPUKey       = "showCPU"
    public static let showMemoryKey    = "showMemory"
    public static let showDiskKey      = "showDisk"
    public static let showPowerKey     = "showPower"
    public static let showNetworkKey   = "showNetwork"
    public static let showProcessesKey = "showProcesses"

    // MARK: - Desktop visibility

    /// Whether the widget window is shown on the desktop. Hiding it keeps the
    /// app and its menu bar icon running so the widget can be summoned again.
    public static let widgetVisibleKey = "widgetVisible"
    public static let defaultVisible: Bool = true

    /// Resolves desktop visibility from the given defaults.
    public static func isVisible(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: widgetVisibleKey) == nil
            ? defaultVisible
            : defaults.bool(forKey: widgetVisibleKey)
    }

    // MARK: - Window Level (Desktop vs Floating)

    /// When false, the widget sits on the desktop background behind all open windows.
    /// When true, it floats above normal windows in HUD mode.
    public static let alwaysOnTopKey = "alwaysOnTop"
    public static let defaultAlwaysOnTop: Bool = false

    // MARK: - Hardware Alerts & Webhook Channels (Telegram, Discord, Slack, Email)

    /// Disk temperature warning threshold in Celsius.
    public static let diskTempThresholdKey = "diskTempThreshold"
    public static let defaultDiskTempThreshold: Double = 60.0

    /// Swap Memory alert threshold in Gigabytes.
    public static let swapAlertThresholdKey = "swapAlertThreshold"
    public static let defaultSwapAlertThreshold: Double = 16.0
    public static let swapAlertEnabledKey = "swapAlertEnabled"

    /// Low Battery alert threshold in percent.
    public static let lowBatteryAlertThresholdKey = "lowBatteryAlertThreshold"
    public static let defaultLowBatteryAlertThreshold: Double = 20.0
    public static let lowBatteryAlertEnabledKey = "lowBatteryAlertEnabled"

    /// CPU Temperature warning threshold in Celsius.
    public static let cpuTempAlertThresholdKey = "cpuTempAlertThreshold"
    public static let defaultCpuTempAlertThreshold: Double = 90.0
    public static let cpuTempAlertEnabledKey = "cpuTempAlertEnabled"

    /// Telegram Bot channel
    public static let telegramAlertsEnabledKey = "telegramAlertsEnabled"
    public static let telegramBotTokenKey = "telegramBotToken"
    public static let telegramChatIdKey = "telegramChatId"

    /// Discord Webhook channel
    public static let discordAlertsEnabledKey = "discordAlertsEnabled"
    public static let discordWebhookUrlKey = "discordWebhookUrl"

    /// Slack Webhook channel
    public static let slackAlertsEnabledKey = "slackAlertsEnabled"
    public static let slackWebhookUrlKey = "slackWebhookUrl"

    /// Email / Custom Webhook channel
    public static let emailAlertsEnabledKey = "emailAlertsEnabled"
    public static let emailWebhookUrlKey = "emailWebhookUrl"

    // MARK: - Software Updates
    public static let autoCheckUpdatesKey = "autoCheckUpdates"
    public static let defaultAutoCheckUpdates: Bool = true
    public static let lastUpdateCheckKey = "lastUpdateCheck"

    // MARK: - Battery Saver Mode
    public static let batterySaverModeKey = "batterySaverMode"
    public static let defaultBatterySaverMode: Bool = true
}
