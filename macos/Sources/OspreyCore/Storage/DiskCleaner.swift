import Foundation

/// Fast scanner and safe cleaner for user caches, developer bloat, and system logs (DaisyDisk / CleanMyMac style).
@MainActor
public final class DiskCleaner: ObservableObject {
    public struct CacheCategory: Identifiable, Sendable, Equatable {
        public let id: String
        public let name: String
        public let detail: String
        public let path: String
        public var sizeBytes: UInt64
        public var itemCount: Int
        public let icon: String
        public var isSelected: Bool

        public init(
            id: String,
            name: String,
            detail: String,
            path: String,
            sizeBytes: UInt64 = 0,
            itemCount: Int = 0,
            icon: String,
            isSelected: Bool = true
        ) {
            self.id = id
            self.name = name
            self.detail = detail
            self.path = path
            self.sizeBytes = sizeBytes
            self.itemCount = itemCount
            self.icon = icon
            self.isSelected = isSelected
        }
    }

    @Published public var categories: [CacheCategory] = []
    @Published public var isScanning: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var lastCleanedBytes: UInt64? = nil

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.categories = [
            CacheCategory(
                id: "user_caches",
                name: "User Application Caches",
                detail: "Temporary web data, image caches, and application buffers",
                path: home + "/Library/Caches",
                icon: "internaldrive",
                isSelected: true
            ),
            CacheCategory(
                id: "xcode_derived",
                name: "Xcode DerivedData & Builds",
                detail: "Intermediate compiler build artifacts and index files",
                path: home + "/Library/Developer/Xcode/DerivedData",
                icon: "hammer.fill",
                isSelected: false
            ),
            CacheCategory(
                id: "cargo_cache",
                name: "Cargo Download Tarballs (.crate archives)",
                detail: "Cached .crate download archives in ~/.cargo/registry/cache. NEVER touches installed CLI binaries (~/.cargo/bin) or project source code.",
                path: home + "/.cargo/registry/cache",
                icon: "shippingbox.fill",
                isSelected: false
            ),
            CacheCategory(
                id: "logs",
                name: "App & System Logs",
                detail: "Diagnostic log files, system traces, and rotated logs",
                path: home + "/Library/Logs",
                icon: "doc.text.fill",
                isSelected: false
            ),
            CacheCategory(
                id: "trash",
                name: "macOS Trash Bin",
                detail: "Deleted files currently retained in the user Trash folder",
                path: home + "/.Trash",
                icon: "trash.fill",
                isSelected: false
            )
        ]
    }

    public var totalReclaimableBytes: UInt64 {
        categories.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    public func scanAll() async {
        guard !isScanning else { return }
        self.isScanning = true

        var updated = categories
        for i in 0..<updated.count {
            let cat = updated[i]
            let (size, count) = await calculateDirectorySize(path: cat.path)
            updated[i].sizeBytes = size
            updated[i].itemCount = count
        }

        self.categories = updated
        self.isScanning = false
    }

    public func cleanSelected() async -> UInt64 {
        guard !isCleaning else { return 0 }
        self.isCleaning = true

        var totalFreed: UInt64 = 0
        let fm = FileManager.default

        for i in 0..<categories.count {
            let cat = categories[i]
            guard cat.isSelected && cat.sizeBytes > 0 else { continue }

            let url = URL(fileURLWithPath: cat.path)
            if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                for item in contents {
                    // Safe skip for active Osprey or essential system lock files
                    if item.lastPathComponent.contains("com.apple.") || item.lastPathComponent == "Osprey" {
                        continue
                    }
                    try? fm.removeItem(at: item)
                }
            }
            totalFreed += cat.sizeBytes
        }

        // Re-scan to update sizes
        await scanAll()

        self.lastCleanedBytes = totalFreed
        self.isCleaning = false
        return totalFreed
    }

    private func calculateDirectorySize(path: String) async -> (size: UInt64, count: Int) {
        await Task.detached(priority: .utility) { () -> (UInt64, Int) in
            let fm = FileManager.default
            let url = URL(fileURLWithPath: path)
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return (0, 0)
            }

            var totalSize: UInt64 = 0
            var fileCount = 0

            while let item = enumerator.nextObject() {
                guard let fileURL = item as? URL else { continue }
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                   resourceValues.isDirectory == false {
                    totalSize += UInt64(resourceValues.fileSize ?? 0)
                    fileCount += 1
                }
                // Cap scan count to keep responsive
                if fileCount > 25000 { break }
            }
            return (totalSize, fileCount)
        }.value
    }
}
