#!/bin/bash

# ==============================================================================
# 10_antivirus_setup.sh
# Summary: Installs and configures an open-source antivirus solution (ClamAV)
#          for basic server-side scanning.
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
log_info "Starting 10_antivirus_setup.sh: ClamAV Antivirus Setup."

# 1. Install ClamAV and clamav-daemon
log_info "Installing ClamAV and clamav-daemon..."
if ! dpkg -s clamav clamav-daemon &> /dev/null; then
    apt install clamav clamav-daemon -y || log_error "Failed to install ClamAV."
    log_success "ClamAV installed."
else
    log_info "ClamAV is already installed."
fi

# 2. Initial update of virus definitions
log_info "Updating ClamAV virus definitions (this may take a while)..."
# Stop clamav-freshclam service temporarily to allow manual freshclam run
systemctl stop clamav-freshclam || log_warn "Failed to stop clamav-freshclam service (might not be running)."
freshclam || log_error "Failed to update ClamAV virus definitions. Check internet connectivity or ClamAV logs."
log_success "ClamAV virus definitions updated."

# 3. Enable and start clamav-daemon service
log_info "Starting and enabling clamav-daemon service..."
systemctl enable clamav-daemon || log_error "Failed to enable clamav-daemon."
systemctl start clamav-daemon || log_error "Failed to start clamav-daemon."
log_success "ClamAV daemon running."

# 4. Set up a basic cron job for daily virus definition updates
log_info "Setting up a cron job for daily ClamAV virus definition updates..."
CRON_JOB="0 3 * * * /usr/bin/freshclam --quiet" # Daily at 3 AM
(crontab -l 2>/dev/null | grep -Fq "$CRON_JOB") || (echo "$CRON_JOB" | crontab -) || log_error "Failed to set up freshclam cron job."
log_success "Daily freshclam cron job configured."

log_warn "To perform a full scan of your home directory, run: 'clamscan -r /home/$USERNAME'"
log_warn "For more detailed configuration, refer to /etc/clamav/clamd.conf and /etc/clamav/freshclam.conf."

log_success "10_antivirus_setup.sh completed."
