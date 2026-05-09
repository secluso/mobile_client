#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <repo-relative-build-script> [args...]" >&2
  exit 2
fi

BUILD_SCRIPT_RELATIVE="$1"
shift || true

SOURCE_ROOT="${SECLUSO_REPRO_SOURCE_ROOT:-/workspace}"
REPRO_CLEAN="${SECLUSO_REPRO_CLEAN:-0}"
SYNC_FAST_CACHES="${SECLUSO_REPRO_SYNC_BACK_FAST_CACHES:-1}"
KEEP_LOCAL_WORK_ROOT="${SECLUSO_REPRO_KEEP_LOCAL_WORK_ROOT:-1}"
SANITIZED_SOURCE_ROOT="$(printf '%s' "$SOURCE_ROOT" | tr '/:' '__')"
LOCAL_ROOT="${SECLUSO_REPRO_LOCAL_WORK_ROOT:-${TMPDIR:-/tmp}/secluso-container-work${SANITIZED_SOURCE_ROOT}}"

cleanup() {
  if [[ "$KEEP_LOCAL_WORK_ROOT" != "1" ]]; then
    rm -rf "$LOCAL_ROOT"
  fi
}
trap cleanup EXIT

if [[ ! -d "$SOURCE_ROOT" ]]; then
  echo "Missing source workspace at $SOURCE_ROOT" >&2
  exit 1
fi

mkdir -p "$LOCAL_ROOT"

rsync_args=(
  -a
  --delete
  --exclude '.git'
  --exclude '.secluso-repro-cache'
  --exclude 'android/local.properties'
  --exclude 'android/app/src/main/jniLibs'
  --exclude 'build'
  --exclude 'ios/Pods'
)

if [[ "$REPRO_CLEAN" == "1" ]]; then
  rm -rf "$LOCAL_ROOT"
  mkdir -p "$LOCAL_ROOT"
  rsync_args+=(
    --exclude '.dart_tool'
    --exclude 'rust/target'
  )
else
  rsync_args+=(
    --exclude '.dart_tool'
    --exclude 'rust/target'
  )
fi

rsync "${rsync_args[@]}" "$SOURCE_ROOT/" "$LOCAL_ROOT/"
rm -rf "$LOCAL_ROOT/android/app/src/main/jniLibs"

seed_local_cache_dir() {
  local relative_path="$1"
  if [[ -d "$LOCAL_ROOT/$relative_path" || ! -d "$SOURCE_ROOT/$relative_path" ]]; then
    return
  fi
  mkdir -p "$LOCAL_ROOT/$relative_path"
  rsync -a "$SOURCE_ROOT/$relative_path/" "$LOCAL_ROOT/$relative_path/"
}

if [[ "$REPRO_CLEAN" != "1" ]]; then
  seed_local_cache_dir "rust/target"
  seed_local_cache_dir "build/rust_lib_secluso_flutter"
  seed_local_cache_dir "build/native_assets"
fi

LOCAL_BUILD_SCRIPT="$LOCAL_ROOT/$BUILD_SCRIPT_RELATIVE"
if [[ ! -x "$LOCAL_BUILD_SCRIPT" ]]; then
  echo "Build script is not executable inside local workspace: $LOCAL_BUILD_SCRIPT" >&2
  exit 1
fi

"$LOCAL_BUILD_SCRIPT" "$@"

mkdir -p "$SOURCE_ROOT/build/reproducible"
rsync -a --delete "$LOCAL_ROOT/build/reproducible/" "$SOURCE_ROOT/build/reproducible/"

while IFS= read -r -d '' sha_file; do
  sed -i "s|$LOCAL_ROOT|$SOURCE_ROOT|g" "$sha_file"
done < <(find "$SOURCE_ROOT/build/reproducible" -type f -name '*.sha256' -print0)

sync_cache_dir() {
  local relative_path="$1"
  if [[ ! -d "$LOCAL_ROOT/$relative_path" ]]; then
    return
  fi
  mkdir -p "$SOURCE_ROOT/$relative_path"
  rsync -a --delete "$LOCAL_ROOT/$relative_path/" "$SOURCE_ROOT/$relative_path/"
}

if [[ "$REPRO_CLEAN" != "1" && "$SYNC_FAST_CACHES" == "1" ]]; then
  sync_cache_dir "rust/target"
  sync_cache_dir "build/rust_lib_secluso_flutter"
  sync_cache_dir "build/native_assets"
fi
