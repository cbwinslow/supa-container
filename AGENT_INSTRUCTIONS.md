# Agent Instructions for Supa-Container Project

This document provides the necessary context, architectural overview, and operational guidelines for any AI agent working on the `supa-container` repository.

---

## 1. Project Overview & Goal

The primary goal of this project is to provide a **production-grade, deployable platform for an advanced agentic RAG system**. The system combines traditional vector search with a knowledge graph to provide deep, contextual analysis of ingested documents.

The project is architected as a multi-service, containerized application managed by Docker Compose and is designed to be deployed on a dedicated server.

## 2. Core Architecture

The application is composed of several key services that work together. Understanding this architecture is critical.

```
[ User Browser ]
       |
       v (HTTPS on your-domain.com)
[ Traefik Reverse Proxy ]
       |
       +--> [ Next.js Frontend ] <--> [ Supabase (Auth) ]
       |      (UI)
       |
       +--> [ FastAPI Backend ] <--> [ Supabase (Postgres/pgvector) ]
       |      (Agentic API) |      (Vector Store & App Data)
       |                    |
       |                    +------> [ Neo4j ]
       |                    |        (Knowledge Graph)
       |                    |
       |                    +------> [ LocalAI ]
       |                             (LLM & Embedding Models)
       |
       +--> [ Flowise ] (AI Lab)
       |
       +--> [ n8n ] (Workflow Automation)
       |
       +--> [ Jaeger ] (Observability UI)
       |
       +--> [ OpenTelemetry Collector ] <-- (Traces from Frontend/Backend)
```

-   **Traefik:** The single entry point for all web traffic. It handles HTTPS, routing to services, and security.
-   **Next.js Frontend:** The user-facing application, built in React. It handles user authentication via Supabase and communicates with the FastAPI backend.
-   **FastAPI Backend:** The "brains" of the application. It's a Python service that contains the AI agent, all the RAG and knowledge graph logic, and the API endpoints.
-   **Supabase:** A containerized Supabase instance that provides PostgreSQL for data storage (including vector embeddings) and handles all user authentication.
-   **Neo4j:** The database for the knowledge graph.
-   **LocalAI:** The service for running local LLMs and embedding models.
-   **Flowise & n8n:** Integrated tools for prototyping and automation.
-   **Observability Stack:** OpenTelemetry and Jaeger provide full-stack distributed tracing.

## 3. Key Files & Conventions

-   **`deploy.sh`:** The **single source of truth** for the production environment's structure. It generates the `docker-compose.yml` and other necessary configuration files. **When adding a new service or changing a configuration, this is the primary file to modify.**
-   **`config.sh`:** The user-facing configuration file. All high-level settings (domain, passwords, etc.) are managed here.
-   **`post-deploy-setup.sh`:** The script for finalizing the setup *after* the containers are running. It handles database schema migration and API key retrieval.
-   **`fastapi_app/`:** The directory for the Python backend. Follow existing conventions for structure (e.g., `api.py` for endpoints, `tools.py` for agent tools).
-   **`nextjs_app/`:** The directory for the React frontend.
-   **`sql/schema.sql`:** The definitive schema for the PostgreSQL database. Any database changes **must** be reflected here.

## 4. Operational Guidelines

-   **Always work on a feature branch.** Never commit directly to `master`.
-   **The deployment target is a server.** All scripts and configurations are designed with this in mind (e.g., file paths in `/opt` and `/var/www/html`).
-   **Test thoroughly.** The project has a `tests/` directory with a Pytest suite. Any changes to the backend **must** be accompanied by corresponding tests.
-   **Follow existing style.** Mimic the code style, naming conventions, and architectural patterns already present in the codebase.
-   **Update documentation.** Any significant changes must be reflected in the `README.md`.
-   **Secrets are managed by the user.** Never hardcode secrets. The `deploy.sh` script generates a `.env` file, which the user populates. Do not attempt to access or manage secrets directly.
