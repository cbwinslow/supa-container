# AI-Enhanced Production Platform for opendiscourse.net

A complete, production-ready AI platform with intelligent orchestration, self-healing capabilities, and comprehensive agent management for deployment on Hetzner infrastructure.

## 🚀 Quick Deploy to Hetzner

### Prerequisites
- Hetzner Cloud Server (minimum 4GB RAM, 2 vCPUs)
- Domain: `opendiscourse.net` with DNS access
- SSH access to server

### 1. Clone and Deploy
```bash
# On your Hetzner server
git clone https://github.com/cbwinslow/hetzner_app.git
cd hetzner_app

# Run master deployment
sudo bash deploy-master.sh
```

### 2. Configure DNS Records
Point these DNS records to your Hetzner server IP:
```
opendiscourse.net → YOUR_SERVER_IP
www.opendiscourse.net → YOUR_SERVER_IP
api.opendiscourse.net → YOUR_SERVER_IP
rabbitmq.opendiscourse.net → YOUR_SERVER_IP
grafana.opendiscourse.net → YOUR_SERVER_IP
jaeger.opendiscourse.net → YOUR_SERVER_IP
langfuse.opendiscourse.net → YOUR_SERVER_IP
flowise.opendiscourse.net → YOUR_SERVER_IP
n8n.opendiscourse.net → YOUR_SERVER_IP
traefik.opendiscourse.net → YOUR_SERVER_IP
```

### 3. Start Platform
```bash
cd /opt/supabase-super-stack
sudo ./start-platform.sh
```

### 4. Monitor AI Agents
```bash
sudo ./monitor-agents.sh
```

## 🧠 AI Orchestrator Brain

The platform includes a sophisticated AI Orchestrator Brain that:

- **Manages all AI agents** with intelligent task distribution
- **Ensures zero data waste** - every piece of data is analyzed and utilized
- **Provides self-healing** through specialized recovery agents
- **Monitors system health** with real-time performance analysis
- **Optimizes resource usage** with intelligent load balancing
- **Coordinates agent communication** via RabbitMQ message broker

### Specialized Agents

1. **Self-Healing Agent**
   - Automatic service recovery
   - Disk space management
   - Memory optimization
   - Error pattern detection

2. **Monitoring Agent**
   - Real-time system metrics
   - Performance tracking
   - Health checks
   - Alert generation

3. **Data Manager Agent**
   - Data flow optimization
   - Storage management
   - Compression and archival
   - Neo4j integration

4. **Learning Agent**
   - Pattern recognition
   - Knowledge extraction
   - Model improvement
   - Insight generation

## 🔗 Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Web Traffic   │───▶│     Traefik      │───▶│   Next.js App   │
│  (HTTPS/SSL)    │    │  Load Balancer   │    │   (Frontend)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌──────────────────┐
                       │   FastAPI App    │
                       │   (Backend)      │
                       └──────────────────┘
                                │
                ┌───────────────┼───────────────┐
                ▼               ▼               ▼
       ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
       │ PostgreSQL  │ │   Neo4j     │ │  RabbitMQ   │
       │ (Supabase)  │ │(Knowledge   │ │ (Messages)  │
       │             │ │   Graph)    │ │             │
       └─────────────┘ └─────────────┘ └─────────────┘
                                │
                                ▼
                    ┌──────────────────────┐
                    │  AI Orchestrator     │
                    │      Brain           │
                    └──────────────────────┘
                                │
                ┌───────────────┼───────────────┐
                ▼               ▼               ▼
       ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
       │Self-Healing │ │ Monitoring  │ │    Data     │
       │   Agent     │ │   Agent     │ │ Manager     │
       └─────────────┘ └─────────────┘ └─────────────┘
```

## 🔧 Key Features

### Maximum Data Utilization
- **95% Data Efficiency Target**: AI Orchestrator ensures no data goes unused
- **Real-time Analysis**: All logs, metrics, and user data processed immediately
- **Historical Processing**: Background agents analyze stored data for insights
- **Graph Knowledge**: Neo4j stores relationships and context for intelligent retrieval

### Zero-Waste Architecture
- **Log Aggregation**: Loki collects all application logs
- **Metrics Collection**: Prometheus gathers system and application metrics
- **Trace Analysis**: Jaeger provides distributed tracing insights
- **Message Processing**: RabbitMQ ensures reliable agent communication

### Self-Healing Capabilities
- **Automatic Recovery**: Services restart automatically on failure
- **Resource Optimization**: Memory and disk cleanup on thresholds
- **Error Pattern Detection**: ML analysis identifies recurring issues
- **Proactive Maintenance**: Scheduled cleanup and optimization tasks

### Comprehensive Monitoring
- **Real-time Dashboards**: Grafana provides visual system overview
- **Health Checks**: All services monitored with automatic alerting
- **Performance Tracking**: Detailed metrics on all system components
- **Agent Coordination**: Visual monitoring of agent communication

## 🛠 Development & Testing

### Run Tests
```bash
# Install dependencies
pip install pytest pytest-asyncio httpx pika neo4j openai

# Run all tests
python -m pytest tests/ -v

# Run specific test suites
python -m pytest tests/test_message_broker.py -v
python -m pytest tests/test_agents.py -v
```

### Test Coverage
- **Message Broker**: Complete RabbitMQ integration testing
- **AI Agents**: Unit and integration tests for all agent types
- **Orchestrator**: Brain functionality and coordination testing
- **API Endpoints**: FastAPI backend testing
- **Database Integration**: PostgreSQL and Neo4j connection testing

## 📚 Platform Components

### Core Services
- **Next.js Frontend**: Modern React-based UI
- **FastAPI Backend**: High-performance Python API
- **PostgreSQL**: Primary data storage (via Supabase)
- **Neo4j**: Knowledge graph and relationships
- **RabbitMQ**: Message broker for agent communication

### AI & ML Services
- **Flowise**: Visual AI workflow builder
- **n8n**: Workflow automation platform
- **LocalAI**: Local model serving
- **Langfuse**: LLM observability and monitoring

### Observability Stack
- **Traefik**: Load balancer and SSL termination
- **Grafana**: Monitoring dashboards
- **Prometheus**: Metrics collection
- **Loki**: Log aggregation
- **Jaeger**: Distributed tracing

## 🔐 Security Features

- **SSL/TLS**: Automatic Let's Encrypt certificates
- **Basic Auth**: Protected admin interfaces
- **Network Isolation**: Docker networks for service communication
- **Access Control**: Role-based permissions
- **Audit Logging**: Complete activity tracking

## 📈 Performance Optimization

- **Container Orchestration**: Docker Compose with health checks
- **Resource Limits**: Configured memory and CPU constraints
- **Auto-scaling**: Agent deployment based on workload
- **Caching**: Redis integration for performance
- **CDN Ready**: Optimized for content delivery networks

## 🔄 Deployment Options

### Development
```bash
# Local development setup
cp .env.example .env
# Edit .env with your configurations
docker-compose up -d
```

### Staging
```bash
# Staging deployment
bash deploy.sh
```

### Production
```bash
# Full production deployment with AI agents
bash deploy-master.sh
```

## 📞 Support & Monitoring

### Accessing Services
- **Main Application**: https://opendiscourse.net
- **API Documentation**: https://api.opendiscourse.net/docs
- **Message Broker**: https://rabbitmq.opendiscourse.net
- **System Monitoring**: https://grafana.opendiscourse.net
- **Distributed Tracing**: https://jaeger.opendiscourse.net
- **AI Workflows**: https://flowise.opendiscourse.net
- **Automation**: https://n8n.opendiscourse.net

### Monitoring Commands
```bash
# Check all services
docker-compose ps

# Monitor AI agents
./monitor-agents.sh

# View logs
docker-compose logs -f orchestrator
docker-compose logs -f self_healing_agent

# Check RabbitMQ queues
docker exec rabbitmq rabbitmqctl list_queues
```

### Troubleshooting
```bash
# Restart specific service
docker-compose restart <service_name>

# Check service health
docker-compose exec <service_name> health-check

# View detailed logs
docker-compose logs --tail=100 <service_name>
```

## 🚀 Advanced Features

### AI Agent Management
The platform automatically manages specialized AI agents for:
- **Self-improvement**: Continuous system optimization
- **Learning**: Pattern recognition and knowledge extraction
- **Troubleshooting**: Intelligent problem diagnosis
- **Feature Building**: Automated capability expansion
- **Testing**: Comprehensive system validation
- **Deployment**: Automated service management

### Data Flow Optimization
- **Stream Processing**: Real-time data analysis
- **Batch Processing**: Efficient bulk data handling
- **Graph Analytics**: Relationship-based insights
- **Vector Search**: Semantic similarity matching
- **Full-Text Search**: Advanced content discovery

### Integration Capabilities
- **RAG (Retrieval-Augmented Generation)**: Enhanced AI responses
- **GraphQL**: Flexible data querying
- **GraphML**: Network analysis and visualization
- **OpenTelemetry**: Comprehensive observability
- **Webhook Support**: External system integration

## 📋 Requirements

### System Requirements
- **RAM**: Minimum 4GB, Recommended 8GB+
- **CPU**: Minimum 2 cores, Recommended 4+ cores
- **Storage**: Minimum 20GB, Recommended 50GB+
- **Network**: Stable internet connection for SSL certificates

### Software Requirements
- **Docker**: Version 20.10+
- **Docker Compose**: Version 2.0+
- **Linux**: Ubuntu 20.04+ or similar
- **Python**: 3.12+ (for development)

---

## 🏆 Production-Ready Features

✅ **Automated SSL/TLS certificates**  
✅ **Health checks and auto-restart**  
✅ **Comprehensive logging and monitoring**  
✅ **Zero-downtime deployments**  
✅ **Automated backups**  
✅ **Security hardening**  
✅ **Performance optimization**  
✅ **AI-powered self-healing**  
✅ **Intelligent agent coordination**  
✅ **Maximum data utilization**  

This platform is ready for production deployment on Hetzner infrastructure with complete AI orchestration, self-healing capabilities, and comprehensive monitoring for the opendiscourse.net domain.