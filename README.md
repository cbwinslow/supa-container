# Supa-Container: Production-Ready AIOps & Agentic RAG Platform

Supa-Container is a complete, production-grade platform for building, deploying, and operating advanced AI applications. It combines a sophisticated agentic backend (RAG + Knowledge Graph) with a full suite of production services, including a polished UI, workflow automation, and a comprehensive AIOps and observability stack.

This repository provides a one-click deployment script to set up the entire containerized environment on your server.

---

## Features

-   **Advanced AI Backend:**
    -   **Agentic Framework:** A custom Python backend using Pydantic AI that can reason and use tools.
    -   **Hybrid RAG:** Combines semantic vector search (via Supabase/pgvector) with a temporal **Knowledge Graph** (via Neo4j) for deep, contextual analysis.
    -   **Secure API:** A robust FastAPI backend with endpoints for ingestion, streaming chat, and model management.
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
-   **Integrated Tooling:**
    -   **AI Prototyping Lab (Flowise):** A low-code UI for rapidly building and testing new AI flows.
    -   **Workflow Automation (n8n):** An integrated n8n instance for connecting your AI to other services.

---

## Deployment Walkthrough

Deploying this platform involves three main steps: configuration, deployment, and post-deployment setup.

### Step 1: Configuration

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/cbwinslow/supa-container.git
    cd supa-container
    ```

2.  **Edit the Configuration File:**
    Open the `config.sh` file. This is the central place to manage your deployment settings.
    ```bash
    # The primary domain you will use for all services.
    export DOMAIN="your-domain.com"

    # The email address for Let's Encrypt SSL registration.
    export LETSENCRYPT_EMAIL="your-email@your-domain.com"

    # A secure password for the Traefik dashboard.
    export TRAEFIK_ADMIN_PASSWORD="your-secure-traefik-password"
    ```
    **Fill in these three variables with your actual domain, email, and a secure password.**

### Step 2: Deployment

Run the main deployment script with `sudo`. This script creates the necessary directories, generates all configuration files, and copies the application code to the correct locations.
```bash
sudo bash deploy.sh
```

### Step 3: Post-Deployment Setup

After the deployment script finishes, run a one-time setup script to initialize the database and retrieve your Supabase API keys.

1.  **Start the Services:**
    ```bash
    cd /opt/supabase-super-stack
    sudo docker-compose up -d
    ```
    Wait a minute or two for all services to start up.

2.  **Run the Post-Deployment Script:**
    This script connects to your running Supabase container, applies the database schemas (including the audit log), and fetches your unique API keys.
    ```bash
    # From the /opt/supabase-super-stack directory
    sudo ../post-deploy-setup.sh
    ```

3.  **Update Your `.env` File:**
    The script will print out two lines for `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`. **You must manually copy these lines and paste them into your `.env` file:**
    ```bash
    sudo nano /opt/supabase-super-stack/.env
    ```
    Paste the keys at the bottom of the file.

4.  **Restart the Application:**
    For the new environment variables to take effect, restart the relevant services.
    ```bash
    sudo docker-compose restart nextjs_app fastapi_app
    ```

Your application is now fully deployed and operational!

---

## Usage Guide

-   **Main Application:** `https://your-domain.com`
-   **API Documentation:** `https://api.your-domain.com/docs`
-   **AI Prototyping Lab (Flowise):** `https://flowise.your-domain.com`
-   **Workflow Automation (n8n):** `https://n8n.your-domain.com`
-   **LLM Observability (Langfuse):** `https://langfuse.your-domain.com`
-   **Observability (Jaeger):** `https://jaeger.your-domain.com`
-   **Traefik Dashboard:** `https://traefik.your-domain.com`