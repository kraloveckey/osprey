#![allow(dead_code)]

use std::fs;
use std::process::Command;
use crate::models::disk::{format_bytes, DiskDevice, PartitionInfo};
use crate::engine::smartctl;

pub fn scan_linux_disks() -> Vec<DiskDevice> {
    let mut devices = Vec::new();

    let block_dir = std::path::Path::new("/sys/block");
    if !block_dir.exists() {
        return devices;
    }

    if let Ok(entries) = fs::read_dir(block_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if !is_physical_block_device(&name) {
                continue;
            }

            let dev_node = format!("/dev/{}", name);
            if let Some(dev) = inspect_linux_disk(&name, &dev_node) {
                devices.push(dev);
            }
        }
    }

    devices.sort_by(|a, b| a.id.cmp(&b.id));
    devices
}

/// True for real storage devices under /sys/block; false for virtual ones
/// (loop, ramdisk, zram swap, device-mapper/LVM, md software RAID,
/// network block devices, floppies, optical drives).
pub fn is_physical_block_device(name: &str) -> bool {
    const VIRTUAL_PREFIXES: [&str; 8] = ["loop", "ram", "zram", "dm-", "md", "nbd", "fd", "sr"];
    let emmc_hw_partition = name.starts_with("mmcblk") && (name.contains("boot") || name.contains("rpmb"));
    !emmc_hw_partition && !VIRTUAL_PREFIXES.iter().any(|p| name.starts_with(p))
}

fn read_sys(path: &str) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// Bus/protocol label derived from the kernel device name and sysfs path.
fn linux_protocol(name: &str, sys_path: &str) -> String {
    let resolved = fs::canonicalize(sys_path)
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();
    if name.starts_with("nvme") {
        "NVMe".to_string()
    } else if name.starts_with("mmcblk") {
        "eMMC/SD".to_string()
    } else if name.starts_with("vd") || resolved.contains("/virtio") {
        "VirtIO".to_string()
    } else if resolved.contains("/usb") {
        "USB".to_string()
    } else if name.starts_with("xvd") {
        "Xen".to_string()
    } else {
        "SATA/SCSI".to_string()
    }
}

fn inspect_linux_disk(name: &str, device_node: &str) -> Option<DiskDevice> {
    let sys_path = format!("/sys/block/{}", name);
    // /sys/block/<dev>/size is always in 512-byte sectors.
    let size_sectors: u64 = read_sys(&format!("{}/size", sys_path))
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);
    let size_bytes = size_sectors.saturating_mul(512);
    if size_bytes == 0 {
        return None; // empty card reader slot, ejected media, etc.
    }

    let rotational: u32 = fs::read_to_string(format!("{}/queue/rotational", sys_path))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);
    let media_type = if rotational == 0 { "SSD".to_string() } else { "HDD".to_string() };

    let removable = read_sys(&format!("{}/removable", sys_path)).as_deref() == Some("1");

    let model = read_sys(&format!("{}/device/model", sys_path))
        .or_else(|| read_sys(&format!("{}/device/name", sys_path))); // eMMC/SD
    let vendor = read_sys(&format!("{}/device/vendor", sys_path))
        .filter(|v| !v.starts_with("0x") && v != "ATA");
    let model_name = match (vendor, model) {
        (Some(v), Some(m)) if !m.starts_with(&v) => format!("{} {}", v, m),
        (_, Some(m)) => m,
        (Some(v), None) => v,
        (None, None) => name.to_string(),
    };
    let serial_number = read_sys(&format!("{}/device/serial", sys_path))
        .unwrap_or_else(|| "Unknown".to_string());
    let firmware_revision = read_sys(&format!("{}/device/firmware_rev", sys_path))
        .or_else(|| read_sys(&format!("{}/device/rev", sys_path)))
        .unwrap_or_else(|| "Unknown".to_string());
    let removable = removable || fs::canonicalize(&sys_path)
        .map(|p| p.to_string_lossy().contains("/usb"))
        .unwrap_or(false);

    let is_removable = removable;
    let smart_report = smartctl::query_smart_data(device_node);

    let partitions = scan_linux_partitions(name);

    Some(DiskDevice {
        id: name.to_string(),
        device_node: device_node.to_string(),
        model_name,
        serial_number,
        firmware_revision,
        protocol: linux_protocol(name, &sys_path),
        media_type,
        size_bytes,
        size_formatted: format_bytes(size_bytes),
        is_internal: !is_removable,
        is_removable,
        partitions,
        smart: smart_report,
    })
}

fn scan_linux_partitions(disk_name: &str) -> Vec<PartitionInfo> {
    let mut parts = Vec::new();

    if let Ok(output) = Command::new("lsblk").args(["-J", "-b", "-o", "NAME,SIZE,MOUNTPOINT,FSTYPE"]).output() {
        if let Ok(val) = serde_json::from_slice::<serde_json::Value>(&output.stdout) {
            if let Some(devices) = val.get("blockdevices").and_then(|v| v.as_array()) {
                for dev in devices {
                    let d_name = dev.get("name").and_then(|v| v.as_str()).unwrap_or("");
                    if d_name == disk_name {
                        if let Some(children) = dev.get("children").and_then(|v| v.as_array()) {
                            for child in children {
                                let c_name = child.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string();
                                // util-linux < 2.33 prints sizes as JSON strings.
                                let c_size = child
                                    .get("size")
                                    .and_then(|v| v.as_u64().or_else(|| v.as_str().and_then(|s| s.parse().ok())))
                                    .unwrap_or(0);
                                let c_mount = child.get("mountpoint").and_then(|v| v.as_str()).map(|s| s.to_string());
                                let c_fs = child.get("fstype").and_then(|v| v.as_str()).map(|s| s.to_string());
                                let is_boot = c_mount.as_deref() == Some("/");

                                parts.push(PartitionInfo {
                                    id: c_name,
                                    name: None,
                                    size_bytes: c_size,
                                    size_formatted: format_bytes(c_size),
                                    mount_point: c_mount,
                                    file_system: c_fs,
                                    is_boot_volume: is_boot,
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    parts
}
