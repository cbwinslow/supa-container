#!/usr/bin/env bash
#===============================================================================
# Script Name  : deploy-master.sh
# Author       : CBW + ChatGPT (GPT-5 Thinking)
# Date         : 2025-08-11
# Summary      : One-click deploy for opendiscourse.net with post-deploy key sync
# Inputs       : .env (provided by user). Optional Cloudflare vars for DNS.
# Outputs      : Running stack, updated .env (Supabase keys), DNS upserts (opt).
# Mod Log      : 2025-08-11 - idempotent & health-check improvements
#===============================================================================
set -Eeuo pipefail
log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
die() { log "ERROR: $*"; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${ROOT_DIR}" && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

require() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }
require sudo
require bash

# Install minimal deps
install_if_missing() {
  local pkg="$1"
  if ! command -v "$pkg" >/dev/null 2>&1; then
    sudo apt-get update -y && sudo apt-get install -y "$pkg" || die "Failed installing $pkg"
  fi
}
install_if_missing curl
install_if_missing jq

[[ -f "$ENV_FILE" ]] || die "Provide .env at project root before running this script."

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${DOMAIN:?Set DOMAIN in .env (e.g., opendiscourse.net)}"
: "${LETSENCRYPT_EMAIL:?Set LETSENCRYPT_EMAIL in .env}"

# 1) Docker setup (if needed)
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER" || true
fi

if ! docker compose version >/dev/null 2>&1; then
  log "Installing docker-compose-plugin..."
  sudo apt-get update -y && sudo apt-get install -y docker-compose-plugin
fi

# 2) Generate secrets only if absent (respect user-provided .env)
if ! grep -q "POSTGRES_PASSWORD=" "$ENV_FILE"; then
  log "Generating missing secrets via populate_secrets.sh..."
  bash "${PROJECT_ROOT}/scripts/populate_secrets.sh"
else
  log "Using provided .env (won't overwrite secrets)."
fi

# 3) Deploy
log "Bringing up the stack..."
sudo bash "${PROJECT_ROOT}/scripts/deploy.sh"

# 4) Post-deploy Supabase keys (one-time fetch, then persist into .env)
log "Waiting for services to stabilize..."
sleep 30
if bash "${PROJECT_ROOT}/scripts/post-deploy-setup.sh"; then
  if [[ -f /opt/supabase-super-stack/.env ]]; then
    # copy back any keys the script appended/echoed there
    ANON=$(grep -E '^SUPABASE_ANON_KEY=' /opt/supabase-super-stack/.env || true)
    SRV=$(grep -E '^SUPABASE_SERVICE_ROLE_KEY=' /opt/supabase-super-stack/.env || true)
    if [[ -n "$ANON" && -n "$SRV" ]]; then
      if ! grep -q '^SUPABASE_ANON_KEY=' "$ENV_FILE"; then echo "$ANON" >> "$ENV_FILE"; fi
      if ! grep -q '^SUPABASE_SERVICE_ROLE_KEY=' "$ENV_FILE"; then echo "$SRV" >> "$ENV_FILE"; fi
      log "Supabase keys synced into project .env."
    else
      log "WARN: post-deploy did not yield Supabase keys. You may add them manually."
    fi
  fi
else
  log "WARN: post-deploy setup encountered issues; continuing."
fi

# 5) Optional DNS sync (if Cloudflare vars are present)
if [[ -n "${CLOUDFLARE_API_TOKEN:-}" && -n "${CLOUDFLARE_ZONE_ID:-}" ]]; then
  bash "${PROJECT_ROOT}/scripts/dns_sync_cloudflare.sh" || log "DNS sync failed."
else
  log "Cloudflare not configured; skip DNS automation."
fi

# 6) Validate
bash "${PROJECT_ROOT}/scripts/validate_stack.sh" || {
  log "Validation reported issues. See logs above."
  exit 3
}

log "Deployment complete. Visit https://${DOMAIN}/"
