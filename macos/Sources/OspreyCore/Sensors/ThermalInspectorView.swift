import AppKit
import SwiftUI

/// Hardware Thermal Sensors & Cooling Architecture inspector (TG Pro / Macs Fan Control style).
public struct ThermalInspectorView: View {
    @Bindable var store: MetricsStore
    @State private var report: ThermalCollector.ThermalReport?
    private let collector = ThermalCollector()

    public init(store: MetricsStore) {
        self.store = store
    }

    private func tempColor(_ temp: Double) -> Color {
        if temp >= 85 { return Color.red }
        if temp >= 70 { return Color.orange }
        if temp >= 50 { return Color.yellow }
        return Color.green
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Thermal Sensors & Cooling")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white)
                        if let r = report {
                            Text(r.isPassive ? "Passive Fanless" : "Active Fan")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(Color.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text("Per-core silicon junction thermistors, chassis dissipation & cooling health")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gray)
                }

                Spacer()

                Button(action: refresh) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            if let rep = report {
                // Top Telemetry Cards
                HStack(spacing: 14) {
                    // Thermal Pressure Card
                    VStack(alignment: .leading, spacing: 6) {
                        Text("THERMAL PRESSURE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.gray)
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text(rep.thermalPressure)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        Text("No throttling detected · 100% compute capacity")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.gray)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))

                    // Cooling Architecture Card
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COOLING ARCHITECTURE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.gray)
                        HStack(spacing: 6) {
                            Image(systemName: rep.isPassive ? "leaf.fill" : "fanblades.fill")
                                .foregroundStyle(rep.isPassive ? Color.green : Color.cyan)
                            Text(rep.isPassive ? "Silent Passive Dissipation" : "\(rep.fanRPM) RPM")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        Text(rep.isPassive ? "MacBook Air Unibody Aluminum Heatsink" : "Dual High-Efficiency Turbofan")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.gray)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .padding(.horizontal, 20)

                // Fan Tachometers (if active cooling)
                if !rep.fans.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(rep.fans) { fan in
                            HStack(spacing: 10) {
                                Image(systemName: "fanblades")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.cyan)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(fan.name)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(Color.white)
                                        Spacer()
                                        Text("\(fan.rpm) RPM (\(fan.percent)%)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color.cyan)
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                                            Capsule().fill(Color.cyan).frame(width: max(2, min(geo.size.width, geo.size.width * CGFloat(fan.percent) / 100.0)), height: 4)
                                        }
                                    }
                                    .frame(height: 4)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Cooling Policy Bar
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Color.gray)
                    Text("Thermal Policy:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.gray)
                    Text(rep.coolingProfile)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text(rep.isPassive ? "Passive Thermal Dissipation (Zero Acoustics)" : "Active SMC Dynamic Closed-Loop")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.04), lineWidth: 1))
                .padding(.horizontal, 20)

                // Thermal Zones Grid
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("SILICON THERMAL SENSOR MATRIX")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.gray)
                        Spacer()
                        Text("Average: \(String(format: "%.1f°C", rep.averageTempC)) - Peak: \(String(format: "%.1f°C", rep.peakTempC))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.gray)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(rep.zones) { zone in
                            sensorTile(zone)
                        }
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
                .padding(.horizontal, 20)
            } else {
                ProgressView()
                    .frame(height: 200)
            }

            Spacer()
        }
        .frame(width: 640, height: 530)
        .background(Theme.background)
        .onAppear {
            refresh()
        }
    }

    private func sensorTile(_ zone: ThermalCollector.ThermalZone) -> some View {
        let col = tempColor(zone.tempC)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: zone.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.gray)
                Text(zone.category)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.gray)
                Spacer()
                Text(String(format: "%.1f°C", zone.tempC))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(col)
            }

            Text(zone.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)

            // Mini bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)
                    Capsule()
                        .fill(col)
                        .frame(width: max(2, min(geo.size.width, geo.size.width * CGFloat(zone.tempC) / 100.0)), height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    private func refresh() {
        let bTemp = store.power?.temperatureCelsius
        let sTemp = store.smart?.primaryDrive?.temperatureC
        self.report = collector.collectReport(batteryTempC: bTemp, ssdTempC: sTemp)
    }
}
