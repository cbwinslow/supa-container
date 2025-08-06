#!/bin/bash

# ==============================================================================
# 13_message_queue_rabbitmq.sh
# Summary: Installs and configures RabbitMQ as a message broker via Docker Compose.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# IMPORTANT: Docker must be installed first (from 12_docker_setup.sh).
# ==============================================================================

# --- Global Variables ---
RABBITMQ_DIR="/opt/rabbitmq"
RABBITMQ_DATA_DIR="$RABBITMQ_DIR/data"
RABBITMQ_LOG_DIR="$RABBITMQ_DIR/logs"

# Generate a random password for the default user (guest is disabled by default in Docker image)
RABBITMQ_DEFAULT_USER="rabbitmq_admin"
RABBITMQ_DEFAULT_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16 ; echo '')

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 13_message_queue_rabbitmq.sh: RabbitMQ (Docker) Setup."

# Ensure Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please run 12_docker_setup.sh first."
fi

# Create directories for RabbitMQ data and logs
log_info "Creating RabbitMQ data and log directories: $RABBITMQ_DATA_DIR, $RABBITMQ_LOG_DIR"
mkdir -p "$RABBITMQ_DATA_DIR" "$RABBITMQ_LOG_DIR" || log_error "Failed to create RabbitMQ directories."
chmod 777 "$RABBITMQ_DATA_DIR" "$RABBITMQ_LOG_DIR" || log_warn "Failed to set permissions for RabbitMQ directories (might need manual adjustment)."
log_success "RabbitMQ directories created."

# Create Docker Compose file for RabbitMQ
RABBITMQ_COMPOSE_FILE="$RABBITMQ_DIR/docker-compose.yml"

if [ ! -f "$RABBITMQ_COMPOSE_FILE" ]; then
    log_info "Creating RabbitMQ Docker Compose file: $RABBITMQ_COMPOSE_FILE"
    cat <<EOF > "$RABBITMQ_COMPOSE_FILE"
version: '3.8'
services:
  rabbitmq:
    image: rabbitmq:3-management-alpine # Use Alpine for smaller image, with management plugin
    container_name: rabbitmq
    restart: unless-stopped
    ports:
      - "5672:5672" # AMQP protocol port
      - "15672:15672" # Management UI port
    volumes:
      - "$RABBITMQ_DATA_DIR:/var/lib/rabbitmq"
      - "$RABBITMQ_LOG_DIR:/var/log/rabbitmq"
    environment:
      RABBITMQ_DEFAULT_USER: "$RABBITMQ_DEFAULT_USER"
      RABBITMQ_DEFAULT_PASS: "$RABBITMQ_DEFAULT_PASS"
    networks:
      - messaging_network
      - web # For Traefik if you want to expose management UI

networks:
  messaging_network:
    driver: bridge
  web:
    external: true # Connect to Traefik's external network
EOF
    log_success "RabbitMQ Docker Compose file created."
    log_warn "RabbitMQ Admin User: $RABBITMQ_DEFAULT_USER"
    log_warn "RabbitMQ Admin Password: $RABBITMQ_DEFAULT_PASS"
    log_warn "SAVE THESE CREDENTIALS SECURELY (e.g., in HashiCorp Vault)."
else
    log_info "RabbitMQ Docker Compose file already exists. Skipping creation."
fi

# Start RabbitMQ via Docker Compose
log_info "Starting RabbitMQ via Docker Compose..."
docker network create messaging_network || log_warn "Docker network 'messaging_network' already exists or failed to create."
docker compose -f "$RABBITMQ_COMPOSE_FILE" up -d || log_error "Failed to start RabbitMQ via Docker Compose."
log_success "RabbitMQ installed and running via Docker Compose."
log_warn "RabbitMQ Management UI is available on port 15672 (http://localhost:15672)."
log_warn "Ensure UFW allows access to port 5672 (AMQP) and 15672 (Management UI) from trusted IPs."
log_warn "For production, expose RabbitMQ management UI only via Traefik with proper authentication."

log_success "13_message_queue_rabbitmq.sh completed."
