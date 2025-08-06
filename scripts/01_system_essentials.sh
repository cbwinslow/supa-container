#!/bin/bash

# ==============================================================================
# 01_system_essentials.sh
# Summary: Handles core system updates, essential package installations,
#          and basic user/SSH key setup. This script is foundational.
# Author: Gemini
# Date: July 23, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
USERNAME="cbwinslow" # <--- IMPORTANT: CHANGE THIS TO YOUR DESIRED USERNAME

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 01_system_essentials.sh: Core System Setup."

# 1. System Update
log_info "Updating system packages..."
apt update -y || log_error "Failed to update package lists."
apt upgrade -y || log_error "Failed to upgrade packages."
apt autoremove -y || log_error "Failed to remove old packages."
log_success "System packages updated."

# 2. Ensure openssh-server is installed
log_info "Ensuring openssh-server is installed..."
if ! dpkg -s openssh-server &> /dev/null; then
    apt install openssh-server -y || log_error "Failed to install openssh-server."
    log_success "openssh-server installed."
else
    log_info "openssh-server is already installed."
fi

# 3. Ensure correct SSH key permissions and ownership for the new user
log_info "Ensuring correct SSH key permissions and ownership for user '$USERNAME'..."
if [ ! -d "/home/$USERNAME/.ssh" ]; then
    log_info "Creating /home/$USERNAME/.ssh directory..."
    mkdir -p "/home/$USERNAME/.ssh" || log_error "Failed to create /home/$USERNAME/.ssh"
fi

# Check if authorized_keys exists in root's .ssh before copying
if [ -f "/root/.ssh/authorized_keys" ]; then
    if [ ! -f "/home/$USERNAME/.ssh/authorized_keys" ]; then
        log_info "Copying authorized_keys from /root/.ssh/ to /home/$USERNAME/.ssh/..."
        cp "/root/.ssh/authorized_keys" "/home/$USERNAME/.ssh/authorized_keys" || log_error "Failed to copy authorized_keys"
    else
        log_info "authorized_keys already exists in /home/$USERNAME/.ssh/, skipping copy."
    fi
else
    log_warn "/root/.ssh/authorized_keys not found. Ensure you have manually added your public SSH key to /home/$USERNAME/.ssh/authorized_keys."
fi

log_info "Setting permissions for /home/$USERNAME/.ssh to 700..."
chmod 700 "/home/$USERNAME/.ssh" || log_error "Failed to set permissions for /home/$USERNAME/.ssh"

# Only set permissions if authorized_keys exists
if [ -f "/home/$USERNAME/.ssh/authorized_keys" ]; then
    log_info "Setting permissions for /home/$USERNAME/.ssh/authorized_keys to 600..."
    chmod 600 "/home/$USERNAME/.ssh/authorized_keys" || log_error "Failed to set permissions for /home/$USERNAME/.ssh/authorized_keys"
else
    log_warn "/home/$USERNAME/.ssh/authorized_keys not found, skipping permissions setting for it."
fi

log_info "Setting ownership of /home/$USERNAME/.ssh to user '$USERNAME'..."
chown -R "$USERNAME":"$USERNAME" "/home/$USERNAME/.ssh" || log_error "Failed to change ownership of /home/$USERNAME/.ssh"
log_success "SSH key permissions and ownership for '$USERNAME' configured."

# 4. Installation of common development tools
log_info "Installing common development tools (build-essential, git, etc.)..."
apt install build-essential git curl wget htop nano vim tmux unzip zip -y || log_error "Failed to install common dev tools."
log_success "Common development tools installed."

log_success "01_system_essentials.sh completed."
