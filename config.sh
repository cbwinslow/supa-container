#!/bin/bash
# Exit on error, undefined variable, and pipe failures
set -euo pipefail

# -----------------------------------------------------------------------------
# Production Configuration for AI-Enhanced Supa Container
# -----------------------------------------------------------------------------
# This file contains the main configuration variables for your deployment.
# Edit these values to match your environment before running deployment scripts.
# -----------------------------------------------------------------------------

# --- Domain and Email Configuration ---
# The primary domain you will use for all services.
# IMPORTANT: You must own this domain and be able to configure its DNS.
# Example: "yourdomain.com" or "example.org"
export DOMAIN="${SUPA_DOMAIN:-opendiscourse.net}"

# The email address to use for Let's Encrypt SSL certificate registration.
# This should be a valid email address you control.
export LETSENCRYPT_EMAIL="${SUPA_EMAIL:-admin@${DOMAIN}}"

# --- Installation Directories ---
# The root directory for all backend services and configurations.
# This is where Docker Compose and all service configurations will be stored.
export APP_ROOT="${SUPA_APP_ROOT:-/opt/supa-container}"

# The root directory for the web application frontend.
# This is where static web assets will be served from.
export WEB_ROOT="${SUPA_WEB_ROOT:-/var/www/html/supa-container}"

# --- Security Configuration ---
# A strong password for the Traefik dashboard basic authentication.
# Change this to a secure password before deployment.
# This will be hashed automatically during deployment.
export TRAEFIK_ADMIN_PASSWORD="${SUPA_TRAEFIK_PASSWORD:-$(openssl rand -base64 32)}"

# --- Advanced Configuration (Optional) ---
# Uncomment and modify these if you need custom settings

# Custom network configuration
# export DOCKER_NETWORK_NAME="supa-container-net"

# Custom database configuration
# export POSTGRES_VERSION="15"
# export NEO4J_VERSION="5"

# Custom resource limits
# export MAX_MEMORY_USAGE="80"  # Percentage
# export MAX_DISK_USAGE="75"    # Percentage

# Monitoring configuration
# export ENABLE_METRICS="true"
# export ENABLE_TRACING="true"
# export ENABLE_LOGGING="true"

# --- Environment Detection ---
# Automatically detect if we're running on Hetzner Cloud
if [ -f /etc/cloud/cloud.cfg.d/90_dpkg.cfg ] && grep -q "hetzner" /etc/cloud/cloud.cfg.d/90_dpkg.cfg 2>/dev/null; then
    export CLOUD_PROVIDER="hetzner"
    export ENABLE_HETZNER_OPTIMIZATIONS="true"
else
    export CLOUD_PROVIDER="generic"
    export ENABLE_HETZNER_OPTIMIZATIONS="false"
fi

# --- Validation Function ---
validate_config() {
    local errors=0
    
    echo "Validating configuration..."
    
    # Check domain format
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        echo "❌ ERROR: Invalid domain format: $DOMAIN"
        errors=$((errors + 1))
    fi
    
    # Check email format
    if [[ ! "$LETSENCRYPT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "❌ ERROR: Invalid email format: $LETSENCRYPT_EMAIL"
        errors=$((errors + 1))
    fi
    
    # Check if running as root for directory creation
    if [ "$EUID" -eq 0 ] && [ ! -d "$APP_ROOT" ]; then
        echo "ℹ️  Will create APP_ROOT directory: $APP_ROOT"
    fi
    
    if [ "$errors" -eq 0 ]; then
        echo "✅ Configuration validation passed"
        return 0
    else
        echo "❌ Configuration validation failed with $errors errors"
        return 1
    fi
}

# --- Display Configuration ---
display_config() {
    echo "=============================================="
    echo "AI-Enhanced Supa Container Configuration"
    echo "=============================================="
    echo "Domain: $DOMAIN"
    echo "Email: $LETSENCRYPT_EMAIL"
    echo "App Root: $APP_ROOT"
    echo "Web Root: $WEB_ROOT"
    echo "Cloud Provider: $CLOUD_PROVIDER"
    echo "=============================================="
}

# Run validation if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    display_config
    validate_config
fi

