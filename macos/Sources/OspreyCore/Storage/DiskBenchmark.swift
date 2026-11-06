import Darwin
import Foundation

/// Fast, safe unbuffered direct-I/O SSD storage benchmark (CrystalDiskMark / Blackmagic style).
@MainActor
public final class DiskBenchmark: ObservableObject {
    public struct BenchmarkResult: Sendable, Equatable {
        public let seqWriteMBps: Double
        public let seqReadMBps: Double
        public let rnd4kWriteMBps: Double
        public let rnd4kWriteIOPS: Double
        public let rnd4kReadMBps: Double
        public let rnd4kReadIOPS: Double
        public let testSizeMB: Int

        public init(
            seqWriteMBps: Double,
            seqReadMBps: Double,
            rnd4kWriteMBps: Double,
            rnd4kWriteIOPS: Double,
            rnd4kReadMBps: Double,
            rnd4kReadIOPS: Double,
            testSizeMB: Int
        ) {
            self.seqWriteMBps = seqWriteMBps
            self.seqReadMBps = seqReadMBps
            self.rnd4kWriteMBps = rnd4kWriteMBps
            self.rnd4kWriteIOPS = rnd4kWriteIOPS
            self.rnd4kReadMBps = rnd4kReadMBps
            self.rnd4kReadIOPS = rnd4kReadIOPS
            self.testSizeMB = testSizeMB
        }
    }

    @Published public var isRunning: Bool = false
    @Published public var currentPhase: String = "Ready"
    @Published public var progress: Double = 0.0
    @Published public var result: BenchmarkResult? = nil

    public init() {}

    public func runBenchmark(testSizeMB: Int = 128, targetDirectory: URL = FileManager.default.temporaryDirectory) async {
        guard !isRunning else { return }
        self.isRunning = true
        self.progress = 0.0
        self.currentPhase = "Initializing Direct-IO File..."

        let testFile = targetDirectory.appendingPathComponent("osprey_bench_\(UUID().uuidString).dat").path

        self.currentPhase = "Sequential Write (1MB Direct-IO)..."
        self.progress = 0.1

        let res = await Task.detached(priority: .userInitiated) { () -> BenchmarkResult? in
            let fd = open(testFile, O_RDWR | O_CREAT | O_TRUNC, 0o644)
            guard fd >= 0 else { return nil }
            defer {
                close(fd)
                unlink(testFile)
            }

            // Disable Darwin OS page cache to benchmark raw storage hardware
            _ = fcntl(fd, F_NOCACHE, 1)

            let mb = 1024 * 1024
            let chunkSize = mb
            var buffer = [UInt8](repeating: 0x5A, count: chunkSize)

            // Phase 1: Sequential Write
            let tWrite0 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<testSizeMB {
                _ = write(fd, &buffer, chunkSize)
            }
            let writeDuration = max(0.001, CFAbsoluteTimeGetCurrent() - tWrite0)
            let seqWriteMBps = Double(testSizeMB) / writeDuration

            // Phase 2: Sequential Read
            lseek(fd, 0, SEEK_SET)
            let tRead0 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<testSizeMB {
                _ = read(fd, &buffer, chunkSize)
            }
            let readDuration = max(0.001, CFAbsoluteTimeGetCurrent() - tRead0)
            let seqReadMBps = Double(testSizeMB) / readDuration

            // Phase 3: Random 4K Write
            let blockSize4k = 4096
            var buf4k = [UInt8](repeating: 0xA5, count: blockSize4k)
            let totalBlocks = (testSizeMB * mb) / blockSize4k
            let opCount = min(2000, totalBlocks)

            let tRndW0 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<opCount {
                let randomBlock = Int.random(in: 0..<totalBlocks)
                lseek(fd, off_t(randomBlock * blockSize4k), SEEK_SET)
                _ = write(fd, &buf4k, blockSize4k)
            }
            let rndWDuration = max(0.001, CFAbsoluteTimeGetCurrent() - tRndW0)
            let rnd4kWriteIOPS = Double(opCount) / rndWDuration
            let rnd4kWriteMBps = (Double(opCount * blockSize4k) / (1024.0 * 1024.0)) / rndWDuration

            // Phase 4: Random 4K Read
            let tRndR0 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<opCount {
                let randomBlock = Int.random(in: 0..<totalBlocks)
                lseek(fd, off_t(randomBlock * blockSize4k), SEEK_SET)
                _ = read(fd, &buf4k, blockSize4k)
            }
            let rndRDuration = max(0.001, CFAbsoluteTimeGetCurrent() - tRndR0)
            let rnd4kReadIOPS = Double(opCount) / rndRDuration
            let rnd4kReadMBps = (Double(opCount * blockSize4k) / (1024.0 * 1024.0)) / rndRDuration

            return BenchmarkResult(
                seqWriteMBps: seqWriteMBps,
                seqReadMBps: seqReadMBps,
                rnd4kWriteMBps: rnd4kWriteMBps,
                rnd4kWriteIOPS: rnd4kWriteIOPS,
                rnd4kReadMBps: rnd4kReadMBps,
                rnd4kReadIOPS: rnd4kReadIOPS,
                testSizeMB: testSizeMB
            )
        }.value

        self.result = res
        self.currentPhase = "Completed"
        self.progress = 1.0
        self.isRunning = false
    }
}
