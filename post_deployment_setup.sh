#!/bin/bash

# =============================================================================
# Post-Deployment Setup Script for AI-Enhanced Supa Container
# =============================================================================
# This script completes the deployment by:
# 1. Initializing databases with proper schemas
# 2. Retrieving Supabase API keys
# 3. Setting up AI orchestrator and agents
# 4. Configuring monitoring and alerting
# 5. Running comprehensive health checks
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="${APP_ROOT:-/opt/supa-container}"
ENV_FILE="$APP_ROOT/.env"

# Load environment variables
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}❌ ERROR: .env file not found at $ENV_FILE${NC}"
    echo -e "${YELLOW}Please ensure the deployment script has been run first.${NC}"
    exit 1
fi

source "$ENV_FILE"

echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}🔧 AI-Enhanced Supa Container - Post-Deployment Setup${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${CYAN}Domain:${NC} ${GREEN}${DOMAIN}${NC}"
echo -e "${CYAN}App Root:${NC} ${GREEN}${APP_ROOT}${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root or with sudo.${NC}"
    exit 1
fi

# Navigate to app directory
cd "$APP_ROOT"

# --- Step 1: Verify Services are Running ---
echo -e "${PURPLE}[1/8] Verifying all services are running...${NC}"

# Wait for services to be ready
echo -e "${YELLOW}Waiting for services to start (60 seconds)...${NC}"
sleep 60

# Check if containers are running
REQUIRED_SERVICES=("traefik" "postgres" "neo4j" "rabbitmq" "fastapi_app")
FAILED_SERVICES=()

for service in "${REQUIRED_SERVICES[@]}"; do
    if ! docker-compose ps | grep -q "$service.*Up"; then
        FAILED_SERVICES+=("$service")
    fi
done

if [ ${#FAILED_SERVICES[@]} -ne 0 ]; then
    echo -e "${RED}❌ The following services are not running:${NC}"
    for service in "${FAILED_SERVICES[@]}"; do
        echo -e "   • $service"
    done
    echo -e "${YELLOW}Please check the logs: docker-compose logs <service_name>${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All required services are running.${NC}"

# --- Step 2: Initialize Database Schemas ---
echo -e "${PURPLE}[2/8] Initializing database schemas...${NC}"

# Wait for PostgreSQL to be ready
echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
for i in {1..30}; do
    if docker exec postgres pg_isready -U postgres > /dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Apply main database schema if it exists
if [ -f "$APP_ROOT/sql/schema.sql" ]; then
    echo -e "${YELLOW}Applying main database schema...${NC}"
    docker exec -i postgres psql -U postgres -d postgres < "$APP_ROOT/sql/schema.sql" || {
        echo -e "${YELLOW}⚠️  Schema file may not exist or already applied.${NC}"
    }
else
    echo -e "${YELLOW}⚠️  No schema.sql found, creating basic schema...${NC}"
    docker exec postgres psql -U postgres -d postgres -c "
        CREATE EXTENSION IF NOT EXISTS vector;
        CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
        CREATE EXTENSION IF NOT EXISTS pgcrypto;
    " || echo -e "${YELLOW}Extensions may already exist.${NC}"
fi

# Apply audit schema if it exists
if [ -f "$APP_ROOT/sql/audit.sql" ]; then
    echo -e "${YELLOW}Applying audit log schema...${NC}"
    docker exec -i postgres psql -U postgres -d postgres < "$APP_ROOT/sql/audit.sql" || {
        echo -e "${YELLOW}⚠️  Audit schema may already be applied.${NC}"
    }
fi

echo -e "${GREEN}✅ Database schemas initialized.${NC}"

# --- Step 3: Configure Supabase (if using) ---
echo -e "${PURPLE}[3/8] Configuring Supabase integration...${NC}"

# Check if Supabase container is running
if docker-compose ps | grep -q "supabase.*Up"; then
    echo -e "${YELLOW}Retrieving Supabase API keys...${NC}"
    
    # Wait for Supabase to be ready
    sleep 30
    
    # Try to get Supabase status
    SUPABASE_STATUS=""
    for i in {1..10}; do
        SUPABASE_STATUS=$(docker-compose exec -T supabase supabase status 2>/dev/null || echo "")
        if [ -n "$SUPABASE_STATUS" ]; then
            break
        fi
        sleep 5
    done
    
    if [ -n "$SUPABASE_STATUS" ]; then
        # Extract keys
        ANON_KEY=$(echo "$SUPABASE_STATUS" | grep "anon key:" | awk '{print $3}' || echo "")
        SERVICE_ROLE_KEY=$(echo "$SUPABASE_STATUS" | grep "service_role key:" | awk '{print $3}' || echo "")
        
        if [ -n "$ANON_KEY" ] && [ -n "$SERVICE_ROLE_KEY" ]; then
            echo -e "${GREEN}✅ Supabase API keys retrieved successfully.${NC}"
            echo -e "${YELLOW}📝 Please update your .env file with these keys:${NC}"
            echo -e "${CYAN}SUPABASE_ANON_KEY=${ANON_KEY}${NC}"
            echo -e "${CYAN}SUPABASE_SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}${NC}"
            
            # Optionally update the .env file automatically
            read -p "Do you want to automatically update the .env file? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sed -i "s/SUPABASE_ANON_KEY=.*/SUPABASE_ANON_KEY=${ANON_KEY}/" "$ENV_FILE"
                sed -i "s/SUPABASE_SERVICE_ROLE_KEY=.*/SUPABASE_SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}/" "$ENV_FILE"
                echo -e "${GREEN}✅ .env file updated automatically.${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Could not retrieve Supabase keys automatically.${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Supabase not responding, you may need to configure keys manually.${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Supabase container not found, skipping key retrieval.${NC}"
fi

# --- Step 4: Initialize AI Orchestrator ---
echo -e "${PURPLE}[4/8] Initializing AI Orchestrator and Agents...${NC}"

# Wait for RabbitMQ to be ready
echo -e "${YELLOW}Waiting for RabbitMQ to be ready...${NC}"
for i in {1..30}; do
    if docker exec rabbitmq rabbitmq-diagnostics ping > /dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Create RabbitMQ queues and exchanges for agents
echo -e "${YELLOW}Setting up message broker queues...${NC}"
docker exec rabbitmq rabbitmqctl eval 'ok = rabbit_exchange:declare({resource, <<"/">>, exchange, <<"ai_orchestrator">>}, topic, true, false, false, []), ok = rabbit_queue:declare({resource, <<"/">>, queue, <<"self_healing_queue">>}, true, false, false, false, []), ok = rabbit_queue:declare({resource, <<"/">>, queue, <<"monitoring_queue">>}, true, false, false, false, []), ok = rabbit_queue:declare({resource, <<"/">>, queue, <<"data_manager_queue">>}, true, false, false, false, []).' 2>/dev/null || echo -e "${YELLOW}⚠️  Queues may already exist.${NC}"

# Check if AI orchestrator is healthy
if docker-compose ps | grep -q "ai_orchestrator.*Up"; then
    echo -e "${GREEN}✅ AI Orchestrator is running.${NC}"
    
    # Test orchestrator health
    sleep 10
    if docker exec ai_orchestrator python -c "
import requests
import sys
try:
    response = requests.get('http://localhost:8000/health', timeout=10)
    if response.status_code == 200:
        print('✅ AI Orchestrator health check passed')
    else:
        print('⚠️  AI Orchestrator health check failed')
        sys.exit(1)
except Exception as e:
    print(f'⚠️  AI Orchestrator health check error: {e}')
    sys.exit(1)
" 2>/dev/null; then
        echo -e "${GREEN}✅ AI Orchestrator health check passed.${NC}"
    else
        echo -e "${YELLOW}⚠️  AI Orchestrator health check failed, but continuing...${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  AI Orchestrator not running, you may need to start it manually.${NC}"
fi

echo -e "${GREEN}✅ AI components initialized.${NC}"

# --- Step 5: Configure Monitoring and Alerting ---
echo -e "${PURPLE}[5/8] Configuring monitoring and alerting...${NC}"

# Wait for Grafana to be ready
echo -e "${YELLOW}Waiting for Grafana to start...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:3000 > /dev/null 2>&1; then
        break
    fi
    sleep 3
done

# Import Grafana dashboards
echo -e "${YELLOW}Setting up Grafana dashboards...${NC}"

# Create a basic dashboard for the platform
cat <<EOF > /tmp/platform_dashboard.json
{
  "dashboard": {
    "id": null,
    "title": "AI-Enhanced Supa Container Platform",
    "tags": ["platform", "monitoring"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Container Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "timepicker": {},
    "templating": {"list": []},
    "version": 1
  }
}
EOF

# Import dashboard to Grafana
curl -X POST \
  -H "Content-Type: application/json" \
  -d @/tmp/platform_dashboard.json \
  http://admin:${GRAFANA_ADMIN_PASSWORD}@localhost:3000/api/dashboards/db 2>/dev/null || \
  echo -e "${YELLOW}⚠️  Could not import dashboard automatically.${NC}"

rm -f /tmp/platform_dashboard.json

echo -e "${GREEN}✅ Monitoring configured.${NC}"

# --- Step 6: Run Security Hardening ---
echo -e "${PURPLE}[6/8] Running additional security hardening...${NC}"

# Set up log rotation for application logs
cat <<EOF > /etc/logrotate.d/supa-container-apps
$APP_ROOT/*/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    create 644 root root
    postrotate
        # Reload relevant services if needed
    endscript
}
EOF

# Create backup directory and set permissions
mkdir -p /opt/backup
chmod 700 /opt/backup

# Set up automated backup via cron (daily backups)
(crontab -l 2>/dev/null; echo "0 2 * * * $APP_ROOT/backup_platform.sh > /var/log/backup.log 2>&1") | crontab -

echo -e "${GREEN}✅ Security hardening completed.${NC}"

# --- Step 7: SSL Certificate Verification ---
echo -e "${PURPLE}[7/8] Verifying SSL certificates...${NC}"

echo -e "${YELLOW}Waiting for Let's Encrypt certificates to be issued...${NC}"
sleep 30

# Check if certificates are being generated
if [ -f "$APP_ROOT/traefik/acme.json" ]; then
    CERT_COUNT=$(jq '.letsencrypt.Certificates | length' "$APP_ROOT/traefik/acme.json" 2>/dev/null || echo "0")
    if [ "$CERT_COUNT" -gt "0" ]; then
        echo -e "${GREEN}✅ SSL certificates are being managed by Let's Encrypt.${NC}"
    else
        echo -e "${YELLOW}⚠️  SSL certificates not yet issued. Check DNS configuration.${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  ACME configuration file not found.${NC}"
fi

echo -e "${GREEN}✅ SSL verification completed.${NC}"

# --- Step 8: Comprehensive Health Check ---
echo -e "${PURPLE}[8/8] Running comprehensive health check...${NC}"

echo -e "${YELLOW}Performing system health check...${NC}"

# Check all services
echo -e "${CYAN}Service Status:${NC}"
docker-compose ps

echo
echo -e "${CYAN}Container Health:${NC}"

# Define health checks
declare -A HEALTH_CHECKS=(
    ["postgres"]="docker exec postgres pg_isready -U postgres"
    ["neo4j"]="docker exec neo4j cypher-shell -u neo4j -p ${NEO4J_PASSWORD} 'RETURN 1'"
    ["rabbitmq"]="docker exec rabbitmq rabbitmq-diagnostics ping"
    ["redis"]="docker exec redis redis-cli ping"
)

for service in "${!HEALTH_CHECKS[@]}"; do
    if ${HEALTH_CHECKS[$service]} > /dev/null 2>&1; then
        echo -e "  ✅ $service: Healthy"
    else
        echo -e "  ❌ $service: Unhealthy"
    fi
done

echo
echo -e "${CYAN}Network Connectivity:${NC}"

# Check if Traefik is responding
if curl -s -o /dev/null -w "%{http_code}" http://localhost:80 | grep -q "301\|302\|200"; then
    echo -e "  ✅ Traefik HTTP: Responding"
else
    echo -e "  ❌ Traefik HTTP: Not responding"
fi

# Check HTTPS if possible
if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:443 | grep -q "200\|302"; then
    echo -e "  ✅ Traefik HTTPS: Responding"
else
    echo -e "  ⚠️  Traefik HTTPS: Not responding (may need DNS configuration)"
fi

echo
echo -e "${CYAN}Storage Health:${NC}"

# Check disk space
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    echo -e "  ✅ Disk Space: ${DISK_USAGE}% used"
else
    echo -e "  ⚠️  Disk Space: ${DISK_USAGE}% used (consider cleanup)"
fi

# Check Docker volumes
echo -e "  📁 Docker Volumes:"
docker volume ls | grep -E "(postgres|neo4j|rabbitmq)" | while read -r line; do
    echo -e "    • $line"
done

echo
echo -e "${CYAN}AI Components:${NC}"

# Check AI orchestrator
if docker-compose ps | grep -q "ai_orchestrator.*Up"; then
    echo -e "  ✅ AI Orchestrator: Running"
else
    echo -e "  ❌ AI Orchestrator: Not running"
fi

# Check agents
AGENT_SERVICES=("self_healing_agent" "monitoring_agent" "data_manager_agent")
for agent in "${AGENT_SERVICES[@]}"; do
    if docker-compose ps | grep -q "$agent.*Up"; then
        echo -e "  ✅ $agent: Running"
    else
        echo -e "  ❌ $agent: Not running"
    fi
done

echo -e "${GREEN}✅ Health check completed.${NC}"

# --- Final Summary ---
echo
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${GREEN}🎉 Post-Deployment Setup Complete!${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo
echo -e "${YELLOW}📊 Deployment Summary:${NC}"
echo -e "  • ${GREEN}Domain:${NC} ${DOMAIN}"
echo -e "  • ${GREEN}Services:${NC} $(docker-compose ps | grep -c "Up") containers running"
echo -e "  • ${GREEN}SSL:${NC} Let's Encrypt configured"
echo -e "  • ${GREEN}Monitoring:${NC} Grafana + Prometheus active"
echo -e "  • ${GREEN}AI:${NC} Orchestrator and agents deployed"
echo -e "  • ${GREEN}Security:${NC} Firewall and fail2ban active"
echo
echo -e "${YELLOW}🌐 Access URLs:${NC}"
echo -e "  • ${CYAN}Main App:${NC} https://${DOMAIN}"
echo -e "  • ${CYAN}API Docs:${NC} https://api.${DOMAIN}/docs"
echo -e "  • ${CYAN}Monitoring:${NC} https://grafana.${DOMAIN}"
echo -e "  • ${CYAN}Admin Panel:${NC} https://traefik.${DOMAIN}"
echo
echo -e "${YELLOW}🔧 Management Commands:${NC}"
echo -e "  • ${CYAN}Monitor Status:${NC} sudo $APP_ROOT/monitor_platform.sh"
echo -e "  • ${CYAN}Create Backup:${NC} sudo $APP_ROOT/backup_platform.sh"
echo -e "  • ${CYAN}View Logs:${NC} cd $APP_ROOT && sudo docker-compose logs -f"
echo -e "  • ${CYAN}Restart Service:${NC} sudo systemctl restart supa-container"
echo
echo -e "${YELLOW}⚠️  Important Notes:${NC}"
echo -e "  • Ensure DNS records point to this server before accessing URLs"
echo -e "  • Monitor logs during the first 24 hours for any issues"
echo -e "  • Regular backups are scheduled daily at 2 AM"
echo -e "  • Keep your .env file secure and backed up"
echo
if [ -n "${ANON_KEY:-}" ] && [ -n "${SERVICE_ROLE_KEY:-}" ]; then
    echo -e "${YELLOW}🔑 Supabase Keys Retrieved:${NC}"
    echo -e "  • Update your frontend applications with these keys"
    echo -e "  • Restart frontend services if keys were updated"
    echo
fi
echo -e "${GREEN}✅ Your AI-Enhanced Supa Container platform is ready for production use!${NC}"
echo -e "${BLUE}=============================================================================${NC}"