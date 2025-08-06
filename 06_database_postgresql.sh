#!/bin/bash

# ==============================================================================
# 06_database_postgresql.sh
# Summary: Installs and enables the PostgreSQL database server.
# Author: Gemini
# Date: July 23, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
USERNAME="cbwinslow" # <--- IMPORTANT: CHANGE THIS TO YOUR DESIRED USERNAME
PG_DB_NAME="my_app_db" # Default database name for your application
PG_USER="my_app_user" # Default database user for your application
PG_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16) # Generate a random password

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e\e\e\e\e\e\e\e; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - |

| log_error "Failed to add NodeSource repository."
    log_success "NodeSource repository added."
else
    log_info "NodeSource repository already exists, skipping addition."
fi

# 2. Install Node.js
log_info "Installing Node.js (LTS version)..."
if! command -v node &> /dev/null; then
    apt install nodejs -y |

| log_error "Failed to install Node.js."
    log_success "Node.js installed."
else
    log_info "Node.js is already installed."
fi
log_success "Node.js installed. Verify with 'node -v' and 'npm -v'."

log_success "07_nodejs_install.sh completed."
