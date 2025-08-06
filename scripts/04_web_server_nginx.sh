#!/bin/bash

# ==============================================================================
# 04_web_server_caddy.sh
# Summary: Installs and configures the Caddy web server, including support for plugins.
#          Caddy automatically handles HTTPS, which simplifies setup.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
USERNAME="cbwinslow" # <--- IMPORTANT: CHANGE THIS TO YOUR DESIRED USERNAME
WEB_ROOT="/var/www/html" # Default web root for Caddy

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
log_info "Starting 04_web_server_caddy.sh: Caddy Web Server Setup."

# 1. Install Caddy
log_info "Installing Caddy web server..."
if ! command -v caddy &> /dev/null; then
    log_info "Adding Caddy's official GPG key and APT repository..."
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https || log_error "Failed to install keyrings."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg || log_error "Failed to add Caddy GPG key."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list || log_error "Failed to add Caddy APT repository."
    apt update -y || log_error "Failed to update apt lists after adding Caddy repo."
    apt install caddy -y || log_error "Failed to install Caddy."
    log_success "Caddy installed."
else
    log_info "Caddy is already installed."
fi

# 2. Configure Caddyfile for a basic web root
log_info "Configuring Caddyfile for web root: $WEB_ROOT..."
CADDYFILE="/etc/caddy/Caddyfile"

# Backup original Caddyfile
cp "$CADDYFILE" "${CADDYFILE}.bak_$(date +%Y%m%d%H%M%S)"

# Clear existing Caddyfile and add basic configuration
log_info "Creating/overwriting basic Caddyfile configuration."
cat <<EOF > "$CADDYFILE"
# The Caddyfile is an easy way to configure your Caddy web server.
#
# For a full reference of Caddyfile syntax and features,
# see https://caddyserver.com/docs/caddyfile
#
# For a practical guide to getting started, see our tutorials:
# https://caddyserver.com/docs/tutorials

:80 {
    # Serve static files from the /var/www/html directory
    root * $WEB_ROOT
    file_server

    # Enable PHP-FPM if needed (uncomment and adjust path)
    # php_fastcgi unix//run/php/php-fpm.sock
}

# Example for a domain with automatic HTTPS:
# yourdomain.com {
#     root * $WEB_ROOT
#     file_server
#     php_fastcgi unix//run/php/php-fpm.sock
# }
EOF
log_success "Basic Caddyfile configured."

# 3. Ensure web root exists and has correct permissions
log_info "Ensuring web root directory '$WEB_ROOT' exists and has correct permissions..."
mkdir -p "$WEB_ROOT" || log_error "Failed to create web root directory."
chown -R "$USERNAME":www-data "$WEB_ROOT" || log_error "Failed to set ownership for web root."
chmod -R 775 "$WEB_ROOT" || log_error "Failed to set permissions for web root directories."
find "$WEB_ROOT" -type f -exec chmod 664 {} \; || log_error "Failed to set permissions for web root files."
log_success "Web root permissions hardened."

# 4. Start and enable Caddy service
log_info "Starting Caddy service..."
systemctl start caddy || log_error "Failed to start Caddy."
log_info "Enabling Caddy to start on boot..."
systemctl enable caddy || log_error "Failed to enable Caddy on boot."
log_success "Caddy installed and running. Test by visiting http://YOUR_SERVER_IP_ADDRESS"
log_warn "For automatic HTTPS, edit /etc/caddy/Caddyfile with your domain name and ensure DNS points to your server."
log_warn "To install Caddy with specific plugins, you might need to build Caddy from source or use a custom Docker image."

log_success "04_web_server_caddy.sh completed."
