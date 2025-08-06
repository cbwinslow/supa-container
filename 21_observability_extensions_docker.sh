#!/bin/bash

# ==============================================================================
# 21_observability_extensions_docker.sh
# Summary: Adds extended observability components: Fluentd, OpenTelemetry Collector,
#          Jaeger, Tempo via Docker Compose.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# IMPORTANT: Docker must be installed first (from 12_docker_setup.sh).
# ==============================================================================

# --- Global Variables ---
OBSERVABILITY_EXT_DIR="/opt/observability-extensions"
FLUENTD_CONFIG_DIR="$OBSERVABILITY_EXT_DIR/fluentd_config"
JAEGER_DATA_DIR="$OBSERVABILITY_EXT_DIR/jaeger_data"
TEMPO_DATA_DIR="$OBSERVABILITY_EXT_DIR/tempo_data"

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 21_observability_extensions_docker.sh: Observability Extensions Setup."

# Ensure Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please run 12_docker_setup.sh first."
fi

# Create directories
log_info "Creating observability extension directories..."
mkdir -p "$FLUENTD_CONFIG_DIR" "$JAEGER_DATA_DIR" "$TEMPO_DATA_DIR" || log_error "Failed to create directories."
chmod 777 "$FLUENTD_CONFIG_DIR" "$JAEGER_DATA_DIR" "$TEMPO_DATA_DIR" || log_warn "Failed to set permissions for directories."
log_success "Observability extension directories created."

# --- Fluentd (Log Forwarding) Setup ---
log_info "Setting up Fluentd (Log Forwarding) via Docker Compose..."

# Create Fluentd configuration file
FLUENTD_CONFIG_FILE="$FLUENTD_CONFIG_DIR/fluent.conf"
if [ ! -f "$FLUENTD_CONFIG_FILE" ]; then
    log_info "Creating Fluentd configuration file: $FLUENTD_CONFIG_FILE"
    cat <<EOF > "$FLUENTD_CONFIG_FILE"
<source>
  @type tail
  path /var/log/syslog
  pos_file /var/log/td-agent/syslog.pos
  tag system.syslog
  <parse>
    @type syslog
  </parse>
</source>

# Example: Tail Nginx access logs and send to OpenSearch
<source>
  @type tail
  path /var/log/nginx/access.log
  pos_file /var/log/td-agent/nginx_access.pos
  tag nginx.access
  <parse>
    @type nginx
  </parse>
</source>

# Example: Tail Nginx error logs and send to OpenSearch
<source>
  @type tail
  path /var/log/nginx/error.log
  pos_file /var/log/td-agent/nginx_error.pos
  tag nginx.error
  <parse>
    @type nginx
  </parse>
</source>

# Example: Tail your AI agent's JSON logs
<source>
  @type tail
  path /opt/ai-apps/my_ai_agent/logs/agent.log # <--- ADJUST THIS PATH
  pos_file /var/log/td-agent/ai_agent.pos
  tag ai.agent
  <parse>
    @type json
  </parse>
</source>

# Output to OpenSearch
<match *.**>
  @type opensearch
  host opensearch # Connects to opensearch service within Docker network
  port 9200
  scheme https
  ssl_verify false # For initial setup, disable SSL verification
  user admin
  password adminpassword # <--- IMPORTANT: CHANGE THIS FOR PRODUCTION
  logstash_format true
  logstash_prefix fluentd
  include_tag_key true
  tag_key @log_name
  <buffer>
    @type file
    path /var/log/fluentd-buffer/opensearch
    flush_interval 5s
    chunk_limit_size 10MB
    queue_limit_length 8
    retry_max_interval 30s
    retry_timeout 2m
    overflow_action block
  </buffer>
</match>
EOF
    log_success "Fluentd configuration created."
    log_warn "Adjust log paths in '$FLUENTD_CONFIG_FILE' to match your actual application log locations."
    log_warn "Remember to change OpenSearch credentials in Fluentd config for production!"
else
    log_info "Fluentd configuration file already exists. Skipping creation."
fi

# Create Fluentd Docker Compose file
FLUENTD_COMPOSE_FILE="$OBSERVABILITY_EXT_DIR/fluentd-compose.yml"
if [ ! -f "$FLUENTD_COMPOSE_FILE" ]; then
    log_info "Creating Fluentd Docker Compose file: $FLUENTD_COMPOSE_FILE"
    cat <<EOF > "$FLUENTD_COMPOSE_FILE"
version: '3.8'
services:
  fluentd:
    image: fluent/fluentd:v1.16-debian-1 # Use a specific version
    container_name: fluentd
    restart: unless-stopped
    volumes:
      - "$FLUENTD_CONFIG_DIR/fluent.conf:/fluentd/etc/fluent.conf:ro"
      - /var/log:/var/log:ro # Mount host logs
      - /opt/ai-apps:/opt/ai-apps:ro # Mount AI apps logs
      - ./fluentd_buffer:/fluentd/buffer # For Fluentd buffering
    ports:
      - "24224:24224" # For TCP input
      - "24224:24224/udp" # For UDP input
    networks:
      - observability_network
      - opensearch_network # To send logs to OpenSearch
    depends_on:
      - opensearch # Ensure OpenSearch is up

networks:
  observability_network:
    external: true # Connect to the main observability network
  opensearch_network:
    external: true # Connect to OpenSearch network
EOF
    log_success "Fluentd Docker Compose file created."
    log_warn "To start Fluentd, navigate to '$OBSERVABILITY_EXT_DIR' and run: 'docker compose -f fluentd-compose.yml up -d'"
else
    log_info "Fluentd Docker Compose file already exists. Skipping creation."
fi

# --- OpenTelemetry Collector, Jaeger, Tempo Setup ---
log_info "Setting up OpenTelemetry Collector, Jaeger, Tempo via Docker Compose..."

# Create OpenTelemetry Collector configuration file
OTEL_COLLECTOR_CONFIG="$OBSERVABILITY_EXT_DIR/otel-collector-config.yaml"
if [ ! -f "$OTEL_COLLECTOR_CONFIG" ]; then
    log_info "Creating OpenTelemetry Collector configuration file: $OTEL_COLLECTOR_CONFIG"
    cat <<EOF > "$OTEL_COLLECTOR_CONFIG"
receivers:
  otlp:
    protocols:
      grpc:
      http:

exporters:
  logging:
    verbosity: detailed
  jaeger:
    endpoint: jaeger:14250 # Connects to Jaeger service
    tls:
      insecure: true
  loki:
    endpoint: http://loki:3100/loki/api/v1/push # Connects to Loki service
    tls:
      insecure: true
  prometheus:
    endpoint: 0.0.0.0:8889 # Expose metrics for Prometheus to scrape
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write # Send metrics to Prometheus
  tempo:
    endpoint: tempo:4317 # Connects to Tempo service
    tls:
      insecure: true

processors:
  batch:

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [jaeger, tempo, logging] # Send traces to Jaeger, Tempo, and log locally
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus, prometheusremotewrite, logging] # Expose for Prometheus, send to Prometheus, log locally
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [loki, logging] # Send logs to Loki, log locally
EOF
    log_success "OpenTelemetry Collector configuration created."
else
    log_info "OpenTelemetry Collector configuration file already exists. Skipping creation."
fi

# Create Tracing Stack Docker Compose file
TRACING_COMPOSE_FILE="$OBSERVABILITY_EXT_DIR/tracing-compose.yml"
if [ ! -f "$TRACING_COMPOSE_FILE" ]; then
    log_info "Creating Tracing Stack Docker Compose file: $TRACING_COMPOSE_FILE"
    cat <<EOF > "$TRACING_COMPOSE_FILE"
version: '3.8'
services:
  jaeger:
    image: jaegertracing/all-in-one:latest
    container_name: jaeger
    restart: unless-stopped
    ports:
      - "6831:6831/udp" # UDP Thrift
      - "14268:14268" # HTTP Thrift
      - "16686:16686" # Jaeger UI
    environment:
      - COLLECTOR_OTLP_ENABLED=true
    networks:
      - observability_network
      - web # For Traefik if you want to expose Jaeger UI

  tempo:
    image: grafana/tempo:latest
    container_name: tempo
    restart: unless-stopped
    ports:
      - "14268:14268" # Jaeger HTTP
      - "4317:4317" # OTLP gRPC
      - "4318:4318" # OTLP HTTP
    volumes:
      - "$TEMPO_DATA_DIR:/tmp/tempo"
    command: [ "-config.file=/etc/tempo.yaml" ]
    networks:
      - observability_network

  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    container_name: otel-collector
    restart: unless-stopped
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - "$OTEL_COLLECTOR_CONFIG:/etc/otel-collector-config.yaml:ro"
    ports:
      - "4317:4317" # OTLP gRPC receiver
      - "4318:4318" # OTLP HTTP receiver
      - "8889:8889" # Prometheus metrics exporter
    networks:
      - observability_network
    depends_on:
      - jaeger
      - tempo
      - loki # Ensure Loki is up for log export
      - prometheus # Ensure Prometheus is up for metrics export

networks:
  observability_network:
    external: true # Connect to the main observability network
  web:
    external: true # Connect to Traefik's external network
EOF
    log_success "Tracing Stack Docker Compose file created."
    log_warn "To start the tracing stack, navigate to '$OBSERVABILITY_EXT_DIR' and run: 'docker compose -f tracing-compose.yml up -d'"
    log_warn "Jaeger UI: http://localhost:16686"
    log_warn "Ensure UFW allows access to port 16686 from trusted IPs, or expose it via Traefik."
    log_warn "Configure your applications to send OTLP traces, metrics, and logs to 'otel-collector:4317' (gRPC) or 'otel-collector:4318' (HTTP)."
else
    log_info "Tracing Stack Docker Compose file already exists. Skipping creation."
fi

log_success "21_observability_extensions_docker.sh completed."
