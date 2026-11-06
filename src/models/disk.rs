use serde::{Deserialize, Serialize};
use super::smart::SmartReport;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartitionInfo {
    pub id: String,
    pub name: Option<String>,
    pub size_bytes: u64,
    pub size_formatted: String,
    pub mount_point: Option<String>,
    pub file_system: Option<String>,
    pub is_boot_volume: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiskDevice {
    pub id: String,
    pub device_node: String,
    pub model_name: String,
    pub serial_number: String,
    pub firmware_revision: String,
    pub protocol: String,
    pub media_type: String,
    pub size_bytes: u64,
    pub size_formatted: String,
    pub is_internal: bool,
    pub is_removable: bool,
    pub partitions: Vec<PartitionInfo>,
    pub smart: Option<SmartReport>,
}

pub fn format_bytes(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    const TB: u64 = GB * 1024;

    if bytes >= TB {
        format!("{:.1} TB", bytes as f64 / TB as f64)
    } else if bytes >= GB {
        format!("{:.1} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.1} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.1} KB", bytes as f64 / KB as f64)
    } else {
        format!("{} B", bytes)
    }
}

pub fn format_rate(bytes_per_sec: u64) -> String {
    format!("{}/s", format_bytes(bytes_per_sec))
}

