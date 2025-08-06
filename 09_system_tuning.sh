#!/bin/bash

# ==============================================================================
# 09_system_tuning.sh
# Summary: Applies basic kernel hardening settings via sysctl and ensures
#          time synchronization.
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
log_info "Starting 09_system_tuning.sh: System Tuning and Kernel Hardening."

# 1. Time Synchronization (NTP/systemd-timesyncd)
log_info "Ensuring time synchronization is enabled..."
if systemctl is-active --quiet systemd-timesyncd; then
    log_info "systemd-timesyncd is active and handling time synchronization."
elif ! command -v ntpq &> /dev/null; then # Check if NTP is installed
    log_info "systemd-timesyncd not active and NTP not found, attempting to install and enable NTP..."
    apt install ntp -y || log_error "Failed to install NTP."
    systemctl enable ntp || log_error "Failed to enable NTP."
    systemctl start ntp || log_error "Failed to start NTP."
    log_success "NTP installed and configured for time synchronization."
else
    log_info "NTP is already installed and running or systemd-timesyncd is active."
fi
log_success "Time synchronization checked/configured."

# 2. Basic Kernel Hardening (sysctl)
log_info "Applying basic kernel hardening (sysctl settings)..."
SYSCTL_CONFIG="/etc/sysctl.d/99-custom-security.conf"

# Ensure the custom security config file exists
touch "$SYSCTL_CONFIG" || log_error "Failed to create $SYSCTL_CONFIG."

# Apply settings using the ensure_line function
log_info "Applying sysctl settings..."
ensure_line "$SYSCTL_CONFIG" "^net\.ipv4\.conf\.all\.rp_filter=.*" "net.ipv4.conf.all.rp_filter=1"
ensure_line "$SYSCTL_CONFIG" "^net\.ipv4\.conf\.default\.rp_filter=.*" "net.ipv4.conf.default.rp_filter=1"
ensure_line "$SYSCTL_CONFIG" "^net\.ipv4\.tcp_syncookies=.*" "net.ipv4.tcp_syncookies=1"
ensure_line "$SYSCTL_CONFIG" "^net\.ipv4\.ip_forward=.*" "net.ipv4.ip_forward=0"
ensure_line "$SYSCTL_CONFIG" "^net\.ipv6\.conf\.all\.disable_ipv6=.*" "net.ipv6.conf.all.disable_ipv6=0"
ensure_line "$SYSCTL_CONFIG" "^net\.ipv6\.conf\.default\.disable_ipv6=.*" "net.ipv6.conf.default.disable_ipv6=0"
ensure_line "$SYSCTL_CONFIG" "^kernel\.sysrq=.*" "kernel.sysrq=0"
ensure_line "$SYSCTL_CONFIG" "^kernel\.core_uses_pid=.*" "kernel.core_uses_pid=1"
ensure_line "$SYSCTL_CONFIG" "^fs\.suid_dumpable=.*" "fs.suid_dumpable=0"
ensure_line "$SYSCTL_CONFIG" "^kernel\.kptr_restrict=.*" "kernel.kptr_restrict=1"
ensure_line "$SYSCTL_CONFIG" "^kernel\.dmesg_restrict=.*" "kernel.dmesg_restrict=1"
ensure_line "$SYSCTL_CONFIG" "^net\.ipv4\.icmp_echo_ignore_broadcasts=.*" "net.ipv4.icmp_echo_ignore_broadcasts=1"
ensure_line "$SYSCTL_CONFIG" "^net\.ipv4\.icmp_ignore_bogus_error_responses=.*" "net.ipv4.icmp_ignore_bogus_error_responses=1"
ensure_line "$SYSCTL_CONFIG" "^net\.ipv4\.tcp_timestamps=.*" "net.ipv4.tcp_timestamps=0"
ensure_line "$SYSCTL_CONFIG" "^net\.ipv4\.tcp_sack=.*" "net.ipv4.tcp_sack=1"

sysctl -p "$SYSCTL_CONFIG" || log_error "Failed to apply sysctl changes."
log_success "Basic kernel hardening applied."

log_success "09_system_tuning.sh completed."
