#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
# Root directory for the web application frontend
WEB_ROOT="/var/www/html/super-stack"
# Root directory for the backend services and all configurations
APP_ROOT="/opt/supabase-super-stack"
# Domain for the services
DOMAIN="local.dev"

# --- Check for Root Privileges ---
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

echo "==================================================================="
echo " Deploying Supabase Super Stack to Production Directories"
echo "==================================================================="
echo "Web Frontend will be installed in: $WEB_ROOT"
echo "Backend & Configs will be installed in: $APP_ROOT"
echo "==================================================================="

# --- Section 1: Install Dependencies (Bun) ---
echo "--> [1/5] Checking for dependencies..."
if ! command -v bun &> /dev/null; then
    echo "Bun is not installed. Installing now..."
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    echo "Bun installed successfully."
fi
echo "Dependencies are ready."

# --- Section 2: Create Directories and Set Permissions ---
echo "--> [2/5] Creating installation directories..."
mkdir -p "$WEB_ROOT"
mkdir -p "$APP_ROOT/traefik/config,kong/declarative,fastapi_app,prometheus,grafana/provisioning/(datasources,dashboards),loki,promtail,opensearch/config,opensearch-dashboards/config,rabbitmq,supabase"

# Set permissions for the web root
chown -R www-data:www-data "$WEB_ROOT"
echo "Directories created and permissions set."

# --- Section 3: Create Next.js App ---
echo "--> [3/5] Creating Next.js frontend in $WEB_ROOT..."
# We create the files directly as the www-data user might not have a home dir for bun install
cat <<EOF > "$WEB_ROOT/package.json"
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
cat <<EOF > "$WEB_ROOT/next.config.mjs"
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
};
export default nextConfig;
EOF
cat <<EOF > "$WEB_ROOT/tailwind.config.js"
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: { extend: {} },
  plugins: [],
};
EOF
mkdir -p "$WEB_ROOT/pages"
cat <<EOF > "$WEB_ROOT/pages/index.js"
import Head from 'next/Head';
export default function Home() {
  return (
    <div className="bg-gray-900 text-white min-h-screen flex items-center justify-center">
      <Head><title>Super Stack</title></Head>
      <main className="text-center">
        <h1 className="text-6xl font-bold">Welcome to the Super Stack</h1>
        <p className="text-xl mt-4">Your Deployed Next.js frontend is running!</p>
      </main>
    </div>
  );
}
EOF
cat <<EOF > "$WEB_ROOT/Dockerfile"
FROM oven/bun:1.0-alpine AS base
WORKDIR /usr/src/app
COPY package.json bun.lockb* ./
RUN bun install --frozen-lockfile
COPY . .
RUN bun run build

FROM oven/bun:1.0-alpine AS release
WORKDIR /usr/src/app
COPY --from=base /usr/src/app/node_modules ./
COPY --from=base /usr/src/app/public ./
COPY --from=base /usr/src/app/.next ./.next
EXPOSE 3000
CMD ["bun", "start"]
EOF
chown -R www-data:www-data "$WEB_ROOT"
echo "Next.js application created."

# --- Section 4: Create FastAPI App ---
echo "--> [4/5] Creating FastAPI backend in $APP_ROOT/fastapi_app..."
cat <<EOF > "$APP_ROOT/fastapi_app/Dockerfile"
FROM python:3.10-slim-buster
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
cat <<EOF > "$APP_ROOT/fastapi_app/requirements.txt"
fastapi
uvicorn
python-dotenv
supabase-py
qdrant-client
weaviate-client
neo4j
httpx
langfuse
jose==1.11.0
passlib[bcrypt]
python-multipart
cryptography
EOF
cat <<EOF > "$APP_ROOT/fastapi_app/main.py"
# FastAPI main application
from fastapi import FastAPI
app = FastAPI(title="Super Stack API")
@app.get("/")
def read_root():
    return {"message": "FastAPI is running"}
EOF
echo "FastAPI application created."

# --- Section 5: Create Docker Compose and Configurations ---
echo "--> [5/5] Creating Docker Compose and service configurations in $APP_ROOT..."

# .env file
cat <<EOF > "$APP_ROOT/.env"
# Environment Variables for Super Stack
DOMAIN=$DOMAIN
# Supabase
SUPABASE_DB_PASSWORD=supersecretpassword
SUPABASE_JWT_SECRET=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 64 ; echo '')
# Neo4j
NEO4J_PASSWORD=supersecretpassword
# Kong
KONG_DB_PASSWORD=supersecretpassword
# Grafana
GRAFANA_ADMIN_PASSWORD=supersecretpassword
# RabbitMQ
RABBITMQ_PASSWORD=supersecretpassword
EOF

# docker-compose.yml with absolute paths
cat <<EOF > "$APP_ROOT/docker-compose.yml"
version: '3.8'

volumes:
  supabase_data:
  qdrant_data:
  weaviate_data:
  neo4j_data:
  neo4j_plugins:
  localai_models:
  prometheus_data:
  grafana_data:
  loki_data:
  opensearch_data:
  kong_db_data:

networks:
  devops-net:
    driver: bridge

services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --entrypoints.web.address=:80
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - $APP_ROOT/traefik:/etc/traefik
    networks: [devops-net]
    labels:
      - "traefik.http.routers.traefik-dashboard.rule=Host(`traefik.$DOMAIN`)"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"

  nextjs_app:
    build:
      context: $WEB_ROOT
      dockerfile: Dockerfile
    container_name: nextjs_app
    networks: [devops-net]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nextjs.rule=Host(`$DOMAIN`) || Host(`www.$DOMAIN`)"
      - "traefik.http.services.nextjs.loadbalancer.server.port=3000"

  fastapi_app:
    build:
      context: $APP_ROOT/fastapi_app
    container_name: fastapi_app
    networks: [devops-net]
    environment:
      - SUPABASE_URL=http://supabase:54321
      - SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
      - JWT_SECRET_KEY=${JWT_SECRET_KEY}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.fastapi.rule=Host(`api.$DOMAIN`)"
      - "traefik.http.services.fastapi.loadbalancer.server.port=8000"

  # ... (other services would be defined here, simplified for clarity)
  # Example for supabase
  supabase:
    image: supabase/cli:latest
    container_name: supabase_local
    command: start
    ports: ["5432:5432", "54321:54321"]
    volumes: ["$APP_ROOT/supabase:/project", "supabase_data:/var/lib/postgresql/data"]
    environment:
      - POSTGRES_PASSWORD=${SUPABASE_DB_PASSWORD}
      - JWT_SECRET=${SUPABASE_JWT_SECRET}
    networks: [devops-net]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.supabase-api.rule=Host(`supabase-api.$DOMAIN`)"
      - "traefik.http.services.supabase-api.loadbalancer.server.port=54321"
EOF

# Traefik static config
cat <<EOF > "$APP_ROOT/traefik/traefik.yml"
api:
  dashboard: true
  insecure: true
providers:
  docker:
    exposedByDefault: false
entryPoints:
  web:
    address: ":80"
EOF

echo "==================================================================="
echo " Deployment Script Finished"
echo "==================================================================="
echo "Next Steps:"
echo "1. (Optional) Review and customize the .env file: $APP_ROOT/.env"
echo "2. Navigate to the application root: cd $APP_ROOT"
echo "3. Start the services: docker-compose up -d"
echo "4. Update your DNS or /etc/hosts file to point your domain ('$DOMAIN' and subdomains) to this server's IP address."
echo "==================================================================="
