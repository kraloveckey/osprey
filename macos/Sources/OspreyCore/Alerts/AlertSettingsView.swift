import SwiftUI

public struct AlertSettingsView: View {
    // Thermal threshold
    @AppStorage(WidgetSettings.diskTempThresholdKey)
    private var tempThreshold: Double = WidgetSettings.defaultDiskTempThreshold

    // Swap alert threshold
    @AppStorage(WidgetSettings.swapAlertEnabledKey)
    private var swapAlertEnabled: Bool = true
    @AppStorage(WidgetSettings.swapAlertThresholdKey)
    private var swapThreshold: Double = WidgetSettings.defaultSwapAlertThreshold

    // Battery alert threshold
    @AppStorage(WidgetSettings.lowBatteryAlertEnabledKey)
    private var batteryAlertEnabled: Bool = true
    @AppStorage(WidgetSettings.lowBatteryAlertThresholdKey)
    private var batteryThreshold: Double = WidgetSettings.defaultLowBatteryAlertThreshold

    // CPU Temp alert threshold
    @AppStorage(WidgetSettings.cpuTempAlertEnabledKey)
    private var cpuAlertEnabled: Bool = false
    @AppStorage(WidgetSettings.cpuTempAlertThresholdKey)
    private var cpuThreshold: Double = WidgetSettings.defaultCpuTempAlertThreshold

    // Do Not Disturb / Silence Alerts
    @AppStorage("dndSilenceAlerts")
    private var dndSilenceAlerts: Bool = false

    // Telegram
    @AppStorage(WidgetSettings.telegramAlertsEnabledKey)
    private var telegramEnabled: Bool = false
    @AppStorage(WidgetSettings.telegramBotTokenKey)
    private var telegramBotToken: String = ""
    @AppStorage(WidgetSettings.telegramChatIdKey)
    private var telegramChatId: String = ""
    @State private var telegramStatus: String?
    @State private var isTestingTelegram = false

    // Discord
    @AppStorage(WidgetSettings.discordAlertsEnabledKey)
    private var discordEnabled: Bool = false
    @AppStorage(WidgetSettings.discordWebhookUrlKey)
    private var discordWebhookUrl: String = ""
    @State private var discordStatus: String?
    @State private var isTestingDiscord = false

    // Slack
    @AppStorage(WidgetSettings.slackAlertsEnabledKey)
    private var slackEnabled: Bool = false
    @AppStorage(WidgetSettings.slackWebhookUrlKey)
    private var slackWebhookUrl: String = ""
    @State private var slackStatus: String?
    @State private var isTestingSlack = false

    // Email / Webhook
    @AppStorage(WidgetSettings.emailAlertsEnabledKey)
    private var emailEnabled: Bool = false
    @AppStorage(WidgetSettings.emailWebhookUrlKey)
    private var emailWebhookUrl: String = ""
    @State private var emailStatus: String?
    @State private var isTestingEmail = false

    @State private var savedToast = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Bar with Auto-Save Badge
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.warning)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Alert Channels & Telemetry Thresholds")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.header)

                            Text("Configure automatic alerts via Telegram, Discord, Slack, Email or macOS Notification Center.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                        }

                        Spacer()

                        // Auto-save visual indicator
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                            Text("Auto-saved to macOS Preferences")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.12))
                        .clipShape(Capsule())
                    }

                    Divider()

                    // SECTION 1: Hardware & System Thresholds
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SYSTEM TELEMETRY THRESHOLDS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.dim)

                        // 1. Disk Temperature
                        thresholdCard(
                            icon: "thermometer.high",
                            iconColor: Theme.warning,
                            title: "Disk Overheat Alert Threshold: \(Int(tempThreshold))°C (\(Int((tempThreshold * 9/5) + 32))°F)",
                            subtitle: "Triggers when internal Apple SSD or connected external NVMe reaches this temperature."
                        ) {
                            Picker("", selection: $tempThreshold) {
                                Text("50°C (122°F)").tag(50.0)
                                Text("55°C (131°F)").tag(55.0)
                                Text("60°C (140°F) – Recommended").tag(60.0)
                                Text("65°C (149°F)").tag(65.0)
                                Text("70°C (158°F)").tag(70.0)
                            }
                            .frame(width: 220)
                        }

                        // 2. High Swap Memory Bleed (SSD Wear Protection)
                        thresholdToggleCard(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: Theme.danger,
                            isOn: $swapAlertEnabled,
                            title: "SSD Swap Wear Alert: > \(Int(swapThreshold)) GB",
                            subtitle: "Warns when excessive kernel swap thrashing increases SSD NAND wear; recommends reboot."
                        ) {
                            Picker("", selection: $swapThreshold) {
                                Text("12 GB").tag(12.0)
                                Text("16 GB – Recommended").tag(16.0)
                                Text("20 GB").tag(20.0)
                                Text("24 GB").tag(24.0)
                            }
                            .frame(width: 170)
                        }

                        // 3. Low Battery Warning
                        thresholdToggleCard(
                            icon: "battery.25",
                            iconColor: Theme.accent,
                            isOn: $batteryAlertEnabled,
                            title: "Low Battery Warning: < \(Int(batteryThreshold))%",
                            subtitle: "Triggers notification when MacBook is on battery power and charge drops below limit."
                        ) {
                            Picker("", selection: $batteryThreshold) {
                                Text("10%").tag(10.0)
                                Text("15%").tag(15.0)
                                Text("20% – Recommended").tag(20.0)
                            }
                            .frame(width: 170)
                        }

                        // 4. CPU Thermal Throttle
                        thresholdToggleCard(
                            icon: "flame.fill",
                            iconColor: Theme.warning,
                            isOn: $cpuAlertEnabled,
                            title: "CPU Thermal Throttle Alert: > \(Int(cpuThreshold))°C",
                            subtitle: "Alerts when Apple Silicon SoC temperature reaches critical thermal throttling levels."
                        ) {
                            Picker("", selection: $cpuThreshold) {
                                Text("85°C (185°F)").tag(85.0)
                                Text("90°C (194°F) – Recommended").tag(90.0)
                                Text("95°C (203°F)").tag(95.0)
                            }
                            .frame(width: 170)
                        }
                    }

                    Divider()

                    // SECTION: Focus & Do Not Disturb
                    focusControlCard

                    Divider()

                    // SECTION 2: Notification Channels
                    VStack(alignment: .leading, spacing: 14) {
                        Text("NOTIFICATION CHANNELS & WEBHOOKS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.dim)

                        // Telegram
                        telegramSection

                        // Discord
                        discordSection

                        // Slack
                        slackSection

                        // Email / Generic Webhook
                        emailSection
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer with Send Advisory Notification and Save confirmation button
            HStack(spacing: 12) {
                Button {
                    AdvisoryCollector.sendNativeNotification(
                        title: "Osprey Advisory",
                        body: "All systems optimal. Storage, memory paging, and hardware telemetry operating normally."
                    )
                    savedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        savedToast = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.badge")
                        Text("Send Advisory Notification")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }

                if savedToast {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Notification Sent / Saved!")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }

                Spacer()

                Button("Save Preferences") {
                    UserDefaults.standard.synchronize()
                    savedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        savedToast = false
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.2))
        }
        .frame(minWidth: 620, minHeight: 640)
        .background(Theme.background)
    }

    // MARK: - Threshold Cards

    private func thresholdCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            content()
        }
        .padding(10)
        .background(Color.white.opacity(0.025))
        .cornerRadius(8)
    }

    private func thresholdToggleCard<Content: View>(
        icon: String,
        iconColor: Color,
        isOn: Binding<Bool>,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: isOn)
                .labelsHidden()

            Image(systemName: icon)
                .foregroundStyle(isOn.wrappedValue ? iconColor : Theme.dim)
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? Theme.text : Theme.dim)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            if isOn.wrappedValue {
                content()
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.025))
        .cornerRadius(8)
    }

    // MARK: - Focus & Do Not Disturb Section

    private var focusControlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOCUS & SYSTEM SILENCING")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.dim)

            HStack(spacing: 12) {
                Toggle("", isOn: $dndSilenceAlerts)
                    .labelsHidden()

                Image(systemName: dndSilenceAlerts ? "bell.slash.fill" : "bell.fill")
                    .foregroundStyle(dndSilenceAlerts ? Theme.warning : Theme.accent)
                    .font(.system(size: 15))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Silence All Alerts (Do Not Disturb)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(dndSilenceAlerts
                        ? "Do Not Disturb is ACTIVE: notification banners and alert chimes are muted."
                        : "Do Not Disturb is OFF: system alerts, banners, and chimes are delivered normally.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                }

                Spacer()

                if dndSilenceAlerts {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.warning)
                            .frame(width: 6, height: 6)
                        Text("Active (Muted)")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.warning.opacity(0.15))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                        Text("Inactive (Alerts On)")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.025))
            .cornerRadius(8)
        }
    }

    // MARK: - Telegram Section

    private var telegramSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $telegramEnabled) {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Color.blue)
                    Text("Telegram Bot Notifications")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.header)
                }
            }

            if telegramEnabled {
                VStack(spacing: 8) {
                    HStack {
                        Text("Bot Token:").font(.system(size: 11)).frame(width: 80, alignment: .leading).foregroundStyle(Theme.dim)
                        TextField("123456789:ABCDefGhIJKlmNoPQRsTUVwxyZ", text: $telegramBotToken)
                            .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    }
                    HStack {
                        Text("Chat ID:").font(.system(size: 11)).frame(width: 80, alignment: .leading).foregroundStyle(Theme.dim)
                        TextField("@channel_name or 123456789", text: $telegramChatId)
                            .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    }
                    HStack {
                        Button {
                            testTelegram()
                        } label: {
                            HStack(spacing: 4) {
                                if isTestingTelegram { ProgressView().scaleEffect(0.6) }
                                Text("Send Test Telegram Alert")
                            }
                        }
                        .disabled(isTestingTelegram || telegramBotToken.isEmpty || telegramChatId.isEmpty)

                        Spacer()

                        if let status = telegramStatus {
                            Text(status).font(.system(size: 11)).foregroundStyle(status.contains("success") ? Theme.accent : Theme.danger)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.02))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Discord Section

    private var discordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $discordEnabled) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundStyle(Color.purple)
                    Text("Discord Webhook Notifications")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.header)
                }
            }

            if discordEnabled {
                VStack(spacing: 8) {
                    HStack {
                        Text("Webhook:").font(.system(size: 11)).frame(width: 80, alignment: .leading).foregroundStyle(Theme.dim)
                        TextField("https://discord.com/api/webhooks/...", text: $discordWebhookUrl)
                            .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    }
                    HStack {
                        Button {
                            testDiscord()
                        } label: {
                            HStack(spacing: 4) {
                                if isTestingDiscord { ProgressView().scaleEffect(0.6) }
                                Text("Send Test Discord Card")
                            }
                        }
                        .disabled(isTestingDiscord || discordWebhookUrl.isEmpty)

                        Spacer()

                        if let status = discordStatus {
                            Text(status).font(.system(size: 11)).foregroundStyle(status.contains("success") ? Theme.accent : Theme.danger)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.02))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Slack Section

    private var slackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $slackEnabled) {
                HStack(spacing: 6) {
                    Image(systemName: "number.square.fill")
                        .foregroundStyle(Color.green)
                    Text("Slack Incoming Webhook")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.header)
                }
            }

            if slackEnabled {
                VStack(spacing: 8) {
                    HStack {
                        Text("Webhook:").font(.system(size: 11)).frame(width: 80, alignment: .leading).foregroundStyle(Theme.dim)
                        TextField("https://hooks.slack.com/services/...", text: $slackWebhookUrl)
                            .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    }
                    HStack {
                        Button {
                            testSlack()
                        } label: {
                            HStack(spacing: 4) {
                                if isTestingSlack { ProgressView().scaleEffect(0.6) }
                                Text("Send Test Slack Message")
                            }
                        }
                        .disabled(isTestingSlack || slackWebhookUrl.isEmpty)

                        Spacer()

                        if let status = slackStatus {
                            Text(status).font(.system(size: 11)).foregroundStyle(status.contains("success") ? Theme.accent : Theme.danger)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.02))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Email Section

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $emailEnabled) {
                HStack(spacing: 6) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(Color.orange)
                    Text("Email Gateway / HTTP Webhook")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.header)
                }
            }

            if emailEnabled {
                VStack(spacing: 8) {
                    HStack {
                        Text("Endpoint:").font(.system(size: 11)).frame(width: 80, alignment: .leading).foregroundStyle(Theme.dim)
                        TextField("https://formspree.io/f/... or Zapier webhook URL", text: $emailWebhookUrl)
                            .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    }
                    HStack {
                        Button {
                            testEmail()
                        } label: {
                            HStack(spacing: 4) {
                                if isTestingEmail { ProgressView().scaleEffect(0.6) }
                                Text("Send Test Webhook")
                            }
                        }
                        .disabled(isTestingEmail || emailWebhookUrl.isEmpty)

                        Spacer()

                        if let status = emailStatus {
                            Text(status).font(.system(size: 11)).foregroundStyle(status.contains("success") ? Theme.accent : Theme.danger)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.02))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Actions

    private func testTelegram() {
        isTestingTelegram = true
        telegramStatus = nil
        Task {
            let msg = """
            🦅 *Osprey Hardware Sentinel Test*
            ✅ Your Telegram notifications are properly configured!
            *Status:* Active & Monitoring
            """
            let res = await AlertDispatcher.sendTelegram(
                botToken: telegramBotToken,
                chatId: telegramChatId,
                message: msg
            )
            await MainActor.run {
                isTestingTelegram = false
                telegramStatus = res.message
            }
        }
    }

    private func testDiscord() {
        isTestingDiscord = true
        discordStatus = nil
        Task {
            let res = await AlertDispatcher.sendDiscord(
                webhookUrl: discordWebhookUrl,
                title: "Osprey Telemetry Test",
                description: "Your Discord webhook alert channel is online and functioning properly.",
                fields: [
                    (name: "Sentinel", value: "Osprey macOS"),
                    (name: "Status", value: "Active & Connected")
                ]
            )
            await MainActor.run {
                isTestingDiscord = false
                discordStatus = res.message
            }
        }
    }

    private func testSlack() {
        isTestingSlack = true
        slackStatus = nil
        Task {
            let res = await AlertDispatcher.sendSlack(
                webhookUrl: slackWebhookUrl,
                text: "🦅 *Osprey Telemetry Test:* Your Slack webhook channel is connected and active!"
            )
            await MainActor.run {
                isTestingSlack = false
                slackStatus = res.message
            }
        }
    }

    private func testEmail() {
        isTestingEmail = true
        emailStatus = nil
        Task {
            let res = await AlertDispatcher.sendEmailWebhook(
                webhookUrl: emailWebhookUrl,
                subject: "[Osprey Test] Webhook Channel Verified",
                body: "This is a test notification from Osprey Storage Sentinel. Your webhook integration is active."
            )
            await MainActor.run {
                isTestingEmail = false
                emailStatus = res.message
            }
        }
    }
}
