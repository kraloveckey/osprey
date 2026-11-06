/// Telemetry for connected AC charger and charging cable authentication.
public struct AdapterInfo: Equatable, Sendable {
    public let isConnected: Bool
    public let watts: Int
    public let isAppleOriginal: Bool
    public let adapterName: String
    public let vendor: String
    public let cableDescription: String
    public let isCableOriginal: Bool

    public init(
        isConnected: Bool,
        watts: Int,
        isAppleOriginal: Bool,
        adapterName: String,
        vendor: String,
        cableDescription: String,
        isCableOriginal: Bool
    ) {
        self.isConnected = isConnected
        self.watts = watts
        self.isAppleOriginal = isAppleOriginal
        self.adapterName = adapterName
        self.vendor = vendor
        self.cableDescription = cableDescription
        self.isCableOriginal = isCableOriginal
    }
}

/// Battery snapshot. Optional fields come from the AppleSmartBattery registry
/// and may be absent (e.g. a Mac mini has no battery at all -> snapshot is nil).
public struct PowerSnapshot: Equatable, Sendable {
    public let levelFraction: Double        // 0...1
    public let healthFraction: Double?      // 0...1
    public let isCharging: Bool
    public let isACConnected: Bool
    public let timeRemainingMinutes: Int?   // time to discharge or to full charge
    public let isTimeEstimated: Bool
    public let cycleCount: Int?
    public let temperatureCelsius: Double?
    public let adapter: AdapterInfo?
    public let voltageMillivolts: Int?
    public let amperageMilliamp: Int?
    public let systemWatts: Double?
    public let isLowPowerMode: Bool

    public init(
        levelFraction: Double,
        healthFraction: Double?,
        isCharging: Bool,
        isACConnected: Bool = false,
        timeRemainingMinutes: Int?,
        isTimeEstimated: Bool = false,
        cycleCount: Int?,
        temperatureCelsius: Double?,
        adapter: AdapterInfo? = nil,
        voltageMillivolts: Int? = nil,
        amperageMilliamp: Int? = nil,
        systemWatts: Double? = nil,
        isLowPowerMode: Bool = false
    ) {
        self.levelFraction = levelFraction
        self.healthFraction = healthFraction
        self.isCharging = isCharging
        self.isACConnected = isACConnected
        self.timeRemainingMinutes = timeRemainingMinutes
        self.isTimeEstimated = isTimeEstimated
        self.cycleCount = cycleCount
        self.temperatureCelsius = temperatureCelsius
        self.adapter = adapter
        self.voltageMillivolts = voltageMillivolts
        self.amperageMilliamp = amperageMilliamp
        self.systemWatts = systemWatts
        self.isLowPowerMode = isLowPowerMode
    }
}
