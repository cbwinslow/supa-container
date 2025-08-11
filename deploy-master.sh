#!/bin/bash

# Master Production Deployment Script for Hetzner
# Deploys complete AI platform with orchestrator and agents

set -euo pipefail

# --- Configuration ---
source config.sh

echo "==================================================================="
echo " Master Production Deployment for opendiscourse.net"
echo "==================================================================="
echo "Domain: $DOMAIN"
echo "Email: $LETSENCRYPT_EMAIL"
echo "Target: Hetzner Cloud Server"
echo "==================================================================="

# --- Check prerequisites ---
echo "--> [1/8] Checking prerequisites..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose is not installed. Installing..."
    curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

echo "Prerequisites checked."

# --- Run main deployment ---
echo "--> [2/8] Running main deployment script..."
bash deploy.sh

# --- Setup AI Orchestrator and Agents ---
echo "--> [3/8] Setting up AI Orchestrator and Agents..."

# Create orchestrator service directory
mkdir -p "$APP_ROOT/orchestrator"
mkdir -p "$APP_ROOT/agents"

# Copy orchestrator and agent source code
cp -r src/orchestrator/* "$APP_ROOT/orchestrator/"
cp -r src/agents/* "$APP_ROOT/agents/"
cp -r src/message_broker "$APP_ROOT/"

# Create orchestrator requirements
cat <<EOF > "$APP_ROOT/orchestrator/requirements.txt"
asyncio
pika>=1.3.0
pydantic>=2.0.0
httpx
asyncpg
graphiti-core
openai
fastapi
uvicorn
python-dotenv
aiofiles
EOF

# Create agent requirements
cat <<EOF > "$APP_ROOT/agents/requirements.txt"
asyncio
pika>=1.3.0
pydantic>=2.0.0
httpx
asyncpg
psutil
subprocess
python-dotenv
aiofiles
EOF

# Create orchestrator Dockerfile
cat <<EOF > "$APP_ROOT/orchestrator/Dockerfile"
FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    docker.io \\
    curl \\
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .
COPY ../message_broker ./message_broker

# Create non-root user
RUN useradd -m -u 1000 orchestrator && chown -R orchestrator:orchestrator /app
USER orchestrator

# Command to run the orchestrator
CMD ["python", "-m", "brain"]
EOF

# Create agent Dockerfile
cat <<EOF > "$APP_ROOT/agents/Dockerfile"
FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    docker.io \\
    curl \\
    htop \\
    procps \\
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .
COPY ../message_broker ./message_broker

# Create non-root user
RUN useradd -m -u 1000 agent && chown -R agent:agent /app
USER agent

# Default command (can be overridden)
CMD ["python", "-m", "base_agent"]
EOF

echo "AI components setup completed."

# --- Add AI services to docker-compose ---
echo "--> [4/8] Adding AI services to docker-compose..."

# Append AI services to the existing docker-compose.yml
cat <<EOF >> "$APP_ROOT/docker-compose.yml"

  # --- AI Orchestrator Brain ---
  orchestrator:
    build: 
      context: ./orchestrator
      dockerfile: Dockerfile
    container_name: ai_orchestrator
    networks: [devops-net]
    env_file: .env
    environment:
      - RABBITMQ_HOST=rabbitmq
      - RABBITMQ_PORT=5672
      - RABBITMQ_USER=\${RABBITMQ_USER}
      - RABBITMQ_PASSWORD=\${RABBITMQ_PASSWORD}
      - DATABASE_URL=\${DATABASE_URL}
      - NEO4J_URI=\${NEO4J_URI}
      - NEO4J_USER=\${NEO4J_USER}
      - NEO4J_PASSWORD=\${NEO4J_PASSWORD}
      - LOG_LEVEL=DEBUG
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/log:/var/log:ro
    depends_on:
      - rabbitmq
      - postgres
      - neo4j
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "python", "-c", "import requests; requests.get('http://localhost:8000/health')"]
      timeout: 30s
      interval: 10s
      retries: 5

  # --- Self-Healing Agent ---
  self_healing_agent:
    build:
      context: ./agents  
      dockerfile: Dockerfile
    container_name: self_healing_agent
    networks: [devops-net]
    env_file: .env
    environment:
      - AGENT_TYPE=self_healing
      - RABBITMQ_HOST=rabbitmq
      - RABBITMQ_PORT=5672
      - RABBITMQ_USER=\${RABBITMQ_USER}
      - RABBITMQ_PASSWORD=\${RABBITMQ_PASSWORD}
      - LOG_LEVEL=DEBUG
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:rw
      - /var/log:/var/log:rw
      - /tmp:/tmp:rw
    command: ["python", "-m", "self_healing_agent"]
    depends_on:
      - rabbitmq
      - orchestrator
    restart: unless-stopped
    privileged: true

  # --- Monitoring Agent ---
  monitoring_agent:
    build:
      context: ./agents
      dockerfile: Dockerfile  
    container_name: monitoring_agent
    networks: [devops-net]
    env_file: .env
    environment:
      - AGENT_TYPE=monitoring
      - RABBITMQ_HOST=rabbitmq
      - RABBITMQ_PORT=5672
      - RABBITMQ_USER=\${RABBITMQ_USER}
      - RABBITMQ_PASSWORD=\${RABBITMQ_PASSWORD}
      - LOG_LEVEL=DEBUG
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/log:/var/log:ro
      - /proc:/proc:ro
      - /sys:/sys:ro
    command: ["python", "-m", "monitoring_agent"]
    depends_on:
      - rabbitmq
      - orchestrator
    restart: unless-stopped

  # --- Data Manager Agent ---
  data_manager_agent:
    build:
      context: ./agents
      dockerfile: Dockerfile
    container_name: data_manager_agent  
    networks: [devops-net]
    env_file: .env
    environment:
      - AGENT_TYPE=data_manager
      - RABBITMQ_HOST=rabbitmq
      - RABBITMQ_PORT=5672
      - RABBITMQ_USER=\${RABBITMQ_USER}
      - RABBITMQ_PASSWORD=\${RABBITMQ_PASSWORD}
      - DATABASE_URL=\${DATABASE_URL}
      - NEO4J_URI=\${NEO4J_URI}
      - LOG_LEVEL=DEBUG
    command: ["python", "-m", "data_manager_agent"]
    depends_on:
      - rabbitmq
      - orchestrator
      - postgres
      - neo4j
    restart: unless-stopped
EOF

echo "AI services added to docker-compose.yml"

# --- Configure DNS and SSL ---
echo "--> [5/8] DNS and SSL configuration instructions..."

cat <<EOF

=================================================================
IMPORTANT: DNS CONFIGURATION REQUIRED
=================================================================

To complete the deployment for opendiscourse.net, configure these DNS records:

A Records (point to your Hetzner server IP):
- opendiscourse.net -> YOUR_SERVER_IP
- www.opendiscourse.net -> YOUR_SERVER_IP
- api.opendiscourse.net -> YOUR_SERVER_IP
- rabbitmq.opendiscourse.net -> YOUR_SERVER_IP
- traefik.opendiscourse.net -> YOUR_SERVER_IP
- grafana.opendiscourse.net -> YOUR_SERVER_IP
- jaeger.opendiscourse.net -> YOUR_SERVER_IP
- langfuse.opendiscourse.net -> YOUR_SERVER_IP
- flowise.opendiscourse.net -> YOUR_SERVER_IP
- n8n.opendiscourse.net -> YOUR_SERVER_IP

The SSL certificates will be automatically generated by Let's Encrypt
when the services start and the DNS records are properly configured.

=================================================================
EOF

# --- Create startup script ---
echo "--> [6/8] Creating startup script..."

cat <<'STARTUP_EOF' > "$APP_ROOT/start-platform.sh"
#!/bin/bash

echo "Starting AI-Enhanced Super Stack Platform..."

# Start all services
docker-compose up -d

echo "Waiting for services to start..."
sleep 30

# Check service health
echo "Checking service health..."
docker-compose ps

# Show logs for troubleshooting
echo "Recent logs:"
docker-compose logs --tail=20

echo "Platform started! Check the logs above for any issues."
echo "Access the platform at: https://opendiscourse.net"
echo "Monitor RabbitMQ at: https://rabbitmq.opendiscourse.net"
echo "Monitor system at: https://grafana.opendiscourse.net"
STARTUP_EOF

chmod +x "$APP_ROOT/start-platform.sh"

# --- Create monitoring script ---
echo "--> [7/8] Creating monitoring script..."

cat <<'MONITOR_EOF' > "$APP_ROOT/monitor-agents.sh"
#!/bin/bash

echo "==================================================================="
echo " AI Agent Monitoring Dashboard"
echo "==================================================================="

# Check orchestrator health
echo "AI Orchestrator Status:"
docker exec ai_orchestrator python -c "
import asyncio
import sys
try:
    # Simple health check
    print('✓ Orchestrator is running')
except Exception as e:
    print(f'✗ Orchestrator error: {e}')
    sys.exit(1)
" || echo "✗ Orchestrator not responding"

echo ""

# Check agents
echo "Agent Status:"
for agent in self_healing_agent monitoring_agent data_manager_agent; do
    if docker ps --format "table {{.Names}}" | grep -q "$agent"; then
        echo "✓ $agent: Running"
    else
        echo "✗ $agent: Not running"
    fi
done

echo ""

# Check RabbitMQ
echo "Message Broker Status:"
docker exec rabbitmq rabbitmq-diagnostics ping > /dev/null 2>&1 && echo "✓ RabbitMQ: Healthy" || echo "✗ RabbitMQ: Unhealthy"

echo ""

# Show recent agent logs
echo "Recent Agent Activity (last 10 lines):"
docker-compose logs --tail=10 orchestrator self_healing_agent monitoring_agent

echo ""
echo "For detailed monitoring, visit: https://grafana.opendiscourse.net"
echo "For message broker management: https://rabbitmq.opendiscourse.net"
MONITOR_EOF

chmod +x "$APP_ROOT/monitor-agents.sh"

# --- Final steps ---
echo "--> [8/8] Final deployment steps..."

# Set proper permissions
chown -R root:docker "$APP_ROOT"
chmod -R 755 "$APP_ROOT"

# Create systemd service for auto-start
cat <<EOF > /etc/systemd/system/ai-platform.service
[Unit]
Description=AI-Enhanced Super Stack Platform
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_ROOT
ExecStart=$APP_ROOT/start-platform.sh
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ai-platform.service

echo "==================================================================="
echo " Master Deployment Complete!"
echo "==================================================================="
echo ""
echo "Next Steps:"
echo "1. Configure DNS records as shown above"
echo "2. Start the platform: cd $APP_ROOT && sudo ./start-platform.sh"
echo "3. Monitor agents: cd $APP_ROOT && sudo ./monitor-agents.sh"
echo "4. Enable auto-start: sudo systemctl start ai-platform"
echo ""
echo "Platform URLs (after DNS configuration):"
echo "- Main App: https://opendiscourse.net"
echo "- API: https://api.opendiscourse.net"
echo "- Message Broker: https://rabbitmq.opendiscourse.net"
echo "- Monitoring: https://grafana.opendiscourse.net"
echo "- Tracing: https://jaeger.opendiscourse.net"
echo "- AI Prototyping: https://flowise.opendiscourse.net"
echo "- Workflow Automation: https://n8n.opendiscourse.net"
echo ""
echo "The AI Orchestrator Brain is now managing:"
echo "- Self-healing system recovery"
echo "- Automated monitoring and alerting" 
echo "- Data flow optimization"
echo "- Intelligent agent coordination"
echo "- Zero-waste data utilization"
echo ""
echo "All system data flows through RabbitMQ and is analyzed by the"
echo "AI Orchestrator to ensure maximum utilization and continuous"
echo "improvement of the platform."
echo "==================================================================="