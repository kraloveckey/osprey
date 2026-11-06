use clap::{Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(
    name = "osprey",
    author = "kraloveckey",
    version,
    about = "High-precision storage S.M.A.R.T. telemetry, SSD wear tracking, and battery health monitor for macOS and Linux"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Commands>,

    /// Launch desktop widget immediately (default behavior when no command specified)
    #[arg(short, long, default_value_t = false)]
    pub widget: bool,

    /// HTTP port for desktop widget server
    #[arg(short, long, default_value_t = 4242)]
    pub port: u16,

    /// Bind host address for widget server
    #[arg(long, default_value = "127.0.0.1")]
    pub host: String,

    /// Do not automatically open default window on launch
    #[arg(long, default_value_t = false)]
    pub no_open: bool,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Scan and display high-level status of all physical disks and battery
    Scan,

    /// Display high-level status table (alias for scan)
    List,

    /// Live updating terminal monitor dashboard with sparklines and system metrics
    Top,


    /// Display comprehensive S.M.A.R.T. hardware telemetry for a specific disk
    Info {
        /// Disk identifier or node (e.g. disk0, nvme0n1, /dev/disk0)
        disk: Option<String>,
    },

    /// Display detailed battery health, cycle count, and capacity retention telemetry
    Battery,

    /// Output standardized plain-text storage diagnostics report
    Report,

    /// Check system degradation and trigger a desktop notification if reboot is advised
    Notify,

    /// Output full machine-readable JSON telemetry stream
    Json {
        /// Optional disk identifier to filter JSON output
        disk: Option<String>,
    },

    /// Run the floating desktop widget server
    Widget {
        /// HTTP port to listen on
        #[arg(short, long, default_value_t = 4242)]
        port: u16,

        /// Bind host address
        #[arg(long, default_value = "127.0.0.1")]
        host: String,

        /// Do not automatically open default window on launch
        #[arg(long, default_value_t = false)]
        no_open: bool,
    },
}
