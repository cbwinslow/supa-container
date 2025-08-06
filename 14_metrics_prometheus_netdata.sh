#!/bin/bash

# ==============================================================================
# 14_metrics_prometheus_netdata.sh
# Summary: Sets up Prometheus for metric collection and Netdata for real-time
#          system monitoring.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
PROMETHEUS_VERSION="2.47.0" # Check for the latest stable version on Prometheus GitHub releases
NODE_EXPORTER_VERSION="1.6.1" # Check for the latest stable version on Node Exporter GitHub releases
INSTALL_DIR="/opt/prometheus"
DATA_DIR="/var/lib/prometheus"

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
log_info "Starting 14_metrics_prometheus_netdata.sh: Prometheus & Netdata Setup."

# --- Prometheus Installation ---
log_info "Setting up Prometheus..."

# Create Prometheus user and directories
if ! id "prometheus" &> /dev/null; then
    log_info "Creating Prometheus user..."
    useradd --no-create-home --shell /bin/false prometheus || log_error "Failed to create prometheus user."
else
    log_info "Prometheus user already exists."
fi

mkdir -p "$INSTALL_DIR/prometheus" "$DATA_DIR" || log_error "Failed to create Prometheus directories."
mkdir -p "$INSTALL_DIR/node_exporter" || log_error "Failed to create Node Exporter directory."

chown prometheus:prometheus "$DATA_DIR" || log_error "Failed to set ownership for Prometheus data directory."
chown -R prometheus:prometheus "$INSTALL_DIR/prometheus" || log_error "Failed to set ownership for Prometheus install directory."
chown -R prometheus:prometheus "$INSTALL_DIR/node_exporter" || log_error "Failed to set ownership for Node Exporter install directory."

# Download and extract Prometheus
if [ ! -f "$INSTALL_DIR/prometheus/prometheus" ]; then
    log_info "Downloading Prometheus v$PROMETHEUS_VERSION..."
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" -O /tmp/prometheus.tar.gz || log_error "Failed to download Prometheus."
    tar xvf /tmp/prometheus.tar.gz -C /tmp/ || log_error "Failed to extract Prometheus."
    cp /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus "$INSTALL_DIR/prometheus/" || log_error "Failed to copy Prometheus binary."
    cp /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool "$INSTALL_DIR/prometheus/" || log_error "Failed to copy promtool binary."
    cp -r /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles "$INSTALL_DIR/prometheus/" || log_error "Failed to copy Prometheus consoles."
    cp -r /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries "$INSTALL_DIR/prometheus/" || log_error "Failed to copy Prometheus console libraries."
    rm -rf /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64 /tmp/prometheus.tar.gz
    log_success "Prometheus binaries copied."
else
    log_info "Prometheus v$PROMETHEUS_VERSION already installed."
fi

# Download and extract Node Exporter
if [ ! -f "$INSTALL_DIR/node_exporter/node_exporter" ]; then
    log_info "Downloading Node Exporter v$NODE_EXPORTER_VERSION..."
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" -O /tmp/node_exporter.tar.gz || log_error "Failed to download Node Exporter."
    tar xvf /tmp/node_exporter.tar.gz -C /tmp/ || log_error "Failed to extract Node Exporter."
    cp /tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter "$INSTALL_DIR/node_exporter/" || log_error "Failed to copy Node Exporter binary."
    rm -rf /tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64 /tmp/node_exporter.tar.gz
    log_success "Node Exporter binary copied."
else
    log_info "Node Exporter v$NODE_EXPORTER_VERSION already installed."
fi

# Configure Prometheus
PROMETHEUS_CONFIG="$INSTALL_DIR/prometheus/prometheus.yml"
if [ ! -f "$PROMETHEUS_CONFIG" ]; then
    log_info "Creating Prometheus configuration file: $PROMETHEUS_CONFIG"
    cat <<EOF > "$PROMETHEUS_CONFIG"
global:
  scrape_interval: 15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. Default is every 1 minute.

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - alertmanager:9093

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
EOF
    log_success "Prometheus configuration created."
else
    log_info "Prometheus configuration file already exists. Skipping creation."
fi
chown prometheus:prometheus "$PROMETHEUS_CONFIG" || log_error "Failed to set ownership for Prometheus config."

# Setup systemd service for Prometheus
PROMETHEUS_SERVICE="/etc/systemd/system/prometheus.service"
if [ ! -f "$PROMETHEUS_SERVICE" ]; then
    log_info "Creating Prometheus systemd service file..."
    cat <<EOF > "$PROMETHEUS_SERVICE"
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=$INSTALL_DIR/prometheus/prometheus \
    --config.file=$INSTALL_DIR/prometheus/prometheus.yml \
    --storage.tsdb.path=$DATA_DIR \
    --web.console.templates=$INSTALL_DIR/prometheus/consoles \
    --web.console.libraries=$INSTALL_DIR/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF
    log_success "Prometheus systemd service created."
else
    log_info "Prometheus systemd service file already exists. Skipping creation."
fi

# Setup systemd service for Node Exporter
NODE_EXPORTER_SERVICE="/etc/systemd/system/node_exporter.service"
if [ ! -f "$NODE_EXPORTER_SERVICE" ]; then
    log_info "Creating Node Exporter systemd service file..."
    cat <<EOF > "$NODE_EXPORTER_SERVICE"
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=$INSTALL_DIR/node_exporter/node_exporter --web.listen-address="0.0.0.0:9100"

[Install]
WantedBy=multi-user.target
EOF
    log_success "Node Exporter systemd service created."
else
    log_info "Node Exporter systemd service file already exists. Skipping creation."
fi

log_info "Reloading systemd daemon and starting Prometheus and Node Exporter..."
systemctl daemon-reload || log_error "Failed to reload systemd daemon."
systemctl enable prometheus || log_error "Failed to enable Prometheus."
systemctl start prometheus || log_error "Failed to start Prometheus."
systemctl enable node_exporter || log_error "Failed to enable Node Exporter."
systemctl start node_exporter || log_error "Failed to start Node Exporter."
log_success "Prometheus and Node Exporter installed and running."
log_warn "Prometheus UI is available on port 9090. Node Exporter metrics on port 9100. Ensure UFW allows access from trusted IPs."

# --- Netdata Installation ---
log_info "Setting up Netdata..."

if ! command -v netdata &> /dev/null; then
    log_info "Downloading and installing Netdata..."
    # Use the official Netdata one-liner for robust installation
    wget -O /tmp/netdata-installer.sh https://my-netdata.io/kickstart.sh || log_error "Failed to download Netdata installer."
    # Run the installer with non-interactive options
    sh /tmp/netdata-installer.sh --dont-wait --install /opt/netdata || log_error "Failed to install Netdata."
    rm /tmp/netdata-installer.sh
    log_success "Netdata installed."
else
    log_info "Netdata is already installed."
fi

log_info "Ensuring Netdata service is running..."
systemctl enable netdata || log_error "Failed to enable Netdata."
systemctl start netdata || log_error "Failed to start Netdata."
log_success "Netdata installed and running."
log_warn "Netdata UI is available on port 19999. Ensure UFW allows access from trusted IPs."

log_success "14_metrics_prometheus_netdata.sh completed."
