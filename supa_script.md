This is an incredibly ambitious and exciting project! Building a local development environment with Supabase, multiple vector databases, AI inference, search, monitoring, and a robust API gateway with authentication is a true "bells and whistles" setup.
We'll leverage Docker Compose as the central orchestrator for all these services, allowing them to communicate seamlessly. For the web-facing components, Traefik will act as our reverse proxy, handling routing and SSL (though for local development, we'll focus on HTTP routing). Kong will serve as the API Gateway, providing an additional layer of control and security.
Due to the sheer volume of services and configurations, this will be a multi-part response. We'll start with the main setup script and the comprehensive docker-compose.yml, then detail the configurations for each service, the FastAPI application, and the authentication frontend.

Part 1: Initial Setup Script & Master Docker Compose

This first part provides the primary setup script (setup-supabase-super-stack.sh) and the overarching docker-compose.yml file that defines all the services.

1. Core Setup Script (setup-supabase-super-stack.sh)

This script will prepare your environment, install the Supabase CLI, initialize your local Supabase project, and then create the docker-compose.yml and necessary directories for the entire stack.

Bash


#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

echo "==================================================================="
echo " Starting Supabase Super Stack Local Development Environment Setup."
echo " This will create multiple directories and configuration files.   "
echo " Ensure Docker and Docker Compose are installed and running.     "
echo "==================================================================="

# --- Section 1: Check for Docker and Docker Compose ---
echo "--> [1/6] Checking for Docker and Docker Compose..."
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker Desktop (for macOS/Windows) or Docker Engine (for Linux) and try again."
    echo "Refer to https://docs.docker.com/get-docker/ for installation instructions."
    exit 1
fi
if ! command -v docker compose &> /dev/null; then
    echo "Error: Docker Compose is not installed. Please ensure you have a recent Docker Desktop/Engine installation that includes 'docker compose'."
    echo "Refer to https://docs.docker.com/compose/install/ for installation instructions."
    exit 1
fi
echo "Docker and Docker Compose found."

# --- Section 2: Install Supabase CLI ---
echo "--> [2/6] Installing Supabase CLI..."
if ! command -v supabase &> /dev/null; then
    # For Linux (Debian/Ubuntu)
    echo "Installing Supabase CLI for Linux. For other OS, please install manually."
    curl -sL https://supabase.com/docs/install/cli | sh
    echo "Supabase CLI installed."
else
    echo "Supabase CLI already installed."
fi

# --- Section 3: Initialize Supabase Project ---
echo "--> [3/6] Initializing Supabase project..."
PROJECT_DIR="supabase-super-stack"
if [ ! -d "$PROJECT_DIR" ]; then
    mkdir "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    supabase init
    echo "Supabase project initialized in '$PROJECT_DIR'."
else
    echo "Supabase project directory '$PROJECT_DIR' already exists. Skipping 'supabase init'."
    cd "$PROJECT_DIR"
fi

# --- Section 4: Prepare Supabase for pgvector ---
echo "--> [4/6] Preparing Supabase for pgvector..."
# Ensure Supabase local services are running to apply migrations
supabase start || true # Start if not already running, ignore error if already running

# Create a migration for pgvector extension if it doesn't exist
PGVECTOR_MIGRATION_FILE="supabase/migrations/$(date +%Y%m%d%H%M%S)_add_pgvector.sql"
if [ ! -f "$PGVECTOR_MIGRATION_FILE" ]; then
    echo "CREATE EXTENSION IF NOT EXISTS vector;" > "$PGVECTOR_MIGRATION_FILE"
    echo "Created pgvector migration: $PGVECTOR_MIGRATION_FILE"
    supabase db reset --local # Apply the migration
else
    echo "pgvector migration already exists. Skipping creation."
fi
echo "Supabase pgvector setup complete."

# --- Section 5: Create project directories ---
echo "--> [5/6] Creating necessary project directories..."
cd .. # Go back to the root of the stack directory
mkdir -p traefik
mkdir -p traefik/config
mkdir -p kong
mkdir -p kong/declarative
mkdir -p fastapi_app
mkdir -p auth_frontend
mkdir -p prometheus
mkdir -p grafana/provisioning/datasources
mkdir -p grafana/provisioning/dashboards
mkdir -p loki
mkdir -p promtail
mkdir -p opensearch/config
mkdir -p opensearch-dashboards/config
echo "Project directories created."

# --- Section 6: Create Docker Compose and initial configuration files ---
echo "--> [6/6] Creating docker-compose.yml and initial config files..."

# Create the master .env file
cat <<EOF > .env
# Master Environment Variables for Supabase Super Stack
# Fill these in before running 'docker compose up'

# Supabase
SUPABASE_DB_PASSWORD=supabase
SUPABASE_JWT_SECRET=super-secret-jwt-key-for-supabase-local-dev-change-me-in-production-please-make-it-long-and-random

# Neo4j
NEO4J_PASSWORD=password # Change this for production

# SearXNG
SEARXNG_SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 32 ; echo '') # Generates a random 32-char key

# FastAPI App
FASTAPI_APP_SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 32 ; echo '') # Generates a random 32-char key

# Kong Admin API Token (for declarative config)
KONG_ADMIN_TOKEN=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 32 ; echo '')

# OAuth/JWT
# For local development, these can be simple. For production, use secure values.
OAUTH_CLIENT_ID=my_oauth_client
OAUTH_CLIENT_SECRET=my_oauth_secret
JWT_SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 64 ; echo '') # Longer key for JWT signing
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# Cloudflare (if deploying later, not used in local Docker Compose directly)
CLOUDFLARE_API_TOKEN=
CLOUDFLARE_ACCOUNT_ID=
EOF
echo ".env file created. Please review and fill in sensitive variables."

# Create docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3.8'

# Define named volumes for persistent data
volumes:
  supabase_data:
  qdrant_data:
  weaviate_data:
  neo4j_data:
  neo4j_plugins:
  localai_models:
  graphite_data:
  prometheus_data:
  grafana_data:
  loki_data:
  opensearch_data:
  kong_data:
  kong_db_data:

# Define custom network for internal communication
networks:
  devops-net:
    driver: bridge # Default Docker bridge network

services:
  # --- 1. Reverse Proxy: Traefik ---
  traefik:
    container_name: traefik
    image: traefik:v2.10
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.file.directory=/etc/traefik/config
      - --providers.file.watch=true
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443 # For future HTTPS if needed
      - --log.level=DEBUG # Set to INFO or WARN for less verbosity
      - --accesslog=true
    ports:
      - "80:80"   # The HTTP port
      - "8080:8080" # The Traefik dashboard (accessible via http://localhost:8080)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro # So Traefik can listen to Docker events
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro # Static configuration
      - ./traefik/config:/etc/traefik/config:ro # Dynamic configuration
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik-dashboard.rule=Host(\`traefik.opendiscourse.net\`)"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
      - "traefik.http.routers.traefik-dashboard.entrypoints=web"
      - "traefik.http.middlewares.traefik-compress.compress=true"

  # --- 2. API Gateway: Kong ---
  kong-db:
    container_name: kong_db
    image: postgres:13
    environment:
      POSTGRES_DB: kong
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: ${KONG_DB_PASSWORD:-kong} # Use .env or default
    volumes:
      - kong_db_data:/var/lib/postgresql/data
    networks:
      - devops-net

  kong:
    container_name: kong_gateway
    image: kong:latest
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-db
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: ${KONG_DB_PASSWORD:-kong}
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001, 0.0.0.0:8444 ssl # Admin API
      KONG_PROXY_LISTEN: 0.0.0.0:8000, 0.0.0.0:8443 ssl # Proxy (data plane)
      KONG_DECLARATIVE_CONFIG: /opt/kong/declarative/kong.yml
      KONG_ADMIN_GUI_URL: http://localhost:8002 # Kong Manager (if enabled)
    ports:
      - "8000:8000" # Proxy HTTP
      - "8443:8443" # Proxy HTTPS
      - "8001:8001" # Admin API HTTP
      - "8444:8444" # Admin API HTTPS
      - "8002:8002" # Kong Manager (GUI)
    links:
      - kong-db:kong-db
    depends_on:
      - kong-db
    volumes:
      - ./kong/declarative:/opt/kong/declarative
    networks:
      - devops-net
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 5
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.kong-proxy.rule=Host(\`api.opendiscourse.net\`)"
      - "traefik.http.routers.kong-proxy.service=kong-proxy-service"
      - "traefik.http.services.kong-proxy-service.loadbalancer.server.port=8000"
      - "traefik.http.routers.kong-admin.rule=Host(\`kong-admin.opendiscourse.net\`)"
      - "traefik.http.routers.kong-admin.service=kong-admin-service"
      - "traefik.http.services.kong-admin-service.loadbalancer.server.port=8001"
      - "traefik.http.routers.kong-admin.entrypoints=web"
      - "traefik.http.routers.kong-proxy.entrypoints=web"


  # --- 3. Supabase Stack (PostgreSQL with pgvector) ---
  supabase:
    container_name: supabase_local
    image: supabase/cli:latest
    command: start
    ports:
      - "5432:5432" # PostgreSQL
      - "8000:8000" # Supabase Studio (already mapped by FastAPI, adjust if needed)
      - "54321:54321" # Supabase API Gateway
    volumes:
      - ./supabase:/project
      - supabase_data:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: ${SUPABASE_DB_PASSWORD}
      POSTGRES_USER: "postgres"
      POSTGRES_DB: "postgres"
      SUPABASE_ANON_KEY: ${SUPABASE_ANON_KEY} # From .env
      SUPABASE_SERVICE_ROLE_KEY: ${SUPABASE_SERVICE_ROLE_KEY} # From .env
      JWT_SECRET: ${SUPABASE_JWT_SECRET} # From .env
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-studio.rule=Host(\`supabase.opendiscourse.net\`)"
      - "traefik.http.routers.supabase-studio.service=supabase-studio-service"
      - "traefik.http.services.supabase-studio-service.loadbalancer.server.port=8000" # Supabase Studio port
      - "traefik.http.routers.supabase-studio.entrypoints=web"
      - "traefik.http.routers.supabase-api.rule=Host(\`supabase-api.opendiscourse.net\`)"
      - "traefik.http.routers.supabase-api.service=supabase-api-service"
      - "traefik.http.services.supabase-api-service.loadbalancer.server.port=54321" # Supabase API Gateway port
      - "traefik.http.routers.supabase-api.entrypoints=web"

  # --- 4. Vector Databases ---
  qdrant:
    container_name: qdrant_local
    image: qdrant/qdrant:latest
    ports:
      - "6333:6333" # HTTP API
      - "6334:6334" # gRPC API
    volumes:
      - qdrant_data:/qdrant/storage
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.qdrant.rule=Host(\`qdrant.opendiscourse.net\`)"
      - "traefik.http.routers.qdrant.service=qdrant-service"
      - "traefik.http.services.qdrant-service.loadbalancer.server.port=6333"
      - "traefik.http.routers.qdrant.entrypoints=web"

  weaviate:
    container_name: weaviate_local
    image: semitechnologies/weaviate:1.24.0
    ports:
      - "8080:8080" # HTTP API (exposed on 8080, but Traefik routes to it)
      - "50051:50051" # gRPC API
    volumes:
      - weaviate_data:/var/lib/weaviate
    environment:
      QUERY_DEFAULTS_LIMIT: 20
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      DEFAULT_VECTORIZER_MODULE: 'none' # Or 'text2vec-transformers' if you install it
      ENABLE_MODULES: '' # e.g., 'text2vec-transformers,generative-openai'
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.weaviate.rule=Host(\`weaviate.opendiscourse.net\`)"
      - "traefik.http.routers.weaviate.service=weaviate-service"
      - "traefik.http.services.weaviate-service.loadbalancer.server.port=8080"
      - "traefik.http.routers.weaviate.entrypoints=web"

  neo4j:
    container_name: neo4j_local
    image: neo4j:latest
    ports:
      - "7474:7474" # HTTP API (Neo4j Browser)
      - "7687:7687" # Bolt protocol
    volumes:
      - neo4j_data:/data
      - neo4j_plugins:/plugins
    environment:
      NEO4J_AUTH: neo4j/${NEO4J_PASSWORD}
      NEO4J_PLUGINS: '["apoc", "graph-data-science"]'
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.neo4j.rule=Host(\`neo4j.opendiscourse.net\`)"
      - "traefik.http.routers.neo4j.service=neo4j-service"
      - "traefik.http.services.neo4j-service.loadbalancer.server.port=7474"
      - "traefik.http.routers.neo4j.entrypoints=web"

  # --- 5. AI Inference & RAG ---
  localai:
    container_name: localai_local
    image: quay.io/go-skynet/local-ai:latest
    ports:
      - "8081:8080" # LocalAI API (exposed on 8081, internal 8080)
    volumes:
      - localai_models:/models
    command: ["/usr/bin/local-ai", "--models-path", "/models", "--debug"]
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.localai.rule=Host(\`localai.opendiscourse.net\`)"
      - "traefik.http.routers.localai.service=localai-service"
      - "traefik.http.services.localai-service.loadbalancer.server.port=8080" # LocalAI internal port
      - "traefik.http.routers.localai.entrypoints=web"

  # --- 6. Monitoring Stack (Prometheus, Grafana, Loki, OpenSearch) ---
  prometheus:
    container_name: prometheus_local
    image: prom/prometheus:latest
    ports:
      - "9090:9090" # Prometheus UI
    volumes:
      - ./prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    command: --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --web.console.libraries=/usr/share/prometheus/console_libraries --web.console.templates=/usr/share/prometheus/consoles
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prometheus.rule=Host(\`prometheus.opendiscourse.net\`)"
      - "traefik.http.routers.prometheus.service=prometheus-service"
      - "traefik.http.services.prometheus-service.loadbalancer.server.port=9090"
      - "traefik.http.routers.prometheus.entrypoints=web"

  grafana:
    container_name: grafana_local
    image: grafana/grafana:latest
    ports:
      - "3000:3000" # Grafana UI
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning/datasources:/etc/grafana/provisioning/datasources
      - ./grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD:-admin} # Set in .env or defaults
      GF_SERVER_DOMAIN: grafana.opendiscourse.net # For correct Grafana links
    depends_on:
      - prometheus
      - loki
      - opensearch # Grafana will connect to OpenSearch for logs/metrics
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(\`grafana.opendiscourse.net\`)"
      - "traefik.http.routers.grafana.service=grafana-service"
      - "traefik.http.services.grafana-service.loadbalancer.server.port=3000"
      - "traefik.http.routers.grafana.entrypoints=web"

  loki:
    container_name: loki_local
    image: grafana/loki:latest
    ports:
      - "3100:3100" # Loki API
    volumes:
      - loki_data:/loki
      - ./loki/loki-config.yaml:/etc/loki/local-config.yaml
    command: -config.file=/etc/loki/local-config.yaml
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.loki.rule=Host(\`loki.opendiscourse.net\`)"
      - "traefik.http.routers.loki.service=loki-service"
      - "traefik.http.services.loki-service.loadbalancer.server.port=3100"
      - "traefik.http.routers.loki.entrypoints=web"

  promtail:
    container_name: promtail_local
    image: grafana/promtail:latest
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ./promtail/promtail-config.yaml:/etc/promtail/config.yaml
    command: -config.file=/etc/promtail/config.yaml
    networks:
      - devops-net
    depends_on:
      - loki

  opensearch:
    container_name: opensearch_local
    image: opensearchproject/opensearch:2.12.0
    ports:
      - "9200:9200" # HTTP API
      - "9600:9600" # Transport (internal)
    volumes:
      - opensearch_data:/usr/share/opensearch/data
      - ./opensearch/config/opensearch.yml:/usr/share/opensearch/config/opensearch.yml
    environment:
      discovery.type: single-node
      OPENSEARCH_JAVA_OPTS: "-Xms512m -Xmx512m" # Adjust based on available RAM
      # Disable security for local dev, enable for production!
      OPENSEARCH_INITIAL_ADMIN_PASSWORD: ${OPENSEARCH_ADMIN_PASSWORD:-admin}
      DISABLE_SECURITY_PLUGIN: "true" # For local development ease
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.opensearch.rule=Host(\`opensearch.opendiscourse.net\`)"
      - "traefik.http.routers.opensearch.service=opensearch-service"
      - "traefik.http.services.opensearch-service.loadbalancer.server.port=9200"
      - "traefik.http.routers.opensearch.entrypoints=web"

  opensearch-dashboards:
    container_name: opensearch_dashboards_local
    image: opensearchproject/opensearch-dashboards:2.12.0
    ports:
      - "5601:5601" # Dashboards UI
    volumes:
      - ./opensearch-dashboards/config/opensearch_dashboards.yml:/usr/share/opensearch-dashboards/config/opensearch_dashboards.yml
    environment:
      OPENSEARCH_HOSTS: '["http://opensearch:9200"]'
    depends_on:
      - opensearch
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.opensearch-dashboards.rule=Host(\`opensearch-dashboards.opendiscourse.net\`)"
      - "traefik.http.routers.opensearch-dashboards.service=opensearch-dashboards-service"
      - "traefik.http.services.opensearch-dashboards-service.loadbalancer.server.port=5601"
      - "traefik.http.routers.opensearch-dashboards.entrypoints=web"

  # --- 7. Messaging Queue ---
  rabbitmq:
    container_name: rabbitmq_local
    image: rabbitmq:3-management-alpine
    ports:
      - "5672:5672" # AMQP protocol
      - "15672:15672" # Management UI
    environment:
      RABBITMQ_DEFAULT_USER: user
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASSWORD:-password} # Set in .env or defaults
    volumes:
      - ./rabbitmq/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.rabbitmq-mgmt.rule=Host(\`rabbitmq.opendiscourse.net\`)"
      - "traefik.http.routers.rabbitmq-mgmt.service=rabbitmq-mgmt-service"
      - "traefik.http.services.rabbitmq-mgmt-service.loadbalancer.server.port=15672"
      - "traefik.http.routers.rabbitmq-mgmt.entrypoints=web"

  # --- 8. Search Engine ---
  searxng:
    container_name: searxng_local
    image: searxng/searxng:latest
    ports:
      - "8083:8080" # SearXNG web UI (exposed on 8083, internal 8080)
    environment:
      SEARXNG_SECRET_KEY: ${SEARXNG_SECRET_KEY}
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.searxng.rule=Host(\`searxng.opendiscourse.net\`)"
      - "traefik.http.routers.searxng.service=searxng-service"
      - "traefik.http.services.searxng-service.loadbalancer.server.port=8080" # SearXNG internal port
      - "traefik.http.routers.searxng.entrypoints=web"

  # --- 9. FastAPI Integration Layer & RAG Implementation ---
  fastapi_app:
    container_name: fastapi_integration
    build:
      context: ./fastapi_app
      dockerfile: Dockerfile
    ports:
      - "8000:8000" # FastAPI application port (exposed on 8000, internal 8000)
    volumes:
      - ./fastapi_app:/app
    environment:
      # Database Connection Strings (using service names for internal Docker network)
      SUPABASE_URL: "http://supabase:54321" # Supabase API Gateway
      SUPABASE_ANON_KEY: ${SUPABASE_ANON_KEY} # From .env
      SUPABASE_SERVICE_ROLE_KEY: ${SUPABASE_SERVICE_ROLE_KEY} # From .env
      QDRANT_URL: "http://qdrant:6333"
      WEAVIATE_URL: "http://weaviate:8080"
      NEO4J_URI: "bolt://neo4j:7687"
      NEO4J_USER: "neo4j"
      NEO4J_PASSWORD: ${NEO4J_PASSWORD}
      LOCALAI_URL: "http://localai:8080"
      LANGFUSE_PUBLIC_KEY: ${LANGFUSE_PUBLIC_KEY} # For Langfuse integration
      LANGFUSE_SECRET_KEY: ${LANGFUSE_SECRET_KEY} # For Langfuse integration
      LANGFUSE_HOST: ${LANGFUSE_HOST:-http://localhost:3000} # Default to local Langfuse UI
      # JWT/OAuth Configuration
      JWT_SECRET_KEY: ${JWT_SECRET_KEY}
      JWT_ALGORITHM: ${JWT_ALGORITHM}
      ACCESS_TOKEN_EXPIRE_MINUTES: ${ACCESS_TOKEN_EXPIRE_MINUTES}
      OAUTH_CLIENT_ID: ${OAUTH_CLIENT_ID}
      OAUTH_CLIENT_SECRET: ${OAUTH_CLIENT_SECRET}
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.fastapi.rule=Host(\`app.opendiscourse.net\`)"
      - "traefik.http.routers.fastapi.service=fastapi-service"
      - "traefik.http.services.fastapi-service.loadbalancer.server.port=8000"
      - "traefik.http.routers.fastapi.entrypoints=web"

  # --- 10. Authentication Frontend (Simple Web Page) ---
  auth_frontend:
    container_name: auth_frontend
    build:
      context: ./auth_frontend
      dockerfile: Dockerfile
    ports:
      - "3001:3000" # React app port (exposed on 3001, internal 3000)
    volumes:
      - ./auth_frontend:/app
      - /app/node_modules # Anonymous volume to prevent host node_modules from overriding
    environment:
      REACT_APP_API_URL: "http://app.opendiscourse.net" # Point to FastAPI
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.auth-frontend.rule=Host(\`opendiscourse.net\`) || Host(\`www.opendiscourse.net\`)"
      - "traefik.http.routers.auth-frontend.service=auth-frontend-service"
      - "traefik.http.services.auth-frontend-service.loadbalancer.server.port=3000"
      - "traefik.http.routers.auth-frontend.entrypoints=web"

  # --- 11. Optional: cAdvisor for Docker Container Metrics ---
  cadvisor:
    container_name: cadvisor_local
    image: gcr.io/cadvisor/cadvisor:latest
    ports:
      - "8084:8080" # cAdvisor UI
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.cadvisor.rule=Host(\`cadvisor.opendiscourse.net\`)"
      - "traefik.http.routers.cadvisor.service=cadvisor-service"
      - "traefik.http.services.cadvisor-service.loadbalancer.server.port=8080"
      - "traefik.http.routers.cadvisor.entrypoints=web"

  # --- 12. Langfuse (Observability for LLM Apps) ---
  langfuse:
    container_name: langfuse_local
    image: ghcr.io/langfuse/langfuse:latest
    ports:
      - "3000:3000" # Langfuse UI
      - "5000:5000" # Langfuse API
    environment:
      DATABASE_URL: "postgresql://postgres:${SUPABASE_DB_PASSWORD}@supabase:5432/postgres" # Connect to Supabase DB
      NEXTAUTH_SECRET: ${LANGFUSE_NEXTAUTH_SECRET:-your-nextauth-secret}
      NEXTAUTH_URL: "http://langfuse.opendiscourse.net"
      SALT: ${LANGFUSE_SALT:-your-salt}
      # Set to "true" to enable authentication
      AUTH_ENABLED: "false" # For local dev, set to "true" and configure users for production
    depends_on:
      - supabase
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.langfuse.rule=Host(\`langfuse.opendiscourse.net\`)"
      - "traefik.http.routers.langfuse.service=langfuse-service"
      - "traefik.http.services.langfuse-service.loadbalancer.server.port=3000"
      - "traefik.http.routers.langfuse.entrypoints=web"

volumes:
  supabase_data:
  qdrant_data:
  weaviate_data:
  neo4j_data:
  neo4j_plugins:
  localai_models:
  graphite_data:
  prometheus_data:
  grafana_data:
  loki_data:
  opensearch_data:
  kong_data:
  kong_db_data:

networks:
  devops-net:
    driver: bridge
EOF
echo "docker-compose.yml created. Proceeding to create service-specific configurations."

# Create Traefik static configuration
cat <<EOF > traefik/traefik.yml
# Static configuration for Traefik
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443" # For future HTTPS
api:
  dashboard: true
  insecure: true # Enable dashboard without authentication for local dev
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
  file:
    directory: "/etc/traefik/config"
    watch: true
log:
  level: INFO
accessLog: {}
EOF
echo "traefik/traefik.yml created."

# Create Traefik dynamic configuration (empty for now, labels handle routing)
# This file can be used for more complex routing or middleware if needed.
touch traefik/config/dynamic.yml
echo "traefik/config/dynamic.yml created (empty)."

# Create Kong declarative configuration
cat <<EOF > kong/declarative/kong.yml
# Kong Declarative Configuration (kong.yml)
# This file defines services, routes, and plugins for Kong.

_format_version: "3.0"
_comment: "Declarative configuration for Kong Gateway"

services:
  - name: fastapi-service
    url: http://fastapi_app:8000 # Internal Docker service name and port
    routes:
      - name: fastapi-route
        paths:
          - /api
        strip_path: true # Remove /api prefix before forwarding to FastAPI
        # Apply JWT authentication to this route
        plugins:
          - name: jwt
            _comment: "JWT plugin configured on the route level"
            config:
              claims_to_verify: "exp" # Verify expiration claim
              key_set_by_uri: true # Kong will fetch JWKS from /auth/jwks
              uri_param_names: "token" # Allow token in query param for testing
              # Replace with your actual JWKS endpoint from FastAPI
              # Kong will fetch the public key from this endpoint to verify JWTs
              # This assumes FastAPI exposes a /auth/jwks endpoint
              key_set_uri: http://fastapi_app:8000/auth/jwks

  - name: supabase-api-service
    url: http://supabase:54321
    routes:
      - name: supabase-api-route
        paths:
          - /supabase-api
        strip_path: true

  - name: localai-service
    url: http://localai:8080
    routes:
      - name: localai-route
        paths:
          - /localai
        strip_path: true

# Consumers for JWT authentication (FastAPI will create JWTs for these)
# These are just examples. Your actual users would be managed by your auth system.
consumers:
  - username: test_user
    jwt:
      - key: "test_user_jwt_key" # This key is used by Kong to identify the consumer
        algorithm: "HS256"
        secret: "${JWT_SECRET_KEY}" # Use the same secret key as FastAPI for symmetric signing

# Global plugins (optional, apply to all services/routes)
# - name: cors
#   config:
#     origins: ["*"]
#     methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
#     headers: ["Content-Type", "Authorization"]
#     exposed_headers: ["Content-Type"]
#     credentials: true


echo "kong/declarative/kong.yml created."

Create FastAPI app directory and files

cat <<EOF > fastapi_app/Dockerfile

Dockerfile for FastAPI application

FROM python:3.10-slim-buster
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
echo "fastapi_app/Dockerfile created."
cat <<EOF > fastapi_app/requirements.txt
fastapi
uvicorn
python-dotenv
supabase-py
qdrant-client
weaviate-client
neo4j
httpx
langfuse
jose==1.11.0 # For JWT handling
passlib[bcrypt] # For password hashing
python-multipart # For form data
EOF
echo "fastapi_app/requirements.txt created."
cat <<EOF > fastapi_app/main.py

main.py for FastAPI application

from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from datetime import datetime, timedelta
from typing import Optional
from pydantic import BaseModel
from dotenv import load_dotenv
import os
import httpx # For making HTTP requests to other services
import asyncio # For async operations
from jose import JWTError, jwt
from passlib.context import CryptContext

Supabase

from supabase import create_client, Client

Qdrant

from qdrant_client import QdrantClient, models

Weaviate

import weaviate

Neo4j

from neo4j import GraphDatabase

Langfuse


from langfuse import Langfuse # Uncomment and configure if needed

load_dotenv() # Load environment variables from .env file
app = FastAPI(
title="Supabase Super Stack Integration API",
description="API to integrate various services in the local DevOps stack.",
version="1.0.0"
)

--- Environment Variables ---

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
QDRANT_URL = os.getenv("QDRANT_URL")
WEAVIATE_URL = os.getenv("WEAVIATE_URL")
NEO4J_URI = os.getenv("NEO4J_URI")
NEO4J_USER = os.getenv("NEO4J_USER")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD")
LOCALAI_URL = os.getenv("LOCALAI_URL")
LANGFUSE_PUBLIC_KEY = os.getenv("LANGFUSE_PUBLIC_KEY")
LANGFUSE_SECRET_KEY = os.getenv("LANGFUSE_SECRET_KEY")
LANGFUSE_HOST = os.getenv("LANGFUSE_HOST")

JWT Configuration

JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY")
JWT_ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 30))

--- Clients for Services ---

supabase_client: Optional[Client] = None
qdrant_client: Optional[QdrantClient] = None
weaviate_client: Optional[weaviate.Client] = None
neo4j_driver: Optional[GraphDatabase.Driver] = None
http_client: Optional[httpx.AsyncClient] = None

langfuse_client: Optional[Langfuse] = None # Uncomment if using Langfuse

@app.on_event("startup")
async def startup_event():
global supabase_client, qdrant_client, weaviate_client, neo4j_driver, http_client # , langfuse_client



# Supabase Client
if SUPABASE_URL and SUPABASE_ANON_KEY:
    supabase_client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    print(f"Connected to Supabase: {SUPABASE_URL}")

# Qdrant Client
if QDRANT_URL:
    qdrant_client = QdrantClient(url=QDRANT_URL)
    print(f"Connected to Qdrant: {QDRANT_URL}")

# Weaviate Client
if WEAVIATE_URL:
    weaviate_client = weaviate.Client(url=WEAVIATE_URL)
    print(f"Connected to Weaviate: {WEAVIATE_URL}")

# Neo4j Driver
if NEO4J_URI and NEO4J_USER and NEO4J_PASSWORD:
    neo4j_driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
    try:
        await neo4j_driver.verify_connectivity()
        print(f"Connected to Neo4j: {NEO4J_URI}")
    except Exception as e:
        print(f"Failed to connect to Neo4j: {e}")
        neo4j_driver = None

# HTTP Client for LocalAI, SearXNG, etc.
http_client = httpx.AsyncClient()

# Langfuse Client (uncomment and configure if needed)
# if LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY and LANGFUSE_HOST:
#     langfuse_client = Langfuse(
#         public_key=LANGFUSE_PUBLIC_KEY,
#         secret_key=LANGFUSE_SECRET_KEY,
#         host=LANGFUSE_HOST
#     )
#     print(f"Connected to Langfuse: {LANGFUSE_HOST}")


@app.on_event("shutdown")
async def shutdown_event():
if neo4j_driver:
await neo4j_driver.close()
print("Neo4j driver closed.")
if http_client:
await http_client.aclose()
print("HTTP client closed.")

--- Authentication (JWT) ---

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")
class User(BaseModel):
username: str
email: Optional[str] = None
full_name: Optional[str] = None
disabled: Optional[bool] = None
class UserInDB(User):
hashed_password: str
class Token(BaseModel):
access_token: str
token_type: str
class TokenData(BaseModel):
username: Optional[str] = None

Dummy user database (replace with Supabase or other DB in production)

FAKE_USERS_DB = {
"john.doe": {
"username": "john.doe",
"full_name": "John Doe",
"email": "john@example.com",
"hashed_password": pwd_context.hash("securepassword"),
"disabled": False,
},
"jane.doe": {
"username": "jane.doe",
"full_name": "Jane Doe",
"email": "jane@example.com",
"hashed_password": pwd_context.hash("anothersecurepassword"),
"disabled": True,
},
}
def verify_password(plain_password, hashed_password):
return pwd_context.verify(plain_password, hashed_password)
def get_user(username: str):
if username in FAKE_USERS_DB:
user_dict = FAKE_USERS_DB[username]
return UserInDB(**user_dict)
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
to_encode = data.copy()
if expires_delta:
expire = datetime.utcnow() + expires_delta
else:
expire = datetime.utcnow() + timedelta(minutes=15)
to_encode.update({"exp": expire})
encoded_jwt = jwt.encode(to_encode, JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)
return encoded_jwt
async def get_current_user(token: str = Depends(oauth2_scheme)):
credentials_exception = HTTPException(
status_code=status.HTTP_401_UNAUTHORIZED,
detail="Could not validate credentials",
headers={"WWW-Authenticate": "Bearer"},
)
try:
payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=[JWT_ALGORITHM])
username: str = payload.get("sub")
if username is None:
raise credentials_exception
token_data = TokenData(username=username)
except JWTError:
raise credentials_exception
user = get_user(token_data.username)
if user is None:
raise credentials_exception
return user
async def get_current_active_user(current_user: User = Depends(get_current_user)):
if current_user.disabled:
raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Inactive user")
return current_user
@app.post("/token", response_model=Token)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
user = get_user(form_data.username)
if not user or not verify_password(form_data.password, user.hashed_password):
raise HTTPException(
status_code=status.HTTP_401_UNAUTHORIZED,
detail="Incorrect username or password",
headers={"WWW-Authenticate": "Bearer"},
)
access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
access_token = create_access_token(
data={"sub": user.username}, expires_delta=access_token_expires
)
return {"access_token": access_token, "token_type": "bearer"}
@app.get("/users/me/", response_model=User)
async def read_users_me(current_user: User = Depends(get_current_active_user)):
return current_user
@app.get("/auth/jwks")
async def get_jwks():
"""
Exposes a JWKS endpoint for Kong to verify JWTs.
For symmetric keys (HS256), this is often just the secret itself or a simple public key representation.
For asymmetric keys (RS256), you would expose the public key here.
"""
# In a real app, you'd generate a proper JWKS. For symmetric, it's simpler.
# Kong's JWT plugin can be configured to use a shared secret directly.
# However, if it expects a JWKS URI, we need to provide a minimal one.
# For HS256, the 'k' (key value) is the base64url encoded secret.
import base64
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend



# This is a simplified JWKS for demonstration.
# For HS256, Kong can directly use the secret.
# If you switch to RS256, you'd generate proper RSA keys.
return {
    "keys": [
        {
            "kty": "oct",
            "kid": "my-key-id", # A unique ID for your key
            "alg": JWT_ALGORITHM,
            "k": base64.urlsafe_b64encode(JWT_SECRET_KEY.encode()).decode().rstrip("="),
            "use": "sig"
        }
    ]
}



--- Service Integration Endpoints ---

@app.get("/")
async def read_root():
return {"message": "Welcome to the Supabase Super Stack FastAPI Integration Layer!"}
@app.get("/test-supabase")
async def test_supabase():
if not supabase_client:
raise HTTPException(status_code=500, detail="Supabase client not initialized.")
try:
# Example: Fetch some data (requires a table 'test_table' in Supabase)
response = await supabase_client.from('test_table').select('*').limit(1).execute()
return {"supabase_status": "connected", "data": response.data}
except Exception as e:
raise HTTPException(status_code=500, detail=f"Supabase error: {e}")
@app.get("/test-qdrant")
async def test_qdrant():
if not qdrant_client:
raise HTTPException(status_code=500, detail="Qdrant client not initialized.")
try:
# Example: Get Qdrant cluster info
cluster_info = qdrant_client.cluster_info()
return {"qdrant_status": "connected", "cluster_info": cluster_info.dict()}
except Exception as e:
raise HTTPException(status_code=500, detail=f"Qdrant error: {e}")
@app.get("/test-weaviate")
async def test_weaviate():
if not weaviate_client:
raise HTTPException(status_code=500, detail="Weaviate client not initialized.")
try:
# Example: Check Weaviate readiness
ready = weaviate_client.is_ready()
return {"weaviate_status": "connected", "ready": ready}
except Exception as e:
raise HTTPException(status_code=500, detail=f"Weaviate error: {e}")
@app.get("/test-neo4j")
async def test_neo4j():
if not neo4j_driver:
raise HTTPException(status_code=500, detail="Neo4j driver not initialized.")
try:
# Example: Run a simple Cypher query
with neo4j_driver.session() as session:
result = session.run("RETURN 'Neo4j is connected!' AS message")
message = result.single()["message"]
return {"neo4j_status": "connected", "message": message}
except Exception as e:
raise HTTPException(status_code=500, detail=f"Neo4j error: {e}")
@app.get("/test-localai")
async def test_localai():
if not http_client:
raise HTTPException(status_code=500, detail="HTTP client not initialized.")
try:
# Example: Call LocalAI health endpoint
response = await http_client.get(f"{LOCALAI_URL}/health")
response.raise_for_status()
return {"localai_status": "connected", "health": response.json()}
except Exception as e:
raise HTTPException(status_code=500, detail=f"LocalAI error: {e}")
@app.get("/test-searxng")
async def test_searxng():
if not http_client:
raise HTTPException(status_code=500, detail="HTTP client not initialized.")
try:
# Example: Make a simple search query via SearXNG
# Note: SearXNG might have rate limits or require specific query parameters.
# This is a basic test.
response = await http_client.get(f"{os.getenv('SEARXNG_URL', 'http://searxng:8080')}/search?q=test")
response.raise_for_status()
return {"searxng_status": "connected", "response_length": len(response.text)}
except Exception as e:
raise HTTPException(status_code=500, detail=f"SearXNG error: {e}")

--- RAG Implementation Placeholder (Conceptual) ---


LocalRecall is typically used as a Python library.


Here's how you might integrate it conceptually.


You would need to install 'localrecall' via pip in your FastAPI container.


from localrecall import LocalRecall # Example import

@app.post("/rag/query")
async def rag_query(query: str):
"""
A placeholder for a RAG (Retrieval Augmented Generation) query.
This would involve:
1. Embedding the query using LocalAI or another model.
2. Performing a vector search in Qdrant/Weaviate/pgvector.
3. Retrieving relevant documents.
4. Passing documents and query to LocalAI for generation.
"""
# Example steps (pseudo-code):
# 1. Generate embedding for query using LocalAI
# embedding_response = await http_client.post(f"{LOCALAI_URL}/v1/embeddings", json={"input": query})
# query_embedding = embedding_response.json()["data"][0]["embedding"]



# 2. Search in Qdrant
#    qdrant_results = qdrant_client.search(
#        collection_name="my_collection",
#        query_vector=query_embedding,
#        limit=3
#    )
#    retrieved_docs = [hit.payload["text"] for hit in qdrant_results]

# 3. Formulate prompt for LocalAI
#    prompt = f"Context: {retrieved_docs.join('\n')}\nQuestion: {query}"

# 4. Generate response using LocalAI
#    generation_response = await http_client.post(f"{LOCALAI_URL}/v1/completions", json={"prompt": prompt})
#    generated_text = generation_response.json()["choices"][0]["text"]

return {"message": "RAG query endpoint (conceptual). Implement your RAG logic here!"}



--- Health Check ---

@app.get("/health")
async def health_check():
return {"status": "ok", "message": "FastAPI is running."}



echo "fastapi_app/main.py created."

# Create Auth Frontend (simple React app)
cat <<EOF > auth_frontend/Dockerfile
# Dockerfile for simple React frontend
FROM node:18-alpine

WORKDIR /app

COPY package.json ./
COPY package-lock.json ./
RUN npm install --silent

COPY . ./

# Build the React app
RUN npm run build

# Serve the static files
FROM nginx:alpine
COPY --from=0 /app/build /usr/share/nginx/html
EXPOSE 3000
CMD ["nginx", "-g", "daemon off;"]
EOF
echo "auth_frontend/Dockerfile created."

cat <<EOF > auth_frontend/package.json
{
  "name": "auth-frontend",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  },
  "devDependencies": {
    "react-scripts": "5.0.1"
  }
}
EOF
echo "auth_frontend/package.json created."

cat <<EOF > auth_frontend/public/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <link rel="icon" href="%PUBLIC_URL%/favicon.ico" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <meta
      name="description"
      content="Web site created using create-react-app"
    />
    <link rel="apple-touch-icon" href="%PUBLIC_URL%/logo192.png" />
    <link rel="manifest" href="%PUBLIC_URL%/manifest.json" />
    <title>OpenDiscourse - Login</title>
    <style>
        body {
            font-family: sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background-color: #f0f2f5;
            margin: 0;
        }
        .login-container {
            background-color: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 4px 10px rgba(0, 0, 0, 0.1);
            width: 100%;
            max-width: 400px;
            text-align: center;
        }
        h1 {
            color: #333;
            margin-bottom: 30px;
        }
        input[type="text"],
        input[type="password"] {
            width: calc(100% - 20px);
            padding: 10px;
            margin-bottom: 15px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 16px;
        }
        button {
            width: 100%;
            padding: 12px;
            background-color: #007bff;
            color: white;
            border: none;
            border-radius: 4px;
            font-size: 18px;
            cursor: pointer;
            transition: background-color 0.3s ease;
        }
        button:hover {
            background-color: #0056b3;
        }
        .message {
            margin-top: 20px;
            color: red;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
</body>
</html>
EOF
echo "auth_frontend/public/index.html created."

cat <<EOF > auth_frontend/src/App.js
import React, { useState } from 'react';

function App() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState('');
  const [loggedIn, setLoggedIn] = useState(false);
  const [token, setToken] = useState('');

  // Use environment variable for API URL
  const API_URL = process.env.REACT_APP_API_URL || 'http://localhost:8000';

  const handleLogin = async (e) => {
    e.preventDefault();
    setMessage('');

    try {
      const response = await fetch(`${API_URL}/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          username: username,
          password: password,
        }),
      });

      if (response.ok) {
        const data = await response.json();
        setToken(data.access_token);
        setLoggedIn(true);
        setMessage('Login successful!');
        // In a real app, you'd store the token securely (e.g., HttpOnly cookie)
        console.log('Access Token:', data.access_token);
      } else {
        const errorData = await response.json();
        setMessage(`Login failed: ${errorData.detail || 'Invalid credentials'}`);
      }
    } catch (error) {
      setMessage('Network error. Could not connect to the API.');
      console.error('Login error:', error);
    }
  };

  const handleTestAPI = async () => {
    setMessage('');
    try {
      const response = await fetch(`${API_URL}/users/me/`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      if (response.ok) {
        const data = await response.json();
        setMessage(`API Test successful! Welcome, ${data.username}`);
      } else {
        const errorData = await response.json();
        setMessage(`API Test failed: ${errorData.detail || 'Unauthorized'}`);
      }
    } catch (error) {
      setMessage('Network error during API test.');
      console.error('API test error:', error);
    }
  };

  const handleLogout = () => {
    setLoggedIn(false);
    setToken('');
    setUsername('');
    setPassword('');
    setMessage('Logged out.');
  };

  return (
    <div className="login-container">
      <h1>OpenDiscourse</h1>
      {!loggedIn ? (
        <form onSubmit={handleLogin}>
          <input
            type="text"
            placeholder="Username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            required
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          <button type="submit">Login</button>
          {message && <p className="message">{message}</p>}
        </form>
      ) : (
        <div>
          <p>You are logged in!</p>
          <button onClick={handleTestAPI}>Test Authenticated API</button>
          <button onClick={handleLogout} style={{ marginTop: '10px', backgroundColor: '#dc3545' }}>Logout</button>
          {message && <p className="message">{message}</p>}
        </div>
      )}
    </div>
  );
}

export default App;
EOF
echo "auth_frontend/src/App.js created."

cat <<EOF > auth_frontend/src/index.js
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF
echo "auth_frontend/src/index.js created."

cat <<EOF > auth_frontend/src/reportWebVitals.js
// If you want to start measuring performance in your app, pass a function
// to log results (for example: reportWebVitals(console.log))
// or send to an analytics endpoint. Learn more: https://bit.ly/CRA-vitals
const reportWebVitals = onPerfEntry => {
  if (onPerfEntry && onPerfEntry instanceof Function) {
    import('web-vitals').then(({ getCLS, getFID, getFCP, getLCP, getTTFB }) => {
      getCLS(onPerfEntry);
      getFID(onPerfEntry);
      getFCP(onPerfEntry);
      getLCP(onPerfEntry);
      getTTFB(onPerfEntry);
    });
  }
};

export default reportWebVitals;
EOF
echo "auth_frontend/src/reportWebVitals.js created."

cat <<EOF > auth_frontend/src/setupTests.js
// jest-dom adds custom jest matchers for asserting on DOM nodes.
// allows you to do things like:
// expect(element).toHaveTextContent(/react/i)
// learn more: https://github.com/testing-library/jest-dom
import '@testing-library/jest-dom';
EOF
echo "auth_frontend/src/setupTests.js created."


# Create Grafana data source provisioning
cat <<EOF > grafana/provisioning/datasources/datasources.yml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    access: proxy
    isDefault: true
    version: 1
    editable: true
  - name: Loki
    type: loki
    url: http://loki:3100
    access: proxy
    version: 1
    editable: true
  - name: OpenSearch
    type: opensearch
    url: http://opensearch:9200
    access: proxy
    version: 1
    editable: true
    jsonData:
      esVersion: 7.10.2 # Or the version of your OpenSearch (2.x is compatible with ES 7.10)
      timeField: "@timestamp" # Common log timestamp field
EOF
echo "grafana/provisioning/datasources/datasources.yml created."

# Create Loki configuration
cat <<EOF > loki/loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9095

common:
  path_prefix: /loki
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory
  storage:
    filesystem:
      directory: /loki/data
  # This is for local development only.
  # For production, use a proper object storage (S3, GCS, Azure Blob)
  # or a distributed file system.
  limits_config:
    enforce_metric_name: false
    reject_old_samples: true
    reject_old_samples_max_age: 168h

schema_config:
  configs:
    - from: 2020-10-27
      store: filesystem
      object_store: filesystem
      schema: v11
      period: 168h
EOF
echo "loki/loki-config.yaml created."

# Create Promtail configuration
cat <<EOF > promtail/promtail-config.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          __path__: /var/lib/docker/containers/*/*log
    pipeline_stages:
      - docker: {}
      - drop:
          source: "__stream__"
          expression: "stdout|stderr" # Drop the stream name from labels
      - labels:
          container_name:
          image_name:
          com_docker_compose_service:
          com_docker_compose_project:
EOF
echo "promtail/promtail-config.yaml created."

# Create Prometheus configuration
cat <<EOF > prometheus/prometheus.yml
global:
  scrape_interval: 15s # How frequently to scrape targets
  evaluation_interval: 15s # How frequently to evaluate rules

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090'] # Prometheus itself

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080'] # cAdvisor for Docker container metrics

  - job_name: 'fastapi_app'
    static_configs:
      - targets: ['fastapi_app:8000'] # FastAPI app (if it exposes /metrics)
    relabel_configs:
      - source_labels: [__address__]
        regex: '(.*):8000'
        target_label: instance
        replacement: '\$1'

  - job_name: 'supabase_exporter'
    # You would typically use a custom exporter for Supabase metrics
    # For simplicity, we're not including a dedicated Supabase exporter here.
    # You could add one if available or write a custom Python script to expose metrics.
    static_configs:
      - targets: ['supabase:5432'] # PostgreSQL port for pgvector, not directly for metrics
    relabel_configs:
      - source_labels: [__address__]
        regex: '(.*):5432'
        target_label: instance
        replacement: 'supabase_db'
    # This is a placeholder. A proper Postgres exporter would be needed.

  - job_name: 'qdrant'
    # Qdrant exposes metrics on /metrics endpoint by default
    static_configs:
      - targets: ['qdrant:6333']
    metrics_path: /metrics

  - job_name: 'weaviate'
    # Weaviate exposes metrics on /metrics endpoint by default
    static_configs:
      - targets: ['weaviate:8080']
    metrics_path: /metrics

  - job_name: 'neo4j'
    # Neo4j has a Prometheus plugin or metrics endpoint
    static_configs:
      - targets: ['neo4j:7474'] # Assuming Neo4j metrics are exposed on the HTTP port
    metrics_path: /metrics # Adjust if Neo4j exposes metrics on a different path or port

  - job_name: 'rabbitmq'
    # RabbitMQ management plugin exposes Prometheus metrics
    static_configs:
      - targets: ['rabbitmq:15672']
    metrics_path: /metrics

  - job_name: 'localai'
    # LocalAI might expose metrics, check its documentation
    static_configs:
      - targets: ['localai:8080']
    metrics_path: /metrics # Adjust if LocalAI exposes metrics

  - job_name: 'searxng'
    # SearXNG typically does not expose Prometheus metrics directly
    # You might need a custom exporter or scrape logs for insights
    static_configs:
      - targets: ['searxng:8080']
    metrics_path: /metrics # Placeholder
EOF
echo "prometheus/prometheus.yml created."

# Create OpenSearch configuration
cat <<EOF > opensearch/config/opensearch.yml
# Basic OpenSearch configuration for single-node development
cluster.name: opensearch-docker-cluster
node.name: opensearch-node1
network.host: 0.0.0.0
http.port: 9200
transport.port: 9600
# Disable security for local development
plugins.security.disabled: true
EOF
echo "opensearch/config/opensearch.yml created."

# Create OpenSearch Dashboards configuration
cat <<EOF > opensearch-dashboards/config/opensearch_dashboards.yml
# Basic OpenSearch Dashboards configuration
server.host: "0.0.0.0"
server.name: "opensearch-dashboards"
opensearch.hosts: ["http://opensearch:9200"]
# Disable security for local development
opensearch_security.enabled: false
EOF
echo "opensearch-dashboards/config/opensearch_dashboards.yml created."

# Create RabbitMQ configuration
cat <<EOF > rabbitmq/rabbitmq.conf
# Basic RabbitMQ configuration
listeners.tcp.default = 5672
management.listener.port = 15672
management.listener.ip = 0.0.0.0
# Enable Prometheus metrics plugin (usually enabled by default with management image)
# management.prometheus.enabled = true
EOF
echo "rabbitmq/rabbitmq.conf created."

echo "All initial configuration files created."
echo "==================================================================="
echo " Setup script finished. Next steps: "
echo "   1. Review and fill in secrets in the '.env' file."
echo "   2. Run 'docker compose up -d' from the root of this directory."
echo "   3. Access services via Traefik: "
echo "      - Main Landing Page: http://opendiscourse.net"
echo "      - FastAPI App: http://app.opendiscourse.net/docs"
echo "      - Supabase Studio: http://supabase.opendiscourse.net"
echo "      - Kong Admin: http://kong-admin.opendiscourse.net (port 8001 directly for API)"
echo "      - Qdrant UI: http://qdrant.opendiscourse.net"
echo "      - Weaviate UI: http://weaviate.opendiscourse.net"
echo "      - Neo4j Browser: http://neo4j.opendiscourse.net"
echo "      - LocalAI: http://localai.opendiscourse.net"
echo "      - Prometheus: http://prometheus.opendiscourse.net"
echo "      - Grafana: http://grafana.opendiscourse.net"
echo "      - Loki: http://loki.opendiscourse.net"
echo "      - OpenSearch: http://opensearch.opendiscourse.net"
echo "      - OpenSearch Dashboards: http://opensearch-dashboards.opendiscourse.net"
echo "      - RabbitMQ Management: http://rabbitmq.opendiscourse.net"
echo "      - SearXNG: http://searxng.opendiscourse.net"
echo "      - cAdvisor: http://cadvisor.opendiscourse.net"
echo "      - Langfuse: http://langfuse.opendiscourse.net"
echo "   4. Add '127.0.0.1 opendiscourse.net www.opendiscourse.net api.opendiscourse.net app.opendiscourse.net supabase.opendiscourse.net supabase-api.opendiscourse.net qdrant.opendiscourse.net weaviate.opendiscourse.net neo4j.opendiscourse.net localai.opendiscourse.net prometheus.opendiscourse.net grafana.opendiscourse.net loki.opendiscourse.net opensearch.opendiscourse.net opensearch-dashboards.opendiscourse.net rabbitmq.opendiscourse.net searxng.opendiscourse.net cadvisor.opendiscourse.net langfuse.opendiscourse.net kong-admin.opendiscourse.net' to your /etc/hosts file (or C:\Windows\System32\drivers\etc\hosts on Windows)."
echo "==================================================================="


</immersive>

Explanation of Components and Setup


1. setup-supabase-super-stack.sh

This script automates the initial setup:
Docker Check: Ensures Docker and Docker Compose are available.
Supabase CLI: Installs the supabase command-line tool.
Supabase Project Initialization: Creates a supabase-super-stack directory and runs supabase init to set up the local Supabase project structure.
pgvector Migration: Automatically creates and applies a database migration to enable the pgvector extension in your local Supabase PostgreSQL instance.
Directory Creation: Sets up all necessary subdirectories for configurations (Traefik, Kong, FastAPI, monitoring, etc.).
File Generation: Dynamically creates the .env file, docker-compose.yml, and initial configuration files for each service.

2. .env File

This file (.env) will contain all your sensitive environment variables and configurable parameters. It's crucial to review and update these values, especially passwords and secrets, before running the stack.

3. docker-compose.yml

This is the heart of your local stack, defining all services, their dependencies, ports, volumes, and network configurations:
traefik: The edge reverse proxy. It listens on ports 80 (HTTP) and 8080 (dashboard). It uses Docker labels on other services to automatically discover and route traffic. The traefik.yml provides static configuration, and traefik/config is for dynamic rules (though most routing is done via Docker labels here).
kong-db & kong: Kong API Gateway. kong-db is a PostgreSQL instance dedicated to Kong's configuration. Kong itself exposes ports for its proxy (8000/8443) and admin API (8001/8444) and Kong Manager GUI (8002). Traefik routes api.opendiscourse.net to Kong's proxy and kong-admin.opendiscourse.net to its admin interface.
supabase: Your local Supabase instance, including PostgreSQL (with pgvector), Supabase Studio, and the API Gateway.
qdrant: A high-performance vector similarity search engine.
weaviate: Another powerful vector database, often used for semantic search and RAG.
neo4j: A graph database.
localai: For local AI inference, allowing you to run various LLMs and embedding models.
Monitoring Stack:
prometheus: Collects metrics from all services.
grafana: Visualizes metrics and logs from Prometheus, Loki, and OpenSearch.
loki: A log aggregation system, similar to Prometheus but for logs.
promtail: An agent that ships logs from your Docker containers to Loki.
opensearch: A distributed search and analytics engine, used here for structured logging and potentially metrics.
opensearch-dashboards: The visualization layer for OpenSearch.
cadvisor: Collects container resource usage metrics, which Prometheus scrapes.
rabbitmq: A robust messaging queue for asynchronous communication between services.
searxng: A privacy-respecting metasearch engine.
fastapi_app: Your custom Python application serving as the integration layer. It will host API endpoints, handle authentication, and orchestrate interactions between the various databases and AI services.
auth_frontend: A simple React application serving as the web-facing login/landing page for opendiscourse.net.
langfuse: An open-source observability and analytics platform for LLM applications, connecting to your Supabase database.
Networks & Volumes: A single devops-net bridge network allows all containers to communicate using their service names. Named volumes ensure data persistence across container restarts.

Next Steps & How to Use

Save the Script: Save the content above as setup-supabase-super-stack.sh in a new, empty directory.
Make Executable: chmod +x setup-supabase-super-stack.sh
Run the Script: ./setup-supabase-super-stack.sh
This will create the supabase-super-stack directory, initialize Supabase, and generate all the docker-compose.yml and configuration files.
Edit .env: Crucially, open the newly created .env file and fill in all the placeholder secrets and passwords.
Update /etc/hosts: Add the provided lines to your /etc/hosts file (or C:\Windows\System32\drivers\etc\hosts on Windows). This maps the custom subdomains to your local Docker host.
Start the Stack: Navigate to the root directory where docker-compose.yml is located and run:
docker compose up -d
This will build the custom images and start all services in the background.
Access Services: Once all services are up (this may take a few minutes, especially for OpenSearch and Neo4j's first boot), you can access them via your browser using the subdomains listed in the script's final output.
In the next part, I will provide the detailed configurations for each service, including the Kong API schema, Prometheus scraping, Grafana provisioning, and the FastAPI application's internal logic.
Sources
1. https://www.cnblogs.com/Riven-LOL/articles/15874759.html
