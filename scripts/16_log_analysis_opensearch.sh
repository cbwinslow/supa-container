#!/bin/bash

# ==============================================================================
# 16_log_analysis_opensearch.sh
# Summary: Installs OpenSearch (a fork of Elasticsearch) for advanced log analysis,
#          full-text search, and structured data querying, including its dashboards.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
OPENSEARCH_VERSION="2.11.1" # Check for the latest stable version on OpenSearch website
INSTALL_DIR="/opt/opensearch"
DATA_DIR="/var/lib/opensearch"
LOG_DIR="/var/log/opensearch"
CONFIG_DIR="/etc/opensearch"
OPENSEARCH_DASHBOARDS_VERSION="2.11.1" # Must match OpenSearch version
DASHBOARDS_CONFIG_DIR="/etc/opensearch-dashboards"
DASHBOARDS_LOG_DIR="/var/log/opensearch-dashboards"

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
log_info "Starting 16_log_analysis_opensearch.sh: OpenSearch & Dashboards Setup."

# --- OpenSearch Installation ---
log_info "Installing OpenSearch..."

# Add OpenSearch GPG key and APT repository
if [ ! -f "/etc/apt/sources.list.d/opensearch-2.x.list" ]; then
    log_info "Adding OpenSearch GPG key and APT repository..."
    wget -qO - https://artifacts.opensearch.org/publickeys/opensearch.gpg | gpg --dearmor | tee /usr/share/keyrings/opensearch-keyring.gpg > /dev/null || log_error "Failed to add OpenSearch GPG key."
    echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring.gpg] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | tee /etc/apt/sources.list.d/opensearch-2.x.list || log_error "Failed to add OpenSearch APT repository."
    apt update -y || log_error "Failed to update apt lists after adding OpenSearch repo."
    log_success "OpenSearch GPG key and repository added."
else
    log_info "OpenSearch GPG key and repository already exist."
fi

if ! dpkg -s opensearch &> /dev/null; then
    apt install opensearch -y || log_error "Failed to install OpenSearch."
    log_success "OpenSearch installed."
else
    log_info "OpenSearch is already installed."
fi

# Configure OpenSearch
log_info "Configuring OpenSearch..."
OPENSEARCH_YML="/etc/opensearch/opensearch.yml"

# Backup original config
cp "$OPENSEARCH_YML" "${OPENSEARCH_YML}.bak_$(date +%Y%m%d%H%M%S)"

# Basic configuration (ensure idempotency with ensure_line or sed -i)
# Network host: 0.0.0.0 for web access, or localhost if only accessed internally
# For initial setup, we'll bind to 0.0.0.0. For production, restrict to internal IPs.
ensure_line "$OPENSEARCH_YML" "^#\?network.host:.*" "network.host: 0.0.0.0"
ensure_line "$OPENSEARCH_YML" "^#\?http.port:.*" "http.port: 9200"
ensure_line "$OPENSEARCH_YML" "^#\?transport.port:.*" "transport.port: 9300"
ensure_line "$OPENSEARCH_YML" "^#\?cluster.name:.*" "cluster.name: opensearch-cluster"
ensure_line "$OPENSEARCH_YML" "^#\?node.name:.*" "node.name: node-1"
ensure_line "$OPENSEARCH_YML" "^#\?path.data:.*" "path.data: $DATA_DIR"
ensure_line "$OPENSEARCH_YML" "^#\?path.logs:.*" "path.logs: $LOG_DIR"

# Enable security plugin (default for OpenSearch)
ensure_line "$OPENSEARCH_YML" "^#\?plugins.security.disabled:.*" "plugins.security.disabled: false"

# Important: For a single node, set discovery.type to single-node
ensure_line "$OPENSEARCH_YML" "^#\?discovery.type:.*" "discovery.type: single-node"

# Ensure directories exist and have correct permissions
mkdir -p "$DATA_DIR" "$LOG_DIR" || log_error "Failed to create OpenSearch data/log directories."
chown -R opensearch:opensearch "$DATA_DIR" "$LOG_DIR" || log_error "Failed to set ownership for OpenSearch directories."
chmod 755 "$DATA_DIR" "$LOG_DIR" || log_error "Failed to set permissions for OpenSearch directories."

log_success "OpenSearch configured."

# Start and enable OpenSearch
log_info "Starting and enabling OpenSearch service..."
systemctl daemon-reload || log_error "Failed to reload systemd daemon."
systemctl enable opensearch || log_error "Failed to enable OpenSearch."
systemctl start opensearch || log_error "Failed to start OpenSearch."
log_success "OpenSearch service started and enabled."
log_warn "OpenSearch is listening on ports 9200 (HTTP) and 9300 (Transport). Ensure UFW allows access from trusted IPs."
log_warn "Initial OpenSearch setup requires running securityadmin.sh to set up users/passwords. This is a manual step."
log_warn "Default admin credentials for security plugin are 'admin'/'admin'. Change immediately!"

# --- OpenSearch Dashboards Installation ---
log_info "Installing OpenSearch Dashboards..."

if ! dpkg -s opensearch-dashboards &> /dev/null; then
    apt install opensearch-dashboards -y || log_error "Failed to install OpenSearch Dashboards."
    log_success "OpenSearch Dashboards installed."
else
    log_info "OpenSearch Dashboards is already installed."
fi

# Configure OpenSearch Dashboards
log_info "Configuring OpenSearch Dashboards..."
DASHBOARDS_YML="/etc/opensearch-dashboards/opensearch_dashboards.yml"

# Backup original config
cp "$DASHBOARDS_YML" "${DASHBOARDS_YML}.bak_$(date +%Y%m%d%H%M%S)"

# Basic configuration
ensure_line "$DASHBOARDS_YML" "^#\?server.port:.*" "server.port: 5601"
ensure_line "$DASHBOARDS_YML" "^#\?server.host:.*" "server.host: \"0.0.0.0\"" # Bind to all interfaces for web access
ensure_line "$DASHBOARDS_YML" "^#\?opensearch.hosts:.*" "opensearch.hosts: [\"https://localhost:9200\"]" # Use HTTPS for security plugin
ensure_line "$DASHBOARDS_YML" "^#\?opensearch.ssl.verificationMode:.*" "opensearch.ssl.verificationMode: none" # For initial setup, disable SSL verification to localhost
ensure_line "$DASHBOARDS_YML" "^#\?opensearch.username:.*" "opensearch.username: \"admin\"" # Default admin user
ensure_line "$DASHBOARDS_YML" "^#\?opensearch.password:.*" "opensearch.password: \"admin\"" # Default admin password (CHANGE THIS AFTER INITIAL SETUP)
ensure_line "$DASHBOARDS_YML" "^#\?logging.dest:.*" "logging.dest: $DASHBOARDS_LOG_DIR/opensearch-dashboards.log"

# Ensure log directory exists and has correct permissions
mkdir -p "$DASHBOARDS_LOG_DIR" || log_error "Failed to create OpenSearch Dashboards log directory."
chown -R opensearch-dashboards:opensearch-dashboards "$DASHBOARDS_LOG_DIR" || log_error "Failed to set ownership for OpenSearch Dashboards log directory."
chmod 755 "$DASHBOARDS_LOG_DIR" || log_error "Failed to set permissions for OpenSearch Dashboards log directory."

log_success "OpenSearch Dashboards configured."

# Start and enable OpenSearch Dashboards
log_info "Starting and enabling OpenSearch Dashboards service..."
systemctl daemon-reload || log_error "Failed to reload systemd daemon."
systemctl enable opensearch-dashboards || log_error "Failed to enable OpenSearch Dashboards."
systemctl start opensearch-dashboards || log_error "Failed to start OpenSearch Dashboards."
log_success "OpenSearch Dashboards service started and enabled."
log_warn "OpenSearch Dashboards UI is available on port 5601. Ensure UFW allows access from trusted IPs."
log_warn "Remember to change default 'admin' credentials for OpenSearch security plugin and Dashboards!"
log_warn "For production, configure proper SSL certificates for OpenSearch and Dashboards."

log_success "16_log_analysis_opensearch.sh completed."
