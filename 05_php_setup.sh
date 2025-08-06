#!/bin/bash

# ==============================================================================
# 05_php_setup.sh
# Summary: Installs PHP-FPM and common PHP extensions, and applies basic PHP hardening.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
USERNAME="cbwinslow" # <--- IMPORTANT: CHANGE THIS TO YOUR DESIRED USERNAME
WEB_ROOT="/var/www/html"

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
log_info "Starting 05_php_setup.sh: PHP-FPM Setup and Hardening."

# 1. Install PHP-FPM and common extensions
log_info "Installing PHP-FPM and common PHP extensions..."
PHP_VERSION=$(apt-cache search ^php[0-9]\.[0-9]-fpm$ | grep -oP 'php[0-9]\.[0-9]' | sort -V | tail -1)

if [ -z "$PHP_VERSION" ]; then
    log_warn "Could not determine latest PHP-FPM version. Attempting to install generic php-fpm and extensions."
    if ! dpkg -s php-fpm &> /dev/null; then
        apt install php-fpm php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip php-intl php-common -y || log_error "Failed to install generic PHP components."
    else
        log_info "Generic php-fpm is already installed. Ensuring extensions are present."
        apt install php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip php-intl php-common -y || log_error "Failed to install generic PHP extensions."
    fi
    PHP_FPM_SERVICE="php-fpm" # Fallback service name
else
    log_info "Detected PHP version: $PHP_VERSION. Installing $PHP_VERSION-fpm and extensions..."
    if ! dpkg -s "$PHP_VERSION"-fpm &> /dev/null; then
        apt install "$PHP_VERSION"-fpm "$PHP_VERSION"-mysql "$PHP_VERSION"-cli "$PHP_VERSION"-curl "$PHP_VERSION"-gd "$PHP_VERSION"-mbstring "$PHP_VERSION"-xml "$PHP_VERSION"-zip "$PHP_VERSION"-intl "$PHP_VERSION"-common -y || log_error "Failed to install PHP components for $PHP_VERSION."
    else
        log_info "$PHP_VERSION-fpm is already installed. Ensuring extensions are present."
        apt install "$PHP_VERSION"-mysql "$PHP_VERSION"-cli "$PHP_VERSION"-curl "$PHP_VERSION"-gd "$PHP_VERSION"-mbstring "$PHP_VERSION"-xml "$PHP_VERSION"-zip "$PHP_VERSION"-intl "$PHP_VERSION"-common -y || log_error "Failed to install PHP extensions for $PHP_VERSION."
    fi
    PHP_FPM_SERVICE="$PHP_VERSION-fpm"
fi

systemctl start "$PHP_FPM_SERVICE" || log_error "Failed to start $PHP_FPM_SERVICE."
systemctl enable "$PHP_FPM_SERVICE" || log_error "Failed to enable "$PHP_FPM_SERVICE" on boot."
log_success "PHP-FPM and common extensions installed."

# 2. Set web root permissions and ownership
log_info "Setting initial web root permissions for user '$USERNAME' and 'www-data' group..."
# Add user to www-data group if not already
if ! id -nG "$USERNAME" | grep -qw "www-data"; then
    log_info "Adding user '$USERNAME' to 'www-data' group..."
    usermod -aG www-data "$USERNAME" || log_error "Failed to add user to www-data group."
    log_warn "Please log out and back in as '$USERNAME' for group changes to take effect!"
else
    log_info "User '$USERNAME' is already in 'www-data' group."
fi

# Ensure web root exists
mkdir -p "$WEB_ROOT"

log_info "Setting ownership of $WEB_ROOT to '$USERNAME:www-data'..."
chown -R "$USERNAME":www-data "$WEB_ROOT" || log_error "Failed to set ownership of $WEB_ROOT."

log_info "Setting directory permissions in $WEB_ROOT to 775 (rwx for owner/group, rx for others)..."
find "$WEB_ROOT" -type d -exec chmod 775 {} \; || log_error "Failed to set directory permissions in $WEB_ROOT."

log_info "Setting file permissions in $WEB_ROOT to 664 (rw for owner/group, r for others)..."
find "$WEB_ROOT" -type f -exec chmod 664 {} \; || log_error "Failed to set file permissions in $WEB_ROOT."
log_success "Web root permissions configured."

# 3. Apply basic PHP-FPM hardening settings
log_info "Applying basic PHP-FPM hardening settings..."
PHP_FPM_POOL_CONFIG="/etc/php/$PHP_VERSION/fpm/pool.d/www.conf" # Default for Ubuntu

if [ -f "$PHP_FPM_POOL_CONFIG" ]; then
    log_info "Setting PHP-FPM user and group to '$USERNAME' and 'www-data' in pool config..."
    ensure_line "$PHP_FPM_POOL_CONFIG" "^user = www-data" "user = $USERNAME"
    ensure_line "$PHP_FPM_POOL_CONFIG" "^group = www-data" "group = www-data"
    log_success "PHP-FPM pool user/group set to $USERNAME:www-data."
else
    log_warn "PHP-FPM pool configuration file not found at $PHP_FPM_POOL_CONFIG. Skipping pool hardening."
fi

PHP_INI_PATH="/etc/php/$PHP_VERSION/fpm/php.ini" # Adjust path if PHP_VERSION is empty or different
if [ -f "$PHP_INI_PATH" ]; then
    log_info "Disabling expose_php..."
    ensure_line "$PHP_INI_PATH" "^expose_php = On" "expose_php = Off"

    log_info "Disabling display_errors and enabling log_errors..."
    ensure_line "$PHP_INI_PATH" "^display_errors = On" "display_errors = Off"
    ensure_line "$PHP_INI_PATH" "^;*\s*log_errors = Off" "log_errors = On"
    # Ensure error_log path exists and is writable by www-data
    if ! grep -q "^error_log =" "$PHP_INI_PATH"; then
        echo "error_log = /var/log/php_errors.log" | tee -a "$PHP_INI_PATH"
    fi
    # Ensure the log file exists and has correct permissions
    touch /var/log/php_errors.log && chown www-data:www-data /var/log/php_errors.log || log_warn "Could not create/set ownership for php_errors.log"

    log_info "Disabling dangerous PHP functions..."
    DISABLED_FUNCTIONS="exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,symlink,link,dl,pcntl_exec,pcntl_fork,pcntl_signal,posix_getpwuid,posix_kill,posix_mkfifo,posix_setpgid,posix_setsid,posix_setuid,posix_setgid,posix_setegid,posix_seteuid,posix_setgpid"
    ensure_line "$PHP_INI_PATH" "^disable_functions\s*=.*" "disable_functions = $DISABLED_FUNCTIONS"

    log_info "Setting open_basedir for PHP-FPM..."
    ensure_line "$PHP_INI_PATH" "^open_basedir\s*=.*" "open_basedir = $WEB_ROOT/:/tmp/"

    log_info "Restarting $PHP_FPM_SERVICE to apply PHP.ini changes..."
    systemctl restart "$PHP_FPM_SERVICE" || log_error "Failed to restart $PHP_FPM_SERVICE."
    log_success "Basic PHP-FPM hardening applied."
else
    log_warn "PHP.ini file not found at $PHP_INI_PATH. Skipping PHP.ini hardening."
fi

# Note: Nginx restart is now handled by 04_web_server_caddy.sh or 17_reverse_proxy_traefik_cloudflare.sh if using Traefik.
# If using Caddy with PHP-FPM, ensure Caddy is configured to use the PHP-FPM socket.

log_success "05_php_setup.sh completed."
