#!/bin/bash

# -----------------------------------------------------------------------------
# High-Level Configuration for Supabase Super Stack
# -----------------------------------------------------------------------------
# This file contains the main configuration variables for your deployment.
# Edit these values to match your environment.
# -----------------------------------------------------------------------------

# --- Domain and Email ---
# The primary domain you will use for all services.
# IMPORTANT: You must own this domain and be able to configure its DNS.
export DOMAIN="your-domain.com"

# The email address to use for Let's Encrypt SSL certificate registration.
export LETSENCRYPT_EMAIL="your-email@your-domain.com"


# --- Installation Directories ---
# The root directory for all backend services and configurations.
# Standard for third-party services.
export APP_ROOT="/opt/supabase-super-stack"

# The root directory for the web application frontend.
# Standard for web-facing applications.
export WEB_ROOT="/var/www/html/super-stack"


# --- Application Choices ---
# In the future, you could add choices for frameworks or databases here.
# For now, we are using Next.js and the standard stack.
# export FRONTEND_FRAMEWORK="nextjs"


# --- Security ---
# A password for the Traefik dashboard basic authentication.
# Change this to a strong password.
export TRAEFIK_ADMIN_PASSWORD="your-secure-traefik-password"

