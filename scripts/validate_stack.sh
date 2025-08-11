#!/usr/bin/env bash
#===============================================================================
# Script Name  : validate_stack.sh
# Author       : CBW + ChatGPT (GPT-5 Thinking)
# Date         : 2025-08-11
# Summary      : Validate containers are healthy and core endpoints respond
# Inputs       : .env (DOMAIN), optional BASIC auth envs for protected UIs
# Outputs      : Exit non-zero on failure; prints tailored hints
# Mod Log      : 2025-08-11 - initial version
#===============================================================================
set -Eeuo pipefail
log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
[[ -f "$ENV_FILE" ]] || { log "WARN: .env not found; domain checks disabled."; DOMAIN=""; }

# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

require() { command -v "$1" >/dev/null 2>&1 || { log "Missing dependency: $1"; exit 1; }; }
require docker
require curl
require awk

fail=0

log "Checking Docker container health..."
while read -r name health; do
  if [[ "$health" != "healthy" ]]; then
    log "Container not healthy: $name (state=$health). Recent logs:"
    docker logs --tail=80 "$name" || true
    fail=1
  else
    log "OK: $name"
  fi
done < <(docker ps --format '{{.Names}} {{.Status}}' | awk '{print $1, $3}' | sed 's/(//; s/)//')

if [[ -n "${DOMAIN:-}" ]]; then
  log "Probing core endpoints at domain: ${DOMAIN}"
  endpoints=(
    "https://${DOMAIN}/"              # Next.js
    "https://api.${DOMAIN}/healthz"  # FastAPI health
    "https://flowise.${DOMAIN}/"
    "https://n8n.${DOMAIN}/"
    "https://langfuse.${DOMAIN}/"
    "https://jaeger.${DOMAIN}/"
    "https://grafana.${DOMAIN}/"
    "https://loki.${DOMAIN}/"
  )
  for url in "${endpoints[@]}"; do
    if curl -fsS --max-time 8 "$url" >/dev/null; then
      log "OK: $url"
    else
      log "WARN: endpoint not responding: $url"
      fail=1
    fi
  done
else
  log "Skipping endpoint probes (DOMAIN unset)."
fi

[[ $fail -eq 0 ]] && { log "Validation passed."; exit 0; } || { log "Validation found issues."; exit 2; }
