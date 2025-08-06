#!/bin/bash

# ==============================================================================
# 11_ids_snort_setup.sh
# Summary: Installs and provides a detailed initial setup for Snort, an
#          intrusion detection system.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
# IMPORTANT: Replace with the network interface Snort should monitor (e.g., eth0, ens18, enp0s3)
# You can find this by running 'ip a' or 'ifconfig'
MONITOR_INTERFACE="eth0" # <--- IMPORTANT: SET YOUR NETWORK INTERFACE HERE

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
log_info "Starting 11_ids_snort_setup.sh: Snort IDS Setup."

# Check if MONITOR_INTERFACE is set
if [ "$MONITOR_INTERFACE" = "eth0" ]; then
    log_warn "MONITOR_INTERFACE is set to default 'eth0'. Please verify this is the correct network interface for your server (e.g., by running 'ip a')."
    read -p "Press Enter to continue or Ctrl+C to exit and set the correct interface."
fi

# 1. Install Snort and its dependencies
log_info "Installing Snort and its dependencies..."
if ! command -v snort &> /dev/null; then
    apt update -y || log_error "Failed to update package lists."
    # Snort requires build tools and libraries
    apt install -y build-essential libpcap-dev libpcre3-dev libdumbnet-dev libdaq-dev || log_error "Failed to install Snort build dependencies."
    apt install -y snort || log_error "Failed to install Snort."
    log_success "Snort installed."
else
    log_info "Snort is already installed."
fi

# 2. Initial configuration of Snort
log_info "Configuring Snort..."
SNORT_CONF="/etc/snort/snort.conf"
SNORT_DEFAULTS="/etc/default/snort"

# Backup original Snort config
cp "$SNORT_CONF" "${SNORT_CONF}.bak_$(date +%Y%m%d%H%M%S)"
cp "$SNORT_DEFAULTS" "${SNORT_DEFAULTS}.bak_$(date +%Y%m%d%H%M%S)"

# Edit snort.conf
log_info "Editing $SNORT_CONF..."
# Set HOME_NET (assuming your server's local network is the home network)
# You might need to adjust this to your actual internal network range, e.g., "192.168.1.0/24"
# For a single server, often just "any" or the server's local IP.
# We'll use "any" for simplicity in this script, but recommend hardening later.
ensure_line "$SNORT_CONF" "ipvar HOME_NET any" "ipvar HOME_NET any" # Or "ipvar HOME_NET [\"10.0.0.0/8\", \"172.16.0.0/12\", \"192.168.0.0/16\"]"

# Set EXTERNAL_NET
ensure_line "$SNORT_CONF" "ipvar EXTERNAL_NET any" "ipvar EXTERNAL_NET any"

# Ensure rule paths are correct (often default)
ensure_line "$SNORT_CONF" "var RULE_PATH ../rules" "var RULE_PATH ../rules"
ensure_line "$SNORT_CONF" "var SO_RULE_PATH ../so_rules" "var SO_RULE_PATH ../so_rules"
ensure_line "$SNORT_CONF" "var PREPROC_RULE_PATH ../preproc_rules" "var PREPROC_RULE_PATH ../preproc_rules"
ensure_line "$SNORT_CONF" "var WHITE_LIST_PATH ../rules" "var WHITE_LIST_PATH ../rules"
ensure_line "$SNORT_CONF" "var BLACK_LIST_PATH ../rules" "var BLACK_LIST_PATH ../rules"

# Include local rules file
if ! grep -q "include \$RULE_PATH/local.rules" "$SNORT_CONF"; then
    echo "include \$RULE_PATH/local.rules" | tee -a "$SNORT_CONF" || log_warn "Failed to add local.rules include."
fi

# Create local.rules file if it doesn't exist
if [ ! -f "/etc/snort/rules/local.rules" ]; then
    touch /etc/snort/rules/local.rules || log_error "Failed to create /etc/snort/rules/local.rules."
    log_info "Created /etc/snort/rules/local.rules for custom rules."
fi

# Edit /etc/default/snort
log_info "Editing $SNORT_DEFAULTS..."
ensure_line "$SNORT_DEFAULTS" "^#\?INTERFACE=.*" "INTERFACE=\"$MONITOR_INTERFACE\""
ensure_line "$SNORT_DEFAULTS" "^#\?ALERTMODE=.*" "ALERTMODE=FAST" # Or FULL, CONSOLE
ensure_line "$SNORT_DEFAULTS" "^#\?LOGDIR=.*" "LOGDIR=/var/log/snort"
ensure_line "$SNORT_DEFAULTS" "^#\?CMD_LINE_ARGS=.*" "CMD_LINE_ARGS=\"-A console\"" # For initial testing, logs to console
# For production, you'd configure logging to a file or syslog and then forward with Promtail/Fluentd

# Create Snort log directory if it doesn't exist
mkdir -p /var/log/snort || log_error "Failed to create /var/log/snort."
chown -R snort:snort /var/log/snort || log_error "Failed to set ownership for /var/log/snort."
chmod -R 755 /var/log/snort || log_error "Failed to set permissions for /var/log/snort."

log_success "Snort configuration updated."

# 3. Download and update Snort rules (requires Oinkcode for registered rules)
log_info "Updating Snort rules (using default rules, consider registering for Snort Subscriber Rules)..."
# Snort community rules are typically included with the package or updated by the package manager.
# For official Snort rules (Talos), you need an Oinkcode and use 'pulledpork' or 'oinkmaster'.
# This script will not automate Oinkcode setup due to personal key requirements.
log_warn "To get the latest official Snort rules, you need to register at snort.org to get an Oinkcode and use a tool like 'pulledpork' or 'oinkmaster'."
log_warn "Example of manual rule update (after installing pulledpork and configuring it with your Oinkcode): sudo pulledpork.pl -c /etc/pulledpork/pulledpork.conf -k"

# 4. Set up Snort to run as a service (IDS mode)
log_info "Enabling and starting Snort service..."
systemctl enable snort || log_error "Failed to enable Snort service."
systemctl start snort || log_error "Failed to start Snort service. Check /var/log/syslog or 'journalctl -xeu snort'."
log_success "Snort IDS installed and running."
log_warn "Verify Snort is running and monitoring by checking 'systemctl status snort' and logs in /var/log/snort."
log_warn "For production, integrate Snort logs into your centralized logging system (Loki/OpenSearch) using Promtail or Fluentd."

log_success "11_ids_snort_setup.sh completed."
