//! SPDX-License-Identifier: GPL-3.0-or-later

pub mod lock_manager;
pub mod logger;
pub mod simple;

use secluso_app_native::{self, Clients};

use log::{debug, error, info, warn};
use once_cell::sync::Lazy;
use parking_lot::{Mutex, MutexGuard};
use std::collections::HashMap;

use std::net::{Shutdown, SocketAddr, TcpStream};
use std::ops::{Deref, DerefMut};
use std::panic;
use std::str::FromStr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

#[derive(Hash, Eq, PartialEq, Clone)]
struct ClientKey {
    camera: String,
    channel: String,
}

#[derive(Clone)]
struct InitParams {
    file_dir: String,
    first_time: bool,
}

static CLIENTS: Lazy<Mutex<HashMap<ClientKey, Arc<Mutex<Option<Box<Clients>>>>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static CLIENT_LOCK_OWNERS: Lazy<Mutex<HashMap<ClientKey, String>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static INIT_PARAMS: Lazy<Mutex<HashMap<String, InitParams>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static IS_SHUTTING_DOWN: Lazy<AtomicBool> = Lazy::new(|| AtomicBool::new(false));

const CLIENT_LOCK_TIMEOUT: Duration = Duration::from_secs(8);
const CLIENT_LOCK_WARN: Duration = Duration::from_millis(250);
// TODO: using different channels for "Clients" break the heartbeat since the heartbeat needs to see the
// latest state of different MLS channels. To solve that, we'll need to use one Clients objects.
// The current fix uses the old code with one Clients channel. In order to be able to use a separate lock
// for each MlsClient channel, we'll need to refactor the code.
/*
const CHANNEL_MOTION: &str = "motion";
const CHANNEL_THUMBNAIL: &str = "thumbnail";
//const CHANNEL_FCM: &str = "fcm";
const CHANNEL_CONFIG: &str = "config";
const CHANNEL_LIVESTREAM: &str = "livestream";
*/
const CHANNEL_SETUP: &str = "setup";
const CHANNEL_FIXED: &str = "fixed";
const TRACE_TAG: &str = "|trace=";

fn split_trace_camera(camera_name: &str) -> (String, Option<&str>) {
    match camera_name.find(TRACE_TAG) {
        Some(idx) => {
            let (base, rest) = camera_name.split_at(idx);
            let trace = rest.strip_prefix(TRACE_TAG).unwrap_or("");
            let trace = if trace.is_empty() { None } else { Some(trace) };
            (base.to_string(), trace)
        }
        None => (camera_name.to_string(), None),
    }
}

macro_rules! lock_client_or_return {
    ($client_mutex:expr, $camera_name:expr, $channel:expr, $op:expr, $owner:expr, $ret:expr) => {{
        match lock_client_with_owner(&$client_mutex, $camera_name, $channel, $op, $owner) {
            Some(guard) => guard,
            None => return $ret,
        }
    }};
}

fn get_or_create_channel_mutex(
    camera_name: &str,
    channel: &str,
) -> Arc<Mutex<Option<Box<Clients>>>> {
    let mut guard = CLIENTS.lock();
    let key = ClientKey {
        camera: camera_name.to_owned(),
        channel: channel.to_owned(),
    };
    guard
        .entry(key)
        .or_insert_with(|| Arc::new(Mutex::new(None)))
        .clone()
}

// Wrap the MLS client lock so we can log who holds it and for how long.
// This keeps lock tracking out of the call sites while making contention visible in logs.
struct TracedClientGuard<'a> {
    guard: MutexGuard<'a, Option<Box<Clients>>>,
    key: ClientKey,
    owner: String,
    op: String,
    acquired_at: Instant,
}

impl<'a> Deref for TracedClientGuard<'a> {
    type Target = Option<Box<Clients>>;
    fn deref(&self) -> &Self::Target {
        &self.guard
    }
}

impl<'a> DerefMut for TracedClientGuard<'a> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.guard
    }
}

impl<'a> Drop for TracedClientGuard<'a> {
    fn drop(&mut self) {
        let mut owners = CLIENT_LOCK_OWNERS.lock();
        owners.remove(&self.key);
        debug!(
            "MLS lock released for {} on camera {} channel {} (owner={}, held={:?})",
            self.op,
            self.key.camera,
            self.key.channel,
            self.owner,
            self.acquired_at.elapsed()
        );
    }
}

fn lock_client_with_owner<'a>(
    client_mutex: &'a Arc<Mutex<Option<Box<Clients>>>>,
    camera_name: &str,
    channel: &str,
    op: &str,
    owner: Option<&str>,
) -> Option<TracedClientGuard<'a>> {
    let start = Instant::now();
    let owner_label = owner.unwrap_or("unknown").to_string();
    let key = ClientKey {
        camera: camera_name.to_owned(),
        channel: channel.to_owned(),
    };
    debug!(
        "MLS lock attempt for {} on camera {} channel {} (owner={})",
        op, camera_name, channel, owner_label
    );
    match client_mutex.try_lock_for(CLIENT_LOCK_TIMEOUT) {
        Some(guard) => {
            {
                let mut owners = CLIENT_LOCK_OWNERS.lock();
                owners.insert(key.clone(), owner_label.clone());
            }
            let elapsed = start.elapsed();
            if elapsed >= CLIENT_LOCK_WARN {
                warn!(
                    "MLS lock wait {:?} for {} on camera {} channel {} (owner={})",
                    elapsed, op, camera_name, channel, owner_label
                );
            }
            debug!(
                "MLS lock acquired for {} on camera {} channel {} (owner={}, wait={:?})",
                op, camera_name, channel, owner_label, elapsed
            );
            Some(TracedClientGuard {
                guard,
                key,
                owner: owner_label,
                op: op.to_string(),
                acquired_at: Instant::now(),
            })
        }
        None => {
            let owner_label = {
                let owners = CLIENT_LOCK_OWNERS.lock();
                owners
                    .get(&key)
                    .cloned()
                    .unwrap_or_else(|| "unknown".to_string())
            };
            warn!(
                "MLS lock busy after {:?} for {} on camera {} channel {} (owner={})",
                CLIENT_LOCK_TIMEOUT, op, camera_name, channel, owner_label
            );
            None
        }
    }
}

fn ensure_client_initialized(
    client_guard: &mut Option<Box<Clients>>,
    camera_name: &str,
    channel: &str,
) -> bool {
    if client_guard.is_some() {
        return true;
    }

    let params = {
        let guard = INIT_PARAMS.lock();
        guard.get(camera_name).cloned()
    };

    let Some(params) = params else {
        warn!(
            "No init params for camera {} (channel {})",
            camera_name, channel
        );
        return false;
    };

    match secluso_app_native::initialize(client_guard, params.file_dir, params.first_time) {
        Ok(_) => true,
        Err(e) => {
            info!(
                "initialize error for camera {} channel {}: {}",
                camera_name, channel, e
            );
            false
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn initialize_camera(camera_name: String, file_dir: String, first_time: bool) -> bool {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    {
        let mut guard = INIT_PARAMS.lock();
        guard.insert(
            camera_name.clone(),
            InitParams {
                file_dir: file_dir.clone(),
                first_time,
            },
        );
    }

    // Lazy per-channel init: only set init params here.
    // Clients get created on first use inside ensure_client_initialized.
    true
}

#[flutter_rust_bridge::frb]
pub fn deregister_camera(camera_name: String) {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let entries: Vec<(ClientKey, Arc<Mutex<Option<Box<Clients>>>>)> = {
        let guard = CLIENTS.lock();
        guard
            .iter()
            .filter(|(key, _)| key.camera == camera_name)
            .map(|(key, arc)| (key.clone(), arc.clone()))
            .collect()
    };

    if entries.is_empty() {
        info!("No client found for camera {}", camera_name);
        return;
    }

    let mut did_deregister = false;
    for (key, client_arc) in &entries {
        let op = format!("deregister_camera({})", key.channel);
        let mut client_guard =
            match lock_client_with_owner(client_arc, &camera_name, &key.channel, &op, trace_id) {
                Some(guard) => guard,
                None => {
                    warn!(
                        "Deregister skipped for camera {} channel {} due to lock timeout",
                        camera_name, key.channel
                    );
                    continue;
                }
            };

        let res = panic::catch_unwind(panic::AssertUnwindSafe(|| {
            secluso_app_native::deregister(&mut *client_guard);
            *client_guard = None;
        }));

        if res.is_err() {
            error!(
                "Panic while deregistering camera {} channel {}",
                camera_name, key.channel
            );
        } else {
            did_deregister = true;
        }
    }

    if !did_deregister {
        warn!("Deregister skipped for camera {}", camera_name);
    }

    {
        let mut guard = CLIENTS.lock();
        guard.retain(|key, _| key.camera != camera_name);
    }
    {
        let mut guard = INIT_PARAMS.lock();
        guard.remove(&camera_name);
    }
}

#[flutter_rust_bridge::frb]
pub fn decrypt_video(camera_name: String, enc_filename: String, _assumed_epoch: u64) -> String {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "decrypt_video(motion)".to_string();
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        "Error: Busy".to_string()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    match secluso_app_native::decrypt_video(&mut *client_guard, enc_filename) {
        Ok(decrypted_filename) => {
            return decrypted_filename;
        }
        Err(_e) => {
            return format!("Error(decrypt_video): {}", _e);
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn decrypt_thumbnail(
    camera_name: String,
    enc_filename: String,
    pending_meta_directory: String,
    _assumed_epoch: u64,
) -> String {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "decrypt_thumbnail(thumbnail)".to_string();
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        "Error: Busy".to_string()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    match secluso_app_native::decrypt_thumbnail(
        &mut *client_guard,
        enc_filename,
        pending_meta_directory,
    ) {
        Ok(decrypted_filename) => {
            return decrypted_filename;
        }
        Err(_e) => {
            return format!("Error(decrypt_thumbnail): {}", _e);
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn flutter_add_camera(
    camera_name: String,
    ip: String,
    secret: Vec<u8>,
    standalone: bool,
    ssid: String,
    password: String,
    pairing_token: String,
    credentials_full: String,
    android: bool,
    subscription_uuid: String,
) -> String {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let result = {
        let channel = CHANNEL_FIXED;
        let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
        let op = "flutter_add_camera(setup)".to_string();
        let mut client_guard = lock_client_or_return!(
            client_mutex,
            &camera_name,
            channel,
            &op,
            trace_id,
            "Error: Busy".to_string()
        );
        if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
            return "Error".to_string();
        }

        //TODO: Have this return a result, and then print the error (and return false)
        secluso_app_native::add_camera(
            &mut *client_guard,
            camera_name.clone(),
            ip,
            secret,
            standalone,
            ssid,
            password,
            pairing_token,
            credentials_full,
            android,
            subscription_uuid,
        )
    };

    if !result.starts_with("Error") {
        {
            let mut guard = INIT_PARAMS.lock();
            if let Some(params) = guard.get_mut(&camera_name) {
                params.first_time = false;
            }
        }

        let entries: Vec<Arc<Mutex<Option<Box<Clients>>>>> = {
            let guard = CLIENTS.lock();
            guard
                .iter()
                .filter(|(key, _)| key.camera == camera_name && key.channel != CHANNEL_SETUP)
                .map(|(_, arc)| arc.clone())
                .collect()
        };

        for entry in entries {
            match entry.try_lock_for(CLIENT_LOCK_TIMEOUT) {
                Some(mut guard) => {
                    *guard = None;
                }
                None => {
                    warn!(
                        "Lock timeout after {:?} for reset_clients on camera {}",
                        CLIENT_LOCK_TIMEOUT, camera_name
                    );
                }
            }
        }
    }

    result
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    logger::rust_set_up();
    info!("Setup logging correctly!");
}

#[flutter_rust_bridge::frb]
pub fn shutdown_app() {
    if IS_SHUTTING_DOWN.swap(true, Ordering::SeqCst) {
        info!("shutdown_app(): already shutting down");
        return;
    }

    if let Err(e) = logger::rust_shutdown() {
        error!("logger shutdown error: {e:?}");
    }

    // If there's ever a shtudown/cleanup function in the app_native layer,
    // we can call it here.

    info!("shutdown_app(): done");
}

#[flutter_rust_bridge::frb]
pub fn ping_proprietary_device(camera_ip: String) -> bool {
    debug!("Pinging proprietary device at {}", camera_ip);
    let addr = match SocketAddr::from_str(&(camera_ip + ":12348")) {
        Ok(a) => a,
        Err(e) => {
            debug!("Invalid proprietary camera IP address: {e}");
            return false;
        }
    };

    match TcpStream::connect_timeout(&addr, Duration::from_secs(1)) {
        Ok(stream) => {
            let _ = stream.shutdown(Shutdown::Both);
            true
        }
        Err(e) => {
            debug!("Proprietary device probe failed: {e}");
            false
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn encrypt_settings_message(camera_name: String, data: Vec<u8>) -> Vec<u8> {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "encrypt_settings_message(config)".to_string();
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        Vec::new()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return Vec::new();
    }

    match secluso_app_native::encrypt_settings_message(&mut *client_guard, data) {
        Ok(encrypted_message) => {
            return encrypted_message;
        }
        Err(e) => {
            info!("Error: {}", e);
            return Vec::new();
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn decrypt_message(client_tag: String, camera_name: String, data: Vec<u8>) -> String {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let op = format!("decrypt_message({})", channel);
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        "Error: Busy".to_string()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    match secluso_app_native::decrypt_message(&mut *client_guard, &client_tag, data) {
        Ok(timestamp) => {
            return timestamp;
        }
        Err(e) => {
            info!("decrypt_message error: {}", e);
            return format!("Error(decrypt_message): {}", e);
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn get_group_name(client_tag: String, camera_name: String) -> String {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let op = format!("get_group_name({})", channel);
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        "Error: Busy".to_string()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    match secluso_app_native::get_group_name(&mut *client_guard, &client_tag) {
        Ok(motion_group_name) => {
            return motion_group_name;
        }
        Err(e) => {
            info!("get_group_name error: {}", e);
            return format!("Error(get_group_name): {}", e);
        }
    }
}

/// The name an object is stored under on the enterprise delivery service.
#[flutter_rust_bridge::frb]
/// The subscription the paired camera bills against
pub fn subscription_uuid_for(camera_name: String) -> String {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "subscription_uuid_for".to_string();
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        String::new()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return String::new();
    }

    secluso_app_native::get_subscription_uuid(&*client_guard).unwrap_or_default()
}

pub fn object_name_for(
    camera_name: String,
    client_tag: String,
    group_name: String,
    epoch: u64,
    kind: String,
) -> String {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let op = format!("object_name_for({})", client_tag);
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        "Error: Busy".to_string()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    let kind = if kind.is_empty() {
        None
    } else {
        Some(kind.as_str())
    };

    match secluso_app_native::object_name_for(
        &mut *client_guard,
        &client_tag,
        &group_name,
        epoch,
        kind,
    ) {
        Ok(name) => name,
        Err(e) => {
            info!("object_name_for error: {}", e);
            format!("Error(object_name_for): {}", e)
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn livestream_update(camera_name: String, msg: Vec<u8>) -> bool {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "livestream_update(livestream)".to_string();
    let mut client_guard =
        lock_client_or_return!(client_mutex, &camera_name, channel, &op, trace_id, false);
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return false;
    }

    match secluso_app_native::livestream_update(&mut *client_guard, msg) {
        Ok(_) => {
            return true;
        }
        Err(e) => {
            info!("Error: {}", e);
            return false;
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn livestream_decrypt(
    camera_name: String,
    data: Vec<u8>,
    expected_chunk_number: u64,
) -> Vec<u8> {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "livestream_decrypt(livestream)".to_string();
    let mut client_guard =
        lock_client_or_return!(client_mutex, &camera_name, channel, &op, trace_id, vec![]);
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return vec![];
    }

    let ret = match secluso_app_native::livestream_decrypt(
        &mut *client_guard,
        data,
        expected_chunk_number,
    ) {
        Ok(dec_data) => dec_data,
        Err(e) => {
            info!("Error: {}", e);
            vec![]
        }
    };

    ret
}

#[flutter_rust_bridge::frb]
pub fn rust_lib_version() -> String {
    return env!("CARGO_PKG_VERSION").to_string();
}

#[flutter_rust_bridge::frb]
pub fn generate_heartbeat_request_config_command(camera_name: String, timestamp: u64) -> Vec<u8> {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "generate_heartbeat_request_config_command(config)".to_string();
    let mut client_guard =
        lock_client_or_return!(client_mutex, &camera_name, channel, &op, trace_id, vec![]);
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return vec![];
    }

    let ret = match secluso_app_native::generate_heartbeat_request_config_command(
        &mut *client_guard,
        timestamp,
    ) {
        Ok(config_msg_enc) => config_msg_enc,
        Err(e) => {
            info!("Error: {}", e);
            vec![]
        }
    };

    ret
}

#[flutter_rust_bridge::frb]
pub fn process_heartbeat_config_response(
    camera_name: String,
    config_response: Vec<u8>,
    expected_timestamp: u64,
) -> String {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "process_heartbeat_config_response(config)".to_string();
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        "Error".to_string()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    match secluso_app_native::process_heartbeat_config_response(
        &mut *client_guard,
        config_response,
        expected_timestamp,
    ) {
        Ok(heartbeat_response) => {
            return heartbeat_response;
        }
        Err(e) => {
            info!("process_heartbeat_config_response error: {}", e);
            return format!("Error(process_heartbeat_config_response): {}", e);
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn get_add_app_secret() -> String {
    match secluso_app_native::get_add_app_secret() {
        Ok(secret) => {
            return secret;
        }
        Err(e) => {
            info!("get_add_app_secret error: {}", e);
            return format!("Error(get_add_app_secret): {}", e);
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn get_key_packages(camera_name: String) -> Vec<u8> {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "get_key_packages(config)".to_string();
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        vec![]
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return vec![];
    }

    let ret = match secluso_app_native::get_key_packages(&mut *client_guard) {
        Ok(key_packages) => key_packages,
        Err(e) => {
            info!("Error: {}", e);
            vec![]
        }
    };

    ret
}

#[flutter_rust_bridge::frb]
pub fn generate_add_app_request_config_command(
    camera_name: String,
    new_app_key_packages_vec: Vec<u8>,
    secret: Vec<u8>,
) -> Vec<u8> {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "generate_add_app_request_config_command(config)".to_string();
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        vec![]
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return vec![];
    }

    let ret = match secluso_app_native::generate_add_app_request_config_command(
        &mut *client_guard,
        new_app_key_packages_vec,
        secret,
    ) {
        Ok(config_msg_enc) => config_msg_enc,
        Err(e) => {
            info!("Error: {}", e);
            vec![]
        }
    };

    ret
}

#[flutter_rust_bridge::frb]
pub fn process_add_app_config_response(
    camera_name: String,
    config_response: Vec<u8>,
    secret: Vec<u8>,
) -> Vec<u8> {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "process_add_app_config_response(config)".to_string();
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        vec![]
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return vec![];
    }

    // now returns (payload, new_app_name). 
    let ret = match secluso_app_native::process_add_app_config_response(
        &mut *client_guard,
        config_response,
        secret,
    ) {
        Ok((new_app_data_vec, _new_app_name)) => new_app_data_vec,
        Err(e) => {
            info!("process_add_app_config_response error: {}", e);
            vec![]
        }
    };

    ret
}

#[flutter_rust_bridge::frb]
pub fn join_camera_groups(
    camera_name: String,
    secret: Vec<u8>,
    new_app_data_vec: Vec<u8>,
) -> Vec<u64> {
    let (camera_name, trace_id) = split_trace_camera(&camera_name);
    let _trace_guard = logger::set_log_trace(trace_id);
    let channel = CHANNEL_FIXED;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let op = "join_camera_groups(config)".to_string();
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        channel,
        &op,
        trace_id,
        vec![]
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return vec![];
    }

    let ret = match secluso_app_native::join_camera_groups(
        &mut *client_guard,
        secret,
        new_app_data_vec,
    ) {
  
        Ok((epochs, _new_app_name)) => epochs.to_vec(),
        Err(e) => {
            info!("join_camera_groups error: {}", e);
            vec![]
        }
    };

    ret
}
