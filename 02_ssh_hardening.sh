#!/bin/bash

# ==============================================================================
# 02_ssh_hardening.sh
# Summary: Focuses solely on securing the SSH daemon configuration.
#          Should be run after 01_system_essentials.sh.
# Author: Gemini
# Date: July 23, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
USERNAME="cbwinslow" # <--- IMPORTANT: CHANGE THIS TO YOUR DESIRED USERNAME
SSH_CONFIG="/etc/ssh/sshd_config"

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
log_info "Starting 02_ssh_hardening.sh: SSH Hardening."

# Backup original SSH config only if a backup for today doesn't exist
BACKUP_FILE="${SSH_CONFIG}.bak_$(date +%Y%m%d)"
if [ ! -f "$BACKUP_FILE" ]; then
    log_info "Creating SSH config backup: $BACKUP_FILE"
    cp "$SSH_CONFIG" "$BACKUP_FILE"
else
    log_info "SSH config backup for today ($BACKUP_FILE) already exists, skipping backup."
fi

# 1. Disable password authentication
log_info "Disabling password authentication..."
ensure_line "$SSH_CONFIG" "^#\?PasswordAuthentication\s\+yes" "PasswordAuthentication no"

# 2. Limit root login to key-only
log_info "Setting PermitRootLogin to prohibit-password..."
ensure_line "$SSH_CONFIG" "^#\?PermitRootLogin\s\+\(yes\|without-password\|prohibit-password\|forced-commands-only\)" "PermitRootLogin prohibit-password"

# 3. Disable X11 forwarding if not needed
log_info "Disabling X11Forwarding..."
ensure_line "$SSH_CONFIG" "^#\?X11Forwarding\s\+yes" "X11Forwarding no"

# 4. Disable GSSAPI authentication if not needed
log_info "Disabling GSSAPIAuthentication..."
ensure_line "$SSH_CONFIG" "^#\?GSSAPIAuthentication\s\+yes" "GSSAPIAuthentication no"

# 5. Restart SSH service to apply changes
log_info "Restarting SSH service to apply changes..."
systemctl restart ssh || log_error "Failed to restart SSH service. If you get locked out, use Hetzner Rescue System to fix SSH config!"
log_success "SSH configuration hardened. Test your SSH key login for '$USERNAME' immediately!"

log_success "02_ssh_hardening.sh completed."
