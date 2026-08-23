use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Utc};
use futures_util::stream::StreamExt;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fs,
    io::Write,
    net::SocketAddr,
    path::PathBuf,
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{
    sync::{broadcast, RwLock},
    time::interval,
};
use tower_http::cors::{Any, CorsLayer};

const DATA_SYSTEM_DIR: &str = "/data/system";
const DATA_APPS_DIR: &str = "/data/apps";
const DATA_USER_DIR: &str = "/data/user";
const PREFS_FILE: &str = "/data/system/prefs.json";
const INSTALLED_FILE: &str = "/data/system/installed.json";

#[derive(Clone)]
struct AppState {
    prefs: Arc<RwLock<Prefs>>,
    installed: Arc<RwLock<InstalledApps>>,
    event_tx: broadcast::Sender<Event>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Prefs {
    version: u32,
    theme: String,
    accent: String,
    accent_dim: String,
    reduce_motion: bool,
    network: NetworkPrefs,
    display: DisplayPrefs,
    sound: SoundPrefs,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct NetworkPrefs {
    last_connected_ssid: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DisplayPrefs {
    brightness: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SoundPrefs {
    volume: u8,
    system_sounds: bool,
}

impl Default for Prefs {
    fn default() -> Self {
        Self {
            version: 1,
            theme: "dark".to_string(),
            accent: "#4FD1C5".to_string(),
            accent_dim: "#2C8A80".to_string(),
            reduce_motion: false,
            network: NetworkPrefs {
                last_connected_ssid: None,
            },
            display: DisplayPrefs { brightness: 80 },
            sound: SoundPrefs {
                volume: 70,
                system_sounds: true,
            },
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct InstalledApps {
    version: u32,
    apps: Vec<AppEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AppEntry {
    id: String,
    r#type: String,
    name: String,
    installed_at: DateTime<Utc>,
}

impl Default for InstalledApps {
    fn default() -> Self {
        Self {
            version: 1,
            apps: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
enum Event {
    BatteryChange { level: u8 },
    NetworkStateChange { connected: bool },
    AppInstalled { id: String },
    AppUninstalled { id: String },
}

#[derive(Debug, Serialize, Deserialize)]
struct SystemInfo {
    hostname: String,
    kernel_version: String,
    uptime_secs: u64,
    memory_total_kb: u64,
    memory_free_kb: u64,
    disk_total_bytes: u64,
    disk_used_bytes: u64,
}

#[derive(Debug, Deserialize)]
struct InstallAppRequest {
    id: String,
    r#type: String,
    name: String,
}

#[derive(Debug, Deserialize)]
struct UninstallAppRequest {
    id: String,
}

#[derive(Debug, Serialize)]
struct NetworkStatus {
    connected: bool,
    ssid: Option<String>,
    ip_address: Option<String>,
}

#[derive(Debug, Serialize)]
struct BatteryStatus {
    present: bool,
    charging: bool,
    level: u8,
}

#[tokio::main]
async fn main() {
    ensure_data_dirs();
    
    let prefs = load_prefs().await;
    let installed = load_installed().await;
    
    let (event_tx, _) = broadcast::channel::<Event>(100);
    
    let state = AppState {
        prefs: Arc::new(RwLock::new(prefs)),
        installed: Arc::new(RwLock::new(installed)),
        event_tx,
    };
    
    // Start background event emitters
    let state_clone = state.clone();
    tokio::spawn(async move {
        let mut int = interval(Duration::from_secs(5));
        loop {
            int.tick().await;
            // In real impl, check battery and emit BatteryChange events
            let _ = &state_clone;
        }
    });
    
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);
    
    let app = Router::new()
        .route("/api/system/info", get(get_system_info))
        .route("/api/prefs", get(get_prefs).post(set_prefs))
        .route("/api/network/status", get(get_network_status))
        .route("/api/network/connect", post(connect_network))
        .route("/api/power/battery", get(get_battery_status))
        .route("/api/apps", get(get_apps).post(install_app))
        .route("/api/apps/:id", delete(uninstall_app))
        .route("/events", get(events_ws))
        .route("/api/system/brightness", post(set_brightness))
        .route("/api/system/volume", post(set_volume))
        .with_state(state)
        .layer(cors);
    
    let addr = SocketAddr::from(([127, 0, 0, 1], 7331));
    println!("endroidd listening on {}", addr);
    
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

fn ensure_data_dirs() {
    fs::create_dir_all(DATA_SYSTEM_DIR).expect("Failed to create /data/system");
    fs::create_dir_all(DATA_APPS_DIR).expect("Failed to create /data/apps");
    fs::create_dir_all(DATA_USER_DIR).expect("Failed to create /data/user");
}

async fn load_prefs() -> Prefs {
    match fs::read_to_string(PREFS_FILE) {
        Ok(content) => {
            match serde_json::from_str::<Prefs>(&content) {
                Ok(p) => migrate_prefs(p),
                Err(_) => Prefs::default(),
            }
        }
        Err(_) => Prefs::default(),
    }
}

async fn load_installed() -> InstalledApps {
    match fs::read_to_string(INSTALLED_FILE) {
        Ok(content) => {
            serde_json::from_str::<InstalledApps>(&content).unwrap_or_else(|_| InstalledApps::default())
        }
        Err(_) => InstalledApps::default(),
    }
}

fn migrate_prefs(mut prefs: Prefs) -> Prefs {
    // Future migrations based on version
    if prefs.version < 1 {
        prefs.version = 1;
    }
    prefs
}

fn save_prefs(prefs: &Prefs) -> Result<(), String> {
    let temp_path = format!("{}.tmp", PREFS_FILE);
    let content = serde_json::to_string_pretty(prefs).map_err(|e| e.to_string())?;
    
    let mut file = fs::File::create(&temp_path).map_err(|e| e.to_string())?;
    file.write_all(content.as_bytes()).map_err(|e| e.to_string())?;
    file.sync_all().map_err(|e| e.to_string())?;
    
    fs::rename(&temp_path, PREFS_FILE).map_err(|e| e.to_string())?;
    Ok(())
}

fn save_installed(installed: &InstalledApps) -> Result<(), String> {
    let temp_path = format!("{}.tmp", INSTALLED_FILE);
    let content = serde_json::to_string_pretty(installed).map_err(|e| e.to_string())?;
    
    let mut file = fs::File::create(&temp_path).map_err(|e| e.to_string())?;
    file.write_all(content.as_bytes()).map_err(|e| e.to_string())?;
    file.sync_all().map_err(|e| e.to_string())?;
    
    fs::rename(&temp_path, INSTALLED_FILE).map_err(|e| e.to_string())?;
    Ok(())
}

async fn get_system_info(State(_state): State<AppState>) -> Json<SystemInfo> {
    let hostname = fs::read_to_string("/etc/hostname")
        .unwrap_or_else(|_| "endroid".to_string())
        .trim()
        .to_string();
    
    let kernel_version = fs::read_to_string("/proc/version")
        .unwrap_or_default()
        .split_whitespace()
        .nth(2)
        .unwrap_or("unknown")
        .to_string();
    
    let uptime_secs = fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|s| s.split_whitespace().next().and_then(|f| f.parse::<f64>().ok()))
        .map(|s| s as u64)
        .unwrap_or(0);
    
    let (mem_total, mem_free) = read_meminfo();
    let (disk_total, disk_used) = read_disk_usage();
    
    Json(SystemInfo {
        hostname,
        kernel_version,
        uptime_secs,
        memory_total_kb: mem_total,
        memory_free_kb: mem_free,
        disk_total_bytes: disk_total,
        disk_used_bytes: disk_used,
    })
}

fn read_meminfo() -> (u64, u64) {
    fs::read_to_string("/proc/meminfo")
        .ok()
        .and_then(|content| {
            let mut total = 0;
            let mut free = 0;
            for line in content.lines() {
                if line.starts_with("MemTotal:") {
                    total = line.split_whitespace().nth(1).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
                } else if line.starts_with("MemFree:") {
                    free = line.split_whitespace().nth(1).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
                }
            }
            Some((total, free))
        })
        .unwrap_or((0, 0))
}

fn read_disk_usage() -> (u64, u64) {
    use std::os::unix::fs::MetadataExt;
    
    match fs::metadata("/data") {
        Ok(meta) => {
            // This is a simplified approach - in production, use nix or statvfs
            (meta.size(), 0)
        }
        Err(_) => (0, 0),
    }
}

async fn get_prefs(State(state): State<AppState>) -> Json<Prefs> {
    let prefs = state.prefs.read().await;
    Json(prefs.clone())
}

async fn set_prefs(
    State(state): State<AppState>,
    Json(new_prefs): Json<Prefs>,
) -> Result<Json<Prefs>, StatusCode> {
    let mut prefs = state.prefs.write().await;
    *prefs = migrate_prefs(new_prefs);
    
    save_prefs(&prefs).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(prefs.clone()))
}

async fn get_network_status(State(_state): State<AppState>) -> Json<NetworkStatus> {
    // Simplified - would integrate with connman/NetworkManager via D-Bus
    Json(NetworkStatus {
        connected: false,
        ssid: None,
        ip_address: None,
    })
}

async fn connect_network(
    State(_state): State<AppState>,
) -> Result<StatusCode, StatusCode> {
    // Would integrate with connman/NetworkManager via D-Bus
    Ok(StatusCode::OK)
}

async fn get_battery_status(State(_state): State<AppState>) -> Json<BatteryStatus> {
    // Check /sys/class/power_supply for battery info
    let battery_path = PathBuf::from("/sys/class/power_supply/BAT0");
    
    if !battery_path.exists() {
        return Json(BatteryStatus {
            present: false,
            charging: false,
            level: 100,
        });
    }
    
    let present = fs::read_to_string(battery_path.join("present"))
        .ok()
        .and_then(|s| s.trim().parse::<u8>().ok())
        .unwrap_or(1)
        == 1;
    
    let charging = fs::read_to_string(battery_path.join("status"))
        .ok()
        .map(|s| s.trim() == "Charging")
        .unwrap_or(false);
    
    let level = fs::read_to_string(battery_path.join("capacity"))
        .ok()
        .and_then(|s| s.trim().parse::<u8>().ok())
        .unwrap_or(100);
    
    Json(BatteryStatus {
        present,
        charging,
        level,
    })
}

async fn get_apps(State(state): State<AppState>) -> Json<InstalledApps> {
    let installed = state.installed.read().await;
    Json(installed.clone())
}

async fn install_app(
    State(state): State<AppState>,
    Json(req): Json<InstallAppRequest>,
) -> Result<StatusCode, StatusCode> {
    let mut installed = state.installed.write().await;
    
    installed.apps.push(AppEntry {
        id: req.id.clone(),
        r#type: req.r#type,
        name: req.name,
        installed_at: Utc::now(),
    });
    
    save_installed(&installed).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    let _ = state.event_tx.send(Event::AppInstalled { id: req.id });
    
    Ok(StatusCode::CREATED)
}

async fn uninstall_app(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<StatusCode, StatusCode> {
    let mut installed = state.installed.write().await;
    
    let initial_len = installed.apps.len();
    installed.apps.retain(|app| app.id != id);
    
    if installed.apps.len() == initial_len {
        return Err(StatusCode::NOT_FOUND);
    }
    
    save_installed(&installed).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // Remove app data directory
    let _ = fs::remove_dir_all(format!("{}/{}", DATA_APPS_DIR, id));
    let _ = fs::remove_dir_all(format!("{}/{}", DATA_USER_DIR, id));
    
    let _ = state.event_tx.send(Event::AppUninstalled { id });
    
    Ok(StatusCode::NO_CONTENT)
}

async fn events_ws(
    State(state): State<AppState>,
) -> impl IntoResponse {
    // Simple SSE-like endpoint for events
    // In production, use WebSocket upgrade
    let mut rx = state.event_tx.subscribe();
    
    let stream = async_stream::stream! {
        while let Ok(event) = rx.recv().await {
            if let Ok(json) = serde_json::to_string(&event) {
                yield Ok::<_, std::convert::Infallible>(axum::body::Body::from(json));
            }
        }
    };
    
    (
        StatusCode::OK,
        [("Content-Type", "text/event-stream")],
        stream,
    )
}

async fn set_brightness(
    State(_state): State<AppState>,
) -> Result<StatusCode, StatusCode> {
    // Write to /sys/class/backlight/*/brightness
    Ok(StatusCode::OK)
}

async fn set_volume(
    State(_state): State<AppState>,
) -> Result<StatusCode, StatusCode> {
    // Use ALSA controls via amixer or direct sysfs
    Ok(StatusCode::OK)
}

