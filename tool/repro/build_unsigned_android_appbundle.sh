#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ ! -f "$REPO_ROOT/pubspec.yaml" ]]; then
  echo "Expected Flutter project root at $REPO_ROOT" >&2
  exit 1
fi

cpu_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
  else
    echo 4
  fi
}

DEFAULT_MAX_WORKERS="$(cpu_count)"
if [[ "$DEFAULT_MAX_WORKERS" -lt 2 ]]; then
  DEFAULT_MAX_WORKERS=2
elif [[ "$DEFAULT_MAX_WORKERS" -gt 2 ]]; then
  DEFAULT_MAX_WORKERS=2
fi

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export TZ=UTC

export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export CARGO_HOME="${CARGO_HOME:-/opt/cargo}"
export FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/opt/gradle-home}"
export SECLUSO_REPRO_MAX_WORKERS="${SECLUSO_REPRO_MAX_WORKERS:-$DEFAULT_MAX_WORKERS}"
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.daemon=false -Dorg.gradle.parallel=true -Dorg.gradle.vfs.watch=false -Dorg.gradle.workers.max=${SECLUSO_REPRO_MAX_WORKERS} -Dkotlin.compiler.execution.strategy=in-process"
export PUB_CACHE="${PUB_CACHE:-/opt/pub-cache}"
export RUSTUP_HOME="${RUSTUP_HOME:-/opt/rustup}"
export CARGOKIT_RUST_TOOLCHAIN="${CARGOKIT_RUST_TOOLCHAIN:-1.90.0}"
export SECLUSO_FLUTTER_VERBOSE="${SECLUSO_FLUTTER_VERBOSE:-0}"
export SECLUSO_FDROID_BUILD="${SECLUSO_FDROID_BUILD:-0}"
export SECLUSO_REPRO_GRADLE_JVMARGS="${SECLUSO_REPRO_GRADLE_JVMARGS:-}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$SECLUSO_REPRO_MAX_WORKERS}"
export CARGO_INCREMENTAL=0
export SECLUSO_REPRO_CLEAN="${SECLUSO_REPRO_CLEAN:-0}"
export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$CARGO_HOME/bin:$PATH"

if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
  if git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" log -1 --format=%ct)"
  else
    SOURCE_DATE_EPOCH="1704067200"
  fi
fi
export SOURCE_DATE_EPOCH

mkdir -p "$ANDROID_HOME" "$CARGO_HOME" "$GRADLE_USER_HOME" "$PUB_CACHE" "$RUSTUP_HOME"

log_step() {
  printf '\n==> %s\n' "$1"
}

run_flutter_build() {
  local -a flutter_cmd=("$@")
  local attempt=1
  local max_attempts=2
  local log_file status

  while true; do
    log_file="$(mktemp "${TMPDIR:-/tmp}/secluso-flutter-build.XXXXXX.log")"
    set +e
    "${flutter_cmd[@]}" 2>&1 | tee "$log_file"
    status="${PIPESTATUS[0]}"
    set -e
    if [[ "$status" -eq 0 ]]; then
      rm -f "$log_file"
      return 0
    fi
    if [[ "$attempt" -lt "$max_attempts" ]] && grep -q 'Unexpected EINTR errno' "$log_file"; then
      log_step "Retrying Flutter build after transient Dart file-copy EINTR"
      attempt=$((attempt + 1))
      rm -f "$log_file"
      continue
    fi
    rm -f "$log_file"
    return "$status"
  done
}

cat > "$REPO_ROOT/android/local.properties" <<EOF
sdk.dir=$ANDROID_HOME
flutter.sdk=$FLUTTER_HOME
EOF

if [[ -n "$SECLUSO_REPRO_GRADLE_JVMARGS" ]]; then
  log_step "Applying reproducible Gradle JVM args"
  gradle_properties="$REPO_ROOT/android/gradle.properties"
  if grep -q '^org\.gradle\.jvmargs=' "$gradle_properties"; then
    sed -i "s|^org\.gradle\.jvmargs=.*|org.gradle.jvmargs=$SECLUSO_REPRO_GRADLE_JVMARGS|" "$gradle_properties"
  else
    printf '\norg.gradle.jvmargs=%s\n' "$SECLUSO_REPRO_GRADLE_JVMARGS" >> "$gradle_properties"
  fi
fi

if [[ "$SECLUSO_REPRO_CLEAN" == "1" ]]; then
  log_step "Cleaning prior build outputs"
  rm -rf \
    "$REPO_ROOT/.dart_tool" \
    "$REPO_ROOT/build" \
    "$REPO_ROOT/rust/target"
else
  log_step "Reusing local build caches"
  rm -rf "$REPO_ROOT/build/reproducible"
fi

cd "$REPO_ROOT"
log_step "Running flutter pub get"
flutter pub get --enforce-lockfile

export SECLUSO_ALLOW_UNSIGNED_RELEASE=1
log_step "Building Android release app bundle"
flutter_build_args=(
  flutter
  build
  appbundle
  --release
  --no-pub
)
if [[ "$SECLUSO_FDROID_BUILD" == "1" ]]; then
  flutter_build_args+=(--dart-define=SECLUSO_FDROID_BUILD=true)
fi
if [[ "$SECLUSO_FLUTTER_VERBOSE" == "1" ]]; then
  flutter_build_args+=(-v)
  run_flutter_build "${flutter_build_args[@]}"
else
  run_flutter_build "${flutter_build_args[@]}"
fi

OUTPUT_DIR="$REPO_ROOT/build/reproducible"
mkdir -p "$OUTPUT_DIR"
log_step "Collecting reproducible build artifact"
cp "$REPO_ROOT/build/app/outputs/bundle/release/app-release.aab" \
  "$OUTPUT_DIR/app-release-unsigned.aab"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUTPUT_DIR/app-release-unsigned.aab" \
    | tee "$OUTPUT_DIR/app-release-unsigned.aab.sha256"
else
  shasum -a 256 "$OUTPUT_DIR/app-release-unsigned.aab" \
    | tee "$OUTPUT_DIR/app-release-unsigned.aab.sha256"
fi
