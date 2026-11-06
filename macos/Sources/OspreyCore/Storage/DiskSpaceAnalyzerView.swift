import AppKit
import SwiftUI

/// Disk Space Analyzer and Safe Junk Cleaner (DaisyDisk / CleanMyMac style).
public struct DiskSpaceAnalyzerView: View {
    let store: MetricsStore
    @StateObject private var cleaner = DiskCleaner()
    @State private var showConfirmAlert: Bool = false

    public init(store: MetricsStore) {
        self.store = store
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.0f MB", mb)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Pinned Header
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().opacity(0.12)

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    if let disk = store.diskUsage {
                        storageOverviewCard(disk: disk)
                    }

                    categoriesTable

                    if let freed = cleaner.lastCleanedBytes, freed > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text("Successfully reclaimed \(formatBytes(freed)) of storage space!")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.green)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Divider().opacity(0.12)

            // Pinned Bottom Action Bar
            bottomActionBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.25))
        }
        .frame(minWidth: 620, idealWidth: 660, maxWidth: .infinity, minHeight: 480, idealHeight: 580, maxHeight: .infinity)
        .background(Theme.background)
        .alert("Clean Selected Cache Files?", isPresented: $showConfirmAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clean \(formatBytes(cleaner.totalReclaimableBytes))", role: .destructive) {
                Task {
                    _ = await cleaner.cleanSelected()
                }
            }
        } message: {
            Text("This will remove \(formatBytes(cleaner.totalReclaimableBytes)) of temporary cache files and intermediate build caches. Installed CLI binaries in ~/.cargo/bin, active project source code, and personal documents are never touched.")
        }
        .task {
            await cleaner.scanAll()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.purple)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Disk Space & Cache Cleaner")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                    if cleaner.totalReclaimableBytes > 0 {
                        Text("\(formatBytes(cleaner.totalReclaimableBytes)) Reclaimable")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundStyle(Color.purple)
                            .clipShape(Capsule())
                    }
                }
                Text("Reclaim gigabytes of disposable developer bloat, system caches, and junk")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gray)
            }

            Spacer()

            Button(action: {
                Task { await cleaner.scanAll() }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text(cleaner.isScanning ? "Scanning..." : "Rescan")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(cleaner.isScanning || cleaner.isCleaning)
        }
    }

    // MARK: - Storage Overview

    private func storageOverviewCard(disk: DiskUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("INTERNAL STORAGE OVERVIEW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.gray)
                Spacer()
                Text("\(formatBytes(disk.used)) Used · \(formatBytes(disk.free)) Free")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            }

            GeometryReader { geo in
                let usedRatio = CGFloat(disk.usedFraction)
                let reclaimableRatio = min(0.3, CGFloat(cleaner.totalReclaimableBytes) / CGFloat(disk.total))

                HStack(spacing: 2) {
                    Capsule()
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: max(2, geo.size.width * max(0.05, (usedRatio - reclaimableRatio))))
                    Capsule()
                        .fill(Color.purple)
                        .frame(width: max(2, geo.size.width * reclaimableRatio))
                    Capsule()
                        .fill(Color.green.opacity(0.7))
                }
            }
            .frame(height: 8)

            HStack(spacing: 16) {
                legendDot(color: Color.orange.opacity(0.8), label: "System & Apps")
                legendDot(color: Color.purple, label: "Reclaimable Cache")
                legendDot(color: Color.green.opacity(0.7), label: "Free Space")
            }
            .font(.system(size: 9))
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Categories Table

    private var categoriesTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECLAIMABLE JUNK CATEGORIES")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.gray)

            VStack(spacing: 8) {
                ForEach($cleaner.categories) { $cat in
                    HStack(spacing: 12) {
                        Toggle("", isOn: $cat.isSelected)
                            .labelsHidden()
                            .toggleStyle(.checkbox)

                        Image(systemName: cat.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.purple)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(cat.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Text(cat.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.gray)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatBytes(cat.sizeBytes))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(cat.sizeBytes > 0 ? Color.white : Color.gray)
                            Text("\(cat.itemCount) items")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.gray)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Zero risk: All deletions target non-essential cache files only.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.gray)
                Text("Binaries in ~/.cargo/bin and project source files are never touched.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.gray.opacity(0.8))
            }

            Spacer()

            Button(action: {
                showConfirmAlert = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text(cleaner.isCleaning ? "Cleaning..." : "Clean Selected (\(formatBytes(cleaner.totalReclaimableBytes)))")
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.purple)
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(cleaner.isScanning || cleaner.isCleaning || cleaner.totalReclaimableBytes == 0)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(Color.gray)
        }
    }
}
