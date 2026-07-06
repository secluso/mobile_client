//! Flutter-facing camera hub API.
//!
//! SPDX-License-Identifier: GPL-3.0-or-later

use std::sync::atomic::{AtomicBool, Ordering};
//use std::sync::Once;
use std::thread;

//static INIT_LOGGER: Once = Once::new();
static CAMERA_HUB_STARTED: AtomicBool = AtomicBool::new(false);

/* Uncomment for debugging.
fn init_logger() {
    INIT_LOGGER.call_once(|| {
        android_logger::init_once(
            android_logger::Config::default()
                .with_tag("SeclusoRustCamera")
                .with_max_level(log::LevelFilter::Trace),
        );
    });
}
*/

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

    thread::Builder::new()
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

    Ok(())
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

    log::info!("stop_android_camera_hub called; exiting app process");
    std::process::exit(0);
    //unsafe {
    //    libc::_exit(0);
    //}
    
}
