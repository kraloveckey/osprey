use crate::models::battery::BatteryReport;
use crate::models::disk::DiskDevice;

pub fn generate_crystal_report(disks: &[DiskDevice], battery: &BatteryReport) -> String {
    let mut out = String::new();

    out.push_str("----------------------------------------------------------------------------\n");
    out.push_str(&format!("Osprey {} (C) 2026 kraloveckey\n", env!("CARGO_PKG_VERSION")));
    out.push_str("                        High-Precision Storage & Hardware Diagnostics\n");
    out.push_str("----------------------------------------------------------------------------\n\n");

    out.push_str(&format!("    OS : {}\n", std::env::consts::OS));
    out.push_str(&format!("  Arch : {}\n", std::env::consts::ARCH));
    out.push_str("\n-- Disk List ---------------------------------------------------------------\n");

    for (idx, disk) in disks.iter().enumerate() {
        let health_str = disk
            .smart
            .as_ref()
            .map(|s| format!("{} ({}%)", s.health_status, s.health_percent.unwrap_or(100)))
            .unwrap_or_else(|| "Unknown".to_string());
        let temp_str = disk
            .smart
            .as_ref()
            .and_then(|s| s.temperature_celsius)
            .map(|t| format!("{} C", t))
            .unwrap_or_else(|| "-- C".to_string());

        out.push_str(&format!(
            " ({:02}) {} : {} [{}] - {} - {}\n",
            idx + 1,
            disk.model_name,
            disk.size_formatted,
            disk.id,
            health_str,
            temp_str
        ));
    }

    if battery.installed {
        out.push_str("\n-- Battery Health ----------------------------------------------------------\n");
        out.push_str(&format!(" Status : {}\n", battery.health_status));
        out.push_str(&format!(" Health : {:.1}%\n", battery.health_percent));
        out.push_str(&format!(" Cycles : {} / {} (Design)\n", battery.cycle_count, battery.design_cycle_count));
        out.push_str(&format!(" Capacity : {} mAh / {} mAh (Full / Design)\n", battery.full_charge_capacity_mah, battery.design_capacity_mah));
        if let Some(v) = battery.voltage_mv {
            out.push_str(&format!(" Voltage : {:.2} V\n", v as f64 / 1000.0));
        }
        out.push_str(&format!(" State : Current {}%, Connected: {}\n", battery.current_capacity_percent, battery.external_connected));
    }

    for (idx, disk) in disks.iter().enumerate() {
        out.push_str("\n----------------------------------------------------------------------------\n");
        out.push_str(&format!(" ({:02}) {}\n", idx + 1, disk.model_name));
        out.push_str("----------------------------------------------------------------------------\n");
        out.push_str(&format!("           Model : {}\n", disk.model_name));
        out.push_str(&format!("   Serial Number : {}\n", disk.serial_number));
        out.push_str(&format!("        Firmware : {}\n", disk.firmware_revision));
        out.push_str(&format!("       Disk Size : {} ({} Bytes)\n", disk.size_formatted, disk.size_bytes));
        out.push_str(&format!("   Rotation Rate : ---- ({})\n", disk.media_type));
        out.push_str(&format!("       Interface : {}\n", disk.protocol));

        if let Some(smart) = &disk.smart {
            if let Some(h) = smart.power_on_hours {
                out.push_str(&format!("  Power On Hours : {} hours\n", h));
            }
            if let Some(c) = smart.power_cycles {
                out.push_str(&format!("  Power On Count : {} count\n", c));
            }
            if let Some(r) = &smart.data_units_read_formatted {
                out.push_str(&format!("Host Reads (Total) : {}\n", r));
            }
            if let Some(w) = &smart.data_units_written_formatted {
                out.push_str(&format!("Host Writes (Total) : {}\n", w));
            }
            if let Some(temp) = smart.temperature_celsius {
                let temp_f = smart.temperature_fahrenheit.unwrap_or(((temp as f64 * 9.0 / 5.0) + 32.0).round() as i32);
                out.push_str(&format!("    Temperature : {} C ({} F)\n", temp, temp_f));
            }
            out.push_str(&format!(
                "   Health Status : {} ({} %)\n",
                smart.health_status,
                smart.health_percent.unwrap_or(100)
            ));
            if !smart.supported_features.is_empty() {
                out.push_str(&format!("        Features : {}\n", smart.supported_features.join(", ")));
            }

            if !smart.attributes.is_empty() {
                out.push_str("\n-- S.M.A.R.T. --------------------------------------------------------------\n");
                out.push_str("ID RawValues(16)   Attribute Name\n");
                for attr in &smart.attributes {
                    out.push_str(&format!(
                        "{:02X} {:<16} {}\n",
                        attr.id,
                        attr.raw_hex,
                        attr.name
                    ));
                }
            }
        }
    }

    out
}
