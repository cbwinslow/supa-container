#!/bin/bash

# ==============================================================================
# 07_nodejs_install.sh
# Summary: Adds the NodeSource repository and installs Node.js LTS.
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
log_info "Starting 07_nodejs_install.sh: Node.js Installation."

# 1. Add NodeSource APT repository
log_info "Adding NodeSource APT repository for Node.js LTS..."
if [ ! -f "/etc/apt/sources.list.d/nodesource.list" ]; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - || log_error "Failed to add NodeSource repository."
    log_success "NodeSource repository added."
else
    log_info "NodeSource repository already exists, skipping addition."
fi

# 2. Install Node.js
log_info "Installing Node.js (LTS version)..."
if ! command -v node &> /dev/null; then
    apt install nodejs -y || log_error "Failed to install Node.js."
    log_success "Node.js installed."
else
    log_info "Node.js is already installed."
fi
log_success "Node.js installed. Verify with 'node -v' and 'npm -v'."

log_success "07_nodejs_install.sh completed."
