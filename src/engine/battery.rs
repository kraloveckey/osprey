#![allow(dead_code)]

#[cfg(target_os = "macos")]
use std::process::Command;
use crate::models::battery::BatteryReport;

pub fn get_battery_telemetry() -> BatteryReport {
    #[cfg(target_os = "macos")]
    {
        get_macos_battery()
    }
    #[cfg(target_os = "linux")]
    {
        get_linux_battery()
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        BatteryReport::default()
    }
}

#[cfg(target_os = "macos")]
pub fn get_macos_battery() -> BatteryReport {
    let mut report = BatteryReport::default();

    let output = match Command::new("ioreg").args(["-rn", "AppleSmartBattery"]).output() {
        Ok(o) => String::from_utf8_lossy(&o.stdout).to_string(),
        Err(_) => return report,
    };

    if output.trim().is_empty() {
        return report;
    }

    report.installed = true;

    let extract_val = |key: &str| -> Option<String> {
        let pattern = format!("\"{}\"", key);
        for line in output.lines() {
            if let Some(pos) = line.find(&pattern) {
                let remainder = &line[pos + pattern.len()..];
                if let Some(eq_pos) = remainder.find('=') {
                    let after_eq = remainder[eq_pos + 1..].trim();
                    let end_pos = after_eq.find(|c| c == ',' || c == '}' || c == ';' || c == '\n').unwrap_or(after_eq.len());
                    let val = after_eq[..end_pos].trim().trim_matches('"');
                    return Some(val.to_string());
                }
            }
        }
        None
    };

    if let Some(s) = extract_val("CycleCount") {
        if let Ok(num) = s.parse::<u32>() {
            report.cycle_count = num;
        }
    }

    if let Some(s) = extract_val("DesignCycleCount9C") {
        if let Ok(num) = s.parse::<u32>() {
            report.design_cycle_count = num;
        }
    } else if let Some(s) = extract_val("DesignCycleCount") {
        if let Ok(num) = s.parse::<u32>() {
            report.design_cycle_count = num;
        }
    }

    if let Some(s) = extract_val("CurrentCapacity") {
        if let Ok(num) = s.parse::<u32>() {
            report.current_capacity_percent = num;
        }
    }

    if let Some(s) = extract_val("DesignCapacity") {
        if let Ok(num) = s.parse::<u32>() {
            report.design_capacity_mah = num;
        }
    }

    if let Some(s) = extract_val("FullChargeCapacity") {
        if let Ok(num) = s.parse::<u32>() {
            report.full_charge_capacity_mah = num;
        }
    }

    if let Some(s) = extract_val("NominalChargeCapacity") {
        if let Ok(num) = s.parse::<u32>() {
            report.nominal_charge_capacity_mah = Some(num);
        }
    }

    if let Some(s) = extract_val("RemainingCapacity") {
        if let Ok(num) = s.parse::<u32>() {
            report.remaining_capacity_mah = Some(num);
        }
    }

    if let Some(s) = extract_val("Voltage") {
        if let Ok(num) = s.parse::<u32>() {
            report.voltage_mv = Some(num);
        }
    }

    if let Some(s) = extract_val("InstantAmperage") {
        if let Ok(num) = s.parse::<i32>() {
            report.amperage_ma = Some(num);
        }
    } else if let Some(s) = extract_val("Amperage") {
        if let Ok(num) = s.parse::<i32>() {
            report.amperage_ma = Some(num);
        }
    }

    if let Some(s) = extract_val("IsCharging") {
        report.is_charging = s == "Yes" || s == "true" || s == "1";
    }

    if let Some(s) = extract_val("FullyCharged") {
        report.is_fully_charged = s == "Yes" || s == "true" || s == "1";
    }

    if let Some(s) = extract_val("ExternalConnected") {
        report.external_connected = s == "Yes" || s == "true" || s == "1";
    }

    if let Some(s) = extract_val("Watts") {
        if let Ok(num) = s.parse::<u32>() {
            report.power_adapter_watts = Some(num);
        }
    }

    if let Some(s) = extract_val("DeviceName") {
        report.device_name = Some(s);
    }

    if let Some(s) = extract_val("Serial") {
        report.serial_number = Some(s);
    }

    if report.design_capacity_mah > 0 && report.full_charge_capacity_mah > 0 {
        let pct = (report.full_charge_capacity_mah as f32 / report.design_capacity_mah as f32) * 100.0;
        report.health_percent = (pct * 10.0).round() / 10.0;
    } else if let Some(s) = extract_val("MaxCapacity") {
        if let Ok(num) = s.parse::<f32>() {
            report.health_percent = num;
        }
    }

    if report.health_percent >= 80.0 {
        report.health_status = "Good".to_string();
    } else if report.health_percent >= 60.0 {
        report.health_status = "Normal".to_string();
    } else {
        report.health_status = "Service Recommended".to_string();
    }

    report
}

#[cfg(target_os = "linux")]
pub fn get_linux_battery() -> BatteryReport {
    use std::fs;
    use std::path::{Path, PathBuf};

    let mut report = BatteryReport::default();

    // First system battery: type == Battery and not a peripheral (mouse,
    // keyboard, headset report scope == Device). Names vary: BAT0, BAT1,
    // CMB0, macsmc-battery, ...
    let Some(bat) = fs::read_dir("/sys/class/power_supply").ok().and_then(|entries| {
        let mut candidates: Vec<PathBuf> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| {
                let read = |f: &str| fs::read_to_string(p.join(f)).map(|s| s.trim().to_string()).ok();
                read("type").as_deref() == Some("Battery")
                    && read("scope").as_deref() != Some("Device")
                    && read("present").as_deref() != Some("0")
            })
            .collect();
        candidates.sort();
        candidates.into_iter().next()
    }) else {
        return report;
    };

    report.installed = true;

    let read_str = |file: &str| -> Option<String> {
        fs::read_to_string(Path::new(&bat).join(file))
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
    };
    let read_num = |file: &str| -> Option<u64> { read_str(file).and_then(|s| s.parse().ok()) };
    let read_signed = |file: &str| -> Option<i64> { read_str(file).and_then(|s| s.parse().ok()) };

    if let Some(c) = read_num("cycle_count") {
        report.cycle_count = c as u32;
    }

    if let Some(cap) = read_num("capacity") {
        report.current_capacity_percent = cap.min(100) as u32;
    }

    // Kernel units: charge_* in µAh, energy_* in µWh, voltage_* in µV.
    // energy-based packs are converted to mAh through the design voltage.
    let design_uv = read_num("voltage_min_design").or_else(|| read_num("voltage_now"));
    let to_mah = |charge_file: &str, energy_file: &str| -> Option<u64> {
        if let Some(uah) = read_num(charge_file) {
            return Some(uah / 1000);
        }
        let uwh = read_num(energy_file)?;
        let uv = design_uv.filter(|v| *v > 0)?;
        Some(((uwh as f64 / uv as f64) * 1000.0).round() as u64)
    };
    let full = to_mah("charge_full", "energy_full");
    let design = to_mah("charge_full_design", "energy_full_design");
    if let Some(f) = full {
        report.full_charge_capacity_mah = f as u32;
    }
    if let Some(d) = design {
        report.design_capacity_mah = d as u32;
    }
    report.remaining_capacity_mah = to_mah("charge_now", "energy_now").map(|v| v as u32);

    // Health from the raw counters so it is exact for both unit families.
    let full_raw = read_num("charge_full").or_else(|| read_num("energy_full"));
    let design_raw = read_num("charge_full_design").or_else(|| read_num("energy_full_design"));
    if let (Some(f), Some(d)) = (full_raw, design_raw) {
        if d > 0 {
            let pct = (f as f32 / d as f32 * 100.0).min(100.0);
            report.health_percent = (pct * 10.0).round() / 10.0;
        }
    }

    if let Some(status) = read_str("status") {
        report.is_charging = status.eq_ignore_ascii_case("charging");
        report.is_fully_charged = status.eq_ignore_ascii_case("full");
        report.external_connected = report.is_charging
            || report.is_fully_charged
            || status.eq_ignore_ascii_case("not charging");
    }
    // An online AC/USB supply is the authoritative "adapter connected" signal.
    if let Ok(entries) = fs::read_dir("/sys/class/power_supply") {
        for entry in entries.flatten() {
            let p = entry.path();
            let kind = fs::read_to_string(p.join("type")).unwrap_or_default();
            if matches!(kind.trim(), "Mains" | "USB" | "USB_PD" | "USB_C")
                && fs::read_to_string(p.join("online")).map(|s| s.trim() == "1").unwrap_or(false)
            {
                report.external_connected = true;
            }
        }
    }

    if let Some(v) = read_num("voltage_now") {
        report.voltage_mv = Some((v / 1000) as u32);
    }
    if let Some(ua) = read_signed("current_now") {
        // Positive while charging, negative while discharging (macOS convention).
        let ma = (ua.abs() / 1000) as i32;
        report.amperage_ma = Some(if report.is_charging { ma } else { -ma });
    }
    if let Some(t) = read_signed("temp") {
        report.temperature_celsius = Some(t as f32 / 10.0); // tenths of °C
    }
    if let Some(secs) = read_num("time_to_empty_now").or_else(|| read_num("time_to_full_now")) {
        report.time_remaining_minutes = Some((secs / 60) as u32);
    }

    report.device_name = read_str("model_name");
    report.serial_number = read_str("serial_number");

    report.health_status = if report.health_percent == 0.0 {
        "Unknown".to_string()
    } else if report.health_percent >= 80.0 {
        "Good".to_string()
    } else if report.health_percent >= 60.0 {
        "Normal".to_string()
    } else {
        "Service Recommended".to_string()
    };

    report
}
