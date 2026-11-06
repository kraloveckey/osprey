use serde_json::json;

#[test]
fn test_format_bytes() {
    assert_eq!(osprey::models::disk::format_bytes(500), "500 B");
    assert_eq!(osprey::models::disk::format_bytes(1024), "1.0 KB");
    assert_eq!(osprey::models::disk::format_bytes(1024 * 1024), "1.0 MB");
    assert_eq!(osprey::models::disk::format_bytes(1024 * 1024 * 1024), "1.0 GB");
    assert_eq!(osprey::models::disk::format_bytes(1024 * 1024 * 1024 * 1024), "1.0 TB");
}

#[test]
fn test_parse_nvme_smart_json() {
    let mock = json!({
        "smart_status": { "passed": true },
        "nvme_smart_health_information_log": {
            "critical_warning": 0,
            "temperature": 31,
            "available_spare": 100,
            "available_spare_threshold": 99,
            "percentage_used": 0,
            "data_units_read": 43230476,
            "data_units_written": 19995421,
            "host_reads": 925203716,
            "host_writes": 357016021,
            "controller_busy_time": 0,
            "power_cycles": 137,
            "power_on_hours": 332,
            "unsafe_shutdowns": 5,
            "media_errors": 0,
            "num_err_log_entries": 0
        }
    });

    let report = osprey::engine::smartctl::parse_smart_json(&mock).expect("Failed to parse NVMe smart JSON");
    assert_eq!(report.health_status, osprey::models::smart::HealthStatus::Good);
    assert_eq!(report.health_percent, Some(100));
    assert_eq!(report.temperature_celsius, Some(31));
    assert_eq!(report.power_cycles, Some(137));
    assert_eq!(report.power_on_hours, Some(332));
    assert_eq!(report.unsafe_shutdowns, Some(5));
    assert_eq!(report.available_spare, Some(100));
    assert_eq!(report.attributes.len(), 15);
}

#[test]
fn test_parse_ata_smart_json() {
    let mock = json!({
        "smart_status": { "passed": true },
        "temperature": { "current": 36 },
        "power_cycle_count": 450,
        "ata_smart_attributes": {
            "table": [
                {
                    "id": 5,
                    "name": "Reallocated_Sector_Ct",
                    "value": 100,
                    "worst": 100,
                    "thresh": 10,
                    "raw": { "value": 0, "string": "0" }
                },
                {
                    "id": 9,
                    "name": "Power_On_Hours",
                    "value": 95,
                    "worst": 95,
                    "thresh": 0,
                    "raw": { "value": 2400, "string": "2400" }
                }
            ]
        }
    });

    let report = osprey::engine::smartctl::parse_smart_json(&mock).expect("Failed to parse ATA smart JSON");
    assert_eq!(report.health_status, osprey::models::smart::HealthStatus::Good);
    assert_eq!(report.temperature_celsius, Some(36));
    assert_eq!(report.power_cycles, Some(450));
    assert_eq!(report.attributes.len(), 2);
}

#[test]
fn test_crystal_report_export() {
    let disk = osprey::models::disk::DiskDevice {
        id: "disk0".to_string(),
        device_node: "/dev/disk0".to_string(),
        model_name: "APPLE SSD AP1024Z".to_string(),
        serial_number: "0333a0883439a02e".to_string(),
        firmware_revision: "241.0.12".to_string(),
        protocol: "Apple Fabric".to_string(),
        media_type: "SSD".to_string(),
        size_bytes: 1000555581440,
        size_formatted: "1000.5 GB".to_string(),
        is_internal: true,
        is_removable: false,
        partitions: Vec::new(),
        smart: None,
    };

    let battery = osprey::models::battery::BatteryReport {
        installed: true,
        health_status: "Good".to_string(),
        health_percent: 100.3,
        cycle_count: 8,
        design_cycle_count: 1000,
        current_capacity_percent: 80,
        full_charge_capacity_mah: 4644,
        design_capacity_mah: 4629,
        nominal_charge_capacity_mah: Some(4771),
        remaining_capacity_mah: Some(3678),
        voltage_mv: Some(12569),
        amperage_ma: Some(0),
        is_charging: false,
        is_fully_charged: false,
        external_connected: true,
        power_adapter_watts: Some(60),
        power_adapter_name: None,
        device_name: Some("bq40z651".to_string()),
        serial_number: Some("BAT-MOCK-SERIAL-01".to_string()),
        temperature_celsius: None,
        time_remaining_minutes: None,
    };

    let txt = osprey::engine::export::generate_crystal_report(&[disk], &battery);
    assert!(txt.contains("Osprey"));
    assert!(txt.contains("APPLE SSD AP1024Z"));
    assert!(txt.contains("Battery Health"));
    assert!(txt.contains("4644 mAh"));
}

#[test]
fn test_health_score_computation() {
    let score = osprey::models::system::HealthScore::compute(
        15.0,  // low CPU
        0.45,  // normal RAM
        0.50,  // normal disk
        Some(100.0), // healthy battery
        Some(80.0),
        false,
    );
    assert_eq!(score.score, 100);
    assert_eq!(score.status, "optimal");

    let degraded = osprey::models::system::HealthScore::compute(
        95.0,  // high CPU (-15)
        0.90,  // high RAM (-15)
        0.95,  // full disk (-20)
        Some(65.0), // degraded battery (-10)
        Some(8.0),  // critical battery (-10)
        false,
    );
    assert_eq!(degraded.score, 30);
    assert_eq!(degraded.status, "critical");
    assert_eq!(degraded.penalties.len(), 5);
}

#[test]
fn test_reboot_advisory_logic() {
    let optimal = osprey::engine::system::evaluate_reboot_advisory(
        0,                 // 0 MB swap
        1024 * 1024 * 1024,
        86400 * 2,         // 2 days uptime
        45.0,              // normal disk
        &[],
    );
    assert!(!optimal.should_reboot);
    assert_eq!(optimal.level, "Optimal");

    let degraded = osprey::engine::system::evaluate_reboot_advisory(
        10 * 1024 * 1024 * 1024, // 10 GB swap
        12 * 1024 * 1024 * 1024,
        86400 * 30,              // 30 days uptime
        92.0,                    // 92% disk
        &[],
    );
    assert!(degraded.should_reboot);
    assert_eq!(degraded.level, "Critical");
    assert!(degraded.triggers.len() >= 3);
}




#[test]
fn test_advisory_summary_names_actual_trigger() {
    // Only storage is low, no swap at all: the summary must not blame swap.
    let adv = osprey::engine::system::evaluate_reboot_advisory(0, 0, 3600, 90.0, &[]);
    assert_eq!(adv.level, "Advisory");
    assert!(adv.summary.contains("storage headroom"));
    assert!(!adv.summary.contains("swap"));
}

#[test]
fn test_linux_block_device_filter() {
    use osprey::engine::linux::is_physical_block_device as physical;
    for name in ["sda", "nvme0n1", "mmcblk0", "vda", "xvda"] {
        assert!(physical(name), "{name} should be listed");
    }
    for name in ["loop0", "zram0", "dm-0", "md127", "sr0", "ram1", "nbd0", "mmcblk0boot0", "mmcblk0rpmb"] {
        assert!(!physical(name), "{name} should be skipped");
    }
}

#[test]
fn test_parse_proc_swaps_splits_zram_and_disk() {
    let text = "Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n\
                /dev/zram0                              partition\t8388604\t\t2097152\t\t100\n\
                /swap.img                               file\t\t2097148\t\t1024\t\t-2\n";
    let s = osprey::engine::system::parse_proc_swaps(text);
    assert_eq!(s.zram_total, 8388604 * 1024);
    assert_eq!(s.zram_used, 2097152 * 1024);
    assert_eq!(s.disk_total, 2097148 * 1024);
    assert_eq!(s.disk_used, 1024 * 1024);
}

#[test]
fn test_linux_advisory_zram_and_reboot_required() {
    use osprey::engine::system::{evaluate_advisory, AdvisoryInput, AdvisoryPlatform, SwapUsage};
    const GB: u64 = 1024 * 1024 * 1024;
    let base = AdvisoryInput {
        platform: AdvisoryPlatform::Linux,
        swap: SwapUsage { zram_used: 4 * GB, zram_total: 8 * GB, ..Default::default() },
        total_ram: 16 * GB,
        uptime_secs: 86400 * 60, // long uptime alone is fine on Linux
        disk_used_pct: 40.0,
        reboot_required: None,
        top_processes: &[],
    };
    // Half-used zram, 60 days up: nothing to report.
    let ok = evaluate_advisory(&base);
    assert_eq!(ok.level, "Optimal");
    assert!(ok.triggers.is_empty());

    // Nearly full zram + full disk: pressure, but no reboot advice.
    let pressure = evaluate_advisory(&AdvisoryInput {
        swap: SwapUsage { zram_used: 15 * GB / 2, zram_total: 8 * GB, ..Default::default() },
        disk_used_pct: 95.0,
        ..base.clone()
    });
    assert!(!pressure.should_reboot);
    assert!(pressure.summary.contains("not required"));

    // Pending kernel update: reboot is the remedy.
    let pending = evaluate_advisory(&AdvisoryInput {
        reboot_required: Some(vec!["linux-image-6.8.0-50-generic".into()]),
        disk_used_pct: 95.0,
        ..base
    });
    assert!(pending.should_reboot);
    assert!(pending.triggers.iter().any(|t| t.category == "Pending Updates"));
}
