# Android Reproducible Builds

This folder is the Android reproducible build setup for the Secluso mobile app.
The basic idea came from the Telegram reproducible builds page:

- https://core.telegram.org/reproducible-builds

The short version is that this folder gives us a pinned Docker build environment, a way to rebuild the Android APK or AAB in that environment, and a way to compare the rebuilt output against either another rebuild or an APK pulled from a phone.

The most basic command is:

```bash
tool/repro/build_with_docker.sh
```

That builds the unsigned Android release APK in Docker and puts it here:

```text
build/reproducible/app-release-unsigned.apk
```

If you want the special F-Droid Android variant instead, use the env var..

```bash
SECLUSO_FDROID_BUILD=1 tool/repro/build_with_docker.sh
```

That flag is passed through to the Docker container and translated into the matching Flutter dart define. So the reproducible build uses the UnifiedPush-only F-Droid Android path instead of the normal Firebase-backed Android path in this case!

For normal repeated local use, the Docker wrappers now try to stay fast:

- they reuse a cached repro image when the Dockerfile has not changed
- they reuse host-side Gradle and Dart package caches in .secluso-repro-cache/
- they reuse local Flutter and Rust build caches by default
- they use multiple Gradle and Cargo workers by default instead of forcing everything onto one core

If you want the stricter clean-room behavior for debugging or verification, set:

```bash
SECLUSO_REPRO_CLEAN=1
```

If you want the canonical Google Play upload artifact instead, use:

```bash
tool/repro/build_aab_with_docker.sh
```

That builds the unsigned Android App Bundle in Docker and puts it here:

```text
build/reproducible/app-release-unsigned.aab
```

Recommended safe reproducibility check

When verifying reproducibility from a dirty local environment, use this command:

```bash
env SECLUSO_REPRO_CLEAN=1 SECLUSO_REPRO_USE_HOST_CACHES=0 SECLUSO_REPRO_GRADLE_JVMARGS='-Xmx2G -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError' tool/repro/build_aab_with_docker.sh
```

- SECLUSO_REPRO_CLEAN=1 removes the copied workspace's Flutter, Android, and Rust build outputs before building. 
- SECLUSO_REPRO_USE_HOST_CACHES=0 avoids mounting the host Gradle and Dart package caches into the container
- SECLUSO_REPRO_GRADLE_JVMARGS=.. caps the Gradle and Kotlin daemon heaps. On Docker Desktop, the default android/gradle.properties heap can reserve too much memory during the clean native build and the Gradle daemon may disappear. 

The same F-Droid switch works for the App Bundle path:

```bash
SECLUSO_FDROID_BUILD=1 tool/repro/build_aab_with_docker.sh
```

If you want to check whether the build is actually reproducible, run:

```bash
tool/repro/check_reproducibility.sh
```

That script makes two fresh copies of the workspace under /tmp` builds the app twice in the same pinned Docker setup, and compares the two APKs. If it works, both the file comparison and the SHA-256 hashes should match.

For the App Bundle itself, there is a matching check:

```bash
tool/repro/check_aab_reproducibility.sh
```

That does the same basic thing, but for the unsigned .aab. It first checks whether the two bundle files are byte-for-byte identical. If they ever differ, it falls back to a member-payload diff so you can see which archive entry drifted.

By default, the reproducibility checks now use a faster proof mode. They still build in two separate temp workspaces, but they first warm the shared source workspace and copy over the heavy Flutter and CargoKit caches that sit in .dart_tool, rust/target, build/rust_lib_secluso_flutter, and build/native_assets. That avoids a full cold Rust rebuild every time.

If you want the slower clean-room version that strips those warmed caches too, set:

```bash
SECLUSO_REPRO_CHECK_STRICT=1
```

You can combine that with the F-Droid variant too:

```bash
SECLUSO_FDROID_BUILD=1 tool/repro/check_reproducibility.sh
SECLUSO_FDROID_BUILD=1 tool/repro/check_aab_reproducibility.sh
```

If you want to compare against a Secluso APK installed on a phone, the flow is also pretty simple. First rebuild the unsigned APK:

```bash
tool/repro/build_with_docker.sh
```

Then make sure adb sees the device:

```bash
adb devices
```

After that, just run:

```bash
tool/repro/compare_with_device.sh
```

For signed releases, the intended model is to build the canonical unsigned APK first and sign it after that. That keeps the reproducible part and the signing part separate.

The official signed-release flow is:

```bash
SECLUSO_ANDROID_SIGNING_DIR=/path/to/signing-material \
tool/repro/build_official_release_with_docker.sh
```

That signing directory needs:

- key.properties
- the keystore file referenced by storeFile

The signed release flow writes:

```text
build/reproducible/app-release-unsigned.apk
build/reproducible/app-release-signed.apk
build/reproducible/app-release-signed.apk.sha256
```

There is a matching App Bundle release flow too:

```bash
SECLUSO_ANDROID_SIGNING_DIR=/path/to/signing-material \
tool/repro/build_official_appbundle_with_docker.sh
```

That writes:

```text
build/reproducible/app-release-unsigned.aab
build/reproducible/app-release-signed.aab
build/reproducible/app-release-signed.aab.sha256
```

One thing that might happen is that the Docker build fails at flutter pub get --enforce-lockfile. If that happens, it means the committed pubspec.lock no longer matches what the pinned Docker toolchain resolves for the current pubspec.yaml. In that case, update the lockfile with:

```bash
tool/repro/update_lockfile_with_docker.sh
```

Then review the pubspec.lock diff, commit it, and rerun the reproducibility check.

There are a few limits to keep in mind. The direct phone-compare setup is still mainly for one installed base.apk. Google Play adds another layer because it takes the uploaded AAB, turns it into split APKs for each device, and then signs those APKs on the Play side.

There is a middle ground now for that. We can build a reproducible unsigned .aab, then run pinned bundletool in Docker to generate the split APK set for one fixed device spec. This does not prove what Google Play actually served, but it does reproduce the same AAB -> fixed device APK set step locally.

The flow looks like this:

1. Build the unsigned AAB:

```bash
tool/repro/build_aab_with_docker.sh
```

2. Get or write a device spec JSON (use bundletool get-device-spec on a connected device)

3. Generate the split APK set for that fixed device:

```bash
tool/repro/generate_device_apk_set_from_aab.sh \
  build/reproducible/app-release-unsigned.aab \
  /path/to/device-spec.json \
  build/reproducible/device.apks
```

4. If you want to check that the whole AAB -> fixed device APK set path is reproducible, run:

```bash
tool/repro/check_bundletool_device_reproducibility.sh /path/to/device-spec.json
```

That script builds two unsigned AABs in fresh workspaces, turns both into device-targeted .apks archives with the same pinned bundletool, and then compares the APK payloads inside with:

```bash
python3 tool/repro/apksdiff.py first.apks second.apks
```

apksdiff.py only compares the APK members inside the .apks archive. It intentionally ignores APK signing metadata the same way apkdiff.py does, because bundletool may sign with a debug key if you do not pass something like a real signing material.

That is the main idea.
