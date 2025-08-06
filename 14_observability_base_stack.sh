#!/bin/bash

# ==============================================================================
# 14_observability_base_stack.sh
# Summary: Sets up the core observability stack: Prometheus, Grafana, Loki,
#          and Promtail via Docker Compose.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# IMPORTANT: Docker must be installed first (from 12_docker_setup.sh).
# ==============================================================================

# --- Global Variables ---
OBSERVABILITY_DIR="/opt/observability-stack"
PROMETHEUS_DATA_DIR="$OBSERVABILITY_DIR/prometheus_data"
LOKI_DATA_DIR="$OBSERVABILITY_DIR/loki_data"
GRAFANA_DATA_DIR="$OBSERVABILITY_DIR/grafana_data"
PROMTAIL_POSITIONS_FILE="$OBSERVABILITY_DIR/promtail_positions.yaml"

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 14_observability_base_stack.sh: Prometheus, Grafana, Loki, Promtail (Docker) Setup."

# Ensure Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please run 12_docker_setup.sh first."
fi

# Create directories for data persistence
log_info "Creating data directories for Prometheus, Loki, Grafana: $PROMETHEUS_DATA_DIR, $LOKI_DATA_DIR, $GRAFANA_DATA_DIR"
mkdir -p "$PROMETHEUS_DATA_DIR" "$LOKI_DATA_DIR" "$GRAFANA_DATA_DIR" || log_error "Failed to create observability data directories."
chmod 777 "$PROMETHEUS_DATA_DIR" "$LOKI_DATA_DIR" "$GRAFANA_DATA_DIR" || log_warn "Failed to set permissions for observability directories (might need manual adjustment)."
log_success "Observability data directories created."

# Create Promtail positions file
touch "$PROMTAIL_POSITIONS_FILE" || log_error "Failed to create Promtail positions file."
chmod 666 "$PROMTAIL_POSITIONS_FILE" || log_warn "Failed to set permissions for Promtail positions file."

# --- Prometheus Configuration ---
PROMETHEUS_CONFIG_FILE="$OBSERVABILITY_DIR/prometheus.yml"
if [ ! -f "$PROMETHEUS_CONFIG_FILE" ]; then
    log_info "Creating Prometheus configuration file: $PROMETHEUS_CONFIG_FILE"
    cat <<EOF > "$PROMETHEUS_CONFIG_FILE"
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090'] # Prometheus scrapes itself

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['host.docker.internal:9100'] # Scrape host's node_exporter
        # On Linux, host.docker.internal might not resolve. Use the host's actual IP if needed.
        # Example: targets: ['<YOUR_SERVER_IP>:9100']
EOF
    log_success "Prometheus configuration created."
else
    log_info "Prometheus configuration file already exists. Skipping creation."
fi

# --- Loki Configuration ---
LOKI_CONFIG_FILE="$OBSERVABILITY_DIR/loki-config.yaml"
if [ ! -f "$LOKI_CONFIG_FILE" ]; then
    log_info "Creating Loki configuration file: $LOKI_CONFIG_FILE"
    cat <<EOF > "$LOKI_CONFIG_FILE"
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9095

common:
  path_prefix: /var/lib/loki
  storage_config:
    boltdb_shipper:
      active_index_directory: /var/lib/loki/boltdb-shipper-active
      cache_location: /var/lib/loki/boltdb-shipper-cache
      cache_ttl: 24h
      shared_store: filesystem
    filesystem:
      directory: /var/lib/loki/chunks
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-27
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      period: 24h
      index:
        prefix: index_
        period: 24h

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s

compactor:
  working_directory: /var/lib/loki/compactor
  shared_store: filesystem
EOF
    log_success "Loki configuration created."
else
    log_info "Loki configuration file already exists. Skipping creation."
fi

# --- Promtail Configuration ---
PROMTAIL_CONFIG_FILE="$OBSERVABILITY_DIR/promtail-config.yaml"
if [ ! -f "$PROMTAIL_CONFIG_FILE" ]; then
    log_info "Creating Promtail configuration file: $PROMTAIL_CONFIG_FILE"
    cat <<EOF > "$PROMTAIL_CONFIG_FILE"
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: $PROMTAIL_POSITIONS_FILE

clients:
  - url: http://loki:3100/loki/api/v1/push # Connects to Loki service within Docker network

scrape_configs:
  - job_name: system_logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*.log
          # Add more specific log paths here as needed, e.g., Nginx, Caddy, PHP-FPM
          # __path__: /var/log/nginx/*.log
          # __path__: /var/log/caddy/*.log
          # __path__: /var/log/php_errors.log
EOF
    log_success "Promtail configuration created."
else
    log_info "Promtail configuration file already exists. Skipping creation."
fi

# --- Docker Compose file for the stack ---
OBSERVABILITY_COMPOSE_FILE="$OBSERVABILITY_DIR/docker-compose.yml"

if [ ! -f "$OBSERVABILITY_COMPOSE_FILE" ]; then
    log_info "Creating Docker Compose file for Prometheus, Grafana, Loki, Promtail: $OBSERVABILITY_COMPOSE_FILE"
    cat <<EOF > "$OBSERVABILITY_COMPOSE_FILE"
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090" # Prometheus UI
    volumes:
      - "$PROMETHEUS_CONFIG_FILE:/etc/prometheus/prometheus.yml:ro"
      - "$PROMETHEUS_DATA_DIR:/prometheus"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    networks:
      - observability_network
      - web # For Traefik if you want to expose Prometheus UI

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000" # Grafana UI
    volumes:
      - "$GRAFANA_DATA_DIR:/var/lib/grafana"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin # <--- IMPORTANT: CHANGE THIS FOR PRODUCTION
      - GF_PATHS_PROVISIONING=/etc/grafana/provisioning
      - GF_AUTH_ANONYMOUS_ENABLED=true # For easy initial access, disable for production
    networks:
      - observability_network
      - web # For Traefik if you want to expose Grafana UI
    depends_on:
      - prometheus
      - loki

  loki:
    image: grafana/loki:latest
    container_name: loki
    restart: unless-stopped
    ports:
      - "3100:3100" # Loki HTTP/HTTPS
      - "9095:9095" # Loki gRPC
    volumes:
      - "$LOKI_CONFIG_FILE:/etc/loki/config.yaml:ro"
      - "$LOKI_DATA_DIR:/var/lib/loki"
    command: -config.file=/etc/loki/config.yaml
    networks:
      - observability_network

  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    restart: unless-stopped
    volumes:
      - "$PROMTAIL_CONFIG_FILE:/etc/promtail/config.yaml:ro"
      - /var/log:/var/log:ro # Mount host logs
      - /var/lib/docker/containers:/var/lib/docker/containers:ro # For Docker container logs
      - "$PROMTAIL_POSITIONS_FILE:/tmp/positions.yaml"
    command: -config.file=/etc/promtail/config.yaml
    networks:
      - observability_network
    depends_on:
      - loki

networks:
  observability_network:
    driver: bridge
  web:
    external: true # Connect to Traefik's external network
EOF
    log_success "Observability Docker Compose file created."
    log_warn "To start the observability stack, navigate to '$OBSERVABILITY_DIR' and run: 'docker compose up -d'"
    log_warn "Remember to change Grafana's default admin password ('admin'/'admin') for production!"
    log_warn "Prometheus UI: http://localhost:9090"
    log_warn "Grafana UI: http://localhost:3000"
    log_warn "Loki API: http://localhost:3100"
    log_warn "Ensure UFW allows access to these ports from trusted IPs, or expose them via Traefik."
else
    log_info "Observability Docker Compose file already exists. Skipping creation."
fi

log_success "14_observability_base_stack.sh completed."
