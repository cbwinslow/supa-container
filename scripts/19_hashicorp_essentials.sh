#!/bin/bash

# ==============================================================================
# 19_hashicorp_essentials_docker.sh
# Summary: Installs HashiCorp Vault (secrets management) and Consul (service discovery)
#          via Docker Compose.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# IMPORTANT: Docker must be installed first (from 12_docker_setup.sh).
# IMPORTANT: This script sets up Vault in 'dev' mode for simplicity.
#            For production, a more robust setup (e.g., Raft storage, TLS) is required.
# ==============================================================================

# --- Global Variables ---
HASHICORP_DIR="/opt/hashicorp-docker"
VAULT_DATA_DIR="$HASHICORP_DIR/vault_data"
VAULT_CONFIG_DIR="$HASHICORP_DIR/vault_config"
CONSUL_DATA_DIR="$HASHICORP_DIR/consul_data"
CONSUL_CONFIG_DIR="$HASHICORP_DIR/consul_config"

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 19_hashicorp_essentials_docker.sh: HashiCorp Essentials (Vault & Consul Docker) Setup."

# Ensure Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please run 12_docker_setup.sh first."
fi

# Create directories for data persistence and configuration
log_info "Creating HashiCorp data and config directories..."
mkdir -p "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR" || log_error "Failed to create Vault directories."
mkdir -p "$CONSUL_DATA_DIR" "$CONSUL_CONFIG_DIR" || log_error "Failed to create Consul directories."
chmod 777 "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR" "$CONSUL_DATA_DIR" "$CONSUL_CONFIG_DIR" || log_warn "Failed to set permissions for HashiCorp directories (might need manual adjustment)."
log_success "HashiCorp directories created."

# --- Vault Setup (Docker Compose) ---
log_info "Setting up HashiCorp Vault via Docker Compose (dev mode)..."

# Create Vault configuration file (for dev mode)
VAULT_HCL_CONFIG="$VAULT_CONFIG_DIR/vault.hcl"
if [ ! -f "$VAULT_HCL_CONFIG" ]; then
    log_info "Creating Vault HCL configuration file: $VAULT_HCL_CONFIG"
    cat <<EOF > "$VAULT_HCL_CONFIG"
storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = "true" # Disable TLS for dev mode, enable for production
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
EOF
    log_success "Vault HCL configuration created."
else
    log_info "Vault HCL configuration file already exists. Skipping creation."
fi

# Create Vault Docker Compose file
VAULT_COMPOSE_FILE="$HASHICORP_DIR/vault-compose.yml"
if [ ! -f "$VAULT_COMPOSE_FILE" ]; then
    log_info "Creating Vault Docker Compose file: $VAULT_COMPOSE_FILE"
    cat <<EOF > "$VAULT_COMPOSE_FILE"
version: '3.8'
services:
  vault:
    image: hashicorp/vault:latest
    container_name: vault
    restart: unless-stopped
    ports:
      - "8200:8200" # Vault HTTP API
    volumes:
      - "$VAULT_DATA_DIR:/vault/file"
      - "$VAULT_CONFIG_DIR:/vault/config:ro"
    environment:
      - VAULT_LOCAL_CONFIG='{"storage": {"file": {"path": "/vault/file"}}, "listener": {"tcp": {"address": "0.0.0.0:8200", "tls_disable": "true"}}, "api_addr": "http://0.0.0.0:8200", "cluster_addr": "http://0.0.0.0:8201", "ui": true}'
      # Alternatively, use command to specify config file:
      # command: "server -config=/vault/config/vault.hcl"
    cap_add:
      - IPC_LOCK # Required for Vault to lock memory
    networks:
      - hashicorp_network
      - web # For Traefik if you want to expose Vault UI/API

networks:
  hashicorp_network:
    driver: bridge
  web:
    external: true # Connect to Traefik's external network
EOF
    log_success "Vault Docker Compose file created."
    log_warn "To start Vault, navigate to '$HASHICORP_DIR' and run: 'docker compose -f vault-compose.yml up -d'"
    log_warn "Vault UI/API is available on port 8200 (http://localhost:8200)."
    log_warn "IMPORTANT: Vault is running in insecure 'dev' mode. For production, you MUST configure TLS, a proper storage backend (e.g., Raft), and unseal process."
    log_warn "Once running, you'll need to initialize and unseal Vault. For dev mode, it's often auto-unsealed, but for production, manually run 'docker exec -it vault vault operator init' and 'vault operator unseal'."
else
    log_info "Vault Docker Compose file already exists. Skipping creation."
fi

# --- Consul Setup (Docker Compose) ---
log_info "Setting up HashiCorp Consul via Docker Compose..."

# Create Consul configuration file
CONSUL_JSON_CONFIG="$CONSUL_CONFIG_DIR/consul.json"
if [ ! -f "$CONSUL_JSON_CONFIG" ]; then
    log_info "Creating Consul JSON configuration file: $CONSUL_JSON_CONFIG"
    cat <<EOF > "$CONSUL_JSON_CONFIG"
{
  "datacenter": "dc1",
  "data_dir": "/consul/data",
  "log_level": "INFO",
  "node_name": "consul-server-1",
  "server": true,
  "bootstrap_expect": 1,
  "ui": true,
  "client_addr": "0.0.0.0",
  "bind_addr": "0.0.0.0",
  "ports": {
    "http": 8500,
    "grpc": 8502,
    "dns": 8600
  }
}
EOF
    log_success "Consul JSON configuration created."
else
    log_info "Consul JSON configuration file already exists. Skipping creation."
fi

# Create Consul Docker Compose file
CONSUL_COMPOSE_FILE="$HASHICORP_DIR/consul-compose.yml"
if [ ! -f "$CONSUL_COMPOSE_FILE" ]; then
    log_info "Creating Consul Docker Compose file: $CONSUL_COMPOSE_FILE"
    cat <<EOF > "$CONSUL_COMPOSE_FILE"
version: '3.8'
services:
  consul:
    image: hashicorp/consul:latest
    container_name: consul
    restart: unless-stopped
    ports:
      - "8500:8500" # HTTP API and UI
      - "8600:8600/udp" # DNS
      - "8600:8600/tcp" # DNS
    volumes:
      - "$CONSUL_DATA_DIR:/consul/data"
      - "$CONSUL_CONFIG_DIR:/consul/config:ro"
    command: "agent -server -ui -bootstrap-expect=1 -client=0.0.0.0 -bind=0.0.0.0 -config-dir=/consul/config"
    networks:
      - hashicorp_network
      - web # For Traefik if you want to expose Consul UI/API

networks:
  hashicorp_network:
    external: true # Use the shared HashiCorp network
  web:
    external: true # Connect to Traefik's external network
EOF
    log_success "Consul Docker Compose file created."
    log_warn "To start Consul, navigate to '$HASHICORP_DIR' and run: 'docker compose -f consul-compose.yml up -d'"
    log_warn "Consul UI/API is available on port 8500 (http://localhost:8500)."
    log_warn "For production, consider setting up a multi-node Consul cluster and securing it with TLS."
else
    log_info "Consul Docker Compose file already exists. Skipping creation."
fi

log_success "19_hashicorp_essentials_docker.sh completed."
