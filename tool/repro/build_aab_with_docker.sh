#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKER_PLATFORM="${SECLUSO_DOCKER_PLATFORM:-linux/amd64}"
HOST_CACHE_ROOT="${SECLUSO_REPRO_CACHE_ROOT:-$REPO_ROOT/.secluso-repro-cache}"
USE_HOST_CACHES="${SECLUSO_REPRO_USE_HOST_CACHES:-1}"
AAB_PATH="$REPO_ROOT/build/reproducible/app-release-unsigned.aab"
AAB_SHA_PATH="$AAB_PATH.sha256"

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

LOCK_DIR="$REPO_ROOT/.secluso-repro-build.lock"
if mkdir "$LOCK_DIR" 2>/dev/null; then
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR"' EXIT
elif [[ -f "$LOCK_DIR/pid" ]] && ! kill -0 "$(cat "$LOCK_DIR/pid")" 2>/dev/null; then
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR"
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR"' EXIT
else
  echo "Another reproducible Android build is already running. Remove $LOCK_DIR if it is stale." >&2
  exit 1
fi

if [[ -z "${SOURCE_DATE_EPOCH:-}" ]] && git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
  export SOURCE_DATE_EPOCH
  SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" log -1 --format=%ct)"
fi

if [[ "${SECLUSO_REPRO_FORCE_IMAGE_BUILD:-0}" == "1" ]] || ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  docker build --platform "$DOCKER_PLATFORM" -f "$SCRIPT_DIR/Dockerfile" -t "$IMAGE_TAG" "$REPO_ROOT"
else
  printf '==> Reusing cached Docker image %s\n' "$IMAGE_TAG"
fi

DOCKER_CACHE_VOLUMES=()
if [[ "$USE_HOST_CACHES" == "1" ]]; then
  mkdir -p "$HOST_CACHE_ROOT/gradle-home" "$HOST_CACHE_ROOT/pub-cache"
  DOCKER_CACHE_VOLUMES+=(
    -v "$HOST_CACHE_ROOT/gradle-home":/opt/gradle-home
    -v "$HOST_CACHE_ROOT/pub-cache":/opt/pub-cache
  )
fi

docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  -e SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1704067200}" \
  -e SECLUSO_FDROID_BUILD="${SECLUSO_FDROID_BUILD:-0}" \
  -e SECLUSO_REPRO_CLEAN="${SECLUSO_REPRO_CLEAN:-0}" \
  -e SECLUSO_REPRO_GRADLE_JVMARGS="${SECLUSO_REPRO_GRADLE_JVMARGS:-}" \
  -e SECLUSO_REPRO_MAX_WORKERS="${SECLUSO_REPRO_MAX_WORKERS:-}" \
  -e SECLUSO_REPRO_SYNC_BACK_FAST_CACHES="${SECLUSO_REPRO_SYNC_BACK_FAST_CACHES:-1}" \
  -v "$REPO_ROOT":/workspace \
  ${DOCKER_CACHE_VOLUMES+"${DOCKER_CACHE_VOLUMES[@]}"} \
  "$IMAGE_TAG" \
  /workspace/tool/repro/run_build_in_container_workspace.sh \
    tool/repro/build_unsigned_android_appbundle.sh

if [[ -f "$AAB_PATH" ]]; then
  tmp_aab="$(mktemp "${TMPDIR:-/tmp}/secluso-aab-normalized.XXXXXX.aab")"
  python3 "$SCRIPT_DIR/aab_normalize.py" "$AAB_PATH" "$tmp_aab" >/dev/null
  mv "$tmp_aab" "$AAB_PATH"
fi

if [[ -f "$AAB_SHA_PATH" ]]; then
  tmp_sha="$(mktemp "${TMPDIR:-/tmp}/secluso-aab-sha.XXXXXX")"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$AAB_PATH" > "$tmp_sha"
  else
    shasum -a 256 "$AAB_PATH" > "$tmp_sha"
  fi
  mv "$tmp_sha" "$AAB_SHA_PATH"
fi

printf '\n==> Host artifact ready at %s\n' "$AAB_PATH"
