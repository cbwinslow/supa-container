# Supa Container

This repository provides a one-click script to run Neo4j, a self-hosted Supabase stack, and a monitoring suite (Prometheus + Grafana). It also includes Pydantic models for configuring ensembles of open source AI models.

## Quick Start
1. Ensure Docker is installed.
2. Run `./install.sh`.
3. See [docs/PROCEDURE.md](docs/PROCEDURE.md) for service URLs and details.

## AI Ensemble
`app/models.py` defines Pydantic classes to describe open source models and weighted ensembles. Adjust the configuration to combine multiple models.
