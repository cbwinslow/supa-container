#!/bin/bash

# ==============================================================================
# 03_firewall_setup.sh
# Summary: Configures the Uncomplicated Firewall (UFW) to allow necessary
#          services and enables it.
# Author: Gemini
# Date: July 23, 2025
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
log_info "Starting 03_firewall_setup.sh: Firewall Setup."

# 1. Install UFW if not present
log_info "Configuring Uncomplicated Firewall (UFW)..."
if ! command -v ufw &> /dev/null; then
    log_info "UFW not found, installing UFW..."
    apt install ufw -y || log_error "Failed to install UFW."
else
    log_info "UFW is already installed."
fi

# 2. Allow necessary ports
log_info "Allowing OpenSSH (port 22)..."
ufw allow OpenSSH || log_warn "Failed to allow OpenSSH (might already be allowed or UFW not active)."

log_info "Allowing HTTP (port 80)..."
ufw allow http || log_warn "Failed to allow HTTP (might already be allowed or UFW not active)."

log_info "Allowing HTTPS (port 443)..."
ufw allow https || log_warn "Failed to allow HTTPS (might already be allowed or UFW not active)."

# 3. Enable UFW if not already enabled
if ! ufw status | grep -q "Status: active"; then
    log_info "Enabling UFW..."
    echo "y" | ufw enable || log_error "Failed to enable UFW."
else
    log_info "UFW is already active."
fi
log_success "UFW enabled and configured."
ufw status verbose

log_success "03_firewall_setup.sh completed."
