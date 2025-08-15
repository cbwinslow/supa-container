# Procedure to Run the Stack

This procedure outlines how to start the Neo4j database, the Supabase stack, and basic monitoring with Prometheus and Grafana. All components use open source images and can be orchestrated with a single command.

## Prerequisites
- [Docker](https://www.docker.com/get-started) and Docker Compose plugin
- Sufficient resources: ~4GB RAM and 10GB disk space

## Quick Start
1. Clone this repository.
2. Run `./install.sh`.
3. Access services:
   - Neo4j Browser: http://localhost:7474 (user: `neo4j`, pass: `test`)
   - Supabase REST: http://localhost:3000
   - Supabase Auth: http://localhost:9999
   - Supabase Realtime: ws://localhost:4000/socket
   - Supabase Storage: http://localhost:5000
   - Supabase Studio: http://localhost:8080
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3001

## Ensemble AI Strategy
Pydantic models in `app/models.py` describe an ensemble of open source models. Add model entries pointing to local paths or Hugging Face references and assign weights to control the ensemble strategy.

## Transparency & Monitoring
The monitoring stack provides transparency into system health. Extend `monitoring/prometheus.yml` with additional scrape targets for each service that exposes metrics.

## Notes
This setup is intended for local development. Review security settings before deploying to production.
