#!/usr/bin/env bash
set -e

echo "Starting Neo4j, Supabase, and monitoring stack..."
docker compose up -d

echo "Services are starting. Check docker logs for progress."
