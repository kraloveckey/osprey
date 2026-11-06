use colored::*;
use crate::models::battery::BatteryReport;
use crate::models::disk::DiskDevice;
use crate::models::smart::{AttributeStatus, HealthStatus};
use crate::models::system::FullTelemetryOverview;

pub fn render_bar(fraction: f32, width: usize) -> String {
    let clamped = fraction.clamp(0.0, 1.0);
    let filled = ((clamped * width as f32).round()) as usize;
    let empty = width.saturating_sub(filled);
    
    let bar_str = "■".repeat(filled);
    let colored_bar = if fraction >= 0.85 {
        bar_str.bright_red()
    } else if fraction >= 0.60 {
        bar_str.bright_yellow()
    } else {
        bar_str.bright_green()
    };

    format!("[{}{}]", colored_bar, "□".repeat(empty).dimmed())
}

pub fn print_system_overview(ov: &FullTelemetryOverview) {
    let dot = match ov.header.health_score.status.as_str() {
        "optimal" => "●".bright_green(),
        "warning" => "●".bright_yellow(),
        _ => "●".bright_red(),
    };

    println!("\n{}", "OSPREY · HARDWARE TELEMETRY & SYSTEM MONITOR".bold().bright_cyan());
    println!("{}", "================================================================================".dimmed());
    println!(
        "{} {} {} · {} · {} · {} {} · up {}",
        "Health".bold().magenta(),
        dot,
        ov.header.health_score.score.to_string().bold().bright_white(),
        ov.header.chip_name.bright_white(),
        ov.header.total_ram_formatted.dimmed(),
        ov.header.os_name.dimmed(),
        ov.header.os_version.dimmed(),
        ov.header.uptime_formatted.dimmed()
    );
    println!("{}", "--------------------------------------------------------------------------------".dimmed());

    // CPU
    let cpu_frac = ov.cpu.total_percent / 100.0;
    let cpu_bar = render_bar(cpu_frac, 10);
    let temp_str = ov.cpu.temp_celsius.map(|t| format!("{:.0}°C", t)).unwrap_or_else(|| "--°C".to_string());
    println!(
        "{:<8} Total: {:>5.1}% {}  Temp: {:>4}  Load: {:.2} / {:.2} / {:.2}",
        "CPU".bold().bright_white(),
        ov.cpu.total_percent,
        cpu_bar,
        temp_str.cyan(),
        ov.cpu.load_average[0],
        ov.cpu.load_average[1],
        ov.cpu.load_average[2]
    );

    let cores_str = ov.cpu.top_cores.iter()
        .map(|c| format!("Core{} {:.1}%", c.index + 1, c.usage_percent))
        .collect::<Vec<_>>()
        .join("   ");
    if !cores_str.is_empty() {
        println!("         Cores: {}", cores_str.dimmed());
    }

    // Memory
    let mem_frac = ov.memory.used_percent / 100.0;
    let mem_bar = render_bar(mem_frac, 10);
    println!(
        "{:<8} Used:  {:>5.1}% {}  {} / {}  (Free: {} · Avail: {})",
        "MEMORY".bold().bright_white(),
        ov.memory.used_percent,
        mem_bar,
        ov.memory.used_formatted.bright_white(),
        ov.memory.total_formatted.dimmed(),
        ov.memory.free_formatted.dimmed(),
        ov.memory.available_formatted.dimmed()
    );

    // Root Disk
    let disk_frac = ov.disk.used_percent / 100.0;
    let disk_bar = render_bar(disk_frac, 10);
    println!(
        "{:<8} Root:  {:>5.1}% {}  {} / {}  Read: {:<10} Write: {}",
        "DISK".bold().bright_white(),
        ov.disk.used_percent,
        disk_bar,
        ov.disk.used_formatted.bright_white(),
        ov.disk.total_formatted.dimmed(),
        ov.disk.read_speed_formatted.cyan(),
        ov.disk.write_speed_formatted.magenta()
    );

    // Network
    let iface_ip = if let Some(ip) = &ov.network.local_ip {
        format!("{} ({})", ov.network.interface_name, ip)
    } else {
        ov.network.interface_name.clone()
    };
    println!(
        "{:<8} {:<24} Down: {:<12} Up: {}",
        "NETWORK".bold().bright_white(),
        iface_ip.dimmed(),
        ov.network.download_formatted.bright_green(),
        ov.network.upload_formatted.bright_purple()
    );

    // Power
    if ov.battery.installed {
        let b = &ov.battery;
        let pwr_state = if b.is_charging {
            "Charging (AC Attached)".green()
        } else if b.external_connected {
            "AC Power (Idle)".cyan()
        } else {
            "On Battery".bright_white()
        };
        let b_temp = b.temperature_celsius.map(|t| format!("{:.1}°C", t)).unwrap_or_else(|| "--".to_string());
        println!(
            "{:<8} Level: {:>3}%  Health: {:>5.1}% ({})  {} cycles · {}  {} · {}W",
            "POWER".bold().bright_white(),
            b.current_capacity_percent,
            b.health_percent,
            b.health_status.green(),
            b.cycle_count,
            b_temp,
            pwr_state,
            b.power_adapter_watts.unwrap_or(0)
        );
    }

    if !ov.physical_disks.is_empty() {
        println!("{}", "--------------------------------------------------------------------------------".dimmed());
        println!("{}", "PHYSICAL STORAGE S.M.A.R.T. HEALTH".bold().bright_cyan());
        println!(
            "{:<10} {:<24} {:<10} {:<12} {:<14} {:<8}",
            "DISK".bold(),
            "MODEL".bold(),
            "SIZE".bold(),
            "PROTOCOL".bold(),
            "HEALTH".bold(),
            "TEMP".bold()
        );
        for disk in &ov.physical_disks {
            let health_colored = match disk.smart.as_ref().map(|s| s.health_status) {
                Some(HealthStatus::Good) => {
                    let pct = disk.smart.as_ref().and_then(|s| s.health_percent).unwrap_or(100);
                    format!("GOOD {}%", pct).bold().green()
                }
                Some(HealthStatus::Caution) => {
                    let pct = disk.smart.as_ref().and_then(|s| s.health_percent).unwrap_or(50);
                    format!("CAUTION {}%", pct).bold().yellow()
                }
                Some(HealthStatus::Bad) => {
                    let pct = disk.smart.as_ref().and_then(|s| s.health_percent).unwrap_or(0);
                    format!("BAD {}%", pct).bold().red()
                }
                _ => "UNKNOWN".dimmed(),
            };

            let temp_colored = if let Some(temp) = disk.smart.as_ref().and_then(|s| s.temperature_celsius) {
                format!("{}°C", temp).cyan()
            } else {
                "--°C".dimmed()
            };

            println!(
                "{:<10} {:<24} {:<10} {:<12} {:<14} {:<8}",
                disk.id.bright_white(),
                disk.model_name.chars().take(22).collect::<String>(),
                disk.size_formatted,
                disk.protocol,
                health_colored,
                temp_colored
            );
        }
    }

    if !ov.top_processes.is_empty() {
        println!("{}", "--------------------------------------------------------------------------------".dimmed());
        println!("{}", "TOP PROCESSES (CPU & MEMORY FOOTPRINT)".bold().bright_cyan());
        println!("{:<8} {:<36} {:<10} {:<12}", "PID".bold(), "PROCESS".bold(), "CPU %".bold(), "RAM".bold());
        for p in &ov.top_processes {
            println!(
                "{:<8} {:<36} {:>5.1}%     {:<12}",
                p.pid.to_string().dimmed(),
                p.name.chars().take(34).collect::<String>().bright_white(),
                p.cpu_percent,
                p.memory_formatted.dimmed()
            );
        }
    }

    // System Maintenance & Reboot Advisory
    let adv = &ov.advisory;
    if adv.should_reboot || !adv.triggers.is_empty() {
        println!("{}", "--------------------------------------------------------------------------------".dimmed());
        println!("{}", "SYSTEM MAINTENANCE & REBOOT ADVISORY".bold().bright_yellow());
        let badge = match (adv.should_reboot, adv.level.as_str()) {
            (true, "Critical") => "  URGENT REBOOT ADVISED  ".on_red().bold().white(),
            (true, _) => "  REBOOT RECOMMENDED  ".on_yellow().bold().black(),
            (false, "Critical") => "  CRITICAL  ".on_red().bold().white(),
            (false, "Warning") => "  ATTENTION  ".on_yellow().bold().black(),
            _ => "  ADVISORY  ".on_blue().bold().white(),
        };
        println!("{}  {}", badge, adv.summary.bright_white());
        for trigger in &adv.triggers {
            let icon = if trigger.severity == "critical" {
                "(!)".bright_red()
            } else {
                "(*)".bright_yellow()
            };
            println!("  {} [{}] {}", icon, trigger.category.dimmed(), trigger.message);
        }
    }

    println!("{}", "================================================================================".dimmed());
    println!("Tip: Run '{}' for full S.M.A.R.T. telemetry attributes or '{}' for Desktop Widget.\n", "osprey info <disk>".cyan(), "osprey".cyan());
}


pub fn run_interactive_top() {
    println!("Starting Osprey Live Monitor (Press Ctrl+C to exit)...");
    loop {
        let ov = crate::engine::get_full_overview();
        // Clear terminal screen and move cursor to top-left
        print!("\x1B[2J\x1B[1;1H");
        print_system_overview(&ov);
        println!("{}", "  Press Ctrl+C to exit | Refreshing every 1s...".dimmed());
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
}



pub fn print_scan_table(disks: &[DiskDevice], battery: &BatteryReport) {
    println!("\n{}", "OSPREY · STORAGE & HARDWARE HEALTH".bold().bright_cyan());
    println!("{}", "================================================================================".dimmed());
    println!(
        "{:<10} {:<24} {:<10} {:<12} {:<14} {:<8}",
        "DISK".bold(),
        "MODEL".bold(),
        "SIZE".bold(),
        "PROTOCOL".bold(),
        "HEALTH".bold(),
        "TEMP".bold()
    );
    println!("{}", "--------------------------------------------------------------------------------".dimmed());

    for disk in disks {
        let health_colored = match disk.smart.as_ref().map(|s| s.health_status) {
            Some(HealthStatus::Good) => {
                let pct = disk.smart.as_ref().and_then(|s| s.health_percent).unwrap_or(100);
                format!("GOOD {}%", pct).bold().green()
            }
            Some(HealthStatus::Caution) => {
                let pct = disk.smart.as_ref().and_then(|s| s.health_percent).unwrap_or(50);
                format!("CAUTION {}%", pct).bold().yellow()
            }
            Some(HealthStatus::Bad) => {
                let pct = disk.smart.as_ref().and_then(|s| s.health_percent).unwrap_or(0);
                format!("BAD {}%", pct).bold().red()
            }
            _ => "UNKNOWN".dimmed(),
        };

        let temp_colored = if let Some(temp) = disk.smart.as_ref().and_then(|s| s.temperature_celsius) {
            if temp < 45 {
                format!("{}°C", temp).cyan()
            } else if temp < 55 {
                format!("{}°C", temp).yellow()
            } else {
                format!("{}°C", temp).bold().red()
            }
        } else {
            "--°C".dimmed()
        };

        println!(
            "{:<10} {:<24} {:<10} {:<12} {:<14} {:<8}",
            disk.id.bright_white(),
            disk.model_name.chars().take(22).collect::<String>(),
            disk.size_formatted,
            disk.protocol,
            health_colored,
            temp_colored
        );
    }

    if battery.installed {
        println!("{}", "--------------------------------------------------------------------------------".dimmed());
        let health_colored = if battery.health_percent >= 80.0 {
            format!("{:.1}% ({})", battery.health_percent, battery.health_status).green()
        } else {
            format!("{:.1}% ({})", battery.health_percent, battery.health_status).yellow()
        };

        let charging_str = if battery.is_charging {
            "Charging (AC Attached)".green()
        } else if battery.external_connected {
            "AC Power (Fully Charged/Idle)".cyan()
        } else {
            "On Battery Power".bright_white()
        };

        println!(
            "{:<10} {:<24} {:<10} {:<12} {:<14} {:<8}",
            "BATTERY".bold().magenta(),
            format!("Cycles: {}/{}", battery.cycle_count, battery.design_cycle_count),
            format!("{}%", battery.current_capacity_percent),
            charging_str,
            health_colored,
            battery.power_adapter_watts.map(|w| format!("{}W", w)).unwrap_or_else(|| "--".to_string())
        );
    }

    println!("{}", "================================================================================".dimmed());
    println!("Tip: Run '{}' for full S.M.A.R.T. telemetry attributes or '{}' to launch Desktop Widget.\n", "osprey info <disk>".cyan(), "osprey".cyan());
}

pub fn print_disk_info(disk: &DiskDevice) {
    println!("\n{}", format!("OSPREY · DISK TELEMETRY · {}", disk.id).bold().bright_cyan());
    println!("{}", "================================================================================".dimmed());

    let smart = disk.smart.as_ref();
    let health_badge = match smart.map(|s| s.health_status) {
        Some(HealthStatus::Good) => {
            let pct = smart.and_then(|s| s.health_percent).unwrap_or(100);
            format!("  GOOD {}%  ", pct).on_green().bold().black()
        }
        Some(HealthStatus::Caution) => {
            let pct = smart.and_then(|s| s.health_percent).unwrap_or(50);
            format!("  CAUTION {}%  ", pct).on_yellow().bold().black()
        }
        Some(HealthStatus::Bad) => {
            let pct = smart.and_then(|s| s.health_percent).unwrap_or(0);
            format!("  BAD {}%  ", pct).on_red().bold().white()
        }
        _ => "  UNKNOWN  ".on_white().black(),
    };

    let temp_badge = if let Some(temp) = smart.and_then(|s| s.temperature_celsius) {
        let temp_f = smart.and_then(|s| s.temperature_fahrenheit).unwrap_or(((temp as f64 * 9.0 / 5.0) + 32.0).round() as i32);
        if temp < 45 {
            format!("  {}°C / {}°F  ", temp, temp_f).on_blue().bold().white()
        } else if temp < 55 {
            format!("  {}°C / {}°F  ", temp, temp_f).on_yellow().bold().black()
        } else {
            format!("  {}°C / {}°F  ", temp, temp_f).on_red().bold().white()
        }
    } else {
        "  --°C  ".on_black().white()
    };

    println!("[{}]   [{}]\n", health_badge, temp_badge);

    println!("  {:<22} : {}", "Model".dimmed(), disk.model_name.bold());
    println!("  {:<22} : {}", "Serial Number".dimmed(), disk.serial_number);
    println!("  {:<22} : {}", "Firmware Revision".dimmed(), disk.firmware_revision);
    println!("  {:<22} : {} ({} bytes)", "Disk Size".dimmed(), disk.size_formatted.bright_white(), disk.size_bytes);
    println!("  {:<22} : {}", "Protocol / Interface".dimmed(), disk.protocol);
    println!("  {:<22} : {}", "Media Type".dimmed(), disk.media_type);

    if let Some(s) = smart {
        if let Some(h) = s.power_on_hours {
            println!("  {:<22} : {} hours ({:.1} days)", "Power On Hours".dimmed(), h.to_string().cyan(), h as f64 / 24.0);
        }
        if let Some(c) = s.power_cycles {
            println!("  {:<22} : {} cycles", "Power On Count".dimmed(), c.to_string().cyan());
        }
        if let Some(u) = s.unsafe_shutdowns {
            println!("  {:<22} : {} times", "Unsafe Shutdowns".dimmed(), u);
        }
        if let Some(r) = &s.data_units_read_formatted {
            println!("  {:<22} : {}", "Total Host Reads".dimmed(), r.bold().green());
        }
        if let Some(w) = &s.data_units_written_formatted {
            println!("  {:<22} : {}", "Total Host Writes (TBW)".dimmed(), w.bold().green());
        }
        if let Some(spare) = s.available_spare {
            let thresh = s.available_spare_threshold.unwrap_or(10);
            println!("  {:<22} : {}% (Threshold: {}%)", "Available Spare".dimmed(), spare, thresh);
        }
        if !s.supported_features.is_empty() {
            println!("  {:<22} : {}", "Features Supported".dimmed(), s.supported_features.join(", ").dimmed());
        }
    }

    if !disk.partitions.is_empty() {
        println!("\n  {}", "PARTITIONS & MOUNT POINTS:".bold());
        for p in &disk.partitions {
            let boot_marker = if p.is_boot_volume { " [Boot]" } else { "" };
            println!(
                "    • {:<12} {:<16} {:<24} {}{}",
                p.id.cyan(),
                p.size_formatted,
                p.name.as_deref().unwrap_or("-"),
                p.mount_point.as_deref().unwrap_or("-"),
                boot_marker.bright_magenta()
            );
        }
    }

    if let Some(s) = smart {
        if !s.attributes.is_empty() {
            println!("\n  {}", "S.M.A.R.T. ATTRIBUTES TELEMETRY:".bold());
            println!("  {}", "----------------------------------------------------------------------------".dimmed());
            println!(
                "  {:<4} {:<32} {:<6} {:<6} {:<6} {:<14} {:<10}",
                "ID".bold(),
                "ATTRIBUTE NAME".bold(),
                "CUR".bold(),
                "WOR".bold(),
                "THR".bold(),
                "RAW (HEX)".bold(),
                "STATUS".bold()
            );
            println!("  {}", "----------------------------------------------------------------------------".dimmed());

            for attr in &s.attributes {
                let status_pill = match attr.status {
                    AttributeStatus::Normal => "● OK".green(),
                    AttributeStatus::Warning => "▲ WARN".yellow(),
                    AttributeStatus::Critical => "✖ CRIT".red(),
                };

                println!(
                    "  {:02X}   {:<32} {:<6} {:<6} {:<6} {:<14} {}",
                    attr.id,
                    attr.name,
                    attr.current.map(|v| v.to_string()).unwrap_or_else(|| "-".to_string()),
                    attr.worst.map(|v| v.to_string()).unwrap_or_else(|| "-".to_string()),
                    attr.threshold.map(|v| v.to_string()).unwrap_or_else(|| "-".to_string()),
                    attr.raw_hex.dimmed(),
                    status_pill
                );
            }
        }
    }

    println!("{}\n", "================================================================================".dimmed());
}

pub fn print_battery_telemetry(battery: &BatteryReport) {
    println!("\n{}", "OSPREY · BATTERY HEALTH & TELEMETRY".bold().bright_magenta());
    println!("{}", "================================================================================".dimmed());

    if !battery.installed {
        println!("  No battery detected on this system.");
        return;
    }

    let health_badge = if battery.health_percent >= 80.0 {
        format!("  HEALTH: {:.1}% ({})  ", battery.health_percent, battery.health_status).on_green().bold().black()
    } else {
        format!("  HEALTH: {:.1}% ({})  ", battery.health_percent, battery.health_status).on_yellow().bold().black()
    };

    let state_badge = if battery.is_charging {
        "  CHARGING  ".on_cyan().bold().black()
    } else if battery.external_connected {
        "  AC CONNECTED  ".on_blue().bold().white()
    } else {
        "  ON BATTERY  ".on_black().bold().white()
    };

    println!("[{}]  [{}]\n", health_badge, state_badge);

    println!("  {:<26} : {}%", "Current Charge".dimmed(), battery.current_capacity_percent.to_string().bold().bright_white());
    println!("  {:<26} : {} / {} (Design)", "Cycle Count".dimmed(), battery.cycle_count.to_string().cyan(), battery.design_cycle_count);
    println!("  {:<26} : {} mAh", "Full Charge Capacity".dimmed(), battery.full_charge_capacity_mah.to_string().green());
    println!("  {:<26} : {} mAh", "Design Capacity".dimmed(), battery.design_capacity_mah);
    if let Some(r) = battery.remaining_capacity_mah {
        println!("  {:<26} : {} mAh", "Remaining Charge".dimmed(), r);
    }
    if let Some(v) = battery.voltage_mv {
        println!("  {:<26} : {:.2} V ({} mV)", "Pack Voltage".dimmed(), v as f64 / 1000.0, v);
    }
    if let Some(w) = battery.power_adapter_watts {
        println!("  {:<26} : {} Watts", "Connected AC Adapter".dimmed(), w);
    }
    if let Some(dev) = &battery.device_name {
        println!("  {:<26} : {}", "Device Chip".dimmed(), dev);
    }
    if let Some(s) = &battery.serial_number {
        println!("  {:<26} : {}", "Serial Number".dimmed(), s);
    }

    println!("{}\n", "================================================================================".dimmed());
}
