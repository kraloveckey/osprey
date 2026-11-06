import AppKit
import Foundation

public struct AppUpdateInfo: Sendable {
    public let version: String
    public let releaseTitle: String
    public let releaseNotes: String
    public let htmlUrl: URL
    public let downloadUrl: URL?
    public let publishedAt: String
    public let isNewer: Bool
}

public enum UpdateInstallState: Equatable, Sendable {
    case idle
    case downloading
    case extracting
    case restarting
    case error(message: String)
}

public enum UpdateChecker {
    public static let releasesPageURL = URL(string: "https://github.com/kraloveckey/osprey/releases")!
    public static let repoPageURL = URL(string: "https://github.com/kraloveckey/osprey")!
    public static let issuesPageURL = URL(string: "https://github.com/kraloveckey/osprey/issues")!
    private static let apiLatestReleaseURL = URL(string: "https://api.github.com/repos/kraloveckey/osprey/releases/latest")!

    public static func checkLatestRelease() async -> (update: AppUpdateInfo?, error: String?) {
        var request = URLRequest(url: apiLatestReleaseURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Osprey-Update-Checker/\(CoreInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (nil, "Invalid server response.")
            }

            if httpResponse.statusCode == 404 {
                let current = AppUpdateInfo(
                    version: CoreInfo.version,
                    releaseTitle: "Osprey v\(CoreInfo.version)",
                    releaseNotes: "You are running the latest version of Osprey.",
                    htmlUrl: releasesPageURL,
                    downloadUrl: nil,
                    publishedAt: "",
                    isNewer: false
                )
                return (current, nil)
            } else if httpResponse.statusCode != 200 {
                return (nil, "GitHub API returned status code \(httpResponse.statusCode).")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (nil, "Malformed JSON response.")
            }

            let tagName = (json["tag_name"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) ?? ""
            let name = json["name"] as? String ?? "Osprey Release"
            var body = json["body"] as? String ?? ""
            let publishedAt = json["published_at"] as? String ?? ""
            let htmlUrlStr = json["html_url"] as? String ?? releasesPageURL.absoluteString
            let htmlUrl = URL(string: htmlUrlStr) ?? releasesPageURL

            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || body == "No release notes provided." {
                body = """
                • Interactive vertical height resizing handles along the bottom edge and corner
                • Adaptive anti-crop protection preventing metric rows and buttons from clipping
                • Double-click handle shortcut to instantly snap back to snug natural height
                • Symmetrical widget zoom controls (70%–130%) for compact and large displays
                • Dynamic macOS Dock icon integration for secondary inspector windows
                """
            }

            var downloadUrl: URL?
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let assetName = asset["name"] as? String,
                       (assetName.hasSuffix(".dmg") || assetName.hasSuffix(".zip")),
                       let browserUrlStr = asset["browser_download_url"] as? String,
                       let url = URL(string: browserUrlStr) {
                        downloadUrl = url
                        break
                    }
                }
            }

            let isNewer = isVersion(tagName, newerThan: CoreInfo.version)

            let info = AppUpdateInfo(
                version: tagName.isEmpty ? CoreInfo.version : tagName,
                releaseTitle: name,
                releaseNotes: body,
                htmlUrl: htmlUrl,
                downloadUrl: downloadUrl,
                publishedAt: publishedAt,
                isNewer: isNewer
            )
            return (info, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    public static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }

    @MainActor
    public static func performAutoUpdate(from downloadUrl: URL, progressHandler: @escaping (UpdateInstallState) -> Void) async {
        progressHandler(.downloading)

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("osprey-update-\(UUID().uuidString)")
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipPath = tempDir.appendingPathComponent("update.zip")

            // 1. Download zip
            let (localURL, response) = try await URLSession.shared.download(from: downloadUrl)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                progressHandler(.error(message: "Failed to download update archive from GitHub."))
                return
            }

            try fm.moveItem(at: localURL, to: zipPath)
            progressHandler(.extracting)

            // 2. Unpack with ditto (preserves macOS file attributes and symlinks)
            let extractDir = tempDir.appendingPathComponent("extracted")
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-xk", zipPath.path, extractDir.path]
            try ditto.run()
            ditto.waitUntilExit()

            guard ditto.terminationStatus == 0 else {
                progressHandler(.error(message: "Failed to unpack update archive."))
                return
            }

            // Find Osprey.app in extracted folder
            let items = try fm.contentsOfDirectory(atPath: extractDir.path)
            guard let appName = items.first(where: { $0.hasSuffix(".app") }) else {
                progressHandler(.error(message: "Update archive did not contain Osprey.app."))
                return
            }

            let extractedAppURL = extractDir.appendingPathComponent(appName)

            // Strip quarantine from extracted app
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-cr", extractedAppURL.path]
            try? xattr.run()
            xattr.waitUntilExit()

            // 3. Locate target app bundle
            let currentBundleURL = Bundle.main.bundleURL
            let targetPath = currentBundleURL.path.hasSuffix(".app") ? currentBundleURL.path : "/Applications/Osprey.app"

            progressHandler(.restarting)

            // 4. Create and launch background updater script
            let scriptPath = tempDir.appendingPathComponent("relaunch.sh")
            let myPID = ProcessInfo.processInfo.processIdentifier
            let scriptContent = """
            #!/bin/bash
            while kill -0 \(myPID) 2>/dev/null; do
                sleep 0.2
            done
            sleep 0.5
            rm -rf "\(targetPath)"
            cp -R "\(extractedAppURL.path)" "\(targetPath)"
            xattr -cr "\(targetPath)"
            open "\(targetPath)"
            rm -rf "\(tempDir.path)"
            exit 0
            """

            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptPath.path]
            try? chmod.run()
            chmod.waitUntilExit()

            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [scriptPath.path]
            try launcher.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        } catch {
            progressHandler(.error(message: error.localizedDescription))
        }
    }
}
