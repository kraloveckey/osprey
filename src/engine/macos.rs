use std::process::Command;
use crate::models::disk::{format_bytes, DiskDevice, PartitionInfo};
use crate::models::smart::{HealthStatus, SmartReport};
use crate::engine::smartctl;

pub fn scan_macos_disks() -> Vec<DiskDevice> {
    let mut devices = Vec::new();

    let diskutil_output = match Command::new("diskutil").arg("list").output() {
        Ok(o) => String::from_utf8_lossy(&o.stdout).to_string(),
        Err(_) => return devices,
    };

    let mut disk_ids = Vec::new();
    for line in diskutil_output.lines() {
        let line = line.trim();
        if line.starts_with("/dev/disk") && line.contains("physical") {
            if let Some(pos) = line.find(' ') {
                let dev_path = &line[..pos];
                let disk_id = dev_path.replace("/dev/", "");
                if !disk_ids.contains(&disk_id) {
                    disk_ids.push(disk_id);
                }
            }
        }
    }

    if disk_ids.is_empty() {
        disk_ids.push("disk0".to_string());
    }

    let partitions_map = scan_storage_volumes();

    for disk_id in disk_ids {
        if let Some(dev) = inspect_disk(&disk_id, &partitions_map) {
            devices.push(dev);
        }
    }

    devices
}

fn inspect_disk(disk_id: &str, partitions_map: &[(Option<String>, PartitionInfo)]) -> Option<DiskDevice> {
    let device_node = format!("/dev/{}", disk_id);
    let output = Command::new("diskutil")
        .args(["info", disk_id])
        .output()
        .ok()?;

    let text = String::from_utf8_lossy(&output.stdout);
    if text.trim().is_empty() {
        return None;
    }

    let extract_field = |key: &str| -> Option<String> {
        for line in text.lines() {
            let line = line.trim();
            if line.starts_with(key) {
                if let Some(colon_pos) = line.find(':') {
                    let val = line[colon_pos + 1..].trim();
                    return Some(val.to_string());
                }
            }
        }
        None
    };

    let mut model_name = extract_field("Device / Media Name").unwrap_or_else(|| "Physical Drive".to_string());
    let protocol = extract_field("Protocol").unwrap_or_else(|| "Unknown".to_string());
    let location = extract_field("Device Location").unwrap_or_else(|| "Internal".to_string());
    let is_internal = location.eq_ignore_ascii_case("Internal");
    let removable = extract_field("Removable Media").unwrap_or_else(|| "Fixed".to_string());
    let is_removable = removable.eq_ignore_ascii_case("Removable") || !is_internal;
    let solid_state = extract_field("Solid State").unwrap_or_else(|| "Yes".to_string());
    let media_type = if solid_state.eq_ignore_ascii_case("Yes") {
        "SSD".to_string()
    } else {
        "HDD".to_string()
    };

    let mut size_bytes = 0u64;
    if let Some(sz_str) = extract_field("Disk Size") {
        if let Some(start) = sz_str.find('(') {
            if let Some(end) = sz_str[start..].find("Bytes)") {
                let num_str = sz_str[start + 1..start + end].trim().replace(',', "");
                if let Ok(b) = num_str.parse::<u64>() {
                    size_bytes = b;
                }
            }
        }
    }

    let mut smart_report = smartctl::query_smart_data(&device_node);

    let mut serial_number = "Unknown".to_string();
    let mut firmware_revision = "Unknown".to_string();

    if smart_report.is_some() {
        if let Some(smartctl_path) = smartctl::find_smartctl() {
            if let Ok(json_out) = Command::new(smartctl_path).args(["-j", "-i", &device_node]).output() {
                if let Ok(val) = serde_json::from_slice::<serde_json::Value>(&json_out.stdout) {
                    if let Some(m) = val.get("model_name").and_then(|v| v.as_str()) {
                        model_name = m.to_string();
                    }
                    if let Some(s) = val.get("serial_number").and_then(|v| v.as_str()) {
                        serial_number = s.to_string();
                    }
                    if let Some(f) = val.get("firmware_version").and_then(|v| v.as_str()) {
                        firmware_revision = f.to_string();
                    }
                }
            }
        }
    }

    if smart_report.is_none() {
        let smart_status_str = extract_field("SMART Status").unwrap_or_default();
        let health_status = if smart_status_str.eq_ignore_ascii_case("Verified") {
            HealthStatus::Good
        } else if smart_status_str.eq_ignore_ascii_case("Failing") {
            HealthStatus::Bad
        } else {
            HealthStatus::Unknown
        };

        smart_report = Some(SmartReport {
            health_status,
            health_percent: Some(if health_status == HealthStatus::Good { 100 } else { 50 }),
            ..SmartReport::default()
        });
    }

    let partitions: Vec<PartitionInfo> = partitions_map
        .iter()
        .filter(|(phys_name, p)| {
            p.id.starts_with(disk_id) || phys_name.as_deref() == Some(&model_name)
        })
        .map(|(_, p)| p.clone())
        .collect();

    Some(DiskDevice {
        id: disk_id.to_string(),
        device_node,
        model_name,
        serial_number,
        firmware_revision,
        protocol,
        media_type,
        size_bytes,
        size_formatted: format_bytes(size_bytes),
        is_internal,
        is_removable,
        partitions,
        smart: smart_report,
    })
}

fn scan_storage_volumes() -> Vec<(Option<String>, PartitionInfo)> {
    let mut volumes = Vec::new();

    if let Ok(output) = Command::new("system_profiler").args(["SPStorageDataType", "-json"]).output() {
        if let Ok(val) = serde_json::from_slice::<serde_json::Value>(&output.stdout) {
            if let Some(list) = val.get("SPStorageDataType").and_then(|v| v.as_array()) {
                for item in list {
                    let bsd = item.get("bsd_name").and_then(|v| v.as_str()).unwrap_or("").to_string();
                    let name = item.get("_name").and_then(|v| v.as_str()).map(|s| s.to_string());
                    let mount = item.get("mount_point").and_then(|v| v.as_str()).map(|s| s.to_string());
                    let fs = item.get("file_system").and_then(|v| v.as_str()).map(|s| s.to_string());
                    let size_bytes = item.get("size_in_bytes").and_then(|v| v.as_u64()).unwrap_or(0);
                    let is_boot = mount.as_deref() == Some("/");

                    let phys_name = item
                        .get("physical_drive")
                        .and_then(|pd| pd.get("device_name"))
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string());

                    if !bsd.is_empty() {
                        volumes.push((
                            phys_name,
                            PartitionInfo {
                                id: bsd,
                                name,
                                size_bytes,
                                size_formatted: format_bytes(size_bytes),
                                mount_point: mount,
                                file_system: fs,
                                is_boot_volume: is_boot,
                            },
                        ));
                    }
                }
            }
        }
    }

    volumes
}
