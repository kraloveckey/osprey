use std::sync::Mutex;
use std::time::Instant;
use sysinfo::{Disks, Networks, System};
use crate::models::battery::BatteryReport;
use crate::models::disk::{format_bytes, format_rate};
use crate::models::system::{
    CpuCoreUsage, CpuTelemetry, FullTelemetryOverview, HealthScore, MemoryTelemetry,
    NetworkTelemetry, ProcessMetric, RootDiskTelemetry, SystemHeader, SystemVitals,
};

// Thread-safe history buffers for sparklines and rate calculation
struct HistoryState {
    last_sample_time: Instant,
    last_rx_bytes: u64,
    last_tx_bytes: u64,
    last_disk_sample: Option<(Instant, u64, u64)>,
    cpu_history: Vec<f32>,
    rx_history: Vec<f32>,
    tx_history: Vec<f32>,
}

static HISTORY: Mutex<Option<HistoryState>> = Mutex::new(None);

fn get_or_init_history() -> (f32, f32, Vec<f32>, Vec<f32>, Vec<f32>) {
    let mut guard = HISTORY.lock().unwrap_or_else(|e| e.into_inner());
    let now = Instant::now();

    // Sum network bytes across non-loopback interfaces
    let mut networks = Networks::new_with_refreshed_list();
    networks.refresh();
    let mut total_rx = 0u64;
    let mut total_tx = 0u64;
    for (name, data) in &networks {
        if !name.starts_with("lo") {
            total_rx += data.total_received();
            total_tx += data.total_transmitted();
        }
    }

    if guard.is_none() {
        *guard = Some(HistoryState {
            last_sample_time: now,
            last_rx_bytes: total_rx,
            last_tx_bytes: total_tx,
            last_disk_sample: None,
            cpu_history: Vec::new(),
            rx_history: Vec::new(),
            tx_history: Vec::new(),
        });
    }

    let state = guard.as_mut().unwrap();
    let elapsed = state.last_sample_time.elapsed().as_secs_f32().max(0.1);
    
    let rx_delta = total_rx.saturating_sub(state.last_rx_bytes);
    let tx_delta = total_tx.saturating_sub(state.last_tx_bytes);

    let rx_rate = (rx_delta as f32 / elapsed).max(0.0);
    let tx_rate = (tx_delta as f32 / elapsed).max(0.0);

    state.last_sample_time = now;
    state.last_rx_bytes = total_rx;
    state.last_tx_bytes = total_tx;

    // Push rates into history, keep max 30 points
    state.rx_history.push(rx_rate);
    if state.rx_history.len() > 30 {
        state.rx_history.remove(0);
    }
    state.tx_history.push(tx_rate);
    if state.tx_history.len() > 30 {
        state.tx_history.remove(0);
    }

    (
        rx_rate,
        tx_rate,
        state.cpu_history.clone(),
        state.rx_history.clone(),
        state.tx_history.clone(),
    )
}

/// One long-lived `System` for the whole process. CPU (and per-process CPU)
/// usage is a delta between two refreshes, so a fresh `System` per call
/// always reports 0 % or garbage – this is what made `osprey top` and the
/// widget server show idle cores. The first use primes every delta-based
/// counter (CPU, processes, network, disk I/O) and waits the minimum
/// sampling interval, so even a one-shot `osprey scan` shows real numbers.
static SYSTEM: Mutex<Option<System>> = Mutex::new(None);

fn with_system<R>(f: impl FnOnce(&mut System) -> R) -> R {
    let mut guard = SYSTEM.lock().unwrap_or_else(|e| e.into_inner());
    if guard.is_none() {
        let mut sys = System::new();
        sys.refresh_cpu_all();
        sys.refresh_memory();
        sys.refresh_processes(sysinfo::ProcessesToUpdate::All);
        let _ = get_or_init_history();
        let _ = get_disk_io_rates();
        std::thread::sleep(sysinfo::MINIMUM_CPU_UPDATE_INTERVAL.max(std::time::Duration::from_millis(250)));
        *guard = Some(sys);
    }
    f(guard.as_mut().expect("system initialised above"))
}

fn record_cpu_sample(cpu: f32) -> Vec<f32> {
    let mut guard = HISTORY.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(state) = guard.as_mut() {
        state.cpu_history.push(cpu);
        if state.cpu_history.len() > 30 {
            state.cpu_history.remove(0);
        }
        state.cpu_history.clone()
    } else {
        vec![cpu]
    }
}

pub fn get_system_vitals() -> SystemVitals {
    let (cpu_usage, total_mem, used_mem, chip_name) = with_system(|sys| {
        sys.refresh_cpu_all();
        sys.refresh_memory();
        (sys.global_cpu_usage(), sys.total_memory(), sys.used_memory(), get_chip_name(sys))
    });
    let free_mem = total_mem.saturating_sub(used_mem);
    let mem_pct = if total_mem > 0 {
        ((used_mem as f64 / total_mem as f64) * 100.0) as f32
    } else {
        0.0
    };

    let uptime_secs = System::uptime();
    let days = uptime_secs / 86400;
    let hours = (uptime_secs % 86400) / 3600;
    let mins = (uptime_secs % 3600) / 60;
    let uptime_formatted = if days > 0 {
        format!("{}d {}h", days, hours)
    } else {
        format!("{}h {}m", hours, mins)
    };

    let os_name = os_display_name();
    let os_version = System::os_version().unwrap_or_else(|| "Unknown".to_string());
    let host_name = System::host_name().unwrap_or_else(|| "localhost".to_string());

    let health_score = HealthScore::compute(
        cpu_usage,
        mem_pct / 100.0,
        0.5,
        None,
        None,
        true,
    );

    SystemVitals {
        os_name,
        os_version,
        host_name,
        chip_name,
        uptime_formatted,
        cpu_usage_percent: cpu_usage,
        cpu_temp_celsius: get_soc_temperature(),
        memory_total_bytes: total_mem,
        memory_used_bytes: used_mem,
        memory_free_bytes: free_mem,
        memory_total_formatted: format_bytes(total_mem),
        memory_used_formatted: format_bytes(used_mem),
        memory_free_formatted: format_bytes(free_mem),
        memory_used_percent: mem_pct,
        health_score,
    }
}

#[allow(unused_variables)]
pub fn get_chip_name(sys: &System) -> String {
    #[cfg(target_os = "macos")]
    {
        let output = std::process::Command::new("sysctl")
            .arg("-n")
            .arg("machdep.cpu.brand_string")
            .output();
        if let Ok(o) = output {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if !s.is_empty() {
                return s;
            }
        }
        "Apple Silicon".to_string()
    }

    #[cfg(not(target_os = "macos"))]
    {
        sys.cpus()
            .first()
            .map(|c| c.brand().to_string())
            .unwrap_or_else(|| "CPU".to_string())
    }
}

pub fn get_cpu_telemetry(sys: &mut System) -> CpuTelemetry {
    sys.refresh_cpu_usage();
    let total_percent = sys.global_cpu_usage();

    let mut cores: Vec<CpuCoreUsage> = sys
        .cpus()
        .iter()
        .enumerate()
        .map(|(index, cpu)| CpuCoreUsage {
            index,
            usage_percent: cpu.cpu_usage(),
        })
        .collect();

    // Sort by busiest cores descending for top 3
    cores.sort_by(|a, b| b.usage_percent.partial_cmp(&a.usage_percent).unwrap_or(std::cmp::Ordering::Equal));
    let top_cores = cores.into_iter().take(3).collect();

    let load_avg = System::load_average();
    let load_average = [load_avg.one, load_avg.five, load_avg.fifteen];

    let history = record_cpu_sample(total_percent);

    // Try finding CPU/SoC temperature
    let temp_celsius = get_soc_temperature();

    CpuTelemetry {
        total_percent,
        top_cores,
        load_average,
        temp_celsius,
        history,
    }
}

pub fn get_soc_temperature() -> Option<f32> {
    // macOS: CPU die sensors from the AppleSMC (same source as the app).
    #[cfg(target_os = "macos")]
    {
        return crate::engine::smc::cpu_temperature();
    }
    #[cfg(target_os = "linux")]
    {
        return linux_cpu_temperature();
    }
    #[allow(unreachable_code)]
    None
}

/// CPU package temperature from hwmon/thermal zones (coretemp, k10temp,
/// zenpower, Raspberry Pi `cpu_thermal`, ...). Falls back to the hottest
/// plausible sensor when no CPU-labelled one exists.
#[cfg(target_os = "linux")]
fn linux_cpu_temperature() -> Option<f32> {
    let components = sysinfo::Components::new_with_refreshed_list();
    let plausible = |t: f32| t.is_finite() && t > 5.0 && t < 125.0;
    const PREFERRED: [&str; 8] = [
        "package id 0", "tctl", "tdie", "coretemp", "k10temp", "zenpower", "cpu_thermal", "cpu",
    ];
    for key in PREFERRED {
        if let Some(c) = components
            .iter()
            .find(|c| c.label().to_lowercase().contains(key) && plausible(c.temperature()))
        {
            return Some(c.temperature());
        }
    }
    components
        .iter()
        .map(|c| c.temperature())
        .filter(|t| plausible(*t))
        .fold(None, |acc: Option<f32>, t| Some(acc.map_or(t, |a| a.max(t))))
}

/// "macOS" instead of the kernel name "Darwin"; distro name on Linux.
fn os_display_name() -> String {
    if cfg!(target_os = "macos") {
        return "macOS".to_string();
    }
    System::name().unwrap_or_else(|| std::env::consts::OS.to_string())
}

pub fn get_memory_telemetry(sys: &mut System) -> MemoryTelemetry {
    sys.refresh_memory();
    let total = sys.total_memory();
    let used = sys.used_memory();
    let free = sys.free_memory();
    let from_sysinfo = (used, free, total.saturating_sub(used + free), sys.available_memory());

    // macOS: use the same formulas as the native app (MemoryUsage.swift) so
    // the CLI and the widget agree; sysinfo reports available = 0 there.
    #[cfg(target_os = "macos")]
    let from_sysinfo = macos_vm_memory(total).unwrap_or(from_sysinfo);
    let (used, free, cached, available) = from_sysinfo;

    let used_percent = if total > 0 {
        ((used as f64 / total as f64) * 100.0) as f32
    } else {
        0.0
    };
    let free_percent = (100.0 - used_percent).max(0.0);

    MemoryTelemetry {
        total_bytes: total,
        used_bytes: used,
        free_bytes: free,
        cached_bytes: cached,
        available_bytes: available,
        total_formatted: format_bytes(total),
        used_formatted: format_bytes(used),
        free_formatted: format_bytes(free),
        cached_formatted: format_bytes(cached),
        available_formatted: format_bytes(available),
        used_percent,
        free_percent,
    }
}

/// (used, free, cached, available) in bytes from `vm_stat`:
/// used = active + wired + compressed, free = total − used,
/// cached = purgeable + file-backed, available = free pages + cached.
#[cfg(target_os = "macos")]
fn macos_vm_memory(total: u64) -> Option<(u64, u64, u64, u64)> {
    let output = std::process::Command::new("vm_stat").output().ok()?;
    let text = String::from_utf8_lossy(&output.stdout);
    let page_size: u64 = text
        .lines()
        .next()
        .and_then(|l| l.split("page size of ").nth(1))
        .and_then(|r| r.split_whitespace().next())
        .and_then(|n| n.parse().ok())
        .unwrap_or(16384);
    let pages = |label: &str| -> u64 {
        text.lines()
            .find(|l| l.starts_with(label))
            .and_then(|l| l.rsplit(':').next())
            .and_then(|v| v.trim().trim_end_matches('.').parse().ok())
            .unwrap_or(0)
    };
    let active = pages("Pages active");
    if active == 0 {
        return None;
    }
    let used = (active + pages("Pages wired down") + pages("Pages occupied by compressor")) * page_size;
    let cached = (pages("Pages purgeable") + pages("File-backed pages")) * page_size;
    let available = pages("Pages free") * page_size + cached;
    Some((used.min(total), total.saturating_sub(used), cached, available.min(total)))
}

pub fn get_root_disk_telemetry() -> RootDiskTelemetry {
    let disks = Disks::new_with_refreshed_list();
    
    // Find root "/" disk or first available disk
    let mut root_total = 0u64;
    let mut root_free = 0u64;
    let mut fs_type = "unknown".to_string();

    if let Some(d) = disks.iter().find(|d| d.mount_point() == std::path::Path::new("/")) {
        root_total = d.total_space();
        root_free = d.available_space();
        fs_type = d.file_system().to_string_lossy().to_string();
    } else if let Some(d) = disks.first() {
        root_total = d.total_space();
        root_free = d.available_space();
        fs_type = d.file_system().to_string_lossy().to_string();
    }

    let root_used = root_total.saturating_sub(root_free);
    let used_pct = if root_total > 0 {
        ((root_used as f64 / root_total as f64) * 100.0) as f32
    } else {
        0.0
    };

    // Live disk I/O rate via iostat or default estimation
    let (read_speed, write_speed) = get_disk_io_rates();

    RootDiskTelemetry {
        mount_point: "/".to_string(),
        file_system: fs_type,
        total_bytes: root_total,
        used_bytes: root_used,
        free_bytes: root_free,
        total_formatted: format_bytes(root_total),
        used_formatted: format_bytes(root_used),
        free_formatted: format_bytes(root_free),
        used_percent: used_pct,
        read_speed_bytes: read_speed,
        write_speed_bytes: write_speed,
        read_speed_formatted: format_rate(read_speed),
        write_speed_formatted: format_rate(write_speed),
    }
}

/// Read/write throughput of the physical disks (bytes/s), computed as the
/// delta of the kernel's cumulative byte counters between two calls.
/// Linux: `/sys/block/<disk>/stat`; macOS: `IOBlockStorageDriver` statistics.
fn get_disk_io_rates() -> (u64, u64) {
    let Some((read_total, write_total)) = disk_io_counters() else {
        return (0, 0);
    };
    let now = Instant::now();
    let mut guard = HISTORY.lock().unwrap_or_else(|e| e.into_inner());
    let Some(state) = guard.as_mut() else {
        return (0, 0);
    };
    let rates = match state.last_disk_sample {
        Some((at, last_read, last_write)) => {
            let secs = now.duration_since(at).as_secs_f64().max(0.05);
            (
                (read_total.saturating_sub(last_read) as f64 / secs) as u64,
                (write_total.saturating_sub(last_write) as f64 / secs) as u64,
            )
        }
        None => (0, 0),
    };
    state.last_disk_sample = Some((now, read_total, write_total));
    rates
}

#[cfg(target_os = "linux")]
fn disk_io_counters() -> Option<(u64, u64)> {
    let mut read = 0u64;
    let mut written = 0u64;
    for entry in std::fs::read_dir("/sys/block").ok()?.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if !crate::engine::linux::is_physical_block_device(&name) {
            continue;
        }
        let Ok(stat) = std::fs::read_to_string(entry.path().join("stat")) else { continue };
        let fields: Vec<u64> = stat.split_whitespace().filter_map(|v| v.parse().ok()).collect();
        // Field 3 = sectors read, field 7 = sectors written; always 512-byte units.
        if fields.len() >= 7 {
            read += fields[2] * 512;
            written += fields[6] * 512;
        }
    }
    Some((read, written))
}

#[cfg(target_os = "macos")]
fn disk_io_counters() -> Option<(u64, u64)> {
    let output = std::process::Command::new("ioreg")
        .args(["-r", "-c", "IOBlockStorageDriver", "-k", "Statistics", "-d", "1"])
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&output.stdout);
    let mut read = 0u64;
    let mut written = 0u64;
    let mut found = false;
    for line in text.lines().filter(|l| l.contains("\"Statistics\"")) {
        if let Some(v) = ioreg_stat_value(line, "Bytes (Read)") {
            read += v;
            found = true;
        }
        if let Some(v) = ioreg_stat_value(line, "Bytes (Write)") {
            written += v;
            found = true;
        }
    }
    found.then_some((read, written))
}

#[cfg(target_os = "macos")]
fn ioreg_stat_value(line: &str, key: &str) -> Option<u64> {
    let start = line.find(&format!("\"{}\"=", key))? + key.len() + 3;
    let digits: String = line[start..].chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

#[cfg(not(any(target_os = "linux", target_os = "macos")))]
fn disk_io_counters() -> Option<(u64, u64)> {
    None
}

pub fn get_network_telemetry() -> NetworkTelemetry {
    let (rx_rate, tx_rate, _, rx_history, tx_history) = get_or_init_history();

    let (interface_name, local_ip) = get_primary_interface_info();

    NetworkTelemetry {
        interface_name,
        local_ip,
        download_bytes_sec: rx_rate as u64,
        upload_bytes_sec: tx_rate as u64,
        download_formatted: format_rate(rx_rate as u64),
        upload_formatted: format_rate(tx_rate as u64),
        download_history: rx_history,
        upload_history: tx_history,
    }
}

fn get_primary_interface_info() -> (String, Option<String>) {
    #[cfg(target_os = "macos")]
    {
        let route_out = std::process::Command::new("route")
            .args(["-n", "get", "default"])
            .output();
        let mut iface = "en0".to_string();
        if let Ok(o) = route_out {
            let text = String::from_utf8_lossy(&o.stdout);
            for line in text.lines() {
                if line.trim().starts_with("interface:") {
                    if let Some(i) = line.split(':').nth(1) {
                        iface = i.trim().to_string();
                    }
                }
            }
        }

        let ip_out = std::process::Command::new("ipconfig")
            .args(["getifaddr", &iface])
            .output();
        let local_ip = if let Ok(o) = ip_out {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if !s.is_empty() {
                Some(s)
            } else {
                None
            }
        } else {
            None
        };

        return (iface, local_ip);
    }

    #[cfg(target_os = "linux")]
    {
        return linux_primary_interface();
    }

    #[allow(unreachable_code)]
    ("unknown".to_string(), None)
}

/// Default-route interface from `/proc/net/route` and its IPv4 address.
#[cfg(target_os = "linux")]
fn linux_primary_interface() -> (String, Option<String>) {
    let route_iface = std::fs::read_to_string("/proc/net/route").ok().and_then(|text| {
        text.lines()
            .skip(1)
            .map(|l| l.split_whitespace().collect::<Vec<_>>())
            .filter(|f| f.len() > 7 && f[1] == "00000000" && f[7] == "00000000")
            .map(|f| f[0].to_string())
            .next()
    });

    let networks = Networks::new_with_refreshed_list();
    let iface = route_iface.or_else(|| {
        // No default route: first non-loopback interface that has an address.
        networks
            .iter()
            .filter(|(name, data)| !name.starts_with("lo") && !data.ip_networks().is_empty())
            .map(|(name, _)| name.clone())
            .min()
    });

    let Some(iface) = iface else {
        return ("none".to_string(), None);
    };
    let ip = networks.get(&iface).and_then(|data| {
        data.ip_networks()
            .iter()
            .find(|n| n.addr.is_ipv4())
            .or_else(|| data.ip_networks().first())
            .map(|n| n.addr.to_string())
    });
    (iface, ip)
}

/// Top processes by CPU usage.
pub fn get_top_processes(limit: usize) -> Vec<ProcessMetric> {
    with_system(|sys| collect_top_processes(sys, limit))
}

fn collect_top_processes(sys: &mut System, limit: usize) -> Vec<ProcessMetric> {
    // macOS: `ps` sees every process without extra entitlements and matches
    // what Activity Monitor reports; fall back to sysinfo if it fails.
    #[cfg(target_os = "macos")]
    {
        let list = macos_ps_top_processes(limit);
        if !list.is_empty() {
            return list;
        }
    }

    sys.refresh_processes(sysinfo::ProcessesToUpdate::All);
    let mut list: Vec<ProcessMetric> = sys
        .processes()
        .values()
        .filter(|p| p.thread_kind().is_none()) // skip Linux userland threads
        .map(|p| {
            let mem = p.memory();
            ProcessMetric {
                pid: p.pid().as_u32(),
                name: process_display_name(p),
                cpu_percent: p.cpu_usage(),
                memory_bytes: mem,
                memory_formatted: format_bytes(mem),
            }
        })
        .collect();
    list.sort_by(|a, b| {
        b.cpu_percent
            .partial_cmp(&a.cpu_percent)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(b.memory_bytes.cmp(&a.memory_bytes))
    });
    list.truncate(limit);
    list
}

/// Linux truncates `comm` to 15 bytes ("environment-man"); prefer the
/// executable's file name when the short name looks cut off.
fn process_display_name(p: &sysinfo::Process) -> String {
    let short = p.name().to_string_lossy().to_string();
    if short.len() < 15 {
        return short;
    }
    p.exe()
        .and_then(|e| e.file_name())
        .or_else(|| p.cmd().first().and_then(|c| std::path::Path::new(c).file_name()))
        .map(|n| n.to_string_lossy().to_string())
        .filter(|n| n.starts_with(&short))
        .unwrap_or(short)
}

#[cfg(target_os = "macos")]
fn macos_ps_top_processes(limit: usize) -> Vec<ProcessMetric> {
    let Ok(output) = std::process::Command::new("ps")
        .args(["-Aceo", "pid,%cpu,rss,comm", "-r"])
        .output()
    else {
        return Vec::new();
    };
    let text = String::from_utf8_lossy(&output.stdout);
    text.lines()
        .skip(1)
        .filter_map(|line| {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() < 4 {
                return None;
            }
            let name = parts[3..].join(" ");
            let name = std::path::Path::new(&name)
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or(name);
            let memory_bytes = parts[2].parse::<u64>().unwrap_or(0) * 1024;
            Some(ProcessMetric {
                pid: parts[0].parse().unwrap_or(0),
                name,
                cpu_percent: parts[1].parse().unwrap_or(0.0),
                memory_bytes,
                memory_formatted: format_bytes(memory_bytes),
            })
        })
        .take(limit)
        .collect()
}

pub fn get_full_telemetry(battery: &BatteryReport, physical_disks: Vec<crate::models::disk::DiskDevice>) -> FullTelemetryOverview {
    let (cpu, memory, chip_name, top_processes) = with_system(|sys| {
        let cpu = get_cpu_telemetry(sys);
        let memory = get_memory_telemetry(sys);
        let chip_name = get_chip_name(sys);
        let top_processes = collect_top_processes(sys, 5);
        (cpu, memory, chip_name, top_processes)
    });
    let disk = get_root_disk_telemetry();
    let network = get_network_telemetry();

    let os_name = os_display_name();
    let os_version = System::os_version().unwrap_or_else(|| "Unknown".to_string());
    let host_name = System::host_name().unwrap_or_else(|| "localhost".to_string());

    let uptime_secs = System::uptime();
    let days = uptime_secs / 86400;
    let hours = (uptime_secs % 86400) / 3600;
    let mins = (uptime_secs % 3600) / 60;
    let uptime_formatted = if days > 0 {
        format!("{}d {}h", days, hours)
    } else {
        format!("{}h {}m", hours, mins)
    };

    let battery_health_opt = if battery.installed {
        Some(battery.health_percent)
    } else {
        None
    };
    let battery_level_opt = if battery.installed {
        Some(battery.current_capacity_percent as f32)
    } else {
        None
    };

    let health_score = HealthScore::compute(
        cpu.total_percent,
        memory.used_percent / 100.0,
        disk.used_percent / 100.0,
        battery_health_opt,
        battery_level_opt,
        battery.is_charging,
    );

    let header = SystemHeader {
        chip_name,
        total_ram_formatted: memory.total_formatted.clone(),
        os_name,
        os_version,
        uptime_formatted,
        host_name,
        health_score,
    };

    let advisory = compute_reboot_advisory(
        uptime_secs,
        disk.used_percent,
        &top_processes,
    );

    FullTelemetryOverview {
        header,
        cpu,
        memory,
        disk,
        network,
        battery: battery.clone(),
        top_processes,
        physical_disks,
        advisory,
    }
}

pub fn get_swap_usage() -> (u64, u64) {
    #[cfg(target_os = "macos")]
    {
        let output = std::process::Command::new("sysctl")
            .args(["-n", "vm.swapusage"])
            .output();
        if let Ok(o) = output {
            let text = String::from_utf8_lossy(&o.stdout);
            let total = parse_swap_token(&text, "total");
            let used = parse_swap_token(&text, "used");
            return (used.unwrap_or(0), total.unwrap_or(0));
        }
    }
    #[cfg(target_os = "linux")]
    {
        if let Ok(content) = std::fs::read_to_string("/proc/meminfo") {
            let mut total_kb = 0u64;
            let mut free_kb = 0u64;
            for line in content.lines() {
                if line.starts_with("SwapTotal:") {
                    total_kb = line.split_whitespace().nth(1).and_then(|v| v.parse().ok()).unwrap_or(0);
                } else if line.starts_with("SwapFree:") {
                    free_kb = line.split_whitespace().nth(1).and_then(|v| v.parse().ok()).unwrap_or(0);
                }
            }
            let used_kb = total_kb.saturating_sub(free_kb);
            return (used_kb * 1024, total_kb * 1024);
        }
    }
    (0, 0)
}

#[cfg(target_os = "macos")]
fn parse_swap_token(text: &str, key: &str) -> Option<u64> {
    if let Some(pos) = text.find(key) {
        let rest = &text[pos + key.len()..];
        let token = rest.trim_start().trim_start_matches('=').trim_start();
        let end = token
            .find(|c: char| !c.is_numeric() && c != '.' && c != 'M' && c != 'G' && c != 'K')
            .unwrap_or(token.len());
        let val_str = token[..end].trim();
        if let Some(num_str) = val_str.strip_suffix('M') {
            num_str.trim().parse::<f64>().ok().map(|m| (m * 1024.0 * 1024.0) as u64)
        } else if let Some(num_str) = val_str.strip_suffix('G') {
            num_str.trim().parse::<f64>().ok().map(|g| (g * 1024.0 * 1024.0 * 1024.0) as u64)
        } else if let Some(num_str) = val_str.strip_suffix('K') {
            num_str.trim().parse::<f64>().ok().map(|k| (k * 1024.0) as u64)
        } else {
            val_str.parse::<u64>().ok()
        }
    } else {
        None
    }
}

/// Swap split by backing store. On Linux, zram/zswap-style compressed RAM
/// swap is cheap and expected; only swap on a real disk/partition/file means
/// paging to storage.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct SwapUsage {
    pub disk_used: u64,
    pub disk_total: u64,
    pub zram_used: u64,
    pub zram_total: u64,
}

impl SwapUsage {
    pub fn total_used(&self) -> u64 {
        self.disk_used + self.zram_used
    }
    pub fn total_size(&self) -> u64 {
        self.disk_total + self.zram_total
    }
}

/// Parses `/proc/swaps` (sizes in KiB).
pub fn parse_proc_swaps(text: &str) -> SwapUsage {
    let mut usage = SwapUsage::default();
    for line in text.lines().skip(1) {
        let f: Vec<&str> = line.split_whitespace().collect();
        if f.len() < 4 {
            continue;
        }
        let size = f[2].parse::<u64>().unwrap_or(0) * 1024;
        let used = f[3].parse::<u64>().unwrap_or(0) * 1024;
        if f[0].starts_with("/dev/zram") {
            usage.zram_total += size;
            usage.zram_used += used;
        } else {
            usage.disk_total += size;
            usage.disk_used += used;
        }
    }
    usage
}

/// Which platform's advice to give.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdvisoryPlatform {
    MacOS,
    Linux,
}

/// Everything the advisory looks at; built from live data by
/// `compute_reboot_advisory`, or by hand in tests.
#[derive(Debug, Clone)]
pub struct AdvisoryInput<'a> {
    pub platform: AdvisoryPlatform,
    pub swap: SwapUsage,
    pub total_ram: u64,
    pub uptime_secs: u64,
    pub disk_used_pct: f32,
    /// Linux: `Some(packages)` when /var/run/reboot-required exists
    /// (Debian/Ubuntu after kernel or core-library updates).
    pub reboot_required: Option<Vec<String>>,
    pub top_processes: &'a [ProcessMetric],
}

pub fn compute_reboot_advisory(
    uptime_secs: u64,
    disk_used_pct: f32,
    top_processes: &[ProcessMetric],
) -> crate::models::system::RebootAdvisory {
    #[cfg(target_os = "linux")]
    {
        let swap = std::fs::read_to_string("/proc/swaps")
            .map(|t| parse_proc_swaps(&t))
            .unwrap_or_default();
        let reboot_required = std::path::Path::new("/var/run/reboot-required").exists().then(|| {
            std::fs::read_to_string("/var/run/reboot-required.pkgs")
                .map(|t| t.lines().map(str::to_string).filter(|l| !l.is_empty()).collect())
                .unwrap_or_default()
        });
        let total_ram = with_system(|sys| sys.total_memory());
        return evaluate_advisory(&AdvisoryInput {
            platform: AdvisoryPlatform::Linux,
            swap,
            total_ram,
            uptime_secs,
            disk_used_pct,
            reboot_required,
            top_processes,
        });
    }
    #[allow(unreachable_code)]
    {
        let (swap_used, swap_total) = get_swap_usage();
        evaluate_reboot_advisory(swap_used, swap_total, uptime_secs, disk_used_pct, top_processes)
    }
}

/// macOS advisory (swap on the internal SSD). Kept as the simple entry point
/// used by the tests and the HTTP API.
pub fn evaluate_reboot_advisory(
    swap_used: u64,
    swap_total: u64,
    uptime_secs: u64,
    disk_used_pct: f32,
    top_processes: &[ProcessMetric],
) -> crate::models::system::RebootAdvisory {
    evaluate_advisory(&AdvisoryInput {
        platform: AdvisoryPlatform::MacOS,
        swap: SwapUsage { disk_used: swap_used, disk_total: swap_total, ..Default::default() },
        total_ram: 0,
        uptime_secs,
        disk_used_pct,
        reboot_required: None,
        top_processes,
    })
}

pub fn evaluate_advisory(input: &AdvisoryInput) -> crate::models::system::RebootAdvisory {
    use crate::models::system::AdvisoryTrigger;
    const GB: u64 = 1024 * 1024 * 1024;

    let linux = input.platform == AdvisoryPlatform::Linux;
    let swap = input.swap;
    let uptime_days = input.uptime_secs / 86400;
    let mut penalties: u32 = 0;
    let mut triggers = Vec::new();
    let mut trigger = |penalty: u32, category: &str, severity: &str, message: String, metric: String| {
        penalties += penalty;
        triggers.push(AdvisoryTrigger {
            category: category.to_string(),
            severity: severity.to_string(),
            message,
            metric_value: metric,
        });
    };

    // --- Swap ---------------------------------------------------------------
    if linux {
        // Disk-backed swap: thresholds relative to RAM (a 2 GB box and a
        // 256 GB server differ), with the macOS absolute values as a floor.
        let ram = input.total_ram.max(GB);
        let (warn, crit) = ((ram / 8).max(GB), (ram / 3).max(3 * GB));
        if swap.disk_used >= crit {
            trigger(
                35,
                "Swap Memory",
                "critical",
                format!(
                    "{} paged out to disk swap. The system is short on RAM; close heavy processes or add memory.",
                    format_bytes(swap.disk_used)
                ),
                format_bytes(swap.disk_used),
            );
        } else if swap.disk_used >= warn {
            trigger(
                15,
                "Swap Memory",
                "warning",
                format!("{} paged out to disk swap; memory pressure is elevated.", format_bytes(swap.disk_used)),
                format_bytes(swap.disk_used),
            );
        }
        // zram is compressed RAM: using it is normal, running out of it is not.
        if swap.zram_total > 0 {
            let pct = swap.zram_used as f64 / swap.zram_total as f64 * 100.0;
            if pct >= 90.0 {
                trigger(
                    30,
                    "Compressed Swap (zram)",
                    "critical",
                    format!("zram swap is {:.0}% full; the OOM killer may start terminating processes.", pct),
                    format!("{:.0}% of {}", pct, format_bytes(swap.zram_total)),
                );
            } else if pct >= 75.0 {
                trigger(
                    12,
                    "Compressed Swap (zram)",
                    "warning",
                    format!("zram swap is {:.0}% full; memory pressure is high.", pct),
                    format!("{:.0}% of {}", pct, format_bytes(swap.zram_total)),
                );
            }
        }
    } else if swap.disk_used >= 8 * GB {
        trigger(
            45,
            "Swap Memory",
            "critical",
            format!(
                "Heavy SSD swap accumulation ({}). Virtual memory paging active; restart will restore full memory bandwidth.",
                format_bytes(swap.disk_used)
            ),
            format_bytes(swap.disk_used),
        );
    } else if swap.disk_used >= 3 * GB {
        trigger(
            20,
            "Swap Memory",
            "warning",
            format!(
                "Elevated swap usage ({}). Frequent app switching may induce NVMe paging wear.",
                format_bytes(swap.disk_used)
            ),
            format_bytes(swap.disk_used),
        );
    }

    // --- Reboot required (Linux) / uptime (macOS) ---------------------------
    if linux {
        // Long uptime is normal on Linux; what matters is a pending reboot
        // after kernel/libc/systemd updates.
        if let Some(pkgs) = &input.reboot_required {
            let detail = if pkgs.is_empty() {
                String::new()
            } else {
                format!(" ({})", pkgs.iter().take(4).cloned().collect::<Vec<_>>().join(", "))
            };
            trigger(
                40,
                "Pending Updates",
                "critical",
                format!("Installed updates need a reboot to take effect{}.", detail),
                "reboot-required".to_string(),
            );
        }
    } else if uptime_days >= 28 {
        trigger(
            25,
            "System Uptime",
            "critical",
            format!(
                "Continuous uptime of {} days. Kernel IPC handles, cache pools, and subsystem allocations should be refreshed.",
                uptime_days
            ),
            format!("{} days", uptime_days),
        );
    } else if uptime_days >= 14 {
        trigger(
            15,
            "System Uptime",
            "warning",
            format!("Uptime is {} days. Background daemons gradually accumulate heap fragmentation.", uptime_days),
            format!("{} days", uptime_days),
        );
    } else if uptime_days >= 7 {
        trigger(8, "System Uptime", "info", format!("Continuous uptime is {} days.", uptime_days), format!("{} days", uptime_days));
    }

    // --- Storage ------------------------------------------------------------
    if input.disk_used_pct >= 88.0 {
        trigger(
            25,
            "Storage Headroom",
            "critical",
            format!(
                "Boot volume is {:.1}% full (<12% free). Low headroom constrains swap files, caches and OS updates.",
                input.disk_used_pct
            ),
            format!("{:.1}% used", input.disk_used_pct),
        );
    } else if input.disk_used_pct >= 82.0 {
        trigger(
            10,
            "Storage Headroom",
            "warning",
            format!("Boot volume free space is low ({:.1}% full).", input.disk_used_pct),
            format!("{:.1}% used", input.disk_used_pct),
        );
    }

    // --- macOS compositor ---------------------------------------------------
    if !linux {
        if let Some(p) = input
            .top_processes
            .iter()
            .take(3)
            .find(|p| p.name.contains("WindowServer") && p.memory_bytes >= 1536 * 1024 * 1024)
        {
            trigger(
                15,
                "GUI Compositor",
                "warning",
                format!("WindowServer has accumulated {} of display surface caches.", p.memory_formatted),
                p.memory_formatted.clone(),
            );
        }
    }

    // The summary names what actually triggered the advisory. On Linux only
    // a pending update makes a reboot the remedy; memory/disk pressure is
    // fixed by freeing resources, not by restarting.
    let reasons = triggers
        .iter()
        .map(|t| format!("{} ({})", t.category.to_lowercase(), t.metric_value))
        .collect::<Vec<_>>()
        .join(", ");
    let score = 100u32.saturating_sub(penalties);
    let reboot_is_remedy = !linux || input.reboot_required.is_some();
    let (level, should_reboot, summary) = if score >= 85 {
        ("Optimal", false, "System performance is optimal. No restart needed.".to_string())
    } else if score >= 65 {
        ("Advisory", false, format!("System health is good; watch {}.", reasons))
    } else if !reboot_is_remedy {
        let level = if score >= 45 { "Warning" } else { "Critical" };
        (level, false, format!("Resource pressure: {}. Free memory or disk space; a reboot is not required.", reasons))
    } else if score >= 45 {
        ("Recommended", true, format!("Reboot recommended: {}.", reasons))
    } else {
        ("Critical", true, format!("Urgent reboot advised: {}. Restart to restore stability.", reasons))
    };

    crate::models::system::RebootAdvisory {
        should_reboot,
        level: level.to_string(),
        score,
        summary,
        swap_used_bytes: swap.total_used(),
        swap_total_bytes: swap.total_size(),
        swap_used_formatted: format_bytes(swap.total_used()),
        uptime_days,
        triggers,
    }
}

pub fn send_desktop_notification(title: &str, subtitle: &str, message: &str) -> bool {
    #[cfg(target_os = "macos")]
    {
        let full_body = if !subtitle.is_empty() {
            format!("{} – {}", subtitle, message)
        } else {
            message.to_string()
        };

        // 1. Try native Osprey app bundle to show the official AppIcon in notification center
        let bundle_candidates = [
            std::path::PathBuf::from("./dist/Osprey.app/Contents/MacOS/Osprey"),
            std::path::PathBuf::from("/Applications/Osprey.app/Contents/MacOS/Osprey"),
        ];

        for candidate in &bundle_candidates {
            if candidate.exists() {
                if let Ok(status) = std::process::Command::new(candidate)
                    .args(["--notify", title, &full_body])
                    .status()
                {
                    if status.success() {
                        return true;
                    }
                }
            }
        }

        // 2. Fallback to AppleScript
        let script = format!(
            "display notification \"{}\" with title \"{}\" subtitle \"{}\"",
            message.replace('\"', "\\\""),
            title.replace('\"', "\\\""),
            subtitle.replace('\"', "\\\"")
        );
        let output = std::process::Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output();
        return output.map(|o| o.status.success()).unwrap_or(false);
    }
    #[cfg(target_os = "linux")]
    {
        let full_msg = if !subtitle.is_empty() {
            format!("{}: {}", subtitle, message)
        } else {
            message.to_string()
        };
        let output = std::process::Command::new("notify-send")
            .args([title, &full_msg])
            .output();
        return output.map(|o| o.status.success()).unwrap_or(false);
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    false
}

