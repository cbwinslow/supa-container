#!/bin/bash

# ==============================================================================
# 17_reverse_proxy_traefik_cloudflare.sh
# Summary: Installs Traefik as a dynamic reverse proxy and load balancer (Docker-based),
#          and configures Cloudflare DNS and 'cloudflared' for secure tunnels.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# IMPORTANT: Docker must be installed first (from 12_docker_setup.sh).
# IMPORTANT: Cloudflare Tunnel setup requires manual steps (Cloudflare Dashboard).
# ==============================================================================

# --- Global Variables ---
USERNAME="cbwinslow" # <--- IMPORTANT: CHANGE THIS TO YOUR DESIRED USERNAME
TRAEFIK_DIR="/opt/traefik"
TRAEFIK_CONFIG_DIR="$TRAEFIK_DIR/config"
TRAEFIK_LOG_DIR="$TRAEFIK_DIR/logs"
TRAEFIK_ACME_FILE="$TRAEFIK_CONFIG_DIR/acme.json" # For Let's Encrypt certificates

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 17_reverse_proxy_traefik_cloudflare.sh: Traefik & Cloudflare Tunnel Setup."

# Ensure Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please run 12_docker_setup.sh first."
fi

# Create Traefik directories
log_info "Creating Traefik directories: $TRAEFIK_CONFIG_DIR, $TRAEFIK_LOG_DIR"
mkdir -p "$TRAEFIK_CONFIG_DIR" "$TRAEFIK_LOG_DIR" || log_error "Failed to create Traefik directories."
touch "$TRAEFIK_ACME_FILE" || log_error "Failed to create acme.json file."
chmod 600 "$TRAEFIK_ACME_FILE" || log_error "Failed to set permissions for acme.json."
log_success "Traefik directories and acme.json created."

# Create Traefik static configuration file
TRAEFIK_STATIC_CONFIG_FILE="$TRAEFIK_CONFIG_DIR/traefik.yml"
if [ ! -f "$TRAEFIK_STATIC_CONFIG_FILE" ]; then
    log_info "Creating Traefik static configuration file: $TRAEFIK_STATIC_CONFIG_FILE"
    cat <<EOF > "$TRAEFIK_STATIC_CONFIG_FILE"
log:
  level: INFO
  filePath: $TRAEFIK_LOG_DIR/traefik.log

accessLog:
  filePath: $TRAEFIK_LOG_DIR/access.log

api:
  dashboard: true
  insecure: true # Set to false for production and secure dashboard access

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false # Only expose containers with specific Traefik labels
  file:
    directory: "$TRAEFIK_CONFIG_DIR/dynamic" # For static file-based routing
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com # <--- IMPORTANT: CHANGE THIS TO YOUR EMAIL
      storage: "$TRAEFIK_ACME_FILE"
      httpChallenge:
        entryPoint: web
EOF
    log_success "Traefik static configuration created."
    log_warn "Remember to change 'your-email@example.com' in $TRAEFIK_STATIC_CONFIG_FILE to your actual email for Let's Encrypt."
else
    log_info "Traefik static configuration file already exists. Skipping creation."
fi

# Create Traefik Docker Compose file
TRAEFIK_COMPOSE_FILE="$TRAEFIK_DIR/docker-compose.yml"

if [ ! -f "$TRAEFIK_COMPOSE_FILE" ]; then
    log_info "Creating Traefik Docker Compose file: $TRAEFIK_COMPOSE_FILE"
    cat <<EOF > "$TRAEFIK_COMPOSE_FILE"
version: '3.8'

services:
  traefik:
    image: traefik:v2.10 # Use a specific version
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080" # Traefik Dashboard (insecure for now, secure in production)
    volumes:
      - "$TRAEFIK_STATIC_CONFIG_FILE:/etc/traefik/traefik.yml:ro"
      - "$TRAEFIK_CONFIG_DIR/dynamic:/etc/traefik/dynamic:ro"
      - "$TRAEFIK_ACME_FILE:/etc/traefik/acme.json"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "$TRAEFIK_LOG_DIR:/var/log/traefik"
    networks:
      - web

networks:
  web:
    external: true # This network will be used by other services to connect to Traefik
EOF
    log_success "Traefik Docker Compose file created."
else
    log_info "Traefik Docker Compose file already exists. Skipping creation."
fi

# Start Traefik via Docker Compose
log_info "Starting Traefik via Docker Compose..."
docker network create web || log_warn "Docker network 'web' already exists or failed to create."
docker compose -f "$TRAEFIK_COMPOSE_FILE" up -d || log_error "Failed to start Traefik via Docker Compose."
log_success "Traefik installed and running via Docker Compose."
log_warn "Traefik Dashboard is available on port 8080 (http://localhost:8080). For production, secure it!"
log_warn "You will need to configure your applications (e.g., OpenWebUI, Grafana) with Traefik labels in their Docker Compose files to expose them."

# --- Cloudflare Tunnel (cloudflared) Installation ---
log_info "Setting up Cloudflare Tunnel (cloudflared)..."

if ! command -v cloudflared &> /dev/null; then
    log_info "Downloading and installing cloudflared..."
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | gpg --dearmor | tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null || log_error "Failed to add Cloudflare GPG key."
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflared.list > /dev/null || log_error "Failed to add Cloudflare APT repository."
    apt update -y || log_error "Failed to update apt lists after adding Cloudflare repo."
    apt install cloudflared -y || log_error "Failed to install cloudflared."
    log_success "cloudflared installed."
else
    log_info "cloudflared is already installed."
fi

log_info "Cloudflare Tunnel setup is largely a manual process after installation."
log_warn "To create a Cloudflare Tunnel: "
log_warn "  1. Log in to your Cloudflare Dashboard."
log_warn "  2. Go to 'Access' -> 'Tunnels' and create a new Tunnel."
log_warn "  3. Follow the instructions to install 'cloudflared' and authenticate it with your Cloudflare account."
log_warn "  4. Define your public hostname and service routes (e.g., yourdomain.com -> http://localhost:8080 for Traefik)."
log_warn "  5. This will create a tunnel configuration file (e.g., ~/.cloudflared/UUID.json or /etc/cloudflared/config.yml)."
log_warn "  6. You will then need to run 'cloudflared tunnel run <TUNNEL_NAME>' or configure it as a systemd service."

log_success "17_reverse_proxy_traefik_cloudflare.sh completed."
