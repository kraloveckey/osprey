use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthScore {
    pub score: u32,
    pub status: String,
    pub dot_color: String,
    pub penalties: Vec<String>,
}

impl HealthScore {
    pub fn compute(
        cpu_usage: f32,
        mem_used_fraction: f32,
        disk_used_fraction: f32,
        battery_health: Option<f32>,
        battery_level: Option<f32>,
        is_charging: bool,
    ) -> Self {
        let mut score: i32 = 100;
        let mut penalties = Vec::new();

        if cpu_usage > 80.0 {
            score -= 15;
            penalties.push("High CPU load (>80%)".to_string());
        }
        if mem_used_fraction > 0.85 {
            score -= 15;
            penalties.push("High memory pressure (>85%)".to_string());
        }
        if disk_used_fraction > 0.90 {
            score -= 20;
            penalties.push("Low root disk space (>90% full)".to_string());
        }
        if let Some(health) = battery_health {
            if health < 80.0 {
                score -= 10;
                penalties.push("Battery degraded (<80% health)".to_string());
            }
        }
        if let Some(level) = battery_level {
            if level < 15.0 && !is_charging {
                score -= 10;
                penalties.push("Battery critical (<15% discharging)".to_string());
            }
        }

        let clamped = score.clamp(0, 100) as u32;
        let (status, dot_color) = if clamped >= 80 {
            ("optimal".to_string(), "#34d399".to_string()) // green
        } else if clamped >= 50 {
            ("warning".to_string(), "#fbbf24".to_string()) // yellow
        } else {
            ("critical".to_string(), "#f87171".to_string()) // red
        };

        Self {
            score: clamped,
            status,
            dot_color,
            penalties,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuCoreUsage {
    pub index: usize,
    pub usage_percent: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuTelemetry {
    pub total_percent: f32,
    pub top_cores: Vec<CpuCoreUsage>,
    pub load_average: [f64; 3],
    pub temp_celsius: Option<f32>,
    pub history: Vec<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryTelemetry {
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub free_bytes: u64,
    pub cached_bytes: u64,
    pub available_bytes: u64,
    pub total_formatted: String,
    pub used_formatted: String,
    pub free_formatted: String,
    pub cached_formatted: String,
    pub available_formatted: String,
    pub used_percent: f32,
    pub free_percent: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RootDiskTelemetry {
    pub mount_point: String,
    pub file_system: String,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub free_bytes: u64,
    pub total_formatted: String,
    pub used_formatted: String,
    pub free_formatted: String,
    pub used_percent: f32,
    pub read_speed_bytes: u64,
    pub write_speed_bytes: u64,
    pub read_speed_formatted: String,
    pub write_speed_formatted: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkTelemetry {
    pub interface_name: String,
    pub local_ip: Option<String>,
    pub download_bytes_sec: u64,
    pub upload_bytes_sec: u64,
    pub download_formatted: String,
    pub upload_formatted: String,
    pub download_history: Vec<f32>,
    pub upload_history: Vec<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessMetric {
    pub pid: u32,
    pub name: String,
    pub cpu_percent: f32,
    pub memory_bytes: u64,
    pub memory_formatted: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemHeader {
    pub chip_name: String,
    pub total_ram_formatted: String,
    pub os_name: String,
    pub os_version: String,
    pub uptime_formatted: String,
    pub host_name: String,
    pub health_score: HealthScore,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemVitals {
    pub os_name: String,
    pub os_version: String,
    pub host_name: String,
    pub chip_name: String,
    pub uptime_formatted: String,
    pub cpu_usage_percent: f32,
    pub cpu_temp_celsius: Option<f32>,
    pub memory_total_bytes: u64,
    pub memory_used_bytes: u64,
    pub memory_free_bytes: u64,
    pub memory_total_formatted: String,
    pub memory_used_formatted: String,
    pub memory_free_formatted: String,
    pub memory_used_percent: f32,
    pub health_score: HealthScore,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdvisoryTrigger {
    pub category: String,
    pub severity: String,
    pub message: String,
    pub metric_value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RebootAdvisory {
    pub should_reboot: bool,
    pub level: String,
    pub score: u32,
    pub summary: String,
    pub swap_used_bytes: u64,
    pub swap_total_bytes: u64,
    pub swap_used_formatted: String,
    pub uptime_days: u64,
    pub triggers: Vec<AdvisoryTrigger>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FullTelemetryOverview {
    pub header: SystemHeader,
    pub cpu: CpuTelemetry,
    pub memory: MemoryTelemetry,
    pub disk: RootDiskTelemetry,
    pub network: NetworkTelemetry,
    pub battery: crate::models::battery::BatteryReport,
    pub top_processes: Vec<ProcessMetric>,
    pub physical_disks: Vec<crate::models::disk::DiskDevice>,
    pub advisory: RebootAdvisory,
}

