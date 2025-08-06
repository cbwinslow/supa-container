#!/bin/bash

# ==============================================================================
# 15_log_analysis_opensearch_docker.sh
# Summary: Installs OpenSearch and OpenSearch Dashboards via Docker Compose
#          for advanced log analysis.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# IMPORTANT: Docker must be installed first (from 12_docker_setup.sh).
# ==============================================================================

# --- Global Variables ---
OPENSEARCH_DIR="/opt/opensearch-docker"
OPENSEARCH_DATA_DIR="$OPENSEARCH_DIR/data"
OPENSEARCH_DASHBOARDS_DATA_DIR="$OPENSEARCH_DIR/dashboards_data"
OPENSEARCH_LOG_DIR="$OPENSEARCH_DIR/logs"

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 15_log_analysis_opensearch_docker.sh: OpenSearch & Dashboards (Docker) Setup."

# Ensure Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please run 12_docker_setup.sh first."
fi

# Create directories for data persistence
log_info "Creating OpenSearch data directories: $OPENSEARCH_DATA_DIR, $OPENSEARCH_DASHBOARDS_DATA_DIR, $OPENSEARCH_LOG_DIR"
mkdir -p "$OPENSEARCH_DATA_DIR" "$OPENSEARCH_DASHBOARDS_DATA_DIR" "$OPENSEARCH_LOG_DIR" || log_error "Failed to create OpenSearch directories."
chmod 777 "$OPENSEARCH_DATA_DIR" "$OPENSEARCH_DASHBOARDS_DATA_DIR" "$OPENSEARCH_LOG_DIR" || log_warn "Failed to set permissions for OpenSearch directories (might need manual adjustment)."
log_success "OpenSearch data directories created."

# Create Docker Compose file for OpenSearch and Dashboards
OPENSEARCH_COMPOSE_FILE="$OPENSEARCH_DIR/docker-compose.yml"

if [ ! -f "$OPENSEARCH_COMPOSE_FILE" ]; then
    log_info "Creating OpenSearch Docker Compose file: $OPENSEARCH_COMPOSE_FILE"
    cat <<EOF > "$OPENSEARCH_COMPOSE_FILE"
version: '3.8'
services:
  opensearch:
    image: opensearchproject/opensearch:2.11.1 # Use a specific version
    container_name: opensearch
    restart: unless-stopped
    environment:
      - cluster.name=opensearch-cluster
      - node.name=opensearch-node1
      - discovery.type=single-node # For single-node setup
      - bootstrap.memory_lock=true
      - OPENSEARCH_JAVA_OPTS="-Xms512m -Xmx512m" # Adjust based on available RAM
      - "OPENSEARCH_INITIAL_ADMIN_PASSWORD=adminpassword" # <--- IMPORTANT: CHANGE THIS FOR PRODUCTION
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - "$OPENSEARCH_DATA_DIR:/usr/share/opensearch/data"
      - "$OPENSEARCH_LOG_DIR:/usr/share/opensearch/logs"
    ports:
      - "9200:9200" # HTTP API
      - "9600:9600" # Transport layer
    networks:
      - opensearch_network

  opensearch-dashboards:
    image: opensearchproject/opensearch-dashboards:2.11.1 # Must match OpenSearch version
    container_name: opensearch-dashboards
    restart: unless-stopped
    ports:
      - "5601:5601" # Dashboards UI
    environment:
      - OPENSEARCH_HOSTS=["https://opensearch:9200"]
      - "OPENSEARCH_USERNAME=admin"
      - "OPENSEARCH_PASSWORD=adminpassword" # <--- IMPORTANT: CHANGE THIS FOR PRODUCTION
      - "OPENSEARCH_SSL_VERIFICATION_MODE=none" # For initial setup, disable SSL verification to opensearch container
    volumes:
      - "$OPENSEARCH_DASHBOARDS_DATA_DIR:/usr/share/opensearch-dashboards/data"
    networks:
      - opensearch_network
      - web # For Traefik if you want to expose Dashboards UI
    depends_on:
      - opensearch

networks:
  opensearch_network:
    driver: bridge
  web:
    external: true # Connect to Traefik's external network
EOF
    log_success "OpenSearch Docker Compose file created."
    log_warn "To start OpenSearch and Dashboards, navigate to '$OPENSEARCH_DIR' and run: 'docker compose up -d'"
    log_warn "IMPORTANT: Change 'OPENSEARCH_INITIAL_ADMIN_PASSWORD' in the compose file for production!"
    log_warn "OpenSearch API: http://localhost:9200"
    log_warn "OpenSearch Dashboards UI: http://localhost:5601"
    log_warn "Ensure UFW allows access to port 5601 from trusted IPs, or expose it via Traefik."
else
    log_info "OpenSearch Docker Compose file already exists. Skipping creation."
fi

log_success "15_log_analysis_opensearch_docker.sh completed."
