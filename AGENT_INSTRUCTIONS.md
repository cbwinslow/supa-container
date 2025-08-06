# Agent Instructions for Supa-Container Project

This document provides the necessary context, architectural overview, and operational guidelines for any AI agent working on the `supa-container` repository.

---

## 1. Project Overview & Goal

The primary goal of this project is to provide a **production-grade, deployable platform for an advanced AIOps and Agentic RAG system**. The system combines a sophisticated agentic backend (RAG + Knowledge Graph) with a full suite of production services, including a polished UI, workflow automation, and a comprehensive observability stack designed for intelligent, self-aware operation.

## 2. Core Architecture

The application is a complex, multi-service, containerized system. Understanding this architecture is critical.

```
[ User Browser ]
       |
       v (HTTPS on your-domain.com)
[ Traefik Reverse Proxy ] (Captures Access Logs -> Promtail)
       |
       +--> [ Next.js Frontend ] ---------> [ Supabase (Auth) ]
       |      (UI, OpenTelemetry Traces)
       |
       +--> [ FastAPI Backend ] ---------> [ Supabase (Postgres/pgvector) ]
       |      (Agentic API, OpenTelemetry & Langfuse Traces) | (Vector Store, App Data, Audit Log)
       |                                                    |
       |                                                    +--> [ Neo4j ]
       |                                                    |    (Knowledge Graph)
       |                                                    |
       |                                                    +--> [ LocalAI ]
       |                                                         (LLM & Embedding Models)
       |
       +--> [ Flowise ] (AI Lab)
       |
       +--> [ n8n ] (Workflow Automation)
       |
       +--> [ Jaeger ] (Trace Visualization)
       |
       +--> [ Langfuse ] (LLM Trace Visualization)
       |
       +--> [ OpenTelemetry Collector ] <--+ (Traces from Frontend/Backend)
       |                                    |
       +------------------------------------+
       |
[ Promtail ] (Collects all container & Traefik logs) -> [ Loki ] (Log Aggregation)
       |
[ Grafana ] (Unified Dashboards for Metrics, Logs, Traces)
```

-   **Traefik:** The single entry point. Handles HTTPS, routing, and generates access logs for traffic monitoring.
-   **Next.js Frontend:** The user-facing application. Instrumented with OpenTelemetry.
-   **FastAPI Backend:** The "brains" of the application. Instrumented with both OpenTelemetry and Langfuse.
-   **Supabase:** Provides PostgreSQL, vector storage, user authentication, and a database-level **audit log**.
-   **Neo4j & LocalAI:** Core components for the agent's knowledge graph and AI model serving.
-   **Flowise & n8n:** Integrated tools for prototyping and automation.
-   **AIOps & Observability Stack:**
    -   **OpenTelemetry & Jaeger:** Provide full-stack distributed tracing.
    -   **Langfuse:** Provides deep observability into the performance and quality of the LLM agent.
    -   **Promtail & Loki:** Aggregate logs from all services, including Traefik's traffic logs.
    -   **Grafana:** The central dashboard for visualizing all monitoring data.

## 3. Key Files & Conventions

-   **`deploy.sh`:** The **single source of truth** for the production environment's structure. **When adding a new service or changing a configuration, this is the primary file to modify.**
-   **`config.sh`:** The user-facing configuration file.
-   **`post-deploy-setup.sh`:** The script for finalizing the setup *after* the containers are running. It handles database schema migrations (including the audit log) and API key retrieval.
-   **`sql/`:** Contains the definitive schemas for the database (`schema.sql`) and the audit log (`audit.sql`).
-   **Always work on a feature branch.** Never commit directly to `master`.

## 4. Operational Guidelines

-   **The system is designed for production.** Assume all changes must be robust, secure, and well-documented.
-   **Test thoroughly.** Any changes to the backend **must** be accompanied by corresponding tests in the `tests/` directory.
-   **Update documentation.** Any significant changes must be reflected in the `README.md` and this file.
-   **Secrets are managed by the user.** Never hardcode secrets. The `deploy.sh` script generates a `.env` file, which the user populates.