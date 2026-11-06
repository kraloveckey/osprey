import DiskArbitration
import Foundation
import IOKit.ps
import Observation

/// Central snapshot store. Polls collectors on timers at different frequencies
/// and publishes the results for SwiftUI.
@MainActor
@Observable
public final class MetricsStore {
    public private(set) var cpu: CPUSnapshot?
    public private(set) var memory: MemorySnapshot?
    public private(set) var diskUsage: DiskUsageSnapshot?
    public private(set) var diskIO: DiskIORates?
    public private(set) var power: PowerSnapshot?
    public private(set) var cpuTemperature: Double?
    public private(set) var netRates: NetIORates?
    public private(set) var networkInfo: NetworkInfo?
    public private(set) var topProcesses: [ProcessUsage] = []
    public private(set) var systemInfo: SystemInfoSnapshot?
    public private(set) var healthScore: Int = 100
    public private(set) var cpuHistory = History()
    public private(set) var netInHistory = History()
    public private(set) var netOutHistory = History()
    public private(set) var diskReadHistory = History()
    public private(set) var diskWriteHistory = History()
    public private(set) var advisory: AdvisorySnapshot?
    public private(set) var smart: SMARTSnapshot?

    @ObservationIgnored private let cpuCollector = CPUCollector()
    @ObservationIgnored private let memoryCollector = MemoryCollector()
    @ObservationIgnored private let diskCollector = DiskCollector()
    @ObservationIgnored private let powerCollector = PowerCollector()
    @ObservationIgnored private let networkCollector = NetworkCollector()
    @ObservationIgnored private let processCollector = ProcessCollector()
    @ObservationIgnored private let systemInfoCollector = SystemInfoCollector()
    @ObservationIgnored private let smcTemperature = SMCTemperature()
    @ObservationIgnored private let advisoryCollector = AdvisoryCollector()
    @ObservationIgnored private let smartCollector = SMARTCollector()

    @ObservationIgnored private var previousCPU: CPUSample?
    @ObservationIgnored private var previousIO: (counters: DiskIOCounters, at: Date)?
    @ObservationIgnored private var previousNetIO: (counters: NetIOCounters, at: Date)?
    @ObservationIgnored private var previousProcs: (samples: [ProcSample], at: Date)?
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var powerWatcherSource: CFRunLoopSource?
    @ObservationIgnored private var powerStateObserver: AnyObject?
    @ObservationIgnored private var daSession: DASession?
    @ObservationIgnored private var isSamplingSMART = false
    @ObservationIgnored private var needsResampleSMART = false
    @ObservationIgnored private var isSamplingProcesses = false

    public init() {}

    deinit {
        timers.forEach { $0.invalidate() }
        if let powerWatcherSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerWatcherSource, .commonModes)
        }
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
        }
    }

    public var isLowPowerModeActive: Bool {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return true }
        if let p = power, !p.isCharging, !p.isACConnected, p.levelFraction < 0.20 {
            return true
        }
        return false
    }

    public func effectiveRefreshInterval() -> Double {
        let base = max(
            1.0,
            UserDefaults.standard.object(forKey: WidgetSettings.refreshIntervalKey) as? Double
                ?? WidgetSettings.defaultRefreshInterval
        )
        let batterySaver = UserDefaults.standard.object(forKey: WidgetSettings.batterySaverModeKey) as? Bool
            ?? WidgetSettings.defaultBatterySaverMode
        if batterySaver && isLowPowerModeActive {
            return max(base, 3.0)
        }
        return base
    }

    public func adaptTimerIntervals() {
        let fastInterval = effectiveRefreshInterval()
        guard !timers.isEmpty else { return }
        let currentTimer = timers[0]
        if abs(currentTimer.timeInterval - fastInterval) > 0.05 {
            currentTimer.invalidate()
            timers[0] = makeTimer(fastInterval, tolerance: fastInterval * 0.2) { $0.refreshFast() }
        }
    }

    public func start() {
        stop() // a repeated start() must not leave stale timers in the RunLoop
        refreshFast()
        refreshProcesses()
        refreshDiskUsage()
        refreshPower()
        refreshAdvisory()
        networkInfo = networkCollector.info()
        systemInfo = systemInfoCollector.sample()

        startHardwareWatchers()

        powerStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.adaptTimerIntervals()
            }
        }

        // Kick off immediate follow-up sample so deltas (CPU %, Disk IO, Net IO, Top Processes) populate immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshFast()
            self?.refreshProcesses()
        }

        let interval = effectiveRefreshInterval()
        timers = [
            makeTimer(interval, tolerance: interval * 0.2) { $0.refreshFast() },
            makeTimer(5, tolerance: 1) { $0.refreshProcesses() },
            makeTimer(10, tolerance: 2) { $0.refreshAdvisory() },
            makeTimer(60, tolerance: 15) { $0.refreshDiskUsage() },
            makeTimer(30, tolerance: 8) { $0.refreshPower() },
        ]
    }

    private func makeTimer(
        _ interval: TimeInterval,
        tolerance: TimeInterval,
        _ body: @escaping (MetricsStore) -> Void
    ) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in if let self { body(self) } }
        }
        timer.tolerance = tolerance
        return timer
    }

    private func startHardwareWatchers() {
        // 1. Instant Power Connect/Disconnect Watcher
        let powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let store = Unmanaged<MetricsStore>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                store.refreshPower()
            }
        }, Unmanaged.passUnretained(self).toOpaque())

        if let powerSource = powerSource?.takeRetainedValue() {
            self.powerWatcherSource = powerSource
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes)
        }

        // 2. Instant Disk Connect/Disconnect Watcher
        if let session = DASessionCreate(kCFAllocatorDefault) {
            self.daSession = session
            DASessionSetDispatchQueue(session, DispatchQueue.main)

            DARegisterDiskAppearedCallback(session, nil, { disk, context in
                guard let context else { return }
                let store = Unmanaged<MetricsStore>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in
                    store.refreshDiskUsage()
                    store.refreshAdvisory()
                }
            }, Unmanaged.passUnretained(self).toOpaque())

            DARegisterDiskDisappearedCallback(session, nil, { disk, context in
                guard let context else { return }
                let store = Unmanaged<MetricsStore>.fromOpaque(context).takeUnretainedValue()
                if let bsdName = DADiskGetBSDName(disk) {
                    let diskId = String(cString: bsdName)
                    Task { @MainActor in
                        store.removeDrive(diskId: diskId)
                        store.refreshDiskUsage()
                        store.refreshAdvisory()
                    }
                }
            }, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    public func removeDrive(diskId: String) {
        guard let current = smart else { return }
        let cleanId = diskId.replacingOccurrences(of: "/dev/", with: "")
        let filtered = current.drives.filter { drive in
            drive.diskId != cleanId && !cleanId.hasPrefix(drive.diskId) && !drive.diskId.hasPrefix(cleanId)
        }
        if filtered.count != current.drives.count {
            smart = SMARTSnapshot(
                drives: filtered,
                primaryDrive: current.primaryDrive,
                highestTempC: filtered.map { $0.temperatureC }.max() ?? 30,
                isOverheating: current.isOverheating
            )
        }
    }

    public func stop() {
        timers.forEach { $0.invalidate() }
        timers = []
        if let powerWatcherSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerWatcherSource, .commonModes)
            self.powerWatcherSource = nil
        }
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
            self.powerStateObserver = nil
        }
        self.daSession = nil
    }

    /// CPU + Memory + Disk I/O: every 2 seconds.
    public func refreshFast() {
        if let ticks = cpuCollector.sampleTicks() {
            if let prev = previousCPU {
                cpu = CPUUsage.snapshot(
                    previous: prev,
                    current: ticks,
                    loadAverage: cpuCollector.loadAverage()
                )
                if let snapshot = cpu {
                    cpuHistory.push(snapshot.totalUsage)
                }
            }
            previousCPU = ticks
        }
        if let mem = memoryCollector.sample() {
            memory = mem
        }
        if let counters = diskCollector.ioCounters() {
            let now = Date()
            if let prev = previousIO {
                let rates = DiskIO.rates(
                    previous: prev.counters,
                    current: counters,
                    interval: now.timeIntervalSince(prev.at)
                )
                diskIO = rates
                diskReadHistory.push(rates.read)
                diskWriteHistory.push(rates.write)
            }
            previousIO = (counters, now)
        } else {
            previousIO = nil // IOKit failure -> next sample pair starts fresh
        }
        if let counters = networkCollector.ioCounters() {
            let now = Date()
            if let prev = previousNetIO {
                let rates = NetIO.rates(
                    previous: prev.counters,
                    current: counters,
                    interval: now.timeIntervalSince(prev.at)
                )
                netRates = rates
                netInHistory.push(rates.download)
                netOutHistory.push(rates.upload)
            }
            previousNetIO = (counters, now)
        } else {
            previousNetIO = nil // getifaddrs failure -> next sample pair starts fresh
        }
        healthScore = HealthScore.compute(
            cpu: cpu?.totalUsage,
            memUsedFraction: memory?.usedFraction,
            diskUsedFraction: diskUsage?.usedFraction,
            batteryHealth: power?.healthFraction,
            batteryLevel: power?.levelFraction,
            isCharging: power?.isCharging ?? false
        )
    }

    /// Top processes: every 5 seconds. Offloaded to background utility queue
    /// so proc_listallpids and proc_pid_rusage loop over 500+ pids never blocks the main thread.
    public func refreshProcesses() {
        guard !isSamplingProcesses else { return }
        isSamplingProcesses = true
        let collector = processCollector
        let prev = previousProcs
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let procSamples = collector.sample()
            let now = Date()
            var calculatedTop: [ProcessUsage] = []
            if !procSamples.isEmpty {
                if let prev {
                    calculatedTop = ProcessMath.top(
                        previous: prev.samples,
                        current: procSamples,
                        interval: now.timeIntervalSince(prev.at)
                    )
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSamplingProcesses = false
                if !procSamples.isEmpty {
                    if !calculatedTop.isEmpty {
                        self.topProcesses = calculatedTop
                    }
                    self.previousProcs = (procSamples, now)
                } else {
                    self.previousProcs = nil
                }
            }
        }
    }

    /// Disk usage: every 60 seconds (changes slowly).
    public func refreshDiskUsage() {
        if let usage = diskCollector.usage() {
            diskUsage = usage
        }
    }

    /// Battery + network interface info + system info: every 30 seconds.
    public func refreshPower() {
        power = powerCollector.sample()
        cpuTemperature = smcTemperature.cpuTemperature()
        networkInfo = networkCollector.info()
        systemInfo = systemInfoCollector.sample()
        adaptTimerIntervals()
    }

    /// Advisory + S.M.A.R.T. storage telemetry: every 10 seconds.
    public func refreshAdvisory() {
        advisory = advisoryCollector.sample()
        if isSamplingSMART {
            needsResampleSMART = true
            return
        }
        isSamplingSMART = true
        needsResampleSMART = false
        let collector = smartCollector
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = collector.sample()
            DispatchQueue.main.async {
                self?.smart = snapshot
                self?.isSamplingSMART = false
                if self?.needsResampleSMART == true {
                    self?.refreshAdvisory()
                }
            }
        }
    }
}

