use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatteryReport {
    pub installed: bool,
    pub health_status: String,
    pub health_percent: f32,
    pub cycle_count: u32,
    pub design_cycle_count: u32,
    pub current_capacity_percent: u32,
    pub full_charge_capacity_mah: u32,
    pub design_capacity_mah: u32,
    pub nominal_charge_capacity_mah: Option<u32>,
    pub remaining_capacity_mah: Option<u32>,
    pub voltage_mv: Option<u32>,
    pub amperage_ma: Option<i32>,
    pub is_charging: bool,
    pub is_fully_charged: bool,
    pub external_connected: bool,
    pub power_adapter_watts: Option<u32>,
    pub power_adapter_name: Option<String>,
    pub device_name: Option<String>,
    pub serial_number: Option<String>,
    pub temperature_celsius: Option<f32>,
    pub time_remaining_minutes: Option<u32>,
}

impl Default for BatteryReport {
    fn default() -> Self {
        Self {
            installed: false,
            health_status: "Unknown".to_string(),
            health_percent: 0.0,
            cycle_count: 0,
            design_cycle_count: 1000,
            current_capacity_percent: 0,
            full_charge_capacity_mah: 0,
            design_capacity_mah: 0,
            nominal_charge_capacity_mah: None,
            remaining_capacity_mah: None,
            voltage_mv: None,
            amperage_ma: None,
            is_charging: false,
            is_fully_charged: false,
            external_connected: false,
            power_adapter_watts: None,
            power_adapter_name: None,
            device_name: None,
            serial_number: None,
            temperature_celsius: None,
            time_remaining_minutes: None,
        }
    }
}
