//! Flutter-facing camera hub API.
//!
//! SPDX-License-Identifier: GPL-3.0-or-later

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
//use std::sync::Once;
use std::thread::{self, JoinHandle};

//static INIT_LOGGER: Once = Once::new();
static CAMERA_HUB_STARTED: AtomicBool = AtomicBool::new(false);
static CAMERA_HUB_THREAD: OnceLock<Mutex<Option<JoinHandle<()>>>> = OnceLock::new();

fn camera_hub_thread() -> &'static Mutex<Option<JoinHandle<()>>> {
    CAMERA_HUB_THREAD.get_or_init(|| Mutex::new(None))
}

/* Uncomment for debugging.
fn init_logger() {
    INIT_LOGGER.call_once(|| {
        android_logger::init_once(
            android_logger::Config::default()
                .with_tag("SeclusoRustCamera")
                .with_max_level(log::LevelFilter::Info),
        );
    });
}
*/

#[flutter_rust_bridge::frb]
pub fn get_android_camera_specs_json() -> Result<String, String> {
    let specs = secluso_camera_hub::get_android_camera_specs()
        .map_err(|e| format!("failed to get Android camera specs: {e}"))?;

    Ok(android_camera_specs_to_json(&specs))
}

#[flutter_rust_bridge::frb]
pub fn set_android_camera_settings(
    facing: i32,
    width: i32,
    height: i32,
    frame_rate_min: i32,
    frame_rate_max: i32,
) -> Result<(), String> {
    if width <= 0
        || height <= 0
        || frame_rate_min <= 0
        || frame_rate_max <= 0
        || frame_rate_min > frame_rate_max
    {
        return Err(
            "camera width and height must be positive, and frame rate range must be positive and ordered"
                .to_string(),
        );
    }

    secluso_camera_hub::set_android_camera_settings(
        secluso_camera_hub::AndroidCameraSettings {
            facing,
            width: width as usize,
            height: height as usize,
            frame_rate_range: secluso_camera_hub::AndroidCameraFrameRateRange {
                min: frame_rate_min,
                max: frame_rate_max,
            },
        },
    )
    .map_err(|e| format!("failed to set Android camera settings: {e}"))
}

#[flutter_rust_bridge::frb]
pub fn start_android_camera_hub(
    work_dir: String,
    server_username: String,
    server_password: String,
    server_addr: String,
) -> Result<(), String> {
    //init_logger();

    log::info!("start_android_camera_hub called");

    if CAMERA_HUB_STARTED.swap(true, Ordering::SeqCst) {
        return Ok(());
    }

    std::fs::create_dir_all(&work_dir)
        .map_err(|e| format!("failed to create camera hub work dir: {e}"))?;

    let handle = thread::Builder::new()
        .name("secluso-camera-hub".to_string())
        .spawn(move || {
            log::info!("camera hub thread started");

            if let Err(e) = std::env::set_current_dir(&work_dir) {
                log::error!("failed to set camera hub working directory: {e}");
                CAMERA_HUB_STARTED.store(false, Ordering::SeqCst);
                return;
            }

            log::info!("About to call run_android");
            if let Err(e) = secluso_camera_hub::run_android(
                server_username,
                server_password,
                server_addr,
            ) {
                log::error!("camera hub exited with error: {e}");
            }
            log::info!("camera hub thread exiting");

            CAMERA_HUB_STARTED.store(false, Ordering::SeqCst);
        })
        .map_err(|e| {
            CAMERA_HUB_STARTED.store(false, Ordering::SeqCst);
            format!("failed to spawn camera hub thread: {e}")
        })?;

    *camera_hub_thread().lock().unwrap() = Some(handle);

    Ok(())
}

fn android_camera_specs_to_json(specs: &[secluso_camera_hub::AndroidCameraSpec]) -> String {
    let mut out = String::from("[");
    for (index, spec) in specs.iter().enumerate() {
        if index > 0 {
            out.push(',');
        }
        out.push_str("{\"facing\":");
        out.push_str(&spec.facing.to_string());
        out.push_str(",\"resolutions\":[");
        for (resolution_index, resolution) in spec.resolutions.iter().enumerate() {
            if resolution_index > 0 {
                out.push(',');
            }
            out.push_str("{\"width\":");
            out.push_str(&resolution.width.to_string());
            out.push_str(",\"height\":");
            out.push_str(&resolution.height.to_string());
            out.push('}');
        }
        out.push_str("],\"frame_rate_ranges\":[");
        for (range_index, range) in spec.frame_rate_ranges.iter().enumerate() {
            if range_index > 0 {
                out.push(',');
            }
            out.push_str("{\"min\":");
            out.push_str(&range.min.to_string());
            out.push_str(",\"max\":");
            out.push_str(&range.max.to_string());
            out.push('}');
        }
        out.push_str("]}");
    }
    out.push(']');
    out
}

#[flutter_rust_bridge::frb]
pub fn reset_android_camera_hub(
    work_dir: String,
    server_username: String,
    server_password: String,
    server_addr: String,
) -> Result<(), String> {
    //init_logger();

    log::info!("reset_android_camera_hub called.");

    let previous_dir = std::env::current_dir()
        .map_err(|e| format!("failed to get current directory before reset: {e}"))?;

    std::fs::create_dir_all(&work_dir)
        .map_err(|e| format!("failed to create camera hub work dir before reset: {e}"))?;

    std::env::set_current_dir(&work_dir)
        .map_err(|e| format!("failed to set camera hub working directory: {e}"))?;

    let reset_result = secluso_camera_hub::reset_android(
        server_username,
        server_password,
        server_addr,
    )
    .map_err(|e| format!("failed to reset android camera hub state: {e}"));

    std::env::set_current_dir(previous_dir)
        .map_err(|e| format!("failed to restore working directory after reset: {e}"))?;

    std::fs::remove_dir_all(&work_dir)
        .map_err(|e| format!("failed to delete camera hub work dir after reset: {e}"))?;

    reset_result?;

    CAMERA_HUB_STARTED.store(false, Ordering::SeqCst);

    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn stop_android_camera_hub() -> Result<(), String> {
    //init_logger();

    log::info!("stop_android_camera_hub called");
    secluso_camera_hub::stop_android();

    if let Some(handle) = camera_hub_thread().lock().unwrap().take() {
        handle
            .join()
            .map_err(|_| "camera hub thread join failed".to_string())?;
    }

    CAMERA_HUB_STARTED.store(false, Ordering::SeqCst);
    log::info!("camera hub stopped");

    Ok(())
}
