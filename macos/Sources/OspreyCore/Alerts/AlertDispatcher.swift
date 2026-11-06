import Foundation
import UserNotifications

public enum AlertDispatcher {
    // MARK: - Telegram Bot

    public static func sendTelegram(
        botToken: String,
        chatId: String,
        message: String
    ) async -> (success: Bool, message: String) {
        let cleanToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanChatId = chatId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanToken.isEmpty, !cleanChatId.isEmpty else {
            return (false, "Bot Token and Chat ID cannot be empty.")
        }

        let urlString = "https://api.telegram.org/bot\(cleanToken)/sendMessage"
        guard let url = URL(string: urlString) else {
            return (false, "Invalid Telegram API URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "chat_id": cleanChatId,
            "text": message,
            "parse_mode": "Markdown"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return (true, "Telegram notification sent successfully!")
            } else {
                let errText = String(data: data, encoding: .utf8) ?? "Unknown server response"
                return (false, "Telegram API error: \(errText)")
            }
        } catch {
            return (false, "Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Discord Webhook

    public static func sendDiscord(
        webhookUrl: String,
        title: String,
        description: String,
        fields: [(name: String, value: String)]
    ) async -> (success: Bool, message: String) {
        let cleanUrl = webhookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanUrl), cleanUrl.hasPrefix("https://discord.com/api/webhooks/") else {
            return (false, "Please provide a valid Discord webhook URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let embedFields = fields.map { ["name": $0.name, "value": $0.value, "inline": true] }
        let payload: [String: Any] = [
            "username": "Osprey Telemetry",
            "avatar_url": "https://raw.githubusercontent.com/kraloveckey/osprey/main/assets/logo.png",
            "embeds": [
                [
                    "title": title,
                    "description": description,
                    "color": 15158332, // Coral/Amber warning color
                    "fields": embedFields,
                    "footer": ["text": "Osprey Storage & Telemetry Sentinel"]
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...204).contains(httpResponse.statusCode) {
                return (true, "Discord notification sent successfully!")
            } else {
                return (false, "Discord returned status code \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
        } catch {
            return (false, "Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Slack Webhook
    public static func sendSlack(
        webhookUrl: String,
        text: String
    ) async -> (success: Bool, message: String) {
        let cleanUrl = webhookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanUrl), cleanUrl.hasPrefix("https://hooks.slack.com/services/") else {
            return (false, "Please provide a valid Slack webhook URL (https://hooks.slack.com/services/...).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["text": text]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...204).contains(httpResponse.statusCode) {
                return (true, "Slack notification sent successfully!")
            } else {
                return (false, "Slack returned status code \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
        } catch {
            return (false, "Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Email / Generic Webhook

    public static func sendEmailWebhook(
        webhookUrl: String,
        subject: String,
        body: String
    ) async -> (success: Bool, message: String) {
        let cleanUrl = webhookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanUrl), cleanUrl.hasPrefix("http") else {
            return (false, "Please provide a valid HTTP/HTTPS email webhook URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "event": "osprey_alert",
            "subject": subject,
            "body": body,
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                return (true, "Email/Webhook notification dispatched successfully!")
            } else {
                return (false, "Webhook returned status code \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
        } catch {
            return (false, "Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - High Temperature / Hardware Alert Dispatcher

    public static func dispatchHardwareAlert(
        title: String,
        driveModel: String,
        temperatureC: Int,
        thresholdC: Double,
        healthStatus: String
    ) {
        let defaults = UserDefaults.standard
        let msg = "Drive '\(driveModel)' has reached \(temperatureC)°C, exceeding your \(Int(thresholdC))°C safety threshold. Health: \(healthStatus)."

        // 1. Native macOS Notification
        AdvisoryCollector.sendNativeNotification(
            title: title,
            body: msg
        )

        // 2. Telegram Alert
        if defaults.bool(forKey: WidgetSettings.telegramAlertsEnabledKey) {
            let token = defaults.string(forKey: WidgetSettings.telegramBotTokenKey) ?? ""
            let chat = defaults.string(forKey: WidgetSettings.telegramChatIdKey) ?? ""
            if !token.isEmpty && !chat.isEmpty {
                let md = """
                🦅 *Osprey Hardware Sentinel*
                ⚠️ *\(title)*

                *Drive:* `\(driveModel)`
                *Temperature:* `\(temperatureC)°C` (Threshold: `\(Int(thresholdC))°C`)
                *Health:* `\(healthStatus)`
                *Message:* \(msg)
                """
                Task {
                    _ = await sendTelegram(botToken: token, chatId: chat, message: md)
                }
            }
        }

        // 3. Discord Alert
        if defaults.bool(forKey: WidgetSettings.discordAlertsEnabledKey) {
            let webhook = defaults.string(forKey: WidgetSettings.discordWebhookUrlKey) ?? ""
            if !webhook.isEmpty {
                let fields = [
                    (name: "Drive", value: driveModel),
                    (name: "Temperature", value: "\(temperatureC)°C (Threshold: \(Int(thresholdC))°C)"),
                    (name: "Health", value: healthStatus)
                ]
                Task {
                    _ = await sendDiscord(
                        webhookUrl: webhook,
                        title: title,
                        description: msg,
                        fields: fields
                    )
                }
            }
        }

        // 4. Email / Webhook Alert
        if defaults.bool(forKey: WidgetSettings.emailAlertsEnabledKey) {
            let webhook = defaults.string(forKey: WidgetSettings.emailWebhookUrlKey) ?? ""
            if !webhook.isEmpty {
                Task {
                    _ = await sendEmailWebhook(
                        webhookUrl: webhook,
                        subject: "[Osprey Alert] \(title) – \(driveModel)",
                        body: msg
                    )
                }
            }
        }
    }
}
