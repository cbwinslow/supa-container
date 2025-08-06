#!/bin/bash

# ==============================================================================
# 15_log_aggregation_loki_promtail.sh
# Summary: Installs Grafana Loki for log aggregation and Promtail as its agent
#          for collecting logs from the server.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
LOKI_VERSION="2.9.0" # Check for the latest stable version on Loki GitHub releases
PROMTAIL_VERSION="2.9.0" # Check for the latest stable version on Promtail GitHub releases
GRAFANA_VERSION="10.2.3" # Check for the latest stable version on Grafana APT repo
INSTALL_DIR="/opt/loki"
DATA_DIR="/var/lib/loki"
LOKI_CONFIG_DIR="/etc/loki"
PROMTAIL_CONFIG_DIR="/etc/promtail"

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# Function to ensure a line exists or is replaced in a file
ensure_line() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"
    if grep -qP "$pattern" "$file"; then
        sed -i "s|$pattern|$replacement|" "$file" || log_warn "Failed to update line in $file: $pattern"
    else
        echo "$replacement" | tee -a "$file" || log_warn "Failed to add line to $file: $replacement"
    fi
}

# --- Main Script Execution ---
log_info "Starting 15_log_aggregation_loki_promtail.sh: Loki & Promtail Setup."

# --- Grafana Installation (for visualization) ---
log_info "Installing Grafana..."
if ! dpkg -s grafana &> /dev/null; then
    log_info "Adding Grafana GPG key and APT repository..."
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/grafana.gpg > /dev/null || log_error "Failed to add Grafana GPG key."
    echo "deb https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list || log_error "Failed to add Grafana APT repository."
    apt update -y || log_error "Failed to update apt lists after adding Grafana repo."
    apt install grafana -y || log_error "Failed to install Grafana."
    log_success "Grafana installed."
else
    log_info "Grafana is already installed."
fi

log_info "Starting and enabling Grafana service..."
systemctl enable grafana-server || log_error "Failed to enable Grafana."
systemctl start grafana-server || log_error "Failed to start Grafana."
log_success "Grafana installed and running."
log_warn "Grafana UI is available on port 3000. Default credentials: admin/admin. Ensure UFW allows access from trusted IPs."

# --- Loki Installation ---
log_info "Setting up Loki..."

# Create Loki user and directories
if ! id "loki" &> /dev/null; then
    log_info "Creating Loki user..."
    useradd --no-create-home --shell /bin/false loki || log_error "Failed to create loki user."
else
    log_info "Loki user already exists."
fi

mkdir -p "$INSTALL_DIR/loki" "$DATA_DIR" "$LOKI_CONFIG_DIR" || log_error "Failed to create Loki directories."
chown loki:loki "$DATA_DIR" || log_error "Failed to set ownership for Loki data directory."
chown -R loki:loki "$INSTALL_DIR/loki" || log_error "Failed to set ownership for Loki install directory."
chown -R loki:loki "$LOKI_CONFIG_DIR" || log_error "Failed to set ownership for Loki config directory."

# Download and extract Loki
if [ ! -f "$INSTALL_DIR/loki/loki" ]; then
    log_info "Downloading Loki v$LOKI_VERSION..."
    wget -q "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip" -O /tmp/loki.zip || log_error "Failed to download Loki."
    unzip /tmp/loki.zip -d /tmp/ || log_error "Failed to extract Loki."
    mv /tmp/loki-linux-amd64 "$INSTALL_DIR/loki/loki" || log_error "Failed to move Loki binary."
    rm /tmp/loki.zip
    log_success "Loki binary copied."
else
    log_info "Loki v$LOKI_VERSION already installed."
fi

# Configure Loki
LOKI_CONFIG_FILE="$LOKI_CONFIG_DIR/loki-config.yaml"
if [ ! -f "$LOKI_CONFIG_FILE" ]; then
    log_info "Creating Loki configuration file: $LOKI_CONFIG_FILE"
    cat <<EOF > "$LOKI_CONFIG_FILE"
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9095

common:
  path_prefix: $DATA_DIR
  storage_config:
    boltdb_shipper:
      active_index_directory: $DATA_DIR/boltdb-shipper-active
      cache_location: $DATA_DIR/boltdb-shipper-cache
      cache_ttl: 24h
      shared_store: filesystem
    filesystem:
      directory: $DATA_DIR/chunks
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-27
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      period: 24h
      index:
        prefix: index_
        period: 24h

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s

compactor:
  working_directory: $DATA_DIR/compactor
  shared_store: filesystem
EOF
    log_success "Loki configuration created."
else
    log_info "Loki configuration file already exists. Skipping creation."
fi
chown loki:loki "$LOKI_CONFIG_FILE" || log_error "Failed to set ownership for Loki config."

# Setup systemd service for Loki
LOKI_SERVICE="/etc/systemd/system/loki.service"
if [ ! -f "$LOKI_SERVICE" ]; then
    log_info "Creating Loki systemd service file..."
    cat <<EOF > "$LOKI_SERVICE"
[Unit]
Description=Loki
After=network.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=$INSTALL_DIR/loki/loki -config.file=$LOKI_CONFIG_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    log_success "Loki systemd service created."
else
    log_info "Loki systemd service file already exists. Skipping creation."
fi

# --- Promtail Installation ---
log_info "Setting up Promtail..."

# Create Promtail user and directories
if ! id "promtail" &> /dev/null; then
    log_info "Creating Promtail user..."
    useradd --no-create-home --shell /bin/false promtail || log_error "Failed to create promtail user."
else
    log_info "Promtail user already exists."
fi

mkdir -p "$INSTALL_DIR/promtail" "$PROMTAIL_CONFIG_DIR" || log_error "Failed to create Promtail directories."
chown -R promtail:promtail "$INSTALL_DIR/promtail" || log_error "Failed to set ownership for Promtail install directory."
chown -R promtail:promtail "$PROMTAIL_CONFIG_DIR" || log_error "Failed to set ownership for Promtail config directory."

# Download and extract Promtail
if [ ! -f "$INSTALL_DIR/promtail/promtail" ]; then
    log_info "Downloading Promtail v$PROMTAIL_VERSION..."
    wget -q "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip" -O /tmp/promtail.zip || log_error "Failed to download Promtail."
    unzip /tmp/promtail.zip -d /tmp/ || log_error "Failed to extract Promtail."
    mv /tmp/promtail-linux-amd64 "$INSTALL_DIR/promtail/promtail" || log_error "Failed to move Promtail binary."
    rm /tmp/promtail.zip
    log_success "Promtail binary copied."
else
    log_info "Promtail v$PROMTAIL_VERSION already installed."
fi

# Configure Promtail
PROMTAIL_CONFIG_FILE="$PROMTAIL_CONFIG_DIR/promtail-config.yaml"
if [ ! -f "$PROMTAIL_CONFIG_FILE" ]; then
    log_info "Creating Promtail configuration file: $PROMTAIL_CONFIG_FILE"
    cat <<EOF > "$PROMTAIL_CONFIG_FILE"
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*log
  - job_name: journal
    journal:
      max_age: 12h
      path: /var/log/journal
      labels:
        job: systemd-journal
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
      - source_labels: ['__journal__boot_id']
        target_label: 'boot_id'
EOF
    log_success "Promtail configuration created."
else
    log_info "Promtail configuration file already exists. Skipping creation."
fi
chown promtail:promtail "$PROMTAIL_CONFIG_FILE" || log_error "Failed to set ownership for Promtail config."

# Setup systemd service for Promtail
PROMTAIL_SERVICE="/etc/systemd/system/promtail.service"
if [ ! -f "$PROMTAIL_SERVICE" ]; then
    log_info "Creating Promtail systemd service file..."
    cat <<EOF > "$PROMTAIL_SERVICE"
[Unit]
Description=Promtail
After=network.target

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=$INSTALL_DIR/promtail/promtail -config.file=$PROMTAIL_CONFIG_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    log_success "Promtail systemd service created."
else
    log_info "Promtail systemd service file already exists. Skipping creation."
fi

log_info "Reloading systemd daemon and starting Loki and Promtail..."
systemctl daemon-reload || log_error "Failed to reload systemd daemon."
systemctl enable loki || log_error "Failed to enable Loki."
systemctl start loki || log_error "Failed to start Loki."
systemctl enable promtail || log_error "Failed to enable Promtail."
systemctl start promtail || log_error "Failed to start Promtail."
log_success "Loki and Promtail installed and running."
log_warn "Loki is listening on port 3100. Promtail on 9080. Ensure UFW allows access from trusted IPs."
log_warn "Remember to configure Grafana to add Loki as a data source (http://localhost:3100)."

log_success "15_log_aggregation_loki_promtail.sh completed."
