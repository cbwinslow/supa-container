#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configurable Variables ---
DOMAIN="local.dev" # Change this to your preferred local domain

echo "==================================================================="
echo " Starting Supabase Super Stack Local Development Environment Setup."
echo " Domain: $DOMAIN"
echo " This will create multiple directories and configuration files.   "
echo " Ensure Docker, Docker Compose, and Bun are installed.     "
echo "==================================================================="

# --- Section 1: Check for Dependencies ---
echo "--> [1/7] Checking for dependencies..."
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install it and try again."
    exit 1
fi
if ! command -v docker-compose &> /dev/null; then
    echo "Error: Docker Compose is not installed. Please install it and try again."
    exit 1
fi
if ! command -v bun &> /dev/null; then
    echo "Bun is not installed. Installing now..."
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    echo "Bun installed successfully."
fi
echo "Dependencies found."

# --- Section 2: Install Supabase CLI ---
echo "--> [2/7] Installing Supabase CLI..."
if ! command -v supabase &> /dev/null; then
    echo "Installing Supabase CLI..."
curl -sL https://supabase.com/docs/install/cli | sh
else
    echo "Supabase CLI already installed."
fi

# --- Section 3: Initialize Supabase Project ---
echo "--> [3/7] Initializing Supabase project..."
PROJECT_DIR="supabase-super-stack"
if [ ! -d "$PROJECT_DIR" ]; then
    mkdir "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    supabase init
else
    echo "Supabase project directory '$PROJECT_DIR' already exists. Skipping 'supabase init'."
    cd "$PROJECT_DIR"
fi

# --- Section 4: Prepare Supabase for pgvector ---
echo "--> [4/7] Preparing Supabase for pgvector..."
supabase start || true
PGVECTOR_MIGRATION_FILE="supabase/migrations/$(date +%Y%m%d%H%M%S)_add_pgvector.sql"
if [ ! -f "$PGVECTOR_MIGRATION_FILE" ]; then
    echo "CREATE EXTENSION IF NOT EXISTS vector;" > "$PGVECTOR_MIGRATION_FILE"
    supabase db reset --local
else
    echo "pgvector migration already exists."
fi
echo "Supabase pgvector setup complete."

# --- Section 5: Create project directories ---
echo "--> [5/7] Creating project directories..."
cd ..
mkdir -p traefik/config kong/declarative fastapi_app nextjs_app prometheus grafana/provisioning/{datasources,dashboards} loki promtail opensearch/config opensearch-dashboards/config rabbitmq

# --- Section 6: Create Next.js App with Bun ---
echo "--> [6/7] Creating Next.js frontend with Bun..."
cat <<EOF > nextjs_app/package.json
{
  "name": "nextjs-frontend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "react": "^18",
    "react-dom": "^18",
    "next": "14.2.3",
    "tailwindcss": "^3.4.1",
    "postcss": "^8",
    "autoprefixer": "^10.0.1"
  }
}
EOF
cat <<EOF > nextjs_app/next.config.mjs
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
};

export default nextConfig;
EOF
cat <<EOF > nextjs_app/tailwind.config.js
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
};
EOF
mkdir -p nextjs_app/pages
cat <<EOF > nextjs_app/pages/index.js
import Head from 'next/head';

export default function Home() {
  return (
    <div className="bg-gray-900 text-white min-h-screen flex items-center justify-center">
      <Head>
        <title>Super Stack</title>
      </Head>
      <main className="text-center">
        <h1 className="text-6xl font-bold">Welcome to the Super Stack</h1>
        <p className="text-xl mt-4">Your Next.js frontend is up and running!</p>
      </main>
    </div>
  );
}
EOF
cat <<EOF > nextjs_app/Dockerfile
FROM oven/bun:1.0-alpine AS base
WORKDIR /usr/src/app

COPY package.json bun.lockb* ./
RUN bun install --frozen-lockfile

COPY . .
RUN bun run build

FROM oven/bun:1.0-alpine AS release
WORKDIR /usr/src/app

COPY --from=base /usr/src/app/node_modules ./node_modules
COPY --from=base /usr/src/app/public ./public
COPY --from=base /usr/src/app/.next ./.next

EXPOSE 3000
CMD ["bun", "start"]
EOF

# --- Section 7: Create Docker Compose and other configs ---
echo "--> [7/7] Creating Docker Compose and other configuration files..."
# (This section will now generate the docker-compose.yml and other files)
# ... (The rest of the script will be added here in the next step)
echo "All files created successfully!"

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
SEARXNG_SECRET_KEY=\$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 32 ; echo '') # Generates a random 32-char key

# FastAPI App
FASTAPI_APP_SECRET_KEY=\$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 32 ; echo '') # Generates a random 32-char key

# Kong Admin API Token (for declarative config)
KONG_ADMIN_TOKEN=\$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 32 ; echo '')

# OAuth/JWT
# For local development, these can be simple. For production, use secure values.
OAUTH_CLIENT_ID=my_oauth_client
OAUTH_CLIENT_SECRET=my_oauth_secret
JWT_SECRET_KEY=\$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 64 ; echo '') # Longer key for JWT signing
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
      - "traefik.http.routers.traefik-dashboard.rule=Host(`traefik.$DOMAIN`)"
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
      POSTGRES_PASSWORD: "${KONG_DB_PASSWORD:-kong}" # Use .env or default
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
      KONG_PG_PASSWORD: "${KONG_DB_PASSWORD:-kong}"
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
      - "traefik.http.routers.kong-proxy.rule=Host(`api.$DOMAIN`)"
      - "traefik.http.routers.kong-proxy.service=kong-proxy-service"
      - "traefik.http.services.kong-proxy-service.loadbalancer.server.port=8000"
      - "traefik.http.routers.kong-admin.rule=Host(`kong-admin.$DOMAIN`)"
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
      POSTGRES_PASSWORD: "${SUPABASE_DB_PASSWORD}"
      POSTGRES_USER: "postgres"
      POSTGRES_DB: "postgres"
      SUPABASE_ANON_KEY: "${SUPABASE_ANON_KEY}" # From .env
      SUPABASE_SERVICE_ROLE_KEY: "${SUPABASE_SERVICE_ROLE_KEY}" # From .env
      JWT_SECRET: "${SUPABASE_JWT_SECRET}" # From .env
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-studio.rule=Host(`supabase.$DOMAIN`)"
      - "traefik.http.routers.supabase-studio.service=supabase-studio-service"
      - "traefik.http.services.supabase-studio-service.loadbalancer.server.port=8000" # Supabase Studio port
      - "traefik.http.routers.supabase-studio.entrypoints=web"
      - "traefik.http.routers.supabase-api.rule=Host(`supabase-api.$DOMAIN`)"
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
      - "traefik.http.routers.qdrant.rule=Host(`qdrant.$DOMAIN`)"
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
      - "traefik.http.routers.weaviate.rule=Host(`weaviate.$DOMAIN`)"
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
      NEO4J_AUTH: neo4j/"${NEO4J_PASSWORD}"
      NEO4J_PLUGINS: '["apoc", "graph-data-science"]'
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.neo4j.rule=Host(`neo4j.$DOMAIN`)"
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
      - "traefik.http.routers.localai.rule=Host(`localai.$DOMAIN`)"
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
      - "traefik.http.routers.prometheus.rule=Host(`prometheus.$DOMAIN`)"
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
      GF_SECURITY_ADMIN_PASSWORD: "${GRAFANA_ADMIN_PASSWORD:-admin}" # Set in .env or defaults
      GF_SERVER_DOMAIN: grafana.$DOMAIN # For correct Grafana links
    depends_on:
      - prometheus
      - loki
      - opensearch # Grafana will connect to OpenSearch for logs/metrics
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.$DOMAIN`)"
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
      - "traefik.http.routers.loki.rule=Host(`loki.$DOMAIN`)"
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
      OPENSEARCH_INITIAL_ADMIN_PASSWORD: "${OPENSEARCH_ADMIN_PASSWORD:-admin}"
      DISABLE_SECURITY_PLUGIN: "true" # For local development ease
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.opensearch.rule=Host(`opensearch.$DOMAIN`)"
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
      - "traefik.http.routers.opensearch-dashboards.rule=Host(`opensearch-dashboards.$DOMAIN`)"
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
      RABBITMQ_DEFAULT_PASS: "${RABBITMQ_PASSWORD:-password}" # Set in .env or defaults
    volumes:
      - ./rabbitmq/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.rabbitmq-mgmt.rule=Host(`rabbitmq.$DOMAIN`)"
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
      SEARXNG_SECRET_KEY: "${SEARXNG_SECRET_KEY}"
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.searxng.rule=Host(`searxng.$DOMAIN`)"
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
      SUPABASE_ANON_KEY: "${SUPABASE_ANON_KEY}" # From .env
      SUPABASE_SERVICE_ROLE_KEY: "${SUPABASE_SERVICE_ROLE_KEY}" # From .env
      QDRANT_URL: "http://qdrant:6333"
      WEAVIATE_URL: "http://weaviate:8080"
      NEO4J_URI: "bolt://neo4j:7687"
      NEO4J_USER: "neo4j"
      NEO4J_PASSWORD: "${NEO4J_PASSWORD}"
      LOCALAI_URL: "http://localai:8080"
      LANGFUSE_PUBLIC_KEY: "${LANGFUSE_PUBLIC_KEY}" # For Langfuse integration
      LANGFUSE_SECRET_KEY: "${LANGFUSE_SECRET_KEY}" # For Langfuse integration
      LANGFUSE_HOST: "${LANGFUSE_HOST:-http://localhost:3000}" # Default to local Langfuse UI
      # JWT/OAuth Configuration
      JWT_SECRET_KEY: "${JWT_SECRET_KEY}"
      JWT_ALGORITHM: "${JWT_ALGORITHM}"
      ACCESS_TOKEN_EXPIRE_MINUTES: "${ACCESS_TOKEN_EXPIRE_MINUTES}"
      OAUTH_CLIENT_ID: "${OAUTH_CLIENT_ID}"
      OAUTH_CLIENT_SECRET: "${OAUTH_CLIENT_SECRET}"
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.fastapi.rule=Host(`app.$DOMAIN`)"
      - "traefik.http.routers.fastapi.service=fastapi-service"
      - "traefik.http.services.fastapi-service.loadbalancer.server.port=8000"
      - "traefik.http.routers.fastapi.entrypoints=web"

  # --- 10. Authentication Frontend (Simple Web Page) ---
  nextjs_app:
    container_name: nextjs_app
    build:
      context: ./nextjs_app
      dockerfile: Dockerfile
    ports:
      - "3001:3000" # React app port (exposed on 3001, internal 3000)
    volumes:
      - ./nextjs_app:/app
      - /app/node_modules # Anonymous volume to prevent host node_modules from overriding
    environment:
      REACT_APP_API_URL: "http://app.$DOMAIN" # Point to FastAPI
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.auth-frontend.rule=Host(`$DOMAIN`) || Host(`www.$DOMAIN`)"
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
      - "traefik.http.routers.cadvisor.rule=Host(`cadvisor.$DOMAIN`)"
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
      NEXTAUTH_SECRET: "${LANGFUSE_NEXTAUTH_SECRET:-your-nextauth-secret}"
      NEXTAUTH_URL: "http://langfuse.$DOMAIN"
      SALT: "${LANGFUSE_SALT:-your-salt}"
      # Set to "true" to enable authentication
      AUTH_ENABLED: "false" # For local dev, set to "true" and configure users for production
    depends_on:
      - supabase
    networks:
      - devops-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.langfuse.rule=Host(`langfuse.$DOMAIN`)"
      - "traefik.http.routers.langfuse.service=langfuse-service"
      - "traefik.http.services.langfuse-service.loadbalancer.server.port=3000"
      - "traefik.http.routers.langfuse.entrypoints=web"
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
EOF
echo "kong/declarative/kong.yml created."

# Create FastAPI app directory and files
cat <<EOF > fastapi_app/Dockerfile
# Dockerfile for FastAPI application
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
cryptography
EOF
echo "fastapi_app/requirements.txt created."

cat <<EOF > fastapi_app/main.py
# main.py for FastAPI application
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

# Supabase
from supabase import create_client, Client

# Qdrant
from qdrant_client import QdrantClient, models

# Weaviate
import weaviate

# Neo4j
from neo4j import GraphDatabase

# Langfuse
from langfuse import Langfuse # Uncomment and configure if needed

load_dotenv() # Load environment variables from .env file
app = FastAPI(
title="Supabase Super Stack Integration API",
description="API to integrate various services in the local DevOps stack.",
version="1.0.0"
)

# --- Environment Variables ---
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

# JWT Configuration
JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY")
JWT_ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 30))

# --- Clients for Services ---
supabase_client: Optional[Client] = None
qdrant_client: Optional[QdrantClient] = None
weaviate_client: Optional[weaviate.Client] = None
neo4j_driver: Optional[GraphDatabase.Driver] = None
http_client: Optional[httpx.AsyncClient] = None
# langfuse_client: Optional[Langfuse] = None # Uncomment if using Langfuse

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

# --- Authentication (JWT) ---
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

# Dummy user database (replace with Supabase or other DB in production)
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
def get_jwks():
    """
    Exposes a JWKS endpoint for Kong to verify JWTs.
    """
    import base64
    return {
        "keys": [
            {
                "kty": "oct",
                "kid": "my-key-id",
                "alg": JWT_ALGORITHM,
                "k": base64.urlsafe_b64encode(JWT_SECRET_KEY.encode()).decode().rstrip("="),
                "use": "sig"
            }
        ]
    }

# --- Service Integration Endpoints ---
@app.get("/")
def read_root():
    return {"message": "Welcome to the Supabase Super Stack FastAPI Integration Layer!"}

# ... (other test endpoints remain the same)
@app.get("/health")
def health_check():
    return {"status": "ok", "message": "FastAPI is running."}
