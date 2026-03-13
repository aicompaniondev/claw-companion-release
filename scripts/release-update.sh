#!/usr/bin/env bash
set -euo pipefail

# Release-based updater for claw-companion.
# Downloads latest GitHub Release tarball + sha256, verifies, extracts into install dir, backs up previous.
# Release artifact is self-contained and should already include server/node_modules.

REPO="aicompaniondev/claw-companion-release"
INSTALL_DIR_DEFAULT="/opt/claw-companion"
LEGACY_DIR_1="/root/.openclaw/companion"
SERVICE_NAME="claw-companion"

log() { echo "[cc-update] $*"; }
err() { echo "[cc-update] ERROR: $*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { err "Missing dependency: $1"; exit 1; }; }

need curl
need tar
need systemctl

INSTALL_DIR="${INSTALL_DIR:-}"
if [[ -z "$INSTALL_DIR" ]]; then
  if [[ -d "$INSTALL_DIR_DEFAULT" ]]; then
    INSTALL_DIR="$INSTALL_DIR_DEFAULT"
  elif [[ -d "$LEGACY_DIR_1" ]]; then
    INSTALL_DIR="$LEGACY_DIR_1"
  else
    INSTALL_DIR="$INSTALL_DIR_DEFAULT"
  fi
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

API="https://api.github.com/repos/${REPO}/releases/latest"
log "Fetching latest release: $API"
JSON=$(curl -fsSL -H "Accept: application/vnd.github+json" "$API")

TAG=$(echo "$JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);console.log(j.tag_name||'');});")
if [[ -z "$TAG" ]]; then
  err "Could not determine latest tag"
  exit 1
fi

ASSET_NAME="claw-companion-${TAG}.tar.gz"
SHA_NAME="${ASSET_NAME}.sha256"

ASSET_URL=$(echo "$JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);const a=(j.assets||[]).find(x=>x.name==='${ASSET_NAME}');console.log(a?a.browser_download_url:'');});")
SHA_URL=$(echo "$JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);const a=(j.assets||[]).find(x=>x.name==='${SHA_NAME}');console.log(a?a.browser_download_url:'');});")

if [[ -z "$ASSET_URL" || -z "$SHA_URL" ]]; then
  err "Release assets not found. Need: ${ASSET_NAME} and ${SHA_NAME}"
  exit 1
fi

TARBALL="$TMP_DIR/${ASSET_NAME}"
SHAFILE="$TMP_DIR/${SHA_NAME}"

log "Downloading tarball..."
curl -fsSL -L "$ASSET_URL" -o "$TARBALL"
log "Downloading checksum..."
curl -fsSL -L "$SHA_URL" -o "$SHAFILE"

log "Verifying sha256..."
EXPECTED=$(awk '{print $1}' "$SHAFILE" | tr -d '\r\n')
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL=$(sha256sum "$TARBALL" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
else
  err "No sha256 tool found"
  exit 1
fi

if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  err "Checksum mismatch expected=$EXPECTED actual=$ACTUAL"
  exit 1
fi

log "Stopping service: $SERVICE_NAME"
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

TS=$(date +%Y%m%d-%H%M%S)
BACKUP="${INSTALL_DIR}.bak.${TS}"
if [[ -d "$INSTALL_DIR" ]]; then
  log "Backing up ${INSTALL_DIR} -> ${BACKUP}"
  mv "$INSTALL_DIR" "$BACKUP"
fi

mkdir -p "$INSTALL_DIR"

log "Extracting..."
tar -xzf "$TARBALL" -C "$TMP_DIR"
if [[ ! -d "$TMP_DIR/claw-companion" ]]; then
  err "Unexpected tarball structure"
  exit 1
fi

rm -rf "$INSTALL_DIR" || true
mv "$TMP_DIR/claw-companion" "$INSTALL_DIR"

if [[ ! -d "$INSTALL_DIR/server/node_modules" ]]; then
  err "Release artifact missing server/node_modules; aborting to avoid runtime npm install on target host"
  exit 1
fi

log "Starting service"
systemctl daemon-reload 2>/dev/null || true
systemctl start "$SERVICE_NAME"

log "Done. Installed ${TAG} at ${INSTALL_DIR}"
