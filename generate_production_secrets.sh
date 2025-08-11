#!/bin/bash

# -----------------------------------------------------------------------------
# Comprehensive Production Secret Generation Script for Hetzner Deployment
# -----------------------------------------------------------------------------
# This script generates all necessary passwords, secrets, and tokens needed
# for a production-ready deployment of the AI-enhanced Supa Container platform.
# 
# Usage: bash generate_production_secrets.sh [domain]
# Example: bash generate_production_secrets.sh example.com
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Configuration ---
DOMAIN="${1:-opendiscourse.net}"
EMAIL="${2:-admin@${DOMAIN}}"
ENV_FILE=".env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE} Production Secret Generation for Hetzner Deployment${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo -e "Domain: ${GREEN}${DOMAIN}${NC}"
echo -e "Email: ${GREEN}${EMAIL}${NC}"
echo -e "Environment file: ${GREEN}${ENV_FILE}${NC}"
echo -e "${BLUE}=================================================================${NC}"

# --- Safety Check ---
if [ -f "$ENV_FILE" ]; then
  echo -e "${YELLOW}⚠️  A .env file already exists.${NC}"
  read -p "Do you want to overwrite it with new secrets? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted. Your existing .env file has not been changed.${NC}"
    exit 1
  fi
fi

# --- Secret Generation Functions ---
generate_password() {
  openssl rand -base64 32 | tr -d '=' | tr -d '\n'
}

generate_jwt_secret() {
  openssl rand -hex 64
}

generate_api_key() {
  echo "sk-$(openssl rand -hex 32)"
}

generate_short_secret() {
  openssl rand -hex 16
}

generate_uuid() {
  uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())"
}

echo -e "${GREEN}--> Generating cryptographically secure secrets...${NC}"

# --- Generate All Secrets ---
POSTGRES_PASSWORD=$(generate_password)
NEO4J_PASSWORD=$(generate_password)
RABBITMQ_PASSWORD=$(generate_password)
N8N_PASSWORD=$(generate_password)
FLOWISE_PASSWORD=$(generate_password)
GRAFANA_ADMIN_PASSWORD=$(generate_password)
TRAEFIK_ADMIN_PASSWORD=$(generate_password)
LANGFUSE_NEXTAUTH_SECRET=$(generate_jwt_secret)
LANGFUSE_SALT=$(generate_short_secret)
SUPABASE_JWT_SECRET=$(generate_jwt_secret)
FASTAPI_SECRET_KEY=$(generate_jwt_secret)
ENCRYPTION_KEY=$(generate_short_secret)
CLICKHOUSE_PASSWORD=$(generate_password)
MINIO_ROOT_PASSWORD=$(generate_password)
REDIS_AUTH=$(generate_password)
N8N_ENCRYPTION_KEY=$(generate_jwt_secret)
N8N_USER_MANAGEMENT_JWT_SECRET=$(generate_jwt_secret)
NEXTAUTH_SECRET=$(generate_jwt_secret)

# Generate Traefik password hash
TRAEFIK_ADMIN_PASSWORD_HASH=$(echo "$TRAEFIK_ADMIN_PASSWORD" | htpasswd -in admin)

echo -e "${GREEN}✅ All secrets generated successfully.${NC}"

# --- Create Production .env File ---
echo -e "${GREEN}--> Creating production .env file...${NC}"

cat <<EOF > "$ENV_FILE"
# =============================================================================
# Production Environment Variables for AI-Enhanced Supa Container
# Generated on: $(date)
# Domain: ${DOMAIN}
# =============================================================================

# --- CORE DEPLOYMENT CONFIGURATION ---
DOMAIN=${DOMAIN}
LETSENCRYPT_EMAIL=${EMAIL}
APP_ROOT=/opt/supa-container
WEB_ROOT=/var/www/html/supa-container

# --- TRAEFIK REVERSE PROXY ---
TRAEFIK_ADMIN_PASSWORD=${TRAEFIK_ADMIN_PASSWORD}
TRAEFIK_ADMIN_PASSWORD_HASH=${TRAEFIK_ADMIN_PASSWORD_HASH}

# --- DATABASE (POSTGRESQL/SUPABASE) ---
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=postgres
POSTGRES_VERSION=15
DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}

# --- SUPABASE AUTHENTICATION ---
# Note: ANON_KEY and SERVICE_ROLE_KEY will be populated after first deployment
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_JWT_SECRET=${SUPABASE_JWT_SECRET}

# --- KNOWLEDGE GRAPH (NEO4J) ---
NEO4J_USER=neo4j
NEO4J_PASSWORD=${NEO4J_PASSWORD}
NEO4J_URI=bolt://neo4j:7687
NEO4J_AUTH=neo4j/${NEO4J_PASSWORD}

# --- MESSAGE BROKER (RABBITMQ) ---
RABBITMQ_USER=admin
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_MANAGEMENT_PORT=15672

# --- WORKFLOW AUTOMATION (N8N) ---
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}
N8N_HOSTNAME=n8n.${DOMAIN}

# --- AI PROTOTYPING (FLOWISE) ---
FLOWISE_USERNAME=admin
FLOWISE_PASSWORD=${FLOWISE_PASSWORD}

# --- LLM OBSERVABILITY (LANGFUSE) ---
LANGFUSE_NEXTAUTH_SECRET=${LANGFUSE_NEXTAUTH_SECRET}
LANGFUSE_SALT=${LANGFUSE_SALT}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
NEXTAUTH_URL=https://langfuse.${DOMAIN}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
TELEMETRY_ENABLED=false
LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES=true

# --- CLICKHOUSE (LANGFUSE ANALYTICS) ---
CLICKHOUSE_URL=http://clickhouse:8123
CLICKHOUSE_USER=clickhouse
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
CLICKHOUSE_MIGRATION_URL=clickhouse://clickhouse:9000
CLICKHOUSE_CLUSTER_ENABLED=false

# --- MINIO (S3-COMPATIBLE STORAGE) ---
MINIO_ROOT_USER=minio
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
LANGFUSE_S3_EVENT_UPLOAD_BUCKET=langfuse
LANGFUSE_S3_EVENT_UPLOAD_REGION=auto
LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID=minio
LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY=${MINIO_ROOT_PASSWORD}
LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT=http://minio:9000
LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE=true
LANGFUSE_S3_EVENT_UPLOAD_PREFIX=events/
LANGFUSE_S3_MEDIA_UPLOAD_BUCKET=langfuse
LANGFUSE_S3_MEDIA_UPLOAD_REGION=auto
LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID=minio
LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY=${MINIO_ROOT_PASSWORD}
LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT=http://minio:9000
LANGFUSE_S3_MEDIA_UPLOAD_FORCE_PATH_STYLE=true
LANGFUSE_S3_MEDIA_UPLOAD_PREFIX=media/

# --- REDIS CACHE ---
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_AUTH=${REDIS_AUTH}
REDIS_TLS_ENABLED=false

# --- MONITORING (GRAFANA) ---
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

# --- FASTAPI BACKEND ---
FASTAPI_SECRET_KEY=${FASTAPI_SECRET_KEY}
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
APP_PORT=8058

# --- LLM & EMBEDDING PROVIDERS (LOCAL AI) ---
LLM_PROVIDER=openai
LLM_BASE_URL=http://localai:8080/v1
LLM_API_KEY=${ENCRYPTION_KEY}
LLM_CHOICE=gpt-4
EMBEDDING_PROVIDER=openai
EMBEDDING_BASE_URL=http://localai:8080/v1
EMBEDDING_API_KEY=${ENCRYPTION_KEY}
EMBEDDING_MODEL=text-embedding-3-small
VECTOR_DIMENSION=1536
INGESTION_LLM_CHOICE=gpt-3.5-turbo

# --- APPLICATION SETTINGS ---
APP_ENV=production
LOG_LEVEL=INFO
DEBUG=false

# --- HOSTNAME CONFIGURATION ---
WEBUI_HOSTNAME=webui.${DOMAIN}
FLOWISE_HOSTNAME=flowise.${DOMAIN}
OLLAMA_HOSTNAME=ollama.${DOMAIN}
SUPABASE_HOSTNAME=supabase.${DOMAIN}
SEARXNG_HOSTNAME=search.${DOMAIN}
LANGFUSE_HOSTNAME=langfuse.${DOMAIN}
NEO4J_HOSTNAME=neo4j.${DOMAIN}

# --- SECURITY SETTINGS ---
ALLOWED_HOSTS=${DOMAIN},www.${DOMAIN},api.${DOMAIN}
CORS_ALLOWED_ORIGINS=https://${DOMAIN},https://www.${DOMAIN},https://api.${DOMAIN}

# --- AI ORCHESTRATOR SETTINGS ---
ORCHESTRATOR_LOG_LEVEL=INFO
AGENT_HEARTBEAT_INTERVAL=30
MAX_AGENT_FAILURES=3
RECOVERY_TIMEOUT=300

EOF

echo -e "${GREEN}✅ Production .env file created successfully.${NC}"

# --- Create Password Summary ---
echo -e "${GREEN}--> Creating password summary file...${NC}"

cat <<EOF > "PRODUCTION_PASSWORDS_${DOMAIN}_$(date +%Y%m%d_%H%M%S).txt"
=============================================================================
PRODUCTION PASSWORDS FOR ${DOMAIN}
Generated on: $(date)
=============================================================================

🔐 SAVE THESE PASSWORDS SECURELY - THEY WILL NOT BE DISPLAYED AGAIN!

--- WEB INTERFACES ---
Traefik Dashboard: https://traefik.${DOMAIN}
  Username: admin
  Password: ${TRAEFIK_ADMIN_PASSWORD}

Grafana Monitoring: https://grafana.${DOMAIN}
  Username: admin
  Password: ${GRAFANA_ADMIN_PASSWORD}

n8n Workflow: https://n8n.${DOMAIN}
  Username: admin
  Password: ${N8N_PASSWORD}

Flowise AI Lab: https://flowise.${DOMAIN}
  Username: admin
  Password: ${FLOWISE_PASSWORD}

RabbitMQ Management: https://rabbitmq.${DOMAIN}
  Username: admin
  Password: ${RABBITMQ_PASSWORD}

--- DATABASE PASSWORDS ---
PostgreSQL/Supabase: ${POSTGRES_PASSWORD}
Neo4j Knowledge Graph: ${NEO4J_PASSWORD}
ClickHouse Analytics: ${CLICKHOUSE_PASSWORD}
Redis Cache: ${REDIS_AUTH}

--- S3 STORAGE ---
MinIO Access Key: minio
MinIO Secret Key: ${MINIO_ROOT_PASSWORD}

--- APPLICATION SECRETS ---
FastAPI Secret: ${FASTAPI_SECRET_KEY}
Supabase JWT Secret: ${SUPABASE_JWT_SECRET}
Langfuse NextAuth Secret: ${LANGFUSE_NEXTAUTH_SECRET}

--- IMPORTANT NOTES ---
1. Store this file securely and delete it after recording passwords
2. Some keys (Supabase ANON_KEY, SERVICE_ROLE_KEY) will be generated after deployment
3. All services use SSL/TLS certificates via Let's Encrypt
4. Default SSH access should be secured with key-based authentication

=============================================================================
EOF

echo -e "${BLUE}=================================================================${NC}"
echo -e "${GREEN}✅ Secret generation completed successfully!${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo
echo -e "${YELLOW}📁 Files created:${NC}"
echo -e "   • ${GREEN}.env${NC} - Environment variables for deployment"
echo -e "   • ${GREEN}PRODUCTION_PASSWORDS_*.txt${NC} - Secure password list"
echo
echo -e "${YELLOW}🔐 Security reminders:${NC}"
echo -e "   • ${RED}Save the password file securely and delete it after use${NC}"
echo -e "   • ${RED}Never commit .env to version control${NC}"
echo -e "   • ${RED}Use strong SSH keys for server access${NC}"
echo
echo -e "${YELLOW}📋 Next steps:${NC}"
echo -e "   1. Review the generated .env file"
echo -e "   2. Run the Hetzner deployment script: ${GREEN}sudo bash deploy_hetzner.sh${NC}"
echo -e "   3. Configure DNS records to point to your Hetzner server"
echo -e "   4. Monitor deployment logs for any issues"
echo
echo -e "${BLUE}=================================================================${NC}"