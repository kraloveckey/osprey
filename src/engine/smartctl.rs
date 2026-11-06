use std::path::PathBuf;
use std::process::Command;
use crate::models::disk::format_bytes;
use crate::models::smart::{AttributeStatus, HealthStatus, SmartAttribute, SmartReport};

pub fn find_smartctl() -> Option<PathBuf> {
    let candidate_paths = [
        "/opt/homebrew/bin/smartctl",
        "/usr/local/bin/smartctl",
        "/usr/bin/smartctl",
        "/bin/smartctl",
    ];

    for path in candidate_paths {
        let p = PathBuf::from(path);
        if p.exists() {
            return Some(p);
        }
    }

    if let Ok(output) = Command::new("which").arg("smartctl").output() {
        if output.status.success() {
            let s = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !s.is_empty() {
                let p = PathBuf::from(s);
                if p.exists() {
                    return Some(p);
                }
            }
        }
    }

    None
}

pub fn query_smart_data(device_node: &str) -> Option<SmartReport> {
    let smartctl_path = find_smartctl()?;

    let output = Command::new(&smartctl_path)
        .args(["-j", "-a", device_node])
        .output()
        .ok()?;

    let stdout_str = String::from_utf8_lossy(&output.stdout);
    if stdout_str.trim().is_empty() {
        return None;
    }

    let json_val: serde_json::Value = serde_json::from_str(&stdout_str).ok()?;
    parse_smart_json(&json_val)
}

pub fn parse_smart_json(val: &serde_json::Value) -> Option<SmartReport> {
    let mut report = SmartReport::default();

    if let Some(passed) = val.pointer("/smart_status/passed").and_then(|v| v.as_bool()) {
        report.health_status = if passed {
            HealthStatus::Good
        } else {
            HealthStatus::Bad
        };
    }

    if let Some(temp) = val.pointer("/temperature/current").and_then(|v| v.as_i64()) {
        report.temperature_celsius = Some(temp as i32);
        report.temperature_fahrenheit = Some(((temp as f64 * 9.0 / 5.0) + 32.0).round() as i32);
    }

    if let Some(power_cycles) = val.pointer("/power_cycle_count").and_then(|v| v.as_u64()) {
        report.power_cycles = Some(power_cycles);
    }

    if let Some(nvme) = val.get("nvme_smart_health_information_log") {
        if let Some(temp) = nvme.get("temperature").and_then(|v| v.as_i64()) {
            report.temperature_celsius = Some(temp as i32);
            report.temperature_fahrenheit = Some(((temp as f64 * 9.0 / 5.0) + 32.0).round() as i32);
        }

        let percentage_used = nvme.get("percentage_used").and_then(|v| v.as_u64()).map(|v| v as u8);
        report.percentage_used = percentage_used;

        if let Some(pct) = percentage_used {
            let remaining = 100_u8.saturating_sub(pct);
            report.health_percent = Some(remaining);
            if remaining < 10 {
                report.health_status = HealthStatus::Caution;
            }
        }

        let available_spare = nvme.get("available_spare").and_then(|v| v.as_u64()).map(|v| v as u8);
        let available_spare_thresh = nvme.get("available_spare_threshold").and_then(|v| v.as_u64()).map(|v| v as u8);
        report.available_spare = available_spare;
        report.available_spare_threshold = available_spare_thresh;

        if let (Some(spare), Some(thresh)) = (available_spare, available_spare_thresh) {
            if spare < thresh {
                report.health_status = HealthStatus::Caution;
            }
        }

        let crit_warn = nvme.get("critical_warning").and_then(|v| v.as_u64()).map(|v| v as u8);
        report.critical_warning = crit_warn;
        if let Some(w) = crit_warn {
            if w != 0 {
                report.health_status = HealthStatus::Bad;
            }
        }

        report.power_on_hours = nvme.get("power_on_hours").and_then(|v| v.as_u64());
        if report.power_cycles.is_none() {
            report.power_cycles = nvme.get("power_cycles").and_then(|v| v.as_u64());
        }
        report.unsafe_shutdowns = nvme.get("unsafe_shutdowns").and_then(|v| v.as_u64());
        report.media_errors = nvme.get("media_errors").and_then(|v| v.as_u64());
        report.error_entries_count = nvme.get("num_err_log_entries").and_then(|v| v.as_u64());
        report.host_read_commands = nvme.get("host_reads").and_then(|v| v.as_u64());
        report.host_write_commands = nvme.get("host_writes").and_then(|v| v.as_u64());

        if let Some(dur) = nvme.get("data_units_read").and_then(|v| v.as_u64()) {
            let bytes = dur.saturating_mul(512_000);
            report.data_units_read_bytes = Some(bytes);
            report.data_units_read_formatted = Some(format_bytes(bytes));
        }

        if let Some(duw) = nvme.get("data_units_written").and_then(|v| v.as_u64()) {
            let bytes = duw.saturating_mul(512_000);
            report.data_units_written_bytes = Some(bytes);
            report.data_units_written_formatted = Some(format_bytes(bytes));
        }

        report.attributes = generate_nvme_attributes(nvme);
    } else if let Some(ata_table) = val.pointer("/ata_smart_attributes/table").and_then(|v| v.as_array()) {
        let mut attrs = Vec::new();
        for item in ata_table {
            let id = item.get("id").and_then(|v| v.as_u64()).unwrap_or(0) as u8;
            let name = item.get("name").and_then(|v| v.as_str()).unwrap_or("Unknown").to_string();
            let current = item.get("value").and_then(|v| v.as_u64());
            let worst = item.get("worst").and_then(|v| v.as_u64());
            let threshold = item.get("thresh").and_then(|v| v.as_u64());
            let raw_val = item.pointer("/raw/value").and_then(|v| v.as_u64()).unwrap_or(0);
            let raw_hex = format!("0x{:012X}", raw_val);

            let mut status = AttributeStatus::Normal;
            if let (Some(cur), Some(thr)) = (current, threshold) {
                if cur <= thr && thr > 0 {
                    status = AttributeStatus::Critical;
                    report.health_status = HealthStatus::Bad;
                }
            }

            if id == 5 && raw_val > 0 {
                status = AttributeStatus::Warning;
                if report.health_status == HealthStatus::Good {
                    report.health_status = HealthStatus::Caution;
                }
            }

            attrs.push(SmartAttribute {
                id,
                name,
                current,
                worst,
                threshold,
                raw_value: raw_val,
                raw_hex,
                status,
            });
        }

        if report.health_percent.is_none() {
            report.health_percent = Some(if report.health_status == HealthStatus::Good { 100 } else { 85 });
        }
        report.attributes = attrs;
    }

    if let Some(features) = val.get("smart_support") {
        if features.get("enabled").and_then(|v| v.as_bool()).unwrap_or(false) {
            report.supported_features.push("S.M.A.R.T.".to_string());
        }
    }
    report.supported_features.push("TRIM".to_string());
    report.supported_features.push("VolatileWriteCache".to_string());

    if let Some(ver) = val.get("nvme_version").and_then(|v| v.get("string")).and_then(|v| v.as_str()) {
        report.nvme_version = Some(ver.to_string());
    }

    Some(report)
}

fn generate_nvme_attributes(nvme: &serde_json::Value) -> Vec<SmartAttribute> {
    let mut list = Vec::new();

    let defs: Vec<(u8, &str, &str)> = vec![
        (0x01, "Critical Warning", "critical_warning"),
        (0x02, "Composite Temperature", "temperature"),
        (0x03, "Available Spare", "available_spare"),
        (0x04, "Available Spare Threshold", "available_spare_threshold"),
        (0x05, "Percentage Used", "percentage_used"),
        (0x06, "Data Units Read", "data_units_read"),
        (0x07, "Data Units Written", "data_units_written"),
        (0x08, "Host Read Commands", "host_reads"),
        (0x09, "Host Write Commands", "host_writes"),
        (0x0A, "Controller Busy Time", "controller_busy_time"),
        (0x0B, "Power Cycles", "power_cycles"),
        (0x0C, "Power On Hours", "power_on_hours"),
        (0x0D, "Unsafe Shutdowns", "unsafe_shutdowns"),
        (0x0E, "Media and Data Integrity Errors", "media_errors"),
        (0x0F, "Error Information Log Entries", "num_err_log_entries"),
    ];

    for (id, name, field) in defs {
        let val = nvme.get(field).and_then(|v| v.as_u64()).unwrap_or(0);
        let mut status = AttributeStatus::Normal;

        if id == 0x01 && val != 0 {
            status = AttributeStatus::Critical;
        } else if id == 0x03 {
            let thresh = nvme.get("available_spare_threshold").and_then(|v| v.as_u64()).unwrap_or(10);
            if val < thresh {
                status = AttributeStatus::Warning;
            }
        } else if id == 0x0E && val > 0 {
            status = AttributeStatus::Critical;
        }

        list.push(SmartAttribute {
            id,
            name: name.to_string(),
            current: Some(100),
            worst: Some(100),
            threshold: Some(if id == 0x03 { 10 } else { 0 }),
            raw_value: val,
            raw_hex: format!("0x{:012X}", val),
            status,
        });
    }

    list
}
