#!/usr/bin/env bash
#===============================================================================
# Script Name  : dns_sync_cloudflare.sh
# Author       : CBW + ChatGPT (GPT-5 Thinking)
# Date         : 2025-08-11
# Summary      : Idempotently create/update DNS records at Cloudflare for the stack
# Inputs       : .env (CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, DOMAIN)
# Outputs      : Upserts A/CNAME records for all required subdomains
# Mod Log      : 2025-08-11 - initial version
#===============================================================================
set -Eeuo pipefail

log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
die() { log "ERROR: $*"; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }
require curl; require jq

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
[[ -f "$ENV_FILE" ]] || die ".env not found at $ENV_FILE"

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${DOMAIN:?DOMAIN required in .env}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN required in .env}"
: "${CLOUDFLARE_ZONE_ID:?CLOUDFLARE_ZONE_ID required in .env}"

API="https://api.cloudflare.com/client/v4"
HEADERS=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")

# Determine public IP for A record
PUBLIC_IP="${PUBLIC_IP:-$(curl -fsS https://ipv4.icanhazip.com || true)}"
[[ -n "${PUBLIC_IP}" ]] || die "Could not determine PUBLIC_IP automatically. Export PUBLIC_IP and retry."

# Records to manage
SUBS=(
  "@"           # apex
  "api"
  "flowise"
  "n8n"
  "langfuse"
  "jaeger"
  "grafana"
  "loki"
  "traefik"
  "supabase"
)

upsert_record() {
  local name="$1" target="$2" type="$3" proxied="$4"
  local fqdn
  [[ "$name" == "@" ]] && fqdn="$DOMAIN" || fqdn="${name}.${DOMAIN}"

  # Fetch existing
  local rid
  rid="$(curl -fsS "${API}/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=${type}&name=${fqdn}" "${HEADERS[@]}" | jq -r '.result[0].id // empty')"

  local payload
  if [[ "$type" == "A" ]]; then
    payload=$(jq -n --arg name "$fqdn" --arg content "$target" --argjson proxied "$proxied" \
      '{type:"A",name:$name,content:$content,ttl:1,proxied:$proxied}')
  else
    payload=$(jq -n --arg name "$fqdn" --arg content "$target" --argjson proxied "$proxied" \
      '{type:"CNAME",name:$name,content:$content,ttl:1,proxied:$proxied}')
  fi

  if [[ -n "$rid" ]]; then
    curl -fsS -X PUT "${API}/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${rid}" "${HEADERS[@]}" --data "$payload" >/dev/null \
      && log "Updated ${type} ${fqdn} -> ${target}" || die "Failed updating ${fqdn}"
  else
    curl -fsS -X POST "${API}/zones/${CLOUDFLARE_ZONE_ID}/dns_records" "${HEADERS[@]}" --data "$payload" >/dev/null \
      && log "Created ${type} ${fqdn} -> ${target}" || die "Failed creating ${fqdn}"
  fi
}

# Apex A record
upsert_record "@" "${PUBLIC_IP}" "A" true

# Service subdomains (A records to same host; Traefik routes by Host + Path)
for s in "${SUBS[@]}"; do
  [[ "$s" == "@" ]] && continue
  upsert_record "$s" "${PUBLIC_IP}" "A" true
done

log "DNS sync complete for ${DOMAIN}."
