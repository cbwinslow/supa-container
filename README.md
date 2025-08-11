# Supa-Container: Production-Ready AIOps & Agentic RAG Platform

Supa-Container is a complete, production-grade platform for building, deploying, and operating advanced AI applications. It combines a sophisticated agentic backend (RAG + Knowledge Graph) with a full suite of production services, including a polished UI, workflow automation, and a comprehensive AIOps and observability stack.

This repository provides a one-click deployment script to set up the entire containerized environment on your server.

## 🚀 Quick Start - One-Click Hetzner Deployment

**Ready for immediate production deployment on Hetzner Cloud!**

```bash
git clone https://github.com/cbwinslow/supa-container.git
cd supa-container
sudo bash one_click_deploy.sh yourdomain.com admin@yourdomain.com
```

🎯 **That's it!** The script handles everything automatically:
- ✅ System optimization for Hetzner Cloud
- ✅ Security hardening (firewall, SSL, fail2ban)  
- ✅ AI orchestrator with autonomous agents
- ✅ Complete observability stack
- ✅ Production-ready configuration

📖 **[Complete Deployment Guide](README_HETZNER_DEPLOYMENT.md)** - Detailed documentation for production deployment

---

## Features

-   **Advanced AI Backend:**
    -   **Agentic Framework:** A custom Python backend using Pydantic AI that can reason and use tools.
    -   **Hybrid RAG:** Combines semantic vector search (via Supabase/pgvector) with a temporal **Knowledge Graph** (via Neo4j) for deep, contextual analysis.
    -   **Secure API:** A robust FastAPI backend with endpoints for ingestion, streaming chat, model management, and built-in rate limiting.
-   **Polished User Interface:**
    -   **ChatGPT-like Experience:** A Next.js frontend with a full chat interface, conversation history, and Markdown/code rendering.
    -   **Supabase Auth:** Secure user authentication (login, signup, etc.) managed by Supabase.
    -   **Agent Transparency:** The UI displays which tools the agent used to arrive at its answer.
-   **Production-Grade AIOps & Observability:**
    -   **Full-Stack Tracing:** OpenTelemetry provides distributed tracing from the frontend click to the database query.
    -   **LLM Observability (Langfuse):** Dedicated tracing for AI performance, quality, and cost analysis.
    -   **Log Aggregation (Loki):** Centralized logging for all services.
    -   **Real-Time Monitoring (Netdata - *coming soon*):** High-fidelity, real-time metrics.
    -   **Unified Dashboards (Grafana):** A single pane of glass for all metrics, logs, and traces.
    -   **Security Auditing:** A database-level audit log tracks all user actions.
    -   **Traffic Monitoring:** Traefik access logs are captured for security and performance analysis.
    -   **Self-Healing Feedback:** An AI orchestrator analyses logs, monitoring exports and database state to launch specialised agents for automatic remediation.
-   **Integrated Tooling:**
    -   **AI Prototyping Lab (Flowise):** A low-code UI for rapidly building and testing new AI flows.
    -   **Workflow Automation (n8n):** An integrated n8n instance for connecting your AI to other services.

---

## Deployment Walkthrough

Deploying this platform is now a simple, one-step process with our new production-ready scripts.

### Option 1: One-Click Deployment (Recommended)

```bash
# Clone the repository
git clone https://github.com/cbwinslow/supa-container.git
cd supa-container

# Run the one-click deployment script
sudo bash one_click_deploy.sh yourdomain.com admin@yourdomain.com
```

This single command will:
- Generate all necessary secrets and passwords
- Install and configure all services  
- Set up security hardening
- Deploy AI orchestrator and agents
- Configure monitoring and observability
- Run comprehensive tests

### Option 2: Step-by-Step Deployment

For more control over the deployment process:

#### Step 1: Generate Secrets
```bash
bash generate_production_secrets.sh yourdomain.com
```

#### Step 2: Deploy Infrastructure  
```bash
sudo bash deploy_hetzner.sh
```

#### Step 3: Start Services
```bash
cd /opt/supa-container
sudo ./start_platform.sh
```

#### Step 4: Complete Setup
```bash
sudo bash post_deployment_setup.sh
```

#### Step 5: Validate Deployment
```bash
sudo bash test_deployment.sh
```

### Post-Deployment

After deployment, configure DNS records to point to your server:

```
yourdomain.com          -> YOUR_SERVER_IP
api.yourdomain.com      -> YOUR_SERVER_IP  
grafana.yourdomain.com  -> YOUR_SERVER_IP
traefik.yourdomain.com  -> YOUR_SERVER_IP
# ... and other subdomains
```

Your application will be fully operational once DNS propagates!

---

## Usage Guide

After deployment and DNS configuration, access your platform at:

-   **Main Application:** `https://your-domain.com`
-   **API Documentation:** `https://api.your-domain.com/docs`
-   **System Monitoring:** `https://grafana.your-domain.com`
-   **AI Workflow Lab:** `https://flowise.your-domain.com`
-   **Automation Hub:** `https://n8n.your-domain.com`
-   **LLM Observability:** `https://langfuse.your-domain.com`
-   **Distributed Tracing:** `https://jaeger.your-domain.com`
-   **Traefik Dashboard:** `https://traefik.your-domain.com`
-   **Message Broker:** `https://rabbitmq.your-domain.com`
-   **Knowledge Graph:** `https://neo4j.your-domain.com`

### Management Commands

```bash
# Monitor platform status
sudo /opt/supa-container/monitor_platform.sh

# Create system backup  
sudo /opt/supa-container/backup_platform.sh

# View real-time logs
cd /opt/supa-container && sudo docker-compose logs -f

# Test all components
sudo bash test_deployment.sh

# Restart platform
sudo systemctl restart supa-container
```

### AI Features

The platform includes an advanced AI orchestrator managing:
- **Self-healing system recovery** - Automatic detection and resolution of issues
- **Intelligent monitoring** - Performance optimization and anomaly detection  
- **Data flow optimization** - Smart data routing and processing
- **Agent coordination** - Autonomous task distribution and execution

Access the AI management interface through the monitoring dashboard to view agent activity and system intelligence.


