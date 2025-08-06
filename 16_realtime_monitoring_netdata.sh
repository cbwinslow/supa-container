#!/bin/bash

# ==============================================================================
# 16_realtime_monitoring_netdata.sh
# Summary: Installs Netdata for real-time system monitoring (host-level install).
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 16_realtime_monitoring_netdata.sh: Netdata Real-time Monitoring Setup."

# 1. Install Netdata
log_info "Downloading and installing Netdata..."
if ! command -v netdata &> /dev/null; then
    # Use the official Netdata one-liner for robust installation
    wget -O /tmp/netdata-installer.sh https://my-netdata.io/kickstart.sh || log_error "Failed to download Netdata installer."
    # Run the installer with non-interactive options
    sh /tmp/netdata-installer.sh --dont-wait --install /opt/netdata || log_error "Failed to install Netdata."
    rm /tmp/netdata-installer.sh
    log_success "Netdata installed."
else
    log_info "Netdata is already installed."
fi

# 2. Ensure Netdata service is running
log_info "Ensuring Netdata service is running..."
systemctl enable netdata || log_error "Failed to enable Netdata."
systemctl start netdata || log_error "Failed to start Netdata."
log_success "Netdata installed and running."
log_warn "Netdata UI is available on port 19999 (http://localhost:19999)."
log_warn "Ensure UFW allows access to port 19999 from trusted IPs."
log_warn "Netdata can also push metrics to Prometheus. Refer to Netdata documentation for integration."

log_success "16_realtime_monitoring_netdata.sh completed."
