#!/bin/bash

# ==============================================================================
# 08_security_enhancements.sh
# Summary: Configures automatic security updates and installs Fail2Ban.
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

# Function to ensure a line exists or is replaced in a file
ensure_line() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"
    if grep -qP "$pattern" "$file"; then
        # Line exists, replace it
        sed -i "s|$pattern|$replacement|" "$file" || log_warn "Failed to update line in $file: $pattern"
    else
        # Line does not exist, append it
        echo "$replacement" | tee -a "$file" || log_warn "Failed to add line to $file: $replacement"
    fi
}

# --- Main Script Execution ---
log_info "Starting 08_security_enhancements.sh: Security Enhancements."

# 1. Configure Automatic Security Updates (Unattended Upgrades)
log_info "Configuring automatic security updates (Unattended Upgrades)..."
if ! dpkg -s unattended-upgrades &> /dev/null; then
    apt install unattended-upgrades -y || log_error "Failed to install unattended-upgrades."
    log_success "Unattended Upgrades installed."
else
    log_info "Unattended Upgrades is already installed."
fi

# Enable automatic updates without interactive prompt
log_info "Ensuring unattended upgrades are enabled non-interactively..."
echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades || log_error "Failed to reconfigure unattended-upgrades."

# Configure to automatically remove unused dependencies and set intervals
UNATTENDED_CONFIG_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
log_info "Configuring unattended upgrades intervals and unused dependency removal..."
ensure_line "$UNATTENDED_CONFIG_FILE" '^APT::Periodic::AutocleanInterval ".*";' 'APT::Periodic::AutocleanInterval "14";'
ensure_line "$UNATTENDED_CONFIG_FILE" '^APT::Periodic::Unattended-Upgrade ".*";' 'APT::Periodic::Unattended-Upgrade "1";'
ensure_line "$UNATTENDED_CONFIG_FILE" '^APT::Periodic::Verbose ".*";' 'APT::Periodic::Verbose "1";'

UNATTENDED_CONFIG_FILE_50="/etc/apt/apt.conf.d/50unattended-upgrades"
ensure_line "$UNATTENDED_CONFIG_FILE_50" '^Unattended-Upgrade::Remove-Unused-Dependencies ".*";' 'Unattended-Upgrade::Remove-Unused-Dependencies "true";'

log_success "Unattended upgrades configured for automatic security updates and unused package removal."

# 2. Install Fail2Ban
log_info "Installing Fail2Ban for brute-force protection..."
if ! command -v fail2ban-client &> /dev/null; then
    apt install fail2ban -y || log_error "Failed to install Fail2Ban."
    log_success "Fail2Ban installed."
else
    log_info "Fail2Ban is already installed."
fi
systemctl enable fail2ban || log_error "Failed to enable Fail2Ban."
systemctl start fail2ban || log_error "Failed to start Fail2Ban."

# Copy default jail.conf to jail.local for custom modifications
if [ ! -f "/etc/fail2ban/jail.local" ]; then
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local || log_warn "Failed to copy jail.conf to jail.local."
    log_info "Created /etc/fail2ban/jail.local. You can customize Fail2Ban settings there."
else
    log_info "/etc/fail2ban/jail.local already exists, skipping copy."
fi

log_success "Fail2Ban installed and running."
log_warn "Review Fail2Ban configuration in /etc/fail2ban/jail.local for customization (e.g., bantime, findtime, maxretry)."

log_success "08_security_enhancements.sh completed."
