# Supa-Container: Production-Ready Agentic RAG & Knowledge Graph Platform

Supa-Container is a complete, production-grade platform for building and deploying advanced AI applications. It combines a sophisticated agentic backend, capable of both semantic search (RAG) and knowledge graph traversal, with a full suite of production services including a polished UI, workflow automation, and a comprehensive observability stack.

This repository provides a one-click deployment script to set up the entire containerized environment on your server.

![Architecture Diagram](https://i.imgur.com/your-architecture-diagram.png) <!-- Placeholder for a diagram -->

---

## Features

- **Advanced AI Backend:**
    - **Agentic Framework:** A custom Python backend using Pydantic AI that can reason and use tools.
    - **Hybrid RAG:** Combines semantic vector search (via Supabase/pgvector) with a temporal **Knowledge Graph** (via Neo4j) for deep, contextual analysis.
    - **Secure API:** A robust FastAPI backend with endpoints for ingestion, streaming chat, and model management.
- **Polished User Interface:**
    - **ChatGPT-like Experience:** A Next.js frontend with a full chat interface, conversation history, and Markdown/code rendering.
    - **Supabase Auth:** Secure user authentication (login, signup, etc.) managed by Supabase.
    - **Agent Transparency:** The UI displays which tools the agent used to arrive at its answer.
    - **Dynamic Model Selection:** Switch between different LLMs from your LocalAI instance on the fly.
- **Production-Grade Stack:**
    - **Containerized Services:** The entire application stack is managed via Docker Compose for consistency and reliability.
    - **Automated Deployment:** A single `deploy.sh` script to set up the entire environment.
    - **HTTPS & Security:** Traefik acts as a reverse proxy, providing automatic SSL certificates (via Let's Encrypt) and secure access to all services.
- **Integrated Tooling:**
    - **AI Prototyping Lab (Flowise):** A low-code UI for rapidly building and testing new AI flows and agents, connected to the same backend services.
    - **Workflow Automation (n8n):** An integrated n8n instance for building custom workflows and connecting your AI to other services.
    - **Full-Stack Observability (OpenTelemetry):** A complete observability stack with Jaeger for distributed tracing, allowing you to monitor performance from the frontend click all the way to the database query.

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
    Open the `config.sh` file in a text editor. This is the central place to manage your deployment settings.

    ```bash
    # The primary domain you will use for all services.
    # IMPORTANT: You must own this domain and point it to your server's IP.
    export DOMAIN="your-domain.com"

    # The email address for Let's Encrypt SSL registration.
    export LETSENCRYPT_EMAIL="your-email@your-domain.com"

    # A secure password for the Traefik dashboard.
    export TRAEFIK_ADMIN_PASSWORD="your-secure-traefik-password"
    ```
    **Fill in these three variables with your actual domain, email, and a secure password.**

### Step 2: Deployment

Run the main deployment script with `sudo`. This script will create the necessary directories (`/opt/supabase-super-stack` and `/var/www/html/super-stack`), generate all configuration files, and copy the application code to the correct locations.

```bash
sudo bash deploy.sh
```

### Step 3: Post-Deployment Setup

After the deployment script finishes, you need to run a one-time setup script to initialize the database and retrieve your Supabase API keys.

1.  **Start the Services:**
    ```bash
    cd /opt/supabase-super-stack
    sudo docker-compose up -d
    ```
    Wait a minute or two for all services to start up.

2.  **Run the Post-Deployment Script:**
    This script will connect to your running Supabase container, apply the database schema, and fetch your unique API keys.
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
-   **Observability (Jaeger):** `https://jaeger.your-domain.com`
-   **Traefik Dashboard:** `https://traefik.your-domain.com`

### Ingesting Documents

The application's RAG capabilities rely on documents being ingested into the vector and graph databases. You can do this by running the ingestion script inside the `fastapi_app` container.

1.  **Place Documents:** Copy the PDF or text documents you want to analyze into a directory on your server.
2.  **Run Ingestion:**
    ```bash
    # From /opt/supabase-super-stack
    sudo docker-compose exec fastapi_app python -m ingestion.ingest --documents /path/to/your/docs --clean
    ```

---

## Local Development

While the scripts are designed for a production server, you can adapt them for local development.

1.  **Comment out `sudo` checks:** In `deploy.sh`, comment out the "Check for Root Privileges" section.
2.  **Change directories:** In `config.sh`, change `APP_ROOT` and `WEB_ROOT` to local directories (e.g., `./deploy/app` and `./deploy/web`).
3.  **Use a local domain:** Set `DOMAIN` to `localhost` or a local domain like `local.dev` and manage it via your `/etc/hosts` file.
4.  **Run the scripts:** Run `./deploy.sh` and then the post-deployment setup as described above.
