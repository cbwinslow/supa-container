#!/bin/bash

# =============================================================================
# Production Hetzner Deployment Script for AI-Enhanced Supa Container
# =============================================================================
# This script deploys a complete, production-ready AI platform on Hetzner Cloud
# with comprehensive security, monitoring, and AI orchestration capabilities.
#
# Prerequisites:
# 1. Run generate_production_secrets.sh first
# 2. Configure DNS records to point to your Hetzner server
# 3. Run as root: sudo bash deploy_hetzner.sh
# =============================================================================

set -euo pipefail

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Load environment variables
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}❌ ERROR: .env file not found.${NC}"
    echo -e "${YELLOW}Please run generate_production_secrets.sh first.${NC}"
    exit 1
fi

source "$ENV_FILE"

# Check required variables
if [ -z "${DOMAIN:-}" ] || [ -z "${LETSENCRYPT_EMAIL:-}" ]; then
    echo -e "${RED}❌ ERROR: DOMAIN and LETSENCRYPT_EMAIL must be set in .env file.${NC}"
    exit 1
fi

# --- Display Banner ---
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}🚀 AI-Enhanced Supa Container - Production Hetzner Deployment${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${CYAN}Domain:${NC} ${GREEN}${DOMAIN}${NC}"
echo -e "${CYAN}Email:${NC} ${GREEN}${LETSENCRYPT_EMAIL}${NC}"
echo -e "${CYAN}App Root:${NC} ${GREEN}${APP_ROOT}${NC}"
echo -e "${CYAN}Deployment Target:${NC} ${GREEN}Hetzner Cloud Production${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root or with sudo.${NC}"
    exit 1
fi

# --- Step 1: System Prerequisites ---
echo -e "${PURPLE}[1/12] Installing system prerequisites and optimizations...${NC}"

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install essential packages
apt-get install -y \
    curl \
    wget \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    fail2ban \
    ufw \
    htop \
    iotop \
    netstat-ss \
    apache2-utils \
    unzip \
    git \
    python3 \
    python3-pip \
    rsync \
    jq \
    uuid-runtime

# Install Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
    rm get-docker.sh
fi

# Install Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}Installing Docker Compose...${NC}"
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

echo -e "${GREEN}✅ System prerequisites installed.${NC}"

# --- Step 2: Hetzner-Specific System Optimizations ---
echo -e "${PURPLE}[2/12] Applying Hetzner-specific optimizations...${NC}"

# Optimize for Hetzner Cloud
cat <<EOF > /etc/sysctl.d/99-hetzner-optimization.conf
# Network optimizations for Hetzner Cloud
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 12582912 16777216
net.ipv4.tcp_wmem = 4096 12582912 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr

# Memory optimizations
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# File system optimizations
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
EOF

sysctl -p /etc/sysctl.d/99-hetzner-optimization.conf

# Increase file limits
cat <<EOF > /etc/security/limits.d/99-docker.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
root soft nofile 65536
root hard nofile 65536
EOF

echo -e "${GREEN}✅ Hetzner optimizations applied.${NC}"

# --- Step 3: Security Hardening ---
echo -e "${PURPLE}[3/12] Implementing security hardening...${NC}"

# Configure UFW firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Configure fail2ban
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3

[nginx-http-auth]
enabled = true

[nginx-noscript]
enabled = true

[nginx-badbots]
enabled = true

[nginx-botsearch]
enabled = true
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# Disable unnecessary services
systemctl disable --now snapd 2>/dev/null || true
systemctl disable --now bluetooth 2>/dev/null || true

echo -e "${GREEN}✅ Security hardening completed.${NC}"

# --- Step 4: Create Directory Structure ---
echo -e "${PURPLE}[4/12] Creating directory structure...${NC}"

mkdir -p "${APP_ROOT}"/{traefik,fastapi_app,nextjs_app,orchestrator,agents,message_broker,prometheus,grafana/provisioning/{datasources,dashboards},loki,jaeger,langfuse,flowise,n8n,rabbitmq,neo4j,supabase,clickhouse,minio,redis}
mkdir -p "${WEB_ROOT}"
mkdir -p /var/log/traefik
mkdir -p /opt/backup

# Set proper permissions
touch "${APP_ROOT}/traefik/acme.json"
chmod 600 "${APP_ROOT}/traefik/acme.json"
chown -R root:docker "${APP_ROOT}" 2>/dev/null || chown -R root:root "${APP_ROOT}"

echo -e "${GREEN}✅ Directory structure created.${NC}"

# --- Step 5: Copy Application Code ---
echo -e "${PURPLE}[5/12] Copying application code and configurations...${NC}"

# Copy FastAPI application
if [ -d "$SCRIPT_DIR/src/fastapi_app" ]; then
    rsync -av "$SCRIPT_DIR/src/fastapi_app/" "${APP_ROOT}/fastapi_app/"
else
    echo -e "${YELLOW}⚠️  FastAPI app not found in src/fastapi_app, checking alternate locations...${NC}"
    # Check if it exists in current directory
    if [ -d "$SCRIPT_DIR/fastapi_app" ]; then
        rsync -av "$SCRIPT_DIR/fastapi_app/" "${APP_ROOT}/fastapi_app/"
    fi
fi

# Copy Next.js application
if [ -d "$SCRIPT_DIR/nextjs_app" ]; then
    rsync -av "$SCRIPT_DIR/nextjs_app/" "${APP_ROOT}/nextjs_app/"
fi

# Copy AI orchestrator and agents
if [ -d "$SCRIPT_DIR/src/orchestrator" ]; then
    rsync -av "$SCRIPT_DIR/src/orchestrator/" "${APP_ROOT}/orchestrator/"
fi

if [ -d "$SCRIPT_DIR/src/agents" ]; then
    rsync -av "$SCRIPT_DIR/src/agents/" "${APP_ROOT}/agents/"
fi

if [ -d "$SCRIPT_DIR/src/message_broker" ]; then
    rsync -av "$SCRIPT_DIR/src/message_broker/" "${APP_ROOT}/message_broker/"
fi

# Copy SQL schemas
if [ -d "$SCRIPT_DIR/sql" ]; then
    rsync -av "$SCRIPT_DIR/sql/" "${APP_ROOT}/sql/"
fi

# Copy configuration files
rsync -av "$SCRIPT_DIR/rabbitmq/" "${APP_ROOT}/rabbitmq/" 2>/dev/null || true

echo -e "${GREEN}✅ Application code copied.${NC}"

# --- Step 6: Create Traefik Configuration ---
echo -e "${PURPLE}[6/12] Creating Traefik configuration...${NC}"

cat <<EOF > "${APP_ROOT}/traefik/traefik.yml"
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entrypoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: devops-net

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${LETSENCRYPT_EMAIL}
      storage: /etc/traefik/acme.json
      httpChallenge:
        entryPoint: web

accessLog:
  filePath: "/var/log/traefik/access.log"
  format: json

log:
  level: INFO
  filePath: "/var/log/traefik/traefik.log"

metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
EOF

echo -e "${GREEN}✅ Traefik configuration created.${NC}"

# --- Step 7: Create Monitoring Configurations ---
echo -e "${PURPLE}[7/12] Creating monitoring configurations...${NC}"

# Prometheus configuration
cat <<EOF > "${APP_ROOT}/prometheus/prometheus.yml"
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']

  - job_name: 'docker'
    static_configs:
      - targets: ['docker-exporter:9323']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'fastapi'
    static_configs:
      - targets: ['fastapi_app:${APP_PORT}']
    metrics_path: '/metrics'
EOF

# Grafana datasources
cat <<EOF > "${APP_ROOT}/grafana/provisioning/datasources/datasources.yml"
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    access: proxy
    isDefault: true

  - name: Loki
    type: loki
    url: http://loki:3100
    access: proxy

  - name: Jaeger
    type: jaeger
    url: http://jaeger:16686
    access: proxy
EOF

# Loki configuration
cat <<EOF > "${APP_ROOT}/loki/config.yml"
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
EOF

# Promtail configuration
cat <<EOF > "${APP_ROOT}/promtail/config.yml"
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: containers
    static_configs:
      - targets: [localhost]
        labels:
          job: containerlogs
          __path__: /var/lib/docker/containers/*/*log
    pipeline_stages:
      - docker: {}

  - job_name: traefik
    static_configs:
      - targets: [localhost]
        labels:
          job: traefik
          __path__: /var/log/traefik/*.log
EOF

echo -e "${GREEN}✅ Monitoring configurations created.${NC}"

# --- Step 8: Create Docker Compose ---
echo -e "${PURPLE}[8/12] Creating production Docker Compose configuration...${NC}"

cat <<EOF > "${APP_ROOT}/docker-compose.yml"
version: '3.8'

networks:
  devops-net:
    driver: bridge

volumes:
  postgres_data:
  neo4j_data:
  qdrant_data:
  localai_models:
  redis_data:
  rabbitmq_data:
  n8n_data:
  flowise_data:
  prometheus_data:
  grafana_data:
  loki_data:
  jaeger_data:
  langfuse_postgres_data:
  langfuse_clickhouse_data:
  langfuse_minio_data:

services:
  # --- Reverse Proxy & SSL Termination ---
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/acme.json:/etc/traefik/acme.json
      - /var/log/traefik:/var/log/traefik
    networks: [devops-net]
    environment:
      - CF_API_EMAIL=\${LETSENCRYPT_EMAIL}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(\`traefik.\${DOMAIN}\`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.middlewares=traefik-auth"
      - "traefik.http.middlewares.traefik-auth.basicauth.users=\${TRAEFIK_ADMIN_PASSWORD_HASH}"

  # --- Frontend Application ---
  nextjs_app:
    build: 
      context: ./nextjs_app
      dockerfile: Dockerfile
    container_name: nextjs_app
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - NEXT_PUBLIC_SUPABASE_URL=https://supabase.\${DOMAIN}
      - NEXT_PUBLIC_SUPABASE_ANON_KEY=\${SUPABASE_ANON_KEY}
      - NEXT_PUBLIC_API_URL=https://api.\${DOMAIN}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nextjs.rule=Host(\`\${DOMAIN}\`) || Host(\`www.\${DOMAIN}\`)"
      - "traefik.http.routers.nextjs.entrypoints=websecure"
      - "traefik.http.routers.nextjs.tls.certresolver=letsencrypt"
      - "traefik.http.services.nextjs.loadbalancer.server.port=3000"

  # --- Backend API ---
  fastapi_app:
    build: 
      context: ./fastapi_app
      dockerfile: Dockerfile
    container_name: fastapi_app
    restart: unless-stopped
    networks: [devops-net]
    env_file: .env
    environment:
      - DATABASE_URL=\${DATABASE_URL}
      - NEO4J_URI=\${NEO4J_URI}
      - NEO4J_USER=\${NEO4J_USER}
      - NEO4J_PASSWORD=\${NEO4J_PASSWORD}
      - RABBITMQ_HOST=\${RABBITMQ_HOST}
      - RABBITMQ_USER=\${RABBITMQ_USER}
      - RABBITMQ_PASSWORD=\${RABBITMQ_PASSWORD}
    depends_on:
      - postgres
      - neo4j
      - qdrant
      - rabbitmq
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.fastapi.rule=Host(\`api.\${DOMAIN}\`)"
      - "traefik.http.routers.fastapi.entrypoints=websecure"
      - "traefik.http.routers.fastapi.tls.certresolver=letsencrypt"
      - "traefik.http.services.fastapi.loadbalancer.server.port=\${APP_PORT}"

  # --- Database Services ---
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  neo4j:
    image: neo4j:5-community
    container_name: neo4j
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - NEO4J_AUTH=\${NEO4J_AUTH}
      - NEO4J_PLUGINS=["apoc", "graph-data-science"]
      - NEO4J_dbms_security_procedures_unrestricted=apoc.*,gds.*
    volumes:
      - neo4j_data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.neo4j.rule=Host(\`neo4j.\${DOMAIN}\`)"
      - "traefik.http.routers.neo4j.entrypoints=websecure"
      - "traefik.http.routers.neo4j.tls.certresolver=letsencrypt"
      - "traefik.http.services.neo4j.loadbalancer.server.port=7474"

  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    networks: [devops-net]
    volumes:
      - qdrant_data:/qdrant/storage

  # --- Message Broker ---
  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    container_name: rabbitmq
    restart: unless-stopped
    hostname: rabbitmq
    networks: [devops-net]
    environment:
      - RABBITMQ_DEFAULT_USER=\${RABBITMQ_USER}
      - RABBITMQ_DEFAULT_PASS=\${RABBITMQ_PASSWORD}
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "ping"]
      interval: 10s
      timeout: 10s
      retries: 5
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.rabbitmq.rule=Host(\`rabbitmq.\${DOMAIN}\`)"
      - "traefik.http.routers.rabbitmq.entrypoints=websecure"
      - "traefik.http.routers.rabbitmq.tls.certresolver=letsencrypt"
      - "traefik.http.services.rabbitmq.loadbalancer.server.port=15672"

  # --- AI Services ---
  localai:
    image: quay.io/go-skynet/local-ai:latest
    container_name: localai
    restart: unless-stopped
    networks: [devops-net]
    volumes:
      - localai_models:/models
    command: ["/usr/bin/local-ai", "--models-path", "/models", "--context-size", "8192"]

  # --- Workflow Automation ---
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=\${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_BASIC_AUTH_PASSWORD}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - WEBHOOK_URL=https://n8n.\${DOMAIN}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_USER=\${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      - postgres
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`n8n.\${DOMAIN}\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"

  # --- AI Prototyping ---
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - DATABASE_URL=\${DATABASE_URL}
      - FLOWISE_USERNAME=\${FLOWISE_USERNAME}
      - FLOWISE_PASSWORD=\${FLOWISE_PASSWORD}
    volumes:
      - flowise_data:/root/.flowise
    depends_on:
      - postgres
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.flowise.rule=Host(\`flowise.\${DOMAIN}\`)"
      - "traefik.http.routers.flowise.entrypoints=websecure"
      - "traefik.http.routers.flowise.tls.certresolver=letsencrypt"
      - "traefik.http.services.flowise.loadbalancer.server.port=3000"

  # --- Observability Stack ---
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    networks: [devops-net]
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prometheus.rule=Host(\`prometheus.\${DOMAIN}\`)"
      - "traefik.http.routers.prometheus.entrypoints=websecure"
      - "traefik.http.routers.prometheus.tls.certresolver=letsencrypt"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - GF_SECURITY_ADMIN_USER=\${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=\${GRAFANA_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    depends_on:
      - prometheus
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(\`grafana.\${DOMAIN}\`)"
      - "traefik.http.routers.grafana.entrypoints=websecure"
      - "traefik.http.routers.grafana.tls.certresolver=letsencrypt"

  loki:
    image: grafana/loki:latest
    container_name: loki
    restart: unless-stopped
    networks: [devops-net]
    volumes:
      - ./loki/config.yml:/etc/loki/local-config.yaml:ro
      - loki_data:/loki
    command: -config.file=/etc/loki/local-config.yaml

  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    restart: unless-stopped
    networks: [devops-net]
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ./promtail/config.yml:/etc/promtail/config.yml:ro
    command: -config.file=/etc/promtail/config.yml
    depends_on:
      - loki

  jaeger:
    image: jaegertracing/all-in-one:latest
    container_name: jaeger
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - COLLECTOR_OTLP_ENABLED=true
    volumes:
      - jaeger_data:/badger
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.jaeger.rule=Host(\`jaeger.\${DOMAIN}\`)"
      - "traefik.http.routers.jaeger.entrypoints=websecure"
      - "traefik.http.routers.jaeger.tls.certresolver=letsencrypt"
      - "traefik.http.services.jaeger.loadbalancer.server.port=16686"

  # --- LLM Observability (Langfuse) ---
  langfuse-postgres:
    image: postgres:15-alpine
    container_name: langfuse-postgres
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=langfuse
    volumes:
      - langfuse_postgres_data:/var/lib/postgresql/data

  clickhouse:
    image: clickhouse/clickhouse-server:latest
    container_name: clickhouse
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - CLICKHOUSE_DB=default
      - CLICKHOUSE_USER=\${CLICKHOUSE_USER}
      - CLICKHOUSE_PASSWORD=\${CLICKHOUSE_PASSWORD}
    volumes:
      - langfuse_clickhouse_data:/var/lib/clickhouse
    healthcheck:
      test: wget --no-verbose --tries=1 --spider http://localhost:8123/ping || exit 1
      interval: 5s
      timeout: 5s
      retries: 10

  minio:
    image: minio/minio:latest
    container_name: minio
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - MINIO_ROOT_USER=\${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=\${MINIO_ROOT_PASSWORD}
    volumes:
      - langfuse_minio_data:/data
    command: minio server --address ":9000" --console-address ":9001" /data
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    networks: [devops-net]
    command: redis-server --requirepass \${REDIS_AUTH}
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  langfuse-web:
    image: langfuse/langfuse:latest
    container_name: langfuse-web
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@langfuse-postgres:5432/langfuse
      - NEXTAUTH_SECRET=\${NEXTAUTH_SECRET}
      - NEXTAUTH_URL=https://langfuse.\${DOMAIN}
      - SALT=\${LANGFUSE_SALT}
      - ENCRYPTION_KEY=\${ENCRYPTION_KEY}
      - TELEMETRY_ENABLED=\${TELEMETRY_ENABLED}
      - LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES=\${LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES}
      - CLICKHOUSE_URL=\${CLICKHOUSE_URL}
      - CLICKHOUSE_USER=\${CLICKHOUSE_USER}
      - CLICKHOUSE_PASSWORD=\${CLICKHOUSE_PASSWORD}
      - REDIS_HOST=\${REDIS_HOST}
      - REDIS_PORT=\${REDIS_PORT}
      - REDIS_AUTH=\${REDIS_AUTH}
    depends_on:
      - langfuse-postgres
      - clickhouse
      - minio
      - redis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.langfuse.rule=Host(\`langfuse.\${DOMAIN}\`)"
      - "traefik.http.routers.langfuse.entrypoints=websecure"
      - "traefik.http.routers.langfuse.tls.certresolver=letsencrypt"
      - "traefik.http.services.langfuse.loadbalancer.server.port=3000"

EOF

echo -e "${GREEN}✅ Docker Compose configuration created.${NC}"

# --- Step 9: Create AI Orchestrator Services ---
echo -e "${PURPLE}[9/12] Setting up AI Orchestrator and Agent services...${NC}"

# Add AI services to docker-compose
cat <<EOF >> "${APP_ROOT}/docker-compose.yml"

  # --- AI Orchestrator Brain ---
  orchestrator:
    build: 
      context: ./orchestrator
      dockerfile: Dockerfile
    container_name: ai_orchestrator
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - RABBITMQ_HOST=\${RABBITMQ_HOST}
      - RABBITMQ_PORT=\${RABBITMQ_PORT}
      - RABBITMQ_USER=\${RABBITMQ_USER}
      - RABBITMQ_PASSWORD=\${RABBITMQ_PASSWORD}
      - DATABASE_URL=\${DATABASE_URL}
      - NEO4J_URI=\${NEO4J_URI}
      - NEO4J_USER=\${NEO4J_USER}
      - NEO4J_PASSWORD=\${NEO4J_PASSWORD}
      - LOG_LEVEL=\${ORCHESTRATOR_LOG_LEVEL}
      - DOMAIN=\${DOMAIN}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/log:/var/log:ro
      - /proc:/proc:ro
      - /sys:/sys:ro
    depends_on:
      - rabbitmq
      - postgres
      - neo4j
    healthcheck:
      test: ["CMD", "python", "-c", "import requests; requests.get('http://localhost:8000/health')"]
      timeout: 30s
      interval: 30s
      retries: 3

  # --- Self-Healing Agent ---
  self_healing_agent:
    build:
      context: ./agents  
      dockerfile: Dockerfile
    container_name: self_healing_agent
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - AGENT_TYPE=self_healing
      - RABBITMQ_HOST=\${RABBITMQ_HOST}
      - RABBITMQ_USER=\${RABBITMQ_USER}
      - RABBITMQ_PASSWORD=\${RABBITMQ_PASSWORD}
      - LOG_LEVEL=INFO
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:rw
      - /var/log:/var/log:rw
      - /tmp:/tmp:rw
    command: ["python", "-m", "self_healing_agent"]
    depends_on:
      - rabbitmq
      - orchestrator
    privileged: true

  # --- Monitoring Agent ---
  monitoring_agent:
    build:
      context: ./agents
      dockerfile: Dockerfile  
    container_name: monitoring_agent
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - AGENT_TYPE=monitoring
      - RABBITMQ_HOST=\${RABBITMQ_HOST}
      - RABBITMQ_USER=\${RABBITMQ_USER}
      - RABBITMQ_PASSWORD=\${RABBITMQ_PASSWORD}
      - LOG_LEVEL=INFO
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/log:/var/log:ro
      - /proc:/proc:ro
      - /sys:/sys:ro
    command: ["python", "-m", "monitoring_agent"]
    depends_on:
      - rabbitmq
      - orchestrator

  # --- Data Manager Agent ---
  data_manager_agent:
    build:
      context: ./agents
      dockerfile: Dockerfile
    container_name: data_manager_agent  
    restart: unless-stopped
    networks: [devops-net]
    environment:
      - AGENT_TYPE=data_manager
      - RABBITMQ_HOST=\${RABBITMQ_HOST}
      - RABBITMQ_USER=\${RABBITMQ_USER}
      - RABBITMQ_PASSWORD=\${RABBITMQ_PASSWORD}
      - DATABASE_URL=\${DATABASE_URL}
      - NEO4J_URI=\${NEO4J_URI}
      - LOG_LEVEL=INFO
    command: ["python", "-m", "data_manager_agent"]
    depends_on:
      - rabbitmq
      - orchestrator
      - postgres
      - neo4j
EOF

echo -e "${GREEN}✅ AI Orchestrator services configured.${NC}"

# --- Step 10: Copy Environment File ---
echo -e "${PURPLE}[10/12] Installing environment configuration...${NC}"

cp "$ENV_FILE" "${APP_ROOT}/.env"
chown root:root "${APP_ROOT}/.env"
chmod 600 "${APP_ROOT}/.env"

echo -e "${GREEN}✅ Environment configuration installed.${NC}"

# --- Step 11: Create Management Scripts ---
echo -e "${PURPLE}[11/12] Creating management and monitoring scripts...${NC}"

# Create startup script
cat <<'EOF' > "${APP_ROOT}/start_platform.sh"
#!/bin/bash

echo "🚀 Starting AI-Enhanced Supa Container Platform..."

# Navigate to application directory
cd "${APP_ROOT}"

# Start all services
docker-compose up -d

echo "⏳ Waiting for services to initialize..."
sleep 60

# Check service health
echo "📊 Service Health Check:"
docker-compose ps

echo "📈 Platform Status:"
docker-compose logs --tail=5 traefik

echo ""
echo "✅ Platform started successfully!"
echo ""
echo "🌐 Access URLs:"
echo "   Main App: https://${DOMAIN}"
echo "   API: https://api.${DOMAIN}"
echo "   Monitoring: https://grafana.${DOMAIN}"
echo "   Workflow: https://n8n.${DOMAIN}"
echo "   AI Lab: https://flowise.${DOMAIN}"
echo ""
echo "🔧 Admin URLs:"
echo "   Traefik: https://traefik.${DOMAIN}"
echo "   RabbitMQ: https://rabbitmq.${DOMAIN}"
echo "   Jaeger: https://jaeger.${DOMAIN}"
echo "   Langfuse: https://langfuse.${DOMAIN}"
EOF

chmod +x "${APP_ROOT}/start_platform.sh"

# Create monitoring script
cat <<'EOF' > "${APP_ROOT}/monitor_platform.sh"
#!/bin/bash

echo "📊 AI-Enhanced Supa Container Platform Monitor"
echo "=============================================="

cd "${APP_ROOT}"

echo ""
echo "🔧 Container Status:"
docker-compose ps

echo ""
echo "🧠 AI Orchestrator Health:"
if docker exec ai_orchestrator python -c "import requests; requests.get('http://localhost:8000/health')" 2>/dev/null; then
    echo "✅ AI Orchestrator: Healthy"
else
    echo "❌ AI Orchestrator: Unhealthy"
fi

echo ""
echo "🤖 Agent Status:"
for agent in self_healing_agent monitoring_agent data_manager_agent; do
    if docker ps --format "table {{.Names}}" | grep -q "$agent"; then
        echo "✅ $agent: Running"
    else
        echo "❌ $agent: Not Running"
    fi
done

echo ""
echo "💬 Message Broker Status:"
if docker exec rabbitmq rabbitmq-diagnostics ping > /dev/null 2>&1; then
    echo "✅ RabbitMQ: Healthy"
else
    echo "❌ RabbitMQ: Unhealthy"
fi

echo ""
echo "💾 Database Status:"
if docker exec postgres pg_isready -U postgres > /dev/null 2>&1; then
    echo "✅ PostgreSQL: Healthy"
else
    echo "❌ PostgreSQL: Unhealthy"
fi

echo ""
echo "📈 Recent Activity (last 10 lines):"
docker-compose logs --tail=10 orchestrator
EOF

chmod +x "${APP_ROOT}/monitor_platform.sh"

# Create backup script
cat <<'EOF' > "${APP_ROOT}/backup_platform.sh"
#!/bin/bash

BACKUP_DIR="/opt/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "💾 Creating platform backup..."

cd "${APP_ROOT}"

# Backup databases
echo "Backing up PostgreSQL..."
docker exec postgres pg_dump -U postgres postgres > "$BACKUP_DIR/postgres_backup.sql"

echo "Backing up Neo4j..."
docker exec neo4j neo4j-admin dump --database=neo4j --to=/tmp/neo4j_backup.dump
docker cp neo4j:/tmp/neo4j_backup.dump "$BACKUP_DIR/"

# Backup configurations
echo "Backing up configurations..."
cp -r traefik "$BACKUP_DIR/"
cp -r grafana "$BACKUP_DIR/"
cp .env "$BACKUP_DIR/"
cp docker-compose.yml "$BACKUP_DIR/"

# Create archive
echo "Creating backup archive..."
tar -czf "/opt/backup/platform_backup_$(date +%Y%m%d_%H%M%S).tar.gz" -C "/opt/backup" "$(basename $BACKUP_DIR)"

echo "✅ Backup completed: /opt/backup/platform_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
EOF

chmod +x "${APP_ROOT}/backup_platform.sh"

# Create systemd service
cat <<EOF > /etc/systemd/system/supa-container.service
[Unit]
Description=AI-Enhanced Supa Container Platform
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${APP_ROOT}
ExecStart=${APP_ROOT}/start_platform.sh
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=300
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable supa-container.service

echo -e "${GREEN}✅ Management scripts created.${NC}"

# --- Step 12: Final Setup ---
echo -e "${PURPLE}[12/12] Finalizing deployment...${NC}"

# Set proper ownership
chown -R root:docker "${APP_ROOT}" 2>/dev/null || chown -R root:root "${APP_ROOT}"
chmod -R 755 "${APP_ROOT}"
chmod 600 "${APP_ROOT}/.env"
chmod 600 "${APP_ROOT}/traefik/acme.json"

# Create log rotation
cat <<EOF > /etc/logrotate.d/supa-container
/var/log/traefik/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    create 644 root root
    postrotate
        docker kill -s USR1 traefik 2>/dev/null || true
    endscript
}
EOF

echo -e "${GREEN}✅ Deployment finalized.${NC}"

# --- Display Completion Summary ---
echo
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${GREEN}🎉 AI-Enhanced Supa Container Deployment Complete!${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo -e "   1. ${CYAN}Configure DNS records to point to this server's IP${NC}"
echo -e "   2. ${CYAN}Start the platform: cd ${APP_ROOT} && sudo ./start_platform.sh${NC}"
echo -e "   3. ${CYAN}Monitor the deployment: sudo ./monitor_platform.sh${NC}"
echo -e "   4. ${CYAN}Run post-deployment setup for Supabase keys${NC}"
echo
echo -e "${YELLOW}🌐 Platform URLs (after DNS configuration):${NC}"
echo -e "   • ${GREEN}Main Application: https://${DOMAIN}${NC}"
echo -e "   • ${GREEN}API Documentation: https://api.${DOMAIN}/docs${NC}"
echo -e "   • ${GREEN}System Monitoring: https://grafana.${DOMAIN}${NC}"
echo -e "   • ${GREEN}Workflow Automation: https://n8n.${DOMAIN}${NC}"
echo -e "   • ${GREEN}AI Prototyping Lab: https://flowise.${DOMAIN}${NC}"
echo -e "   • ${GREEN}LLM Observability: https://langfuse.${DOMAIN}${NC}"
echo -e "   • ${GREEN}Distributed Tracing: https://jaeger.${DOMAIN}${NC}"
echo -e "   • ${GREEN}Message Broker: https://rabbitmq.${DOMAIN}${NC}"
echo -e "   • ${GREEN}Knowledge Graph: https://neo4j.${DOMAIN}${NC}"
echo -e "   • ${GREEN}Reverse Proxy: https://traefik.${DOMAIN}${NC}"
echo
echo -e "${YELLOW}🔐 Security Features Enabled:${NC}"
echo -e "   ✅ UFW Firewall (SSH, HTTP, HTTPS only)"
echo -e "   ✅ Fail2ban intrusion prevention"
echo -e "   ✅ Let's Encrypt SSL certificates"
echo -e "   ✅ Password-protected admin interfaces"
echo -e "   ✅ Docker security best practices"
echo -e "   ✅ System optimization for Hetzner Cloud"
echo
echo -e "${YELLOW}🤖 AI Features:${NC}"
echo -e "   ✅ AI Orchestrator Brain for system management"
echo -e "   ✅ Self-healing agent for automatic recovery"
echo -e "   ✅ Monitoring agent for performance optimization"
echo -e "   ✅ Data manager agent for intelligent data flow"
echo -e "   ✅ RabbitMQ message broker for agent communication"
echo -e "   ✅ Comprehensive observability and logging"
echo
echo -e "${YELLOW}🛠️  Management Commands:${NC}"
echo -e "   • ${CYAN}Start Platform: cd ${APP_ROOT} && sudo ./start_platform.sh${NC}"
echo -e "   • ${CYAN}Monitor Status: cd ${APP_ROOT} && sudo ./monitor_platform.sh${NC}"
echo -e "   • ${CYAN}Create Backup: cd ${APP_ROOT} && sudo ./backup_platform.sh${NC}"
echo -e "   • ${CYAN}View Logs: cd ${APP_ROOT} && sudo docker-compose logs -f${NC}"
echo -e "   • ${CYAN}Auto-start: sudo systemctl start supa-container${NC}"
echo
echo -e "${RED}⚠️  Important:${NC}"
echo -e "   • Review and save the generated passwords from PRODUCTION_PASSWORDS_*.txt"
echo -e "   • Configure DNS A records before starting the platform"
echo -e "   • Run the post-deployment script to get Supabase API keys"
echo -e "   • Monitor logs during first startup for any issues"
echo
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${GREEN}Deployment completed successfully! 🚀${NC}"
echo -e "${BLUE}=============================================================================${NC}"