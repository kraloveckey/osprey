use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum HealthStatus {
    Good,
    Caution,
    Bad,
    Unknown,
}

impl std::fmt::Display for HealthStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Good => write!(f, "GOOD"),
            Self::Caution => write!(f, "CAUTION"),
            Self::Bad => write!(f, "BAD"),
            Self::Unknown => write!(f, "UNKNOWN"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AttributeStatus {
    Normal,
    Warning,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SmartAttribute {
    pub id: u8,
    pub name: String,
    pub current: Option<u64>,
    pub worst: Option<u64>,
    pub threshold: Option<u64>,
    pub raw_value: u64,
    pub raw_hex: String,
    pub status: AttributeStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SmartReport {
    pub health_status: HealthStatus,
    pub health_percent: Option<u8>,
    pub temperature_celsius: Option<i32>,
    pub temperature_fahrenheit: Option<i32>,
    pub power_on_hours: Option<u64>,
    pub power_cycles: Option<u64>,
    pub unsafe_shutdowns: Option<u64>,
    pub data_units_read_bytes: Option<u64>,
    pub data_units_read_formatted: Option<String>,
    pub data_units_written_bytes: Option<u64>,
    pub data_units_written_formatted: Option<String>,
    pub host_read_commands: Option<u64>,
    pub host_write_commands: Option<u64>,
    pub percentage_used: Option<u8>,
    pub available_spare: Option<u8>,
    pub available_spare_threshold: Option<u8>,
    pub critical_warning: Option<u8>,
    pub media_errors: Option<u64>,
    pub error_entries_count: Option<u64>,
    pub attributes: Vec<SmartAttribute>,
    pub self_test_status: Option<String>,
    pub nvme_version: Option<String>,
    pub rotation_rate: Option<String>,
    pub interface_speed: Option<String>,
    pub supported_features: Vec<String>,
}

impl Default for SmartReport {
    fn default() -> Self {
        Self {
            health_status: HealthStatus::Unknown,
            health_percent: None,
            temperature_celsius: None,
            temperature_fahrenheit: None,
            power_on_hours: None,
            power_cycles: None,
            unsafe_shutdowns: None,
            data_units_read_bytes: None,
            data_units_read_formatted: None,
            data_units_written_bytes: None,
            data_units_written_formatted: None,
            host_read_commands: None,
            host_write_commands: None,
            percentage_used: None,
            available_spare: None,
            available_spare_threshold: None,
            critical_warning: None,
            media_errors: None,
            error_entries_count: None,
            attributes: Vec::new(),
            self_test_status: None,
            nvme_version: None,
            rotation_rate: None,
            interface_speed: None,
            supported_features: Vec::new(),
        }
    }
}
