#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKER_PLATFORM="${SECLUSO_DOCKER_PLATFORM:-linux/amd64}"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/secluso-mobile-repro.XXXXXX")"
KEEP_WORK_ROOT="${KEEP_WORK_ROOT:-0}"
SOURCE_DATE_EPOCH_VALUE="${SOURCE_DATE_EPOCH:-}"
REPRO_CHECK_PARALLEL="${SECLUSO_REPRO_CHECK_PARALLEL:-0}"
REPRO_CHECK_STRICT="${SECLUSO_REPRO_CHECK_STRICT:-0}"

cpu_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
  else
    echo 4
  fi
}

DEFAULT_REPRO_CHECK_MAX_WORKERS="$(cpu_count)"
if [[ "$REPRO_CHECK_STRICT" == "1" ]]; then
  if [[ "$DEFAULT_REPRO_CHECK_MAX_WORKERS" -gt 2 ]]; then
    DEFAULT_REPRO_CHECK_MAX_WORKERS=2
  fi
else
  if [[ "$DEFAULT_REPRO_CHECK_MAX_WORKERS" -lt 2 ]]; then
    DEFAULT_REPRO_CHECK_MAX_WORKERS=2
  elif [[ "$DEFAULT_REPRO_CHECK_MAX_WORKERS" -gt 4 ]]; then
    DEFAULT_REPRO_CHECK_MAX_WORKERS=4
  fi
fi

REPRO_CHECK_MAX_WORKERS="${SECLUSO_REPRO_CHECK_MAX_WORKERS:-$DEFAULT_REPRO_CHECK_MAX_WORKERS}"
DEFAULT_USE_HOST_CACHES=1
if [[ "$REPRO_CHECK_STRICT" == "1" ]]; then
  DEFAULT_USE_HOST_CACHES=0
fi
USE_HOST_CACHES="${SECLUSO_REPRO_USE_HOST_CACHES:-$DEFAULT_USE_HOST_CACHES}"
HOST_CACHE_ROOT="${SECLUSO_REPRO_CACHE_ROOT:-$REPO_ROOT/.secluso-repro-cache}"

dockerfile_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$SCRIPT_DIR/Dockerfile" | awk '{print substr($1, 1, 12)}'
  else
    shasum -a 256 "$SCRIPT_DIR/Dockerfile" | awk '{print substr($1, 1, 12)}'
  fi
}

DEFAULT_IMAGE_TAG="secluso-mobile-repro:$(dockerfile_hash)"
IMAGE_TAG="${SECLUSO_REPRO_IMAGE_TAG:-$DEFAULT_IMAGE_TAG}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

cleanup() {
  if [[ "$KEEP_WORK_ROOT" != "1" ]]; then
    rm -rf "$WORK_ROOT"
  else
    echo "Preserving work directory: $WORK_ROOT"
  fi
}
trap cleanup EXIT

if [[ -z "$SOURCE_DATE_EPOCH_VALUE" ]] && git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
  SOURCE_DATE_EPOCH_VALUE="$(git -C "$REPO_ROOT" log -1 --format=%ct)"
fi
if [[ -z "$SOURCE_DATE_EPOCH_VALUE" ]]; then
  SOURCE_DATE_EPOCH_VALUE="1704067200"
fi

copy_workspace() {
  local destination="$1"
  mkdir -p "$destination"
  local rsync_args=(
    -a
    --exclude '.git'
    --exclude 'android/local.properties'
    --exclude 'android/app/src/main/jniLibs'
    --exclude '.secluso-repro-cache'
    --exclude 'build'
    --exclude 'ios/Pods'
  )
  if [[ "$REPRO_CHECK_STRICT" == "1" ]]; then
    rsync_args+=(--exclude '.dart_tool' --exclude 'rust/target')
  fi
  rsync "${rsync_args[@]}" "$REPO_ROOT/" "$destination/"
  if [[ "$REPRO_CHECK_STRICT" != "1" ]]; then
    sync_fast_build_caches "$destination"
  fi
}

sync_fast_build_caches() {
  local destination="$1"
  local cache_path
  for cache_path in \
    ".dart_tool" \
    "rust/target" \
    "build/rust_lib_secluso_flutter" \
    "build/native_assets"; do
    if [[ -e "$REPO_ROOT/$cache_path" ]]; then
      mkdir -p "$destination/$(dirname "$cache_path")"
      rsync -a "$REPO_ROOT/$cache_path" "$destination/$(dirname "$cache_path")/"
    fi
  done
}

run_build() {
  local workspace="$1"
  local docker_cache_volumes=()
  if [[ "$USE_HOST_CACHES" == "1" ]]; then
    mkdir -p "$HOST_CACHE_ROOT/gradle-home" "$HOST_CACHE_ROOT/pub-cache"
    docker_cache_volumes=(
      -v "$HOST_CACHE_ROOT/gradle-home":/opt/gradle-home
      -v "$HOST_CACHE_ROOT/pub-cache":/opt/pub-cache
    )
  fi
  docker run --rm \
    --platform "$DOCKER_PLATFORM" \
    -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH_VALUE" \
    -e SECLUSO_FDROID_BUILD="${SECLUSO_FDROID_BUILD:-0}" \
    -e SECLUSO_REPRO_CLEAN="$REPRO_CHECK_STRICT" \
    -e SECLUSO_REPRO_MAX_WORKERS="$REPRO_CHECK_MAX_WORKERS" \
    -v "$workspace":/workspace \
    "${docker_cache_volumes[@]}" \
    "$IMAGE_TAG" \
    /workspace/tool/repro/run_build_in_container_workspace.sh \
      tool/repro/build_unsigned_android_release.sh
}

warm_source_workspace() {
  if [[ "$REPRO_CHECK_STRICT" == "1" ]]; then
    return
  fi
  if [[ -d "$REPO_ROOT/.dart_tool" \
    && -d "$REPO_ROOT/build/rust_lib_secluso_flutter" \
    && -d "$REPO_ROOT/build/native_assets" ]]; then
    return
  fi
  echo "==> Warming source workspace caches"
  SECLUSO_FDROID_BUILD="${SECLUSO_FDROID_BUILD:-0}" "$SCRIPT_DIR/build_with_docker.sh"
}

BUILD_ONE="$WORK_ROOT/build-one"
BUILD_TWO="$WORK_ROOT/build-two"

warm_source_workspace
copy_workspace "$BUILD_ONE"
copy_workspace "$BUILD_TWO"

if [[ "${SECLUSO_REPRO_FORCE_IMAGE_BUILD:-0}" == "1" ]] || ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  docker build --platform "$DOCKER_PLATFORM" -f "$SCRIPT_DIR/Dockerfile" -t "$IMAGE_TAG" "$REPO_ROOT"
else
  printf '==> Reusing cached Docker image %s\n' "$IMAGE_TAG"
fi

if [[ "$REPRO_CHECK_PARALLEL" == "1" ]]; then
  run_build "$BUILD_ONE" &
  PID_ONE=$!
  run_build "$BUILD_TWO" &
  PID_TWO=$!
  wait "$PID_ONE"
  wait "$PID_TWO"
else
  run_build "$BUILD_ONE"
  run_build "$BUILD_TWO"
fi

FIRST_APK="$BUILD_ONE/build/reproducible/app-release-unsigned.apk"
SECOND_APK="$BUILD_TWO/build/reproducible/app-release-unsigned.apk"

python3 "$REPO_ROOT/tool/repro/apkdiff.py" "$FIRST_APK" "$SECOND_APK"
echo "First build sha256:"
cat "$FIRST_APK.sha256"
echo "Second build sha256:"
cat "$SECOND_APK.sha256"
