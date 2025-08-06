#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

# --- Source Configuration ---
if [ -f "config.sh" ]; then
  source config.sh
else
  echo "ERROR: config.sh not found. Please create it before running this script."
  exit 1
fi

# --- Check for Root Privileges ---
if [ "\$EUID" -ne 0 ]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

echo "==================================================================="
echo " Deploying Production-Ready Super Stack"
echo "==================================================================="
echo "Domain: $DOMAIN"
echo "App Root: $APP_ROOT"
echo "Web Root: $WEB_ROOT"
echo "==================================================================="

# --- Section 1: Create Directories and Permissions ---
echo "--> [1/5] Creating directories and setting permissions..."
mkdir -p "$WEB_ROOT"
mkdir -p "$APP_ROOT"/{traefik,n8n_data,fastapi_app,nextjs_app,prometheus,grafana/provisioning/{datasources,dashboards},loki,promtail,opensearch/config,opensearch-dashboards/config,supabase}
touch "$APP_ROOT/traefik/acme.json"
chmod 600 "$APP_ROOT/traefik/acme.json"
chown -R www-data:www-data "$WEB_ROOT"
echo "Directories created."

# --- Section 2: Create Secure .env File ---
echo "--> [2/5] Creating secure .env file..."
# Generate a hashed password for Traefik basic auth
export TRAEFIK_ADMIN_PASSWORD_HASH=\$(htpasswd -nb admin "\$TRAEFIK_ADMIN_PASSWORD")

cat <<EOF > "$APP_ROOT/.env"
# --- Production Environment Variables ---
DOMAIN=$DOMAIN
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
TRAEFIK_ADMIN_PASSWORD_HASH=$TRAEFIK_ADMIN_PASSWORD_HASH

# Supabase - These are retrieved after first launch
# SUPABASE_ANON_KEY=
# SUPABASE_SERVICE_ROLE_KEY=

# n8n
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)

# FastAPI
JWT_SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 64)
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
EOF
echo ".env file created in $APP_ROOT/.env. Please review and save these passwords."

# --- Section 3: Create Production Docker Compose with n8n ---
echo "--> [3/5] Creating production docker-compose.yml with n8n..."
cat <<'EOF' > "$APP_ROOT/docker-compose.yml"
version: '3.8'

networks:
  devops-net:
    driver: bridge

volumes:
  supabase_data:
  n8n_data:
  qdrant_data:
  localai_models:

services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.myresolver.acme.tlschallenge=true
      - --certificatesresolvers.myresolver.acme.email=${LETSENCRYPT_EMAIL}
      - --certificatesresolvers.myresolver.acme.storage=/etc/traefik/acme.json
    ports: ["80:80", "443:443"]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/acme.json:/etc/traefik/acme.json
    networks: [devops-net]
    env_file: .env
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik-dashboard.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
      - "traefik.http.routers.traefik-dashboard.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=admin:${TRAEFIK_ADMIN_PASSWORD_HASH}"

  nextjs_app:
    build: { context: /var/www/html/super-stack, dockerfile: Dockerfile }
    container_name: nextjs_app
    networks: [devops-net]
    env_file: .env
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nextjs.rule=Host(`${DOMAIN}`) || Host(`www.${DOMAIN}`)"
      - "traefik.http.routers.nextjs.entrypoints=websecure"
      - "traefik.http.routers.nextjs.tls.certresolver=myresolver"
      - "traefik.http.services.nextjs.loadbalancer.server.port=3000"

  fastapi_app:
    build: { context: ./fastapi_app }
    container_name: fastapi_app
    networks: [devops-net]
    env_file: .env
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.fastapi.rule=Host(`api.${DOMAIN}`)"
      - "traefik.http.routers.fastapi.entrypoints=websecure"
      - "traefik.http.routers.fastapi.tls.certresolver=myresolver"
      - "traefik.http.services.fastapi.loadbalancer.server.port=8000"

  n8n:
    image: n8nio/n8n
    container_name: n8n
    volumes: [n8n_data:/home/node/.n8n]
    networks: [devops-net]
    env_file: .env
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`n8n.${DOMAIN}`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=myresolver"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"

  supabase:
    image: supabase/cli:latest
    container_name: supabase
    command: start
    volumes: ["./supabase:/project", "supabase_data:/var/lib/postgresql/data"]
    networks: [devops-net]
    env_file: .env
    # No ports exposed to the web

  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    volumes: [qdrant_data:/qdrant/storage]
    networks: [devops-net]

  localai:
    image: quay.io/go-skynet/local-ai:latest
    container_name: localai
    volumes: [localai_models:/models]
    command: ["/usr/bin/local-ai", "--models-path", "/models"]
    networks: [devops-net]
EOF
echo "docker-compose.yml created."

# --- Section 4: Create Application Code ---
echo "--> [4/5] Creating application code..."
# This will be handled in subsequent steps to build out the full RAG UI and API.
# For now, create placeholders.
mkdir -p "$APP_ROOT/fastapi_app"
touch "$APP_ROOT/fastapi_app/main.py"
mkdir -p "$WEB_ROOT/pages"
touch "$WEB_ROOT/pages/index.js"
echo "Placeholder application files created."

# --- Section 5: Create Helper Scripts ---
echo "--> [5/5] Creating helper scripts..."
cat <<EOF > "/usr/local/bin/setup_firewall.sh"
#!/bin/bash
echo "Configuring firewall (ufw)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable
echo "Firewall enabled. Only SSH, HTTP, and HTTPS are allowed."
EOF
chmod +x "/usr/local/bin/setup_firewall.sh"
echo "Firewall script created at /usr/local/bin/setup_firewall.sh"

echo "==================================================================="
echo " Deployment Script Finished"
echo "==================================================================="
echo "NEXT STEPS:"
echo "1. Edit 'config.sh' with your domain, email, and passwords."
echo "2. Run this script again: sudo ./deploy.sh"
echo "3. Run the firewall script ONCE: sudo /usr/local/bin/setup_firewall.sh"
echo "4. cd $APP_ROOT && sudo docker-compose up -d"
echo "==================================================================="
