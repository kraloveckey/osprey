use axum::{
    extract::Path,
    http::{header, StatusCode},
    response::{Html, IntoResponse, Response},
    routing::get,
    Json, Router,
};
use std::net::SocketAddr;
use std::process::Command;
use colored::Colorize;

use crate::engine::{battery, export, scan_all_disks, system};

const INDEX_HTML: &str = include_str!("../web/index.html");
const APP_CSS: &str = include_str!("../web/css/app.css");
const APP_JS: &str = include_str!("../web/js/app.js");
const LOGO_PNG: &[u8] = include_bytes!("../web/assets/logo.png");

pub async fn start_server(host: &str, port: u16, open_browser: bool) -> Result<(), Box<dyn std::error::Error>> {
    let app = Router::new()
        .route("/", get(serve_index))
        .route("/css/app.css", get(serve_css))
        .route("/js/app.js", get(serve_js))
        .route("/assets/logo.png", get(serve_logo_png))
        .route("/api/overview", get(api_overview))
        .route("/api/advisory", get(api_advisory))
        .route("/api/notify", get(api_notify))
        .route("/api/open/activity-monitor", get(api_open_activity_monitor))
        .route("/api/drives", get(api_drives))
        .route("/api/drives/:id", get(api_drive_by_id))
        .route("/api/battery", get(api_battery))
        .route("/api/system", get(api_system))
        .route("/api/report", get(api_report))
        .route("/api/health", get(api_health))
        .route("/metrics", get(api_metrics));
    // No CORS layer on purpose: the bundled UI is same-origin, and a
    // permissive policy would let any web page you visit read this machine's
    // telemetry (process list, IPs, disk serials) from 127.0.0.1.

    let addr: SocketAddr = format!("{}:{}", host, port).parse()?;
    let url = format!("http://{}:{}", host, port);

    // Bind before opening a window so the page never loads before the
    // server is listening (and a busy port fails fast with a clear error).
    let listener = tokio::net::TcpListener::bind(addr).await?;

    println!("\n  {}", "Osprey Widget & Server Running".bold().green());
    println!("  URL        : {}", url.bright_cyan());
    println!("  API        : {}/api/overview", url.dimmed());
    println!("  Press Ctrl+C to terminate\n");

    if open_browser {
        #[cfg(target_os = "macos")]
        {
            // Prefer a chromeless app window (Chrome/Brave `--app`), else
            // the default browser.
            let app_browser = ["Google Chrome", "Brave Browser"]
                .into_iter()
                .find(|name| std::path::Path::new(&format!("/Applications/{}.app", name)).exists());
            match app_browser {
                Some(browser) => {
                    let _ = Command::new("open")
                        .args(["-na", browser, "--args", &format!("--app={}", url), "--window-size=580,520"])
                        .spawn();
                }
                None => {
                    let _ = Command::new("open").arg(&url).spawn();
                }
            }
        }
        #[cfg(target_os = "linux")]
        {
            let _ = Command::new("xdg-open").arg(&url).spawn();
        }
    }

    axum::serve(listener, app).await?;

    Ok(())
}


async fn serve_index() -> Html<&'static str> {
    Html(INDEX_HTML)
}

async fn serve_css() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], APP_CSS)
}

async fn serve_js() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "application/javascript; charset=utf-8")], APP_JS)
}

async fn serve_logo_png() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "image/png")], LOGO_PNG)
}

async fn api_overview() -> Json<serde_json::Value> {
    let overview = crate::engine::get_full_overview();
    Json(serde_json::to_value(overview).unwrap_or_default())
}

async fn api_advisory() -> Json<serde_json::Value> {
    let overview = crate::engine::get_full_overview();
    Json(serde_json::to_value(overview.advisory).unwrap_or_default())
}

async fn api_notify() -> Response {
    let overview = crate::engine::get_full_overview();
    let sent = crate::engine::system::send_desktop_notification(
        "Osprey Health Advisory",
        &overview.advisory.level,
        &overview.advisory.summary,
    );
    Json(serde_json::json!({
        "sent": sent,
        "advisory": overview.advisory
    })).into_response()
}

async fn api_open_activity_monitor() -> Response {
    #[cfg(target_os = "macos")]
    {
        let _ = Command::new("open").arg("-a").arg("Activity Monitor").spawn();
    }
    (StatusCode::OK, "Activity Monitor opened").into_response()
}



async fn api_drives() -> Json<serde_json::Value> {
    let disks = scan_all_disks();
    Json(serde_json::to_value(disks).unwrap_or_default())
}

async fn api_drive_by_id(Path(id): Path<String>) -> Response {
    let disks = scan_all_disks();
    if let Some(disk) = disks.into_iter().find(|d| d.id == id) {
        Json(disk).into_response()
    } else {
        (StatusCode::NOT_FOUND, "Drive not found").into_response()
    }
}

async fn api_battery() -> Json<serde_json::Value> {
    let batt = battery::get_battery_telemetry();
    Json(serde_json::to_value(batt).unwrap_or_default())
}

async fn api_system() -> Json<serde_json::Value> {
    let sys = system::get_system_vitals();
    Json(serde_json::to_value(sys).unwrap_or_default())
}

async fn api_report() -> impl IntoResponse {
    let disks = scan_all_disks();
    let batt = battery::get_battery_telemetry();
    let report_txt = export::generate_crystal_report(&disks, &batt);
    ([(header::CONTENT_TYPE, "text/plain; charset=utf-8")], report_txt)
}

async fn api_health() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "healthy",
        "service": "osprey",
        "version": "0.1.0"
    }))
}

async fn api_metrics() -> impl IntoResponse {
    let disks = scan_all_disks();
    let batt = battery::get_battery_telemetry();

    let mut m = String::new();
    m.push_str("# HELP osprey_disk_health_percent Estimated SSD life remaining or health percentage\n");
    m.push_str("# TYPE osprey_disk_health_percent gauge\n");
    for d in &disks {
        let pct = d.smart.as_ref().and_then(|s| s.health_percent).unwrap_or(100);
        m.push_str(&format!("osprey_disk_health_percent{{disk=\"{}\",model=\"{}\"}} {}\n", d.id, d.model_name, pct));
    }

    m.push_str("\n# HELP osprey_disk_temperature_celsius Storage drive composite temperature in Celsius\n");
    m.push_str("# TYPE osprey_disk_temperature_celsius gauge\n");
    for d in &disks {
        if let Some(t) = d.smart.as_ref().and_then(|s| s.temperature_celsius) {
            m.push_str(&format!("osprey_disk_temperature_celsius{{disk=\"{}\"}} {}\n", d.id, t));
        }
    }

    m.push_str("\n# HELP osprey_disk_power_on_hours Total hours drive has been powered on\n");
    m.push_str("# TYPE osprey_disk_power_on_hours counter\n");
    for d in &disks {
        if let Some(h) = d.smart.as_ref().and_then(|s| s.power_on_hours) {
            m.push_str(&format!("osprey_disk_power_on_hours{{disk=\"{}\"}} {}\n", d.id, h));
        }
    }

    m.push_str("\n# HELP osprey_disk_bytes_written_total Total bytes written to storage media (TBW)\n");
    m.push_str("# TYPE osprey_disk_bytes_written_total counter\n");
    for d in &disks {
        if let Some(b) = d.smart.as_ref().and_then(|s| s.data_units_written_bytes) {
            m.push_str(&format!("osprey_disk_bytes_written_total{{disk=\"{}\"}} {}\n", d.id, b));
        }
    }

    if batt.installed {
        m.push_str("\n# HELP osprey_battery_health_percent Battery capacity retention percentage\n");
        m.push_str("# TYPE osprey_battery_health_percent gauge\n");
        m.push_str(&format!("osprey_battery_health_percent {:.1}\n", batt.health_percent));

        m.push_str("\n# HELP osprey_battery_cycle_count Cumulative battery charge cycle count\n");
        m.push_str("# TYPE osprey_battery_cycle_count counter\n");
        m.push_str(&format!("osprey_battery_cycle_count {}\n", batt.cycle_count));

        m.push_str("\n# HELP osprey_battery_charge_percent Current state of battery charge\n");
        m.push_str("# TYPE osprey_battery_charge_percent gauge\n");
        m.push_str(&format!("osprey_battery_charge_percent {}\n", batt.current_capacity_percent));
    }

    ([(header::CONTENT_TYPE, "text/plain; version=0.0.4; charset=utf-8")], m)
}
