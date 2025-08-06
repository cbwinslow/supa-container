#!/bin/bash

# ==============================================================================
# Hetzner Dedicated Server Post-Installation Setup Script
# Author: Gemini
# Date: July 23, 2025
#
# This script automates essential post-installation tasks for a fresh
# Ubuntu 24.04 Hetzner server, including:
# - Ensuring correct SSH key permissions for a non-root user.
# - Hardening SSH configuration (disabling password auth, limiting root login).
# - Updating the system packages.
# - Setting up a basic firewall (UFW).
# - Installing a web server (Nginx).
# - Installing PHP-FPM and common PHP extensions.
# - Installing a database server (MariaDB/MySQL).
# - Installing Node.js.
# - Installing common development tools.
# - Configuring automatic security updates.
# - Installing Fail2Ban for brute-force protection.
# - Setting up time synchronization.
# - Applying basic kernel hardening.
# - Configuring initial web root permissions for development.
# - Applying basic PHP-FPM hardening.
#
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
# Your non-root username with sudo privileges
USERNAME="cbwinslow" # <--- IMPORTANT: CHANGE THIS TO YOUR DESIRED USERNAME

# --- Script Configuration ---
# Set to 'true' to disable password authentication and limit root login (recommended)
# Ensure your SSH key works for the USERNAME before setting this to 'true'!
HARDEN_SSH="true"

# --- Error Handling ---
# Exit immediately if a command exits with a non-zero status.
set -e

# --- Functions ---

# Function to display messages
log_info() {
    echo -e "\n\e[1;34m[INFO]\e[0m $1"
}

# Function to display warnings
log_warn() {
    echo -e "\n\e[1;33m[WARN]\e[0m $1"
}

# Function to display success messages
log_success() {
    echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"
}

# Function to display error messages and exit
log_error() {
    echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2
    exit 1
}

# Function to ensure a line exists or is replaced in a file
# $1: file path
# $2: pattern to search for (regex)
# $3: replacement string (full line)
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

log_info "Starting Hetzner Server Post-Installation Setup..."

# 1. Ensure correct SSH key permissions and ownership for the new user
#    This is critical if the previous copy operation failed or had incorrect permissions.
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

# 2. System Update
log_info "Updating system packages..."
apt update -y || log_error "Failed to update package lists."
apt upgrade -y || log_error "Failed to upgrade packages."
apt autoremove -y || log_error "Failed to remove old packages."
log_success "System packages updated."

# 3. Configure Firewall (UFW)
log_info "Configuring Uncomplicated Firewall (UFW)..."
if ! command -v ufw &> /dev/null; then
    log_info "UFW not found, installing UFW..."
    apt install ufw -y || log_error "Failed to install UFW."
fi

log_info "Allowing OpenSSH (port 22)..."
ufw allow OpenSSH || log_warn "Failed to allow OpenSSH (might already be allowed or UFW not active)."

log_info "Allowing HTTP (port 80) and HTTPS (port 443)..."
ufw allow http || log_warn "Failed to allow HTTP (might already be allowed or UFW not active)."
ufw allow https || log_warn "Failed to allow HTTPS (might already be allowed or UFW not active)."

# Only enable UFW if it's not already enabled
if ! ufw status | grep -q "Status: active"; then
    log_info "Enabling UFW..."
    echo "y" | ufw enable || log_error "Failed to enable UFW."
else
    log_info "UFW is already active."
fi
log_success "UFW enabled and configured."
ufw status verbose

# 4. SSH Hardening (Optional but Recommended)
if [ "$HARDEN_SSH" = "true" ]; then
    log_info "Hardening SSH configuration..."
    SSH_CONFIG="/etc/ssh/sshd_config"

    # Ensure openssh-server is installed before configuring
    if ! dpkg -s openssh-server &> /dev/null; then
        log_info "openssh-server not found, installing it..."
        apt install openssh-server -y || log_error "Failed to install openssh-server. Cannot proceed with SSH hardening."
    fi

    # Backup original SSH config only if a backup for today doesn't exist
    BACKUP_FILE="${SSH_CONFIG}.bak_$(date +%Y%m%d)"
    if [ ! -f "$BACKUP_FILE" ]; then
        log_info "Creating SSH config backup: $BACKUP_FILE"
        cp "$SSH_CONFIG" "$BACKUP_FILE"
    else
        log_info "SSH config backup for today ($BACKUP_FILE) already exists, skipping backup."
    fi

    # Disable password authentication
    log_info "Disabling password authentication..."
    ensure_line "$SSH_CONFIG" "^#\?PasswordAuthentication\s\+yes" "PasswordAuthentication no"

    # Limit root login to key-only
    log_info "Setting PermitRootLogin to prohibit-password..."
    ensure_line "$SSH_CONFIG" "^#\?PermitRootLogin\s\+\(yes\|without-password\|prohibit-password\|forced-commands-only\)" "PermitRootLogin prohibit-password"

    # Disable X11 forwarding if not needed
    log_info "Disabling X11Forwarding..."
    ensure_line "$SSH_CONFIG" "^#\?X11Forwarding\s\+yes" "X11Forwarding no"

    # Disable GSSAPI authentication if not needed
    log_info "Disabling GSSAPIAuthentication..."
    ensure_line "$SSH_CONFIG" "^#\?GSSAPIAuthentication\s\+yes" "GSSAPIAuthentication no"

    # Use a stronger KexAlgorithms and Ciphers (example, adjust as needed)
    # This might vary based on OpenSSH version and desired security level.
    # For Ubuntu 24.04, default ciphers are generally good.
    # Example:
    # ensure_line "$SSH_CONFIG" "^#\?KexAlgorithms\s*=.*" "KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256"
    # ensure_line "$SSH_CONFIG" "^#\?Ciphers\s*=.*" "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"

    log_info "Restarting SSH service to apply changes..."
    # Corrected service name from sshd.service to ssh.service
    systemctl restart ssh || log_error "Failed to restart SSH service. If you get locked out, use Hetzner Rescue System to fix SSH config!"
    log_success "SSH configuration hardened. Test your SSH key login for '$USERNAME' immediately!"
else
    log_warn "SSH hardening skipped. Password authentication and root login might still be enabled. Consider enabling it for production."
fi

# 5. Install Web Server (Nginx)
log_info "Installing Nginx web server..."
if ! command -v nginx &> /dev/null; then
    apt install nginx -y || log_error "Failed to install Nginx."
else
    log_info "Nginx is already installed."
fi
systemctl start nginx || log_error "Failed to start Nginx."
systemctl enable nginx || log_error "Failed to enable Nginx on boot."
log_success "Nginx installed and running. Test by visiting http://YOUR_SERVER_IP_ADDRESS"

# 6. Install PHP-FPM and common extensions
log_info "Installing PHP-FPM and common PHP extensions..."
# Find the latest PHP version available, typically 8.x for Ubuntu 24.04
PHP_VERSION=$(apt-cache search ^php[0-9]\.[0-9]-fpm$ | grep -oP 'php[0-9]\.[0-9]' | sort -V | tail -1)
if [ -z "$PHP_VERSION" ]; then
    log_warn "Could not determine latest PHP-FPM version. Installing php-fpm, php-mysql, php-cli without specific version."
    apt install php-fpm php-mysql php-cli -y || log_error "Failed to install PHP components."
    PHP_FPM_SERVICE="php-fpm" # Fallback service name
else
    log_info "Detected PHP version: $PHP_VERSION. Installing $PHP_VERSION-fpm and extensions..."
    # Check if PHP-FFPM is already installed to avoid redundant installation messages
    if ! dpkg -s "$PHP_VERSION"-fpm &> /dev/null; then
        apt install "$PHP_VERSION"-fpm "$PHP_VERSION"-mysql "$PHP_VERSION"-cli "$PHP_VERSION"-curl "$PHP_VERSION"-gd "$PHP_VERSION"-mbstring "$PHP_VERSION"-xml "$PHP_VERSION"-zip "$PHP_VERSION"-intl "$PHP_VERSION"-common -y || log_error "Failed to install PHP components."
    else
        log_info "$PHP_VERSION-fpm is already installed. Ensuring extensions are present."
        apt install "$PHP_VERSION"-mysql "$PHP_VERSION"-cli "$PHP_VERSION"-curl "$PHP_VERSION"-gd "$PHP_VERSION"-mbstring "$PHP_VERSION"-xml "$PHP_VERSION"-zip "$PHP_VERSION"-intl "$PHP_VERSION"-common -y || log_error "Failed to install PHP extensions."
    fi
    PHP_FPM_SERVICE="$PHP_VERSION-fpm"
fi

systemctl start "$PHP_FPM_SERVICE" || log_error "Failed to start $PHP_FPM_SERVICE."
systemctl enable "$PHP_FPM_SERVICE" || log_error "Failed to enable "$PHP_FPM_SERVICE" on boot."
log_success "PHP-FPM and common extensions installed."
log_warn "Remember to configure Nginx to process PHP files (e.g., in /etc/nginx/sites-available/default or a new site config)."

# 7. Install Database Server (MariaDB/MySQL)
log_info "Installing MariaDB (MySQL compatible) database server..."
if ! command -v mariadb &> /dev/null; then
    apt install mariadb-server -y || log_error "Failed to install MariaDB server."
else
    log_info "MariaDB is already installed."
fi
systemctl start mariadb || log_error "Failed to start MariaDB."
systemctl enable mariadb || log_error "Failed to enable MariaDB on boot."
log_success "MariaDB installed."
log_warn "IMPORTANT: Run 'sudo mysql_secure_installation' manually to secure your database installation!"

# 8. Install Node.js
log_info "Installing Node.js (LTS version)..."
# Check if NodeSource repository is already added
if [ ! -f "/etc/apt/sources.list.d/nodesource.list" ]; then
    log_info "Adding NodeSource APT repository..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - || log_error "Failed to add NodeSource repository."
else
    log_info "NodeSource repository already exists, skipping addition."
fi
if ! command -v node &> /dev/null; then
    apt install nodejs -y || log_error "Failed to install Node.js."
else
    log_info "Node.js is already installed."
fi
log_success "Node.js installed. Verify with 'node -v' and 'npm -v'."

# 9. Install Common Development Tools
log_info "Installing common development tools..."
# apt install is idempotent for already installed packages
apt install build-essential git unzip zip htop curl wget nano vim tmux -y || log_error "Failed to install common dev tools."
log_success "Common development tools installed."

# 10. Configure Automatic Security Updates (Unattended Upgrades)
log_info "Configuring automatic security updates (Unattended Upgrades)..."
if ! dpkg -s unattended-upgrades &> /dev/null; then
    apt install unattended-upgrades -y || log_error "Failed to install unattended-upgrades."
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

# 11. Install Fail2Ban
log_info "Installing Fail2Ban for brute-force protection..."
if ! command -v fail2ban-client &> /dev/null; then
    apt install fail2ban -y || log_error "Failed to install Fail2Ban."
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

# 12. Time Synchronization (NTP/systemd-timesyncd)
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

# 13. Basic Kernel Hardening (sysctl)
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

# 14. Initial Web Root Permissions and Nginx/PHP-FPM Configuration
log_info "Setting initial web root permissions for user '$USERNAME' and 'www-data' group..."
# Add cbwinslow to www-data group if not already
if ! id -nG "$USERNAME" | grep -qw "www-data"; then
    log_info "Adding user '$USERNAME' to 'www-data' group..."
    usermod -aG www-data "$USERNAME" || log_error "Failed to add user to www-data group."
    log_warn "Please log out and back in as '$USERNAME' for group changes to take effect!"
else
    log_info "User '$USERNAME' is already in 'www-data' group."
fi

WEB_ROOT="/var/www/html"
# Ensure web root exists
mkdir -p "$WEB_ROOT"

log_info "Setting ownership of $WEB_ROOT to '$USERNAME:www-data'..."
chown -R "$USERNAME":www-data "$WEB_ROOT" || log_error "Failed to set ownership of $WEB_ROOT."

log_info "Setting directory permissions in $WEB_ROOT to 775 (rwx for owner/group, rx for others)..."
find "$WEB_ROOT" -type d -exec chmod 775 {} \; || log_error "Failed to set directory permissions in $WEB_ROOT."

log_info "Setting file permissions in $WEB_ROOT to 664 (rw for owner/group, r for others)..."
find "$WEB_ROOT" -type f -exec chmod 664 {} \; || log_error "Failed to set file permissions in $WEB_ROOT."
log_success "Web root permissions configured."

log_info "Applying basic PHP-FPM hardening settings..."
# Determine PHP-FPM pool configuration file path
PHP_FPM_POOL_CONFIG="/etc/php/$PHP_VERSION/fpm/pool.d/www.conf" # Default for Ubuntu

if [ -f "$PHP_FPM_POOL_CONFIG" ]; then
    log_info "Setting PHP-FPM user and group to '$USERNAME' and 'www-data'..."
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
    # Add common dangerous functions to disable
    # Note: This list can be expanded based on specific security needs.
    DISABLED_FUNCTIONS="exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,symlink,link,dl,pcntl_exec,pcntl_fork,pcntl_signal,posix_getpwuid,posix_kill,posix_mkfifo,posix_setpgid,posix_setsid,posix_setuid,posix_setgid,posix_setegid,posix_seteuid,posix_setgpid"
    ensure_line "$PHP_INI_PATH" "^disable_functions\s*=.*" "disable_functions = $DISABLED_FUNCTIONS"

    log_info "Setting open_basedir for PHP-FPM..."
    # This restricts PHP to only access files within the web root and /tmp
    ensure_line "$PHP_INI_PATH" "^open_basedir\s*=.*" "open_basedir = $WEB_ROOT/:/tmp/"

    log_info "Restarting $PHP_FPM_SERVICE to apply PHP.ini changes..."
    systemctl restart "$PHP_FPM_SERVICE" || log_error "Failed to restart $PHP_FPM_SERVICE."
    log_success "Basic PHP-FPM hardening applied."
else
    log_warn "PHP.ini file not found at $PHP_INI_PATH. Skipping PHP.ini hardening."
fi

log_info "Restarting Nginx to ensure it picks up any new PHP-FPM socket changes (if applicable)..."
systemctl restart nginx || log_error "Failed to restart Nginx."
log_success "Nginx restarted."

log_success "Hetzner Server Post-Installation Setup Complete!"
log_info "Please remember to:"
log_info "  1. Log out and log back in as '$USERNAME' for full group changes to take effect."
log_info "  2. Run 'sudo mysql_secure_installation' to secure your MariaDB installation."
log_info "  3. Configure Nginx virtual hosts for your specific domains and applications."
log_info "  4. Consider setting up SSL/TLS with Certbot (e.g., 'sudo apt install certbot python3-certbot-nginx' then 'sudo certbot --nginx')."
log_info "  5. Regularly review system logs and security configurations."

