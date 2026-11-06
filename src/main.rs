use clap::Parser;

use osprey::cli::{Cli, Commands};
use osprey::engine;
use osprey::server;
use osprey::ui;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    match cli.command {
        Some(Commands::Scan) | Some(Commands::List) => {
            let overview = engine::get_full_overview();
            ui::print_system_overview(&overview);
        }
        Some(Commands::Top) => {
            ui::run_interactive_top();
        }
        Some(Commands::Info { disk }) => {
            let disks = engine::scan_all_disks();
            if disks.is_empty() {
                eprintln!("No storage disks detected.");
                return Ok(());
            }

            let target = match disk {
                Some(id) => {
                    let clean_id = id.replace("/dev/", "");
                    disks
                        .into_iter()
                        .find(|d| d.id == clean_id || d.device_node == id)
                }
                None => disks.into_iter().next(),
            };

            match target {
                Some(d) => ui::print_disk_info(&d),
                None => eprintln!("Specified disk was not found on this system."),
            }
        }
        Some(Commands::Battery) => {
            let battery = engine::battery::get_battery_telemetry();
            ui::print_battery_telemetry(&battery);
        }
        Some(Commands::Report) => {
            let disks = engine::scan_all_disks();
            let battery = engine::battery::get_battery_telemetry();
            let report_txt = engine::export::generate_crystal_report(&disks, &battery);
            println!("{}", report_txt);
        }
        Some(Commands::Notify) => {
            let ov = engine::get_full_overview();
            if ov.advisory.should_reboot || !ov.advisory.triggers.is_empty() {
                let sent = engine::system::send_desktop_notification(
                    "Osprey Health Advisory",
                    &ov.advisory.level,
                    &ov.advisory.summary,
                );
                if sent {
                    println!("Desktop notification sent: {}", ov.advisory.summary);
                } else {
                    // Headless Linux / no notify-send: still useful from cron.
                    println!("{}", ov.advisory.summary);
                    if cfg!(target_os = "linux") {
                        eprintln!("(no desktop notification: notify-send missing or no graphical session)");
                    }
                }
                // Non-zero exit lets cron/systemd timers/monitoring react.
                std::process::exit(if ov.advisory.should_reboot { 2 } else { 1 });
            } else {
                println!("System status is optimal. No action needed.");
            }
        }


        Some(Commands::Json { disk }) => {
            if let Some(id) = disk {
                let disks = engine::scan_all_disks();
                let clean_id = id.replace("/dev/", "");
                if let Some(d) = disks.into_iter().find(|d| d.id == clean_id) {
                    println!("{}", serde_json::to_string_pretty(&d)?);
                } else {
                    eprintln!("Disk '{}' not found.", clean_id);
                }
            } else {
                let overview = engine::get_full_overview();
                println!("{}", serde_json::to_string_pretty(&overview)?);
            }
        }

        Some(Commands::Widget { port, host, no_open }) => {
            server::start_server(&host, port, !no_open).await?;
        }
        None => {
            // Default behavior: launch desktop widget
            server::start_server(&cli.host, cli.port, !cli.no_open).await?;
        }
    }

    Ok(())
}
