pub mod battery;
pub mod export;
pub mod linux;
pub mod macos;
#[cfg(target_os = "macos")]
pub mod smc;
pub mod smartctl;
pub mod system;

use crate::models::disk::DiskDevice;

pub fn scan_all_disks() -> Vec<DiskDevice> {
    #[cfg(target_os = "macos")]
    {
        macos::scan_macos_disks()
    }
    #[cfg(target_os = "linux")]
    {
        linux::scan_linux_disks()
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        Vec::new()
    }
}

pub fn get_full_overview() -> crate::models::system::FullTelemetryOverview {
    let battery = battery::get_battery_telemetry();
    let physical_disks = scan_all_disks();
    system::get_full_telemetry(&battery, physical_disks)
}


