//! Secluso camera native bridge.
//!
//! SPDX-License-Identifier: GPL-3.0-or-later

#[cfg(feature = "android")]
pub mod api;
mod frb_generated;

/// Hand the Android system certificate verifier its context. 
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn JNI_OnLoad(
    vm: *mut jni::sys::JavaVM,
    _reserved: *mut std::ffi::c_void,
) -> jni::sys::jint {
    let vm = unsafe { jni::JavaVM::from_raw(vm) };

    let _ = vm.attach_current_thread(|env| -> jni::errors::Result<()> {
        let context = env
            .call_static_method(
                jni::jni_str!("android/app/ActivityThread"),
                jni::jni_str!("currentApplication"),
                jni::jni_sig!("()Landroid/app/Application;"),
                &[],
            )?
            .l()?;
        let _ = rustls_platform_verifier::android::init_with_env(env, context);
        Ok(())
    });

    jni::sys::JNI_VERSION_1_6
}
