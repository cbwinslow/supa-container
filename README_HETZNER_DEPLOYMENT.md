# 🚀 AI-Enhanced Supa Container - Production Hetzner Deployment

A complete, production-ready AI platform with comprehensive observability, security, and AI orchestration capabilities. This repository provides a one-click deployment solution for Hetzner Cloud that includes:

- **Advanced AI Backend** with FastAPI and Pydantic AI
- **Hybrid RAG System** combining vector search (Qdrant) with knowledge graphs (Neo4j)
- **Modern Frontend** with Next.js and Supabase authentication
- **AI Orchestrator** with specialized autonomous agents
- **Complete Observability Stack** (Grafana, Prometheus, Loki, Jaeger, Langfuse)
- **Workflow Automation** (n8n) and AI Prototyping (Flowise)
- **Production Security** with Traefik, Let's Encrypt SSL, and comprehensive hardening

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Deployment Guide](#detailed-deployment-guide)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [Platform Services](#platform-services)
- [Management and Monitoring](#management-and-monitoring)
- [Security Features](#security-features)
- [AI Components](#ai-components)
- [Troubleshooting](#troubleshooting)
- [Backup and Recovery](#backup-and-recovery)

## 🔧 Prerequisites

### Hetzner Cloud Server
- **Minimum:** 4 vCPU, 8GB RAM, 80GB SSD
- **Recommended:** 8 vCPU, 16GB RAM, 160GB SSD
- **Operating System:** Ubuntu 22.04 LTS or newer
- **Network:** Public IPv4 address

### Domain Configuration
- Own a domain name with DNS control
- Ability to create A records pointing to your server

### Local Requirements
- SSH key-based authentication configured
- Basic knowledge of Docker and command line

## 🚀 Quick Start

### 1. Server Preparation

```bash
# Connect to your Hetzner server
ssh root@YOUR_SERVER_IP

# Clone the repository
git clone https://github.com/cbwinslow/supa-container.git
cd supa-container
```

### 2. Generate Secrets

```bash
# Generate all necessary passwords and secrets
bash generate_production_secrets.sh your-domain.com

# Review the generated .env file
cat .env
```

### 3. Deploy Platform

```bash
# Run the comprehensive deployment script
sudo bash deploy_hetzner.sh
```

### 4. Configure DNS

Create the following A records pointing to your server IP:

```
yourdomain.com          -> YOUR_SERVER_IP
www.yourdomain.com      -> YOUR_SERVER_IP
api.yourdomain.com      -> YOUR_SERVER_IP
grafana.yourdomain.com  -> YOUR_SERVER_IP
traefik.yourdomain.com  -> YOUR_SERVER_IP
n8n.yourdomain.com      -> YOUR_SERVER_IP
flowise.yourdomain.com  -> YOUR_SERVER_IP
langfuse.yourdomain.com -> YOUR_SERVER_IP
jaeger.yourdomain.com   -> YOUR_SERVER_IP
rabbitmq.yourdomain.com -> YOUR_SERVER_IP
neo4j.yourdomain.com    -> YOUR_SERVER_IP
```

### 5. Start Platform

```bash
# Navigate to application directory
cd /opt/supa-container

# Start all services
sudo ./start_platform.sh
```

### 6. Complete Setup

```bash
# Run post-deployment configuration
sudo bash post_deployment_setup.sh

# Monitor platform status
sudo ./monitor_platform.sh
```

## 📚 Detailed Deployment Guide

### Step 1: Server Setup and Optimization

The deployment script automatically:
- Updates the system and installs dependencies
- Installs Docker and Docker Compose
- Applies Hetzner-specific optimizations
- Configures security hardening (UFW firewall, fail2ban)
- Sets up system monitoring and logging

### Step 2: Application Architecture

The platform deploys the following components:

#### Core Services
- **Traefik**: Reverse proxy with automatic SSL
- **PostgreSQL**: Primary database with extensions
- **Neo4j**: Knowledge graph database
- **Qdrant**: Vector database for embeddings
- **Redis**: Caching and session storage
- **RabbitMQ**: Message broker for AI agents

#### Application Services
- **FastAPI**: Backend API with RAG capabilities
- **Next.js**: Frontend application
- **LocalAI**: Self-hosted LLM inference
- **n8n**: Workflow automation
- **Flowise**: AI flow prototyping

#### Observability Stack
- **Prometheus**: Metrics collection
- **Grafana**: Monitoring dashboards
- **Loki**: Log aggregation
- **Promtail**: Log shipping
- **Jaeger**: Distributed tracing
- **Langfuse**: LLM observability

#### AI Orchestration
- **AI Orchestrator**: Central brain for system management
- **Self-Healing Agent**: Automatic problem resolution
- **Monitoring Agent**: Performance optimization
- **Data Manager Agent**: Intelligent data flow management

### Step 3: Security Configuration

#### Network Security
- UFW firewall (SSH, HTTP, HTTPS only)
- Fail2ban intrusion prevention
- SSL/TLS encryption via Let's Encrypt
- Security headers via Traefik

#### Application Security
- Password-protected admin interfaces
- JWT-based authentication
- Secrets management via environment variables
- Container isolation and non-root users

#### System Security
- Automatic security updates
- Log rotation and monitoring
- File system permissions
- Process isolation

## 🔧 Post-Deployment Configuration

### 1. SSL Certificate Verification

SSL certificates are automatically generated by Let's Encrypt. Monitor the process:

```bash
# Check certificate status
sudo docker logs traefik | grep -i acme

# Verify certificates in acme.json
sudo jq '.letsencrypt.Certificates | length' /opt/supa-container/traefik/acme.json
```

### 2. Supabase Configuration

If using Supabase integration:

```bash
# Retrieve API keys
sudo docker-compose exec supabase supabase status

# Update .env file with keys
sudo nano /opt/supa-container/.env

# Restart applications
sudo docker-compose restart nextjs_app fastapi_app
```

### 3. AI Model Configuration

Configure LocalAI models:

```bash
# Download models (this may take time)
sudo docker exec localai wget -P /models https://huggingface.co/microsoft/DialoGPT-medium/resolve/main/pytorch_model.bin

# Restart LocalAI
sudo docker-compose restart localai
```

## 🌐 Platform Services

### Primary Application URLs

| Service | URL | Description |
|---------|-----|-------------|
| **Main App** | `https://yourdomain.com` | Primary application interface |
| **API Docs** | `https://api.yourdomain.com/docs` | FastAPI documentation |
| **Monitoring** | `https://grafana.yourdomain.com` | System monitoring dashboard |
| **Workflow** | `https://n8n.yourdomain.com` | Automation workflows |
| **AI Lab** | `https://flowise.yourdomain.com` | AI flow prototyping |

### Administrative URLs

| Service | URL | Purpose |
|---------|-----|---------|
| **Traefik** | `https://traefik.yourdomain.com` | Reverse proxy dashboard |
| **RabbitMQ** | `https://rabbitmq.yourdomain.com` | Message broker management |
| **Neo4j** | `https://neo4j.yourdomain.com` | Knowledge graph browser |
| **Jaeger** | `https://jaeger.yourdomain.com` | Distributed tracing |
| **Langfuse** | `https://langfuse.yourdomain.com` | LLM observability |

### Default Credentials

Check your `PRODUCTION_PASSWORDS_*.txt` file for all login credentials.

## 🛠️ Management and Monitoring

### Platform Management

```bash
# Start the platform
cd /opt/supa-container
sudo ./start_platform.sh

# Monitor platform status
sudo ./monitor_platform.sh

# View real-time logs
sudo docker-compose logs -f

# Restart specific service
sudo docker-compose restart <service_name>

# Stop all services
sudo docker-compose down

# Auto-start on boot
sudo systemctl enable supa-container
sudo systemctl start supa-container
```

### Health Monitoring

The platform includes comprehensive monitoring:

#### Automated Monitoring
- **Container health checks**: Automatic restart of failed containers
- **Service discovery**: Prometheus scraping of all services
- **Log aggregation**: Centralized logging via Loki
- **Alert management**: Grafana alerting for critical issues

#### Manual Monitoring
```bash
# Check service status
sudo docker-compose ps

# Monitor resource usage
sudo docker stats

# Check logs for specific service
sudo docker-compose logs <service_name>

# Monitor AI agent activity
sudo docker-compose logs orchestrator self_healing_agent
```

### AI Agent Monitoring

```bash
# View orchestrator status
sudo docker exec ai_orchestrator python -c "import requests; print(requests.get('http://localhost:8000/health').json())"

# Check agent communication
sudo docker exec rabbitmq rabbitmqctl list_queues

# Monitor agent logs
sudo docker-compose logs --tail=50 orchestrator monitoring_agent self_healing_agent data_manager_agent
```

## 🔒 Security Features

### Network Security
- **Firewall**: UFW configured for minimal attack surface
- **Intrusion Prevention**: Fail2ban monitoring and blocking
- **SSL/TLS**: Let's Encrypt certificates with automatic renewal
- **Security Headers**: HSTS, CSP, and other protection headers

### Application Security
- **Authentication**: JWT-based with secure secret management
- **Authorization**: Role-based access control
- **Input Validation**: Comprehensive API input sanitization
- **Rate Limiting**: Built-in API rate limiting and DDoS protection

### Infrastructure Security
- **Container Isolation**: Services run in isolated containers
- **Secrets Management**: Environment-based secret injection
- **Privilege Separation**: Non-root container execution
- **Regular Updates**: Automated security updates

### Monitoring and Auditing
- **Access Logs**: Comprehensive logging of all access attempts
- **Security Events**: Fail2ban and system security monitoring
- **Audit Trail**: Database and application audit logging
- **Alerting**: Real-time security alert notifications

## 🤖 AI Components

### AI Orchestrator Brain

The central AI system that manages the entire platform:

```python
# Core capabilities:
- System health monitoring and analysis
- Intelligent resource allocation
- Automated problem detection and resolution
- Agent coordination and task distribution
- Performance optimization recommendations
```

### Specialized Agents

#### Self-Healing Agent
- Monitors container health and performance
- Automatically restarts failed services
- Clears resource bottlenecks
- Optimizes system configuration

#### Monitoring Agent
- Collects and analyzes system metrics
- Detects performance anomalies
- Generates optimization recommendations
- Manages alerting and notifications

#### Data Manager Agent
- Optimizes database performance
- Manages data retention policies
- Coordinates backup operations
- Ensures data consistency and integrity

### Agent Communication

Agents communicate via RabbitMQ message broker:

```bash
# Monitor message queues
sudo docker exec rabbitmq rabbitmqctl list_queues

# View agent communication logs
sudo docker-compose logs rabbitmq | grep -i agent
```

## 🔧 Troubleshooting

### Common Issues

#### Services Not Starting
```bash
# Check Docker daemon
sudo systemctl status docker

# Check resource usage
free -h && df -h

# Review startup logs
sudo docker-compose logs
```

#### SSL Certificate Issues
```bash
# Check DNS resolution
nslookup yourdomain.com

# Monitor certificate generation
sudo docker logs traefik | grep -i certificate

# Manually trigger certificate renewal
sudo docker exec traefik traefik-certs-dumper
```

#### Database Connection Issues
```bash
# Check PostgreSQL status
sudo docker exec postgres pg_isready

# Review connection logs
sudo docker-compose logs postgres

# Test database connection
sudo docker exec postgres psql -U postgres -l
```

#### AI Agent Issues
```bash
# Check orchestrator health
sudo docker exec ai_orchestrator python -c "import requests; requests.get('http://localhost:8000/health')"

# Review agent logs
sudo docker-compose logs orchestrator

# Check RabbitMQ connectivity
sudo docker exec rabbitmq rabbitmq-diagnostics ping
```

### Performance Optimization

#### Resource Monitoring
```bash
# Monitor container resources
sudo docker stats

# Check system resources
htop

# Monitor disk I/O
sudo iotop
```

#### Database Optimization
```bash
# PostgreSQL performance
sudo docker exec postgres psql -U postgres -c "SELECT * FROM pg_stat_activity;"

# Neo4j performance
sudo docker exec neo4j cypher-shell -u neo4j -p password "CALL dbms.queryJmx('java.lang:type=Memory');"
```

### Log Analysis

```bash
# View all application logs
sudo docker-compose logs

# Filter logs by service
sudo docker-compose logs fastapi_app

# Monitor real-time logs
sudo docker-compose logs -f --tail=100

# Search logs for errors
sudo docker-compose logs | grep -i error
```

## 💾 Backup and Recovery

### Automated Backups

The platform includes automated daily backups:

```bash
# Manual backup
sudo /opt/supa-container/backup_platform.sh

# Check backup status
ls -la /opt/backup/

# Restore from backup
sudo bash restore_platform.sh /opt/backup/platform_backup_YYYYMMDD_HHMMSS.tar.gz
```

### Database Backups

```bash
# PostgreSQL backup
sudo docker exec postgres pg_dump -U postgres postgres > postgres_backup.sql

# Neo4j backup
sudo docker exec neo4j neo4j-admin dump --database=neo4j --to=/tmp/neo4j_backup.dump

# Restore PostgreSQL
sudo docker exec -i postgres psql -U postgres < postgres_backup.sql
```

### Configuration Backups

```bash
# Backup configurations
sudo tar -czf config_backup.tar.gz /opt/supa-container/

# Backup secrets (handle with care)
sudo cp /opt/supa-container/.env ~/.env.backup
```

## 🔄 Updates and Maintenance

### Platform Updates

```bash
# Update platform code
cd /path/to/supa-container
git pull origin main

# Rebuild containers
sudo docker-compose build --no-cache

# Restart with new images
sudo docker-compose up -d
```

### Security Updates

```bash
# System updates
sudo apt update && sudo apt upgrade -y

# Docker updates
sudo apt update docker-ce docker-ce-cli containerd.io

# Restart platform after updates
sudo systemctl restart supa-container
```

### Maintenance Tasks

```bash
# Clean up Docker resources
sudo docker system prune -a

# Rotate logs
sudo logrotate -f /etc/logrotate.d/supa-container

# Update SSL certificates (if needed)
sudo docker exec traefik traefik-certs-dumper
```

## 📞 Support and Documentation

### Getting Help

1. **Check the logs**: Most issues can be diagnosed from the application logs
2. **Review monitoring**: Grafana dashboards provide insights into system health
3. **Consult documentation**: Each service has detailed documentation
4. **Community support**: Join the discussion on GitHub

### Additional Resources

- **Platform Documentation**: Available at `https://api.yourdomain.com/docs`
- **Monitoring Dashboards**: `https://grafana.yourdomain.com`
- **Component Documentation**: Each service provides detailed documentation
- **Security Best Practices**: Follow the security checklist in the documentation

---

## 🎉 Congratulations!

Your AI-Enhanced Supa Container platform is now deployed and ready for production use. The system includes:

✅ **Production-grade infrastructure** with automatic scaling and monitoring  
✅ **Comprehensive security** with firewalls, SSL, and access controls  
✅ **AI-powered automation** with intelligent agents and orchestration  
✅ **Complete observability** with metrics, logs, and distributed tracing  
✅ **Backup and recovery** systems for business continuity  

For ongoing support and updates, monitor the GitHub repository and join the community discussions.

**Happy building! 🚀**