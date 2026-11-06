import Foundation
import IOKit
import IOKit.ps

/// Battery data collector: IOPowerSources (level, status) + AppleSmartBattery registry
/// (cycles, capacities, temperature).
public struct PowerCollector {
    public init() {}

    /// nil - if no battery power source is present (desktop Mac).
    public func sample() -> PowerSnapshot? {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        // Look specifically for the internal battery: the first list entry may be an external UPS.
        let internalBattery = list.first { ref in
            let d = IOPSGetPowerSourceDescription(blob, ref)?.takeUnretainedValue() as? [String: Any]
            return d?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
        guard
            let source = internalBattery,
            let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else { return nil }

        let currentCapacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
        let battery = smartBatteryProperties()
        let isConnected = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue || (battery?["ExternalConnected"] as? Bool == true)

        let batteryData = battery?["BatteryData"] as? [String: Any]
        let rawCurrent = (batteryData?["AppleRawCurrentCapacity"] as? Int)
            ?? (batteryData?["RemainingCapacity"] as? Int)
            ?? (battery?["AppleRawCurrentCapacity"] as? Int)
            ?? (battery?["RemainingCapacity"] as? Int)

        let cycleCount = (battery?["CycleCount"] as? Int) ?? (batteryData?["CycleCount"] as? Int)
        let designCapacity = (batteryData?["DesignCapacity"] as? Int) ?? (battery?["DesignCapacity"] as? Int)
        let rawMax = (batteryData?["AppleRawMaxCapacity"] as? Int)
            ?? (batteryData?["FullChargeCapacity"] as? Int)
            ?? (battery?["AppleRawMaxCapacity"] as? Int)
            ?? (battery?["NominalChargeCapacity"] as? Int)

        var timeRemaining: Int? = nil
        var isTimeEstimated = false

        if isConnected {
            if isCharging {
                let m = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
                if m > 0 && m < 1440 {
                    timeRemaining = m
                } else if let rawCurrent, let rawMax, rawMax > rawCurrent {
                    let remainingChargeMAh = rawMax - rawCurrent
                    let amperage = (battery?["InstantAmperage"] as? Int) ?? (battery?["Amperage"] as? Int) ?? 0
                    if amperage > 50 {
                        timeRemaining = Int((Double(remainingChargeMAh) / Double(amperage)) * 60.0)
                    } else {
                        timeRemaining = Int((Double(remainingChargeMAh) / 2000.0) * 60.0)
                        isTimeEstimated = true
                    }
                }
            }
        } else {
            let m = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            let avgTimeToEmpty = (battery?["AvgTimeToEmpty"] as? Int) ?? (batteryData?["AvgTimeToEmpty"] as? Int) ?? 65535

            if m > 0 && m < 1440 {
                timeRemaining = m
            } else if avgTimeToEmpty > 0 && avgTimeToEmpty < 1440 {
                timeRemaining = avgTimeToEmpty
            } else {
                let amperage = (battery?["InstantAmperage"] as? Int) ?? (battery?["Amperage"] as? Int) ?? 0
                if let rawCurrent, amperage < -50 {
                    let calculated = Int((Double(rawCurrent) / abs(Double(amperage))) * 60.0)
                    if calculated > 0 && calculated < 1440 {
                        timeRemaining = calculated
                    }
                } else if let rawCurrent, rawCurrent > 0 {
                    let baselineMin = Int((Double(rawCurrent) / 380.0) * 60.0)
                    if baselineMin > 0 && baselineMin < 1440 {
                        timeRemaining = baselineMin
                        isTimeEstimated = true
                    }
                } else if currentCapacity > 0 {
                    let baselineMin = Int((Double(currentCapacity) / 100.0) * 14.0 * 60.0)
                    timeRemaining = baselineMin
                    isTimeEstimated = true
                }
            }
        }

        var health: Double?
        if let rawMax, let designCapacity {
            health = BatteryMath.health(rawMaxCapacity: rawMax, designCapacity: designCapacity)
        }
        let temperature = (battery?["Temperature"] as? Int)
            .map(BatteryMath.celsius(fromRawTemperature:))

        // Adapter & Cable inspection
        var adapterInfo: AdapterInfo? = nil

        if isConnected {
            let details = (battery?["AdapterDetails"] as? [String: Any])
                ?? ((battery?["AppleRawAdapterDetails"] as? [[String: Any]])?.first)
            let watts = details?["Watts"] as? Int ?? (battery?["Watts"] as? Int ?? 60)
            let adapterID = details?["AdapterID"] as? Int ?? 0
            let descStr = (details?["Description"] as? String) ?? ""
            let manufacturer = (details?["Manufacturer"] as? String) ?? ""
            let rawName = (details?["Name"] as? String) ?? ""
            let serial = (details?["SerialString"] as? String) ?? ""
            let modelStr = String(describing: details?["Model"] ?? "")

            let isApple = manufacturer.localizedCaseInsensitiveContains("Apple")
                || rawName.localizedCaseInsensitiveContains("Apple")
                || descStr.localizedCaseInsensitiveContains("Apple")
                || serial.uppercased().hasPrefix("C4H")
                || serial.uppercased().hasPrefix("C4M")
                || serial.uppercased().hasPrefix("W0")
                || adapterID == 0x05ac
                || adapterID == 28675
                || modelStr.contains("0x7003")

            let finalName: String
            if !rawName.isEmpty {
                finalName = rawName.localizedCaseInsensitiveContains("Apple") ? rawName : "Apple \(rawName)"
            } else if isApple {
                finalName = "Apple \(watts)W USB-C Power Adapter"
            } else {
                finalName = "Third-Party USB-PD Power Adapter (\(watts)W)"
            }

            if isApple {
                adapterInfo = AdapterInfo(
                    isConnected: true,
                    watts: watts,
                    isAppleOriginal: true,
                    adapterName: finalName,
                    vendor: "Apple Inc. (OEM)",
                    cableDescription: "Apple USB-C / MagSafe Power Delivery Cable",
                    isCableOriginal: true
                )
            } else {
                let vendorName = manufacturer.isEmpty ? "Third-Party USB-PD" : manufacturer
                adapterInfo = AdapterInfo(
                    isConnected: true,
                    watts: watts,
                    isAppleOriginal: false,
                    adapterName: finalName,
                    vendor: vendorName,
                    cableDescription: "Standard USB-C Charging Cable (Non-OEM)",
                    isCableOriginal: false
                )
            }
        }

        let voltageMV = (battery?["Voltage"] as? Int) ?? (batteryData?["Voltage"] as? Int)
        let amperageMA = (battery?["InstantAmperage"] as? Int)
            ?? (battery?["Amperage"] as? Int)
            ?? (batteryData?["InstantAmperage"] as? Int)
            ?? (batteryData?["Amperage"] as? Int)

        var systemWatts: Double? = nil
        if let v = voltageMV, let a = amperageMA {
            systemWatts = (Double(v) * Double(a)) / 1_000_000.0
        }

        let isLPM = ProcessInfo.processInfo.isLowPowerModeEnabled

        return PowerSnapshot(
            levelFraction: maxCapacity > 0 ? min(1.0, Double(currentCapacity) / Double(maxCapacity)) : 0,
            healthFraction: health,
            isCharging: isCharging,
            isACConnected: isConnected,
            timeRemainingMinutes: timeRemaining,
            isTimeEstimated: isTimeEstimated,
            cycleCount: cycleCount,
            temperatureCelsius: temperature,
            adapter: adapterInfo,
            voltageMillivolts: voltageMV,
            amperageMilliamp: amperageMA,
            systemWatts: systemWatts,
            isLowPowerMode: isLPM
        )
    }

    private func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS
        else { return nil }
        return unmanaged?.takeRetainedValue() as? [String: Any]
    }
}
