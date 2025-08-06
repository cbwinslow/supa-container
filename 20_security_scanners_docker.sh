#!/bin/bash

# ==============================================================================
# 20_security_scanners_docker.sh
# Summary: Installs security scanning tools (Falco, Trivy, Clair) via Docker Compose
#          or as host binaries for runtime security and vulnerability scanning.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# IMPORTANT: Docker must be installed first (from 12_docker_setup.sh).
# ==============================================================================

# --- Global Variables ---
SECURITY_TOOLS_DIR="/opt/security-tools"
FALCO_CONFIG_DIR="/etc/falco"
FALCO_RULES_DIR="/etc/falco/rules.d"
FALCO_LOG_DIR="/var/log/falco"

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 20_security_scanners_docker.sh: Security Scanners Setup."

# Ensure Docker is installed (for Falco via Docker)
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please run 12_docker_setup.sh first."
fi

# --- Falco (Runtime Security) Setup ---
log_info "Setting up Falco (Runtime Security) via Docker..."

# Create Falco directories
mkdir -p "$FALCO_CONFIG_DIR" "$FALCO_RULES_DIR" "$FALCO_LOG_DIR" || log_error "Failed to create Falco directories."
chmod 755 "$FALCO_CONFIG_DIR" "$FALCO_RULES_DIR" "$FALCO_LOG_DIR" || log_warn "Failed to set permissions for Falco directories."

# Create a minimal Falco configuration file
FALCO_CONFIG_FILE="$FALCO_CONFIG_DIR/falco.yaml"
if [ ! -f "$FALCO_CONFIG_FILE" ]; then
    log_info "Creating Falco configuration file: $FALCO_CONFIG_FILE"
    cat <<EOF > "$FALCO_CONFIG_FILE"
# Falco configuration
# For full options, see https://falco.org/docs/reference/daemon/config/
log_level: info
json_output: true
json_include_tags: true
file_output:
  enabled: true
  keep_alive: false
  filename: $FALCO_LOG_DIR/falco_events.json
EOF
    log_success "Falco configuration created."
else
    log_info "Falco configuration file already exists. Skipping creation."
fi

# Create a basic local rules file
FALCO_LOCAL_RULES_FILE="$FALCO_RULES_DIR/local.yaml"
if [ ! -f "$FALCO_LOCAL_RULES_FILE" ]; then
    log_info "Creating basic Falco local rules file: $FALCO_LOCAL_RULES_FILE"
    cat <<EOF > "$FALCO_LOCAL_RULES_FILE"
# Example local Falco rules
# For more rules and examples, see https://falco.org/docs/rules/
- rule: Detect outbound connections to common crypto mining ports
  desc: Alert when a process makes an outbound connection to a known crypto mining port.
  condition: >
    evt.type = connect and fd.type = ipv4 and fd.cip = "127.0.0.1" and fd.cport in (3333, 4444, 5555, 6666, 7777, 8888, 9999)
  output: >
    Outbound connection to crypto mining port (command=%proc.cmdline user=%user.name ip=%fd.cip:%fd.cport)
  priority: WARNING
  tags: [network, crypto-mining]
EOF
    log_success "Falco local rules file created."
else
    log_info "Falco local rules file already exists. Skipping creation."
fi

# Create Falco systemd service to run as Docker container
FALCO_SERVICE_FILE="/etc/systemd/system/falco-docker.service"
if [ ! -f "$FALCO_SERVICE_FILE" ]; then
    log_info "Creating Falco systemd service file for Docker deployment..."
    cat <<EOF > "$FALCO_SERVICE_FILE"
[Unit]
Description=Falco Container
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStartPre=-/usr/bin/docker rm falco
ExecStart=/usr/bin/docker run --name falco --privileged -d \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /dev:/dev \
    -v /proc:/host/proc:ro \
    -v /boot:/host/boot:ro \
    -v /lib/modules:/host/lib/modules:ro \
    -v /usr:/host/usr:ro \
    -v $FALCO_CONFIG_DIR:/etc/falco:ro \
    -v $FALCO_RULES_DIR:/etc/falco/rules.d:ro \
    -v $FALCO_LOG_DIR:/var/log/falco:rw \
    --network host \
    falcosecurity/falco:latest \
    -c /etc/falco/falco.yaml

ExecStop=/usr/bin/docker stop falco
ExecStopPost=/usr/bin/docker rm falco

[Install]
WantedBy=multi-user.target
EOF
    log_success "Falco systemd service file created."
else
    log_info "Falco systemd service file already exists. Skipping creation."
fi

log_info "Reloading systemd daemon and starting Falco..."
systemctl daemon-reload || log_error "Failed to reload systemd daemon."
systemctl enable falco-docker || log_error "Failed to enable Falco Docker service."
systemctl start falco-docker || log_error "Failed to start Falco Docker service. Check 'journalctl -xeu falco-docker'."
log_success "Falco installed and running via Docker."
log_warn "Falco will log events to '$FALCO_LOG_DIR/falco_events.json'. Configure Promtail/Fluentd to pick these up for centralized logging."
log_warn "Review Falco rules in '$FALCO_CONFIG_DIR/falco.yaml' and '$FALCO_RULES_DIR/local.yaml' and add/customize as needed."

# --- Trivy (Vulnerability Scanner) Installation ---
log_info "Installing Trivy (Vulnerability Scanner)..."
if ! command -v trivy &> /dev/null; then
    log_info "Adding Trivy GPG key and APT repository..."
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | tee /usr/share/keyrings/trivy.gpg > /dev/null || log_error "Failed to add Trivy GPG key."
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/trivy.list > /dev/null || log_error "Failed to add Trivy APT repository."
    apt update -y || log_error "Failed to update apt lists after adding Trivy repo."
    apt install trivy -y || log_error "Failed to install Trivy."
    log_success "Trivy installed."
else
    log_info "Trivy is already installed."
fi
log_warn "Trivy is a command-line tool. Example usage: 'trivy image nginx:latest' or 'trivy fs /path/to/scan'."
log_warn "Consider integrating Trivy into your CI/CD pipeline for automated image scanning."

# --- Clair (Container Image Vulnerability Scanner) Installation ---
log_info "Installing Clair (Container Image Vulnerability Scanner)..."
# Clair is typically deployed as a service, often via Docker Compose.
# It requires a PostgreSQL database. We'll provide a basic Docker Compose setup.
CLAIR_DIR="$SECURITY_TOOLS_DIR/clair"
mkdir -p "$CLAIR_DIR/config" "$CLAIR_DIR/data" || log_error "Failed to create Clair directories."

CLAIR_COMPOSE_FILE="$CLAIR_DIR/docker-compose.yml"
if [ ! -f "$CLAIR_COMPOSE_FILE" ]; then
    log_info "Creating Clair Docker Compose file: $CLAIR_COMPOSE_FILE"
    cat <<EOF > "$CLAIR_COMPOSE_FILE"
version: '3.8'
services:
  clair:
    image: quay.io/projectquay/clair:latest
    container_name: clair
    restart: unless-stopped
    ports:
      - "6060:6060" # Clair API
      - "6061:6061" # Health check
    volumes:
      - ./config:/config:ro
      - ./data:/data
    environment:
      - CLAIR_CONF=/config/config.yaml
    networks:
      - clair_network
    depends_on:
      - clair-db

  clair-db:
    image: postgres:15-alpine
    container_name: clair-db
    restart: unless-stopped
    environment:
      - POSTGRES_DB=clair
      - POSTGRES_USER=clair
      - POSTGRES_PASSWORD=clairpassword # <--- IMPORTANT: CHANGE THIS FOR PRODUCTION
    volumes:
      - ./db_data:/var/lib/postgresql/data
    networks:
      - clair_network

networks:
  clair_network:
    driver: bridge
EOF
    log_success "Clair Docker Compose file created."
    log_warn "To configure Clair, create a 'config.yaml' in '$CLAIR_DIR/config'. See Clair documentation for details."
    log_warn "To start Clair, navigate to '$CLAIR_DIR' and run: 'docker compose up -d'"
    log_warn "IMPORTANT: Change 'POSTGRES_PASSWORD' for Clair's database in the compose file for production!"
    log_warn "Clair is often integrated with container registries like Harbor for automated scanning."
else
    log_info "Clair Docker Compose file already exists. Skipping creation."
fi

log_success "20_security_scanners_docker.sh completed."
