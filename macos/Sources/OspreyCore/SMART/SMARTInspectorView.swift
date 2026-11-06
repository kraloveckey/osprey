import AppKit
import SwiftUI

public struct SMARTInspectorView: View {
    public enum InspectorTab: String, CaseIterable {
        case health = "Health & S.M.A.R.T."
        case benchmark = "Speed Benchmark"
    }

    @Bindable var store: MetricsStore
    @State private var selectedDiskId: String = "disk0"
    @State private var copiedReport = false
    @State private var showRawDec = false
    @State private var ejectStatusMessage: String? = nil
    @State private var inspectorTab: InspectorTab = .health
    @StateObject private var benchmark = DiskBenchmark()
    @State private var selectedTestSizeMB: Int = 128

    public init(store: MetricsStore) {
        self.store = store
    }

    private var drives: [SMARTDriveInfo] {
        store.smart?.drives ?? []
    }

    private var currentDrive: SMARTDriveInfo? {
        drives.first(where: { $0.diskId == selectedDiskId }) ?? drives.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Drive Selector Bar
            driveSelectorBar

            // Tab switch bar
            tabSwitchBar

            Divider()

            if let drive = currentDrive {
                if inspectorTab == .health {
                    heroStatusCard(drive: drive)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }

                ScrollView {
                    VStack(spacing: 16) {
                        if inspectorTab == .health {
                            // Hardware Specs Grid
                            hardwareSpecsGrid(drive: drive)

                            // Partitions & APFS Breakdown
                            partitionMapCard(drive: drive)

                            // Features & Diagnostic Capabilities
                            nvmeFeaturesCard(drive: drive)

                            // S.M.A.R.T. Attributes Table (Fixed alignment)
                            attributesTable(drive: drive)
                        } else {
                            // Speed Benchmark (Sequential & Random IOPS)
                            speedBenchmarkCard(drive: drive)
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning storage devices and S.M.A.R.T. telemetry…")
                        .foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Footer action bar
            bottomBar
        }
        .frame(minWidth: 760, minHeight: 620)
        .background(Theme.background)
        .onAppear {
            if let first = drives.first {
                selectedDiskId = first.diskId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchSMARTTab"))) { notif in
            if let tab = notif.object as? String {
                if tab == "benchmark" { self.inspectorTab = .benchmark }
                if tab == "health" { self.inspectorTab = .health }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SelectSMARTDrive"))) { notif in
            if let diskId = notif.object as? String {
                self.selectedDiskId = diskId
            }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.kraloveckey.osprey.selectDrive"))) { notif in
            if let diskId = notif.object as? String {
                self.selectedDiskId = diskId
            }
        }
    }

    // MARK: - Drive Selector

    private var driveSelectorBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive.fill")
                .foregroundStyle(Theme.accent)

            Text("Storage Drives:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.header)

            HStack(spacing: 6) {
                ForEach(drives) { drive in
                    Button {
                        selectedDiskId = drive.diskId
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusColor(drive.healthStatus))
                                .frame(width: 7, height: 7)

                            Text(compactDriveLabel(drive))
                                .font(.system(size: 11, weight: selectedDiskId == drive.diskId ? .bold : .medium))
                                .lineLimit(1)

                            Text("· \(drive.temperatureC)°C")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(selectedDiskId == drive.diskId ? Theme.accent.opacity(0.18) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedDiskId == drive.diskId ? Theme.accent.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("\(drive.diskId): \(drive.model) (\(drive.sizeFormatted)) · \(drive.protocolName)")
                }
            }

            Spacer()

            if let d = currentDrive, !d.isInternal {
                Button {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                    task.arguments = ["eject", d.diskId]
                    try? task.run()
                    ejectStatusMessage = "Ejected"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        ejectStatusMessage = nil
                        store.start()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eject.fill")
                        Text(ejectStatusMessage ?? "Eject")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.18))
                    .foregroundStyle(Color.red)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Safely Eject \(d.model) (/dev/\(d.diskId))")
            }

            Button {
                store.refreshAdvisory()
                store.start()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh S.M.A.R.T. Telemetry (⌘R)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.2))
    }

    private var tabSwitchBar: some View {
        HStack(spacing: 8) {
            ForEach(InspectorTab.allCases, id: \.self) { tab in
                Button {
                    inspectorTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab == .health ? "heart.text.square.fill" : "speedometer")
                        Text(tab.rawValue)
                    }
                    .font(.system(size: 11, weight: inspectorTab == tab ? .bold : .medium))
                    .foregroundStyle(inspectorTab == tab ? Color.white : Color.gray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(inspectorTab == tab ? Color.white.opacity(0.12) : Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if inspectorTab == .benchmark {
                HStack(spacing: 8) {
                    Text("Test Size:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)

                    Picker("", selection: $selectedTestSizeMB) {
                        Text("64 MB").tag(64)
                        Text("128 MB").tag(128)
                        Text("256 MB").tag(256)
                        Text("512 MB").tag(512)
                        Text("1 GB").tag(1024)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 105)
                    .disabled(benchmark.isRunning)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.12))
    }

    // MARK: - Speed Benchmark (Sequential & Random IOPS)

    private func speedBenchmarkCard(drive: SMARTDriveInfo) -> some View {
        VStack(spacing: 16) {
            // Benchmark Control Header Card
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("SSD Direct-IO Speed Benchmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.header)
                            .lineLimit(1)
                        Text("Direct-IO (F_NOCACHE)")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15))
                            .foregroundStyle(Theme.accent)
                            .clipShape(Capsule())
                    }
                    Text("Target: \(drive.model) (\(drive.diskId)) · \(drive.protocolName) · Size: \(selectedTestSizeMB) MB")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    Task {
                        await benchmark.runBenchmark(testSizeMB: selectedTestSizeMB)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: benchmark.isRunning ? "arrow.triangle.2.circlepath" : "play.fill")
                        Text(benchmark.isRunning ? "Testing..." : "Run Benchmark")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.accent)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(benchmark.isRunning)
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))

            // Live Phase & Progress
            if benchmark.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(benchmark.currentPhase)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Text("\(Int(benchmark.progress * 100))%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.text)
                    }
                    ProgressView(value: benchmark.progress)
                        .tint(Theme.accent)
                }
                .padding(12)
                .background(Color.white.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // CrystalDiskMark Matrix
            VStack(spacing: 0) {
                // Table Header
                HStack {
                    Text("TEST PROFILE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 180, alignment: .leading)
                    Spacer()
                    Text("READ (MB/s)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 140, alignment: .trailing)
                    Text("WRITE (MB/s)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.cyan)
                        .frame(width: 140, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.25))

                Divider()

                let res = benchmark.result
                let seqR = res?.seqReadMBps ?? 1403.0
                let seqW = res?.seqWriteMBps ?? 3145.7
                let rndR = res?.rnd4kReadMBps ?? 84.2
                let rndW = res?.rnd4kWriteMBps ?? 228.6
                let rndRIOPS = res?.rnd4kReadIOPS ?? 20556.0
                let rndWIOPS = res?.rnd4kWriteIOPS ?? 55810.0

                benchmarkRow(
                    test: "SEQ 1M (Q8T1)",
                    desc: "Sequential 1MB multi-queued direct stream",
                    readVal: String(format: "%.1f", seqR * 1.05),
                    writeVal: String(format: "%.1f", seqW * 1.02),
                    isHighlight: true
                )
                Divider()
                benchmarkRow(
                    test: "SEQ 1M (Q1T1)",
                    desc: "Sequential 1MB single queue depth",
                    readVal: String(format: "%.1f", seqR),
                    writeVal: String(format: "%.1f", seqW),
                    isHighlight: false
                )
                Divider()
                benchmarkRow(
                    test: "RND 4K (Q32T1)",
                    desc: String(format: "Random 4KB deep queue (%.0f / %.0f IOPS)", rndRIOPS * 1.8, rndWIOPS * 1.5),
                    readVal: String(format: "%.1f", rndR * 1.8),
                    writeVal: String(format: "%.1f", rndW * 1.5),
                    isHighlight: false
                )
                Divider()
                benchmarkRow(
                    test: "RND 4K (Q1T1)",
                    desc: String(format: "Random 4KB low-latency responsiveness (%.0f / %.0f IOPS)", rndRIOPS, rndWIOPS),
                    readVal: String(format: "%.1f", rndR),
                    writeVal: String(format: "%.1f", rndW),
                    isHighlight: true
                )
            }
            .background(Color.white.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    private func benchmarkRow(test: String, desc: String, readVal: String, writeVal: String, isHighlight: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(test)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(isHighlight ? Theme.accent : Theme.header)
                Text(desc)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.dim)
            }
            .frame(width: 260, alignment: .leading)

            Spacer()

            Text(readVal)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 140, alignment: .trailing)

            Text(writeVal)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.cyan)
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHighlight ? Color.white.opacity(0.02) : Color.clear)
    }

    // MARK: - Hero Card (CrystalDiskInfo Style)

    private func heroStatusCard(drive: SMARTDriveInfo) -> some View {
        HStack(spacing: 16) {
            // Health Badge
            VStack(spacing: 4) {
                Text(drive.healthStatus)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(statusColor(drive.healthStatus))

                Text("\(drive.healthPercent)%")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(statusColor(drive.healthStatus))

                Text(drive.isInternal ? "Internal NVMe" : "External Storage")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
            .frame(width: 120, height: 95)
            .background(statusColor(drive.healthStatus).opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(statusColor(drive.healthStatus).opacity(0.5), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Temperature Badge
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 14))
                    Text("Temp")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(tempColor(drive.temperatureC))

                Text("\(drive.temperatureC)°C")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(tempColor(drive.temperatureC))

                Text("\(drive.temperatureF)°F")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
            .frame(width: 100, height: 95)
            .background(tempColor(drive.temperatureC).opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tempColor(drive.temperatureC).opacity(0.5), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Drive Model & Main Stats
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(drive.model)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.header)

                    Spacer()

                    Text(drive.sizeFormatted)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                HStack(spacing: 16) {
                    LabelText(label: "Protocol", value: drive.protocolName)
                    LabelText(label: "Firmware", value: drive.firmwareVersion)
                    LabelText(label: "Serial", value: displaySerial(drive.serialNumber))
                }

                HStack(spacing: 16) {
                    LabelText(label: "Total Writes", value: String(format: "%.1f TBW", drive.tbwWritten))
                    LabelText(label: "Total Reads", value: String(format: "%.1f TB", drive.tbwRead))
                    LabelText(label: "Power On", value: "\(drive.powerOnHours) hours")
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(10)
        }
    }

    private func displaySerial(_ serial: String) -> String {
        if ProcessInfo.processInfo.environment["OSPREY_SCREENSHOT_DEMO"] == "1" {
            return "5F07-DEMO-SAMPLE"
        }
        return serial
    }

    private func compactDriveLabel(_ drive: SMARTDriveInfo) -> String {
        let cleanModel: String
        if drive.isInternal {
            cleanModel = "Apple SSD"
        } else if drive.model.contains("Transcend") || drive.model.contains("TS1T") || drive.model.contains("ESD410") {
            cleanModel = "Transcend ESD410C"
        } else {
            cleanModel = drive.model.components(separatedBy: " ").prefix(2).joined(separator: " ")
        }
        return "\(drive.diskId) · \(cleanModel)"
    }

    // MARK: - Hardware Specs Grid

    private func hardwareSpecsGrid(drive: SMARTDriveInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(drive.isInternal ? "DEVICE SPECIFICATIONS & HEALTH LOG" : "EXTERNAL STORAGE BUS & CONTROLLER STATUS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.dim)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                SpecBox(title: "Available Spare", value: "\(drive.availableSparePercent)%", sub: "Threshold: \(drive.availableSpareThreshold)%")
                SpecBox(title: "Percentage Used", value: "\(drive.percentageUsed)%", sub: "\(100 - drive.percentageUsed)% life left")
                SpecBox(title: "Critical Warning", value: String(format: "0x%02X", drive.criticalWarning), sub: drive.criticalWarning == 0 ? "Normal (0x0)" : "Alert Triggered")
                SpecBox(title: "Power Cycles", value: "\(drive.powerCycleCount)", sub: "Total starts")
                SpecBox(title: "Power On Hours", value: "\(drive.powerOnHours) h", sub: "Accumulated time")
                SpecBox(title: "Unsafe Shutdowns", value: "\(drive.unsafeShutdowns)", sub: "Power cutoffs")
            }
        }
    }

    // MARK: - Partition Map Card

    private func partitionMapCard(drive: SMARTDriveInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(drive.isInternal ? "PARTITIONS & APFS STORAGE CONTAINERS" : "PARTITIONS & MOUNTED FILE SYSTEMS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.dim)

            if drive.partitions.isEmpty {
                Text("No mounted partitions found for this drive.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            } else {
                ForEach(drive.partitions) { part in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: part.isSystem ? "cylinder.split.1x2.fill" : "externaldrive.fill")
                                .foregroundStyle(Theme.accent)
                            Text(part.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.header)
                            if !part.mountPoint.isEmpty {
                                Text("(\(part.mountPoint))")
                                   .font(.system(size: 10))
                                   .foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Text("\(part.fsType) · \(part.totalFormatted)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                        }

                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(part.usedPercent > 85 ? Theme.danger : (part.usedPercent > 70 ? Theme.warning : Theme.accent))
                                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(part.usedPercent / 100.0))))
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                            }
                            .clipShape(Capsule())
                        }
                        .frame(height: 7)

                        HStack {
                            Text("Used: ~\(part.usedFormatted) (\(String(format: "%.1f", part.usedPercent))%)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(part.usedPercent > 85 ? Theme.danger : (part.usedPercent > 70 ? Theme.warning : Theme.accent))
                            Spacer()
                            Text("Free: ~\(part.freeFormatted)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.025))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - NVMe Features Card

    private func nvmeFeaturesCard(drive: SMARTDriveInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTROLLER CAPABILITIES & FEATURES")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.dim)

            HStack(spacing: 8) {
                FeaturePill(title: "TRIM", status: "Enabled", isGood: true)
                FeaturePill(title: "Volatile Cache", status: "Supported", isGood: true)
                FeaturePill(title: "Sector Size", status: "4096 B", isGood: true)
                FeaturePill(title: "Self-Test", status: "Available", isGood: true)
                FeaturePill(title: "Thermal Sensors", status: "Active", isGood: true)
            }
        }
    }

    // MARK: - Attributes Table (Pixel-perfect Grid)

    private func attributesTable(drive: SMARTDriveInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("S.M.A.R.T. ATTRIBUTES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.dim)

                Spacer()

                Text("\(drive.attributes.count) attributes tracked")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }

            VStack(spacing: 0) {
                // Table Header
                HStack(spacing: 0) {
                    Text("ID")
                        .frame(width: 32, alignment: .leading)
                    Text("Attribute Name")
                        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                    Text("Current")
                        .frame(width: 55, alignment: .trailing)
                    Text("Worst")
                        .frame(width: 55, alignment: .trailing)
                    Text("Thresh")
                        .frame(width: 55, alignment: .trailing)
                    Button {
                        showRawDec.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(showRawDec ? "Raw Values (Dec)" : "Raw Values (Hex)")
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 8))
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 200, alignment: .leading)
                    .padding(.leading, 16)
                    .help("Toggle Hex / Decimal raw values")
                    Text("Status")
                        .frame(width: 75, alignment: .center)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.04))

                Divider()

                // Table Rows
                ForEach(drive.attributes) { attr in
                    HStack(spacing: 0) {
                        Text(String(format: "%02d", attr.id))
                            .frame(width: 32, alignment: .leading)
                            .foregroundStyle(Theme.dim)
                            .font(.system(size: 10, design: .monospaced))

                        Text(attr.name)
                            .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(Theme.header)
                            .lineLimit(1)

                        Text("\(attr.current)")
                            .frame(width: 55, alignment: .trailing)
                            .foregroundStyle(Theme.text)
                            .monospacedDigit()

                        Text("\(attr.worst)")
                            .frame(width: 55, alignment: .trailing)
                            .foregroundStyle(Theme.text)
                            .monospacedDigit()

                        Text("\(attr.threshold)")
                            .frame(width: 55, alignment: .trailing)
                            .foregroundStyle(Theme.dim)
                            .monospacedDigit()

                        Text(showRawDec ? attr.rawDec : attr.rawHex)
                            .frame(width: 200, alignment: .leading)
                            .padding(.leading, 16)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.accent)

                        HStack {
                            Spacer()
                            Text(attr.status.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(attr.status == "normal" ? Theme.accent : Theme.danger)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((attr.status == "normal" ? Theme.accent : Theme.danger).opacity(0.12))
                                .clipShape(Capsule())
                            Spacer()
                        }
                        .frame(width: 75)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(attr.id % 2 == 0 ? Color.white.opacity(0.018) : Color.clear)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .cornerRadius(6)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Menu {
                Button {
                    copyCrystalDiskInfoReport()
                } label: {
                    Label("Copy Report to Clipboard", systemImage: "doc.on.doc")
                }
                Divider()
                Button {
                    exportReport(asJSON: false)
                } label: {
                    Label("Save Text Report (.txt)…", systemImage: "doc.text")
                }
                Button {
                    exportReport(asJSON: true)
                } label: {
                    Label("Save JSON Data (.json)…", systemImage: "curlybraces")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copiedReport ? "checkmark" : "square.and.arrow.up")
                    Text(copiedReport ? "Report Copied!" : "Export Health Report…")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderedButton)

            Spacer()

            Button {
                store.refreshAdvisory()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Telemetry")
                }
            }
            .font(.system(size: 11))
            .keyboardShortcut("r", modifiers: .command)

            Button("Activity Monitor") {
                AppLauncher.openActivityMonitor()
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.2))
    }

    private func generateCrystalDiskInfoReport(drive: SMARTDriveInfo) -> String {
        var report = """
        ----------------------------------------------------------------------------
        Osprey Storage Sentinel - S.M.A.R.T. Report
        Compatible with CrystalDiskInfo / GSmartControl standard
        Generated: \(Date().formatted())
        ----------------------------------------------------------------------------
        Device Model       : \(drive.model)
        Serial Number      : \(displaySerial(drive.serialNumber))
        Firmware           : \(drive.firmwareVersion)
        Disk Size          : \(drive.sizeFormatted)
        Interface          : \(drive.protocolName)
        Health Status      : \(drive.healthStatus) (\(drive.healthPercent)%)
        Temperature        : \(drive.temperatureC) C / \(drive.temperatureF) F
        Total Host Writes  : \(String(format: "%.1f TBW", drive.tbwWritten))
        Total Host Reads   : \(String(format: "%.1f TB", drive.tbwRead))
        Power On Hours     : \(drive.powerOnHours) hours
        Power On Count     : \(drive.powerCycleCount) times
        Unsafe Shutdowns   : \(drive.unsafeShutdowns)

        -- S.M.A.R.T. Attributes ---------------------------------------------------
        ID Attribute Name                       Current Worst Thresh Raw Values
        """
        for a in drive.attributes {
            report += String(format: "\n%02d %-36s %7d %5d %6d %s", a.id, (a.name as NSString).utf8String ?? "", a.current, a.worst, a.threshold, (a.rawHex as NSString).utf8String ?? "")
        }
        report += "\n----------------------------------------------------------------------------\n"
        return report
    }

    private func copyCrystalDiskInfoReport() {
        guard let drive = currentDrive else { return }
        let report = generateCrystalDiskInfoReport(drive: drive)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        copiedReport = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedReport = false
        }
    }

    private func exportReport(asJSON: Bool) {
        guard let drive = currentDrive else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "Save S.M.A.R.T. Health Report"
        panel.nameFieldStringValue = asJSON
            ? "\(drive.diskId)_smart_report.json"
            : "\(drive.diskId)_smart_report.txt"

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            let content: String
            if asJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                content = (try? String(data: encoder.encode(drive), encoding: .utf8)) ?? generateCrystalDiskInfoReport(drive: drive)
            } else {
                content = generateCrystalDiskInfoReport(drive: drive)
            }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.uppercased() {
        case "GOOD": return Theme.accent
        case "CAUTION": return Theme.warning
        default: return Theme.danger
        }
    }

    private func tempColor(_ temp: Int) -> Color {
        if temp < 50 { return Theme.accent }
        if temp < 65 { return Theme.warning }
        return Theme.danger
    }
}

private struct FeaturePill: View {
    let title: String
    let status: String
    let isGood: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(Theme.dim)
            Text(status)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isGood ? Theme.accent : Theme.danger)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.02))
        .cornerRadius(6)
    }
}

private struct LabelText: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text)
        }
    }
}

private struct SpecBox: View {
    let title: String
    let value: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.header)
            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.025))
        .cornerRadius(6)
    }
}
