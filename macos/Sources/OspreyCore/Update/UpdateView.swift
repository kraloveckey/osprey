import AppKit
import SwiftUI

public struct UpdateView: View {
    @AppStorage(WidgetSettings.autoCheckUpdatesKey)
    private var autoCheckUpdates = WidgetSettings.defaultAutoCheckUpdates

    @State private var isChecking = false
    @State private var updateInfo: AppUpdateInfo?
    @State private var errorMessage: String?
    @State private var hasChecked = false
    @State private var installState: UpdateInstallState = .idle

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Pinned Header
            headerBar

            Divider().opacity(0.12)

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    if isChecking {
                        checkingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if let info = updateInfo {
                        if info.isNewer {
                            newerVersionView(info: info)
                        } else {
                            upToDateView
                        }
                    }
                }
                .padding(20)
            }

            Divider().opacity(0.12)

            // Pinned Footer
            footerBar
        }
        .frame(minWidth: 560, idealWidth: 600, maxWidth: .infinity, minHeight: 480, idealHeight: 540, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear {
            checkForUpdates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerCheckForUpdates"))) { _ in
            checkForUpdates()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.accent)

            Text("Osprey Software Update")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.header)

            Spacer()

            Text("Current: v\(CoreInfo.version)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Checking View

    private var checkingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Checking for updates on GitHub…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.warning)

            Text("Update Check Failed")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.header)

            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Try Again") {
                checkForUpdates()
            }
            .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    // MARK: - Newer Version View

    private func newerVersionView(info: AppUpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Highlight Banner Card
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("A new version of Osprey is available!")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.header)

                    Text("Osprey v\(info.version) is ready to install (current version: v\(CoreInfo.version)).")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }

                Spacer()
            }
            .padding(14)
            .background(Theme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.25), lineWidth: 1))

            // Release Notes Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("WHAT'S NEW IN V\(info.version)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.gray)

                    Spacer()

                    if !info.publishedAt.isEmpty {
                        Text(info.publishedAt.prefix(10))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dim)
                    }
                }

                Text(info.releaseNotes)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))

            // Action Buttons
            actionButtons(info: info)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private func actionButtons(info: AppUpdateInfo) -> some View {
        HStack(spacing: 12) {
            switch installState {
            case .idle:
                Button {
                    if let url = info.downloadUrl {
                        Task {
                            await UpdateChecker.performAutoUpdate(from: url) { state in
                                self.installState = state
                            }
                        }
                    } else {
                        NSWorkspace.shared.open(info.htmlUrl)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download & Install Update")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    NSWorkspace.shared.open(info.htmlUrl)
                } label: {
                    HStack(spacing: 4) {
                        Text("View on GitHub")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)

            case .downloading:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Downloading update package…")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            case .extracting:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Extracting and verifying bundle…")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            case .restarting:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text("Restarting Osprey v\(info.version)…")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            case .error(let msg):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Auto-install failed: \(msg)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.danger)

                    HStack(spacing: 8) {
                        Button("Download Manually in Browser") {
                            if let url = info.downloadUrl {
                                NSWorkspace.shared.open(url)
                            } else {
                                NSWorkspace.shared.open(info.htmlUrl)
                            }
                        }
                        .font(.system(size: 11))

                        Button("Retry") {
                            installState = .idle
                        }
                        .font(.system(size: 11))
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Up To Date View

    private var upToDateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)

            Text("You're Up to Date!")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.header)

            Text("Osprey v\(CoreInfo.version) is currently the newest version available.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)

            Button("Check Again") {
                checkForUpdates()
            }
            .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack(spacing: 12) {
            Toggle("Automatically check for updates", isOn: $autoCheckUpdates)
                .font(.system(size: 11))
                .toggleStyle(.checkbox)

            Spacer()

            Button("Report an Issue…") {
                NSWorkspace.shared.open(UpdateChecker.issuesPageURL)
            }
            .font(.system(size: 11))

            Button("Close") {
                NSApp.keyWindow?.close()
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
    }

    private func checkForUpdates() {
        isChecking = true
        errorMessage = nil
        hasChecked = true
        Task {
            let res = await UpdateChecker.checkLatestRelease()
            await MainActor.run {
                isChecking = false
                if let err = res.error {
                    errorMessage = err
                } else {
                    updateInfo = res.update
                }
            }
        }
    }
}
