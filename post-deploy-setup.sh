#!/bin/bash

# -----------------------------------------------------------------------------
# Post-Deployment Setup Script for Supabase Super Stack
# -----------------------------------------------------------------------------
# This script automates the final setup steps required after the main
# deployment script has been run and the Docker containers are running.
#
# It will:
#   1. Apply the necessary SQL schema to your Supabase PostgreSQL database.
#   2. Retrieve the Supabase API keys required by the application.
#   3. Guide you on how to add these keys to your .env file.
# -----------------------------------------------------------------------------

# Exit on error, undefined variable, and pipe failures
set -euo pipefail

# --- Configuration ---
# The script assumes it is being run from the APP_ROOT directory.
APP_ROOT=$(pwd)
ENV_FILE="$APP_ROOT/.env"
SQL_SCHEMA_FILE="$APP_ROOT/../sql/schema.sql"
AUDIT_SCHEMA_FILE="$APP_ROOT/../sql/audit.sql"

echo "==================================================================="
echo " Supabase Super Stack: Post-Deployment Setup"
echo "==================================================================="
echo "This script will apply the database schema and retrieve API keys."
echo "Please ensure your Docker containers are running before proceeding."
echo "-------------------------------------------------------------------"

# --- Check for running containers ---
if ! docker-compose ps | grep -q "Up"; then
    echo "❌ ERROR: No running Docker containers found. Please run 'docker-compose up -d' first."
    exit 1
fi

# --- Step 1: Apply SQL Schema ---
echo "--> [1/3] Applying main database schema..."
if [ ! -f "$SQL_SCHEMA_FILE" ]; then
    echo "❌ ERROR: SQL schema file not found at $SQL_SCHEMA_FILE"
    exit 1
fi

# Get database connection details from .env
DB_USER=$(grep "POSTGRES_USER" "$ENV_FILE" | cut -d '=' -f2)
DB_PASSWORD=$(grep "POSTGRES_PASSWORD" "$ENV_FILE" | cut -d '=' -f2)
DB_NAME=$(grep "POSTGRES_DB" "$ENV_FILE" | cut -d '=' -f2)

# Execute the schema file inside the Supabase container
docker-compose exec -T supabase psql "postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}" < "$SQL_SCHEMA_FILE"

echo "✅ Main database schema applied successfully."
echo ""

# --- Step 2: Apply Audit Log Schema ---
echo "--> [2/3] Applying audit log schema..."
if [ ! -f "$AUDIT_SCHEMA_FILE" ]; then
    echo "❌ ERROR: Audit schema file not found at $AUDIT_SCHEMA_FILE"
    exit 1
fi
docker-compose exec -T supabase psql "postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}" < "$AUDIT_SCHEMA_FILE"
echo "✅ Audit log schema and triggers applied successfully."
echo ""

# --- Step 3: Retrieve and Display Supabase API Keys ---
echo "--> [3/3] Retrieving Supabase API Keys..."
echo "The following keys are required by your application. Please add them to your"
echo ".env file located at: $ENV_FILE"
echo ""

# Get the output of supabase status
status_output=$(docker-compose exec supabase supabase status)

# Extract the keys using grep and awk
ANON_KEY=$(echo "$status_output" | grep "anon key:" | awk '{print $3}')
SERVICE_ROLE_KEY=$(echo "$status_output" | grep "service_role key:" | awk '{print $3}')

echo "-------------------------------------------------------------------"
echo "COPY THE FOLLOWING LINES INTO YOUR .env FILE:"
echo "-------------------------------------------------------------------"
echo ""
echo "SUPABASE_ANON_KEY=${ANON_KEY}"
echo "SUPABASE_SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}"
echo ""
echo "-------------------------------------------------------------------"
echo "After adding these keys, you must restart your application for the"
echo "changes to take effect:"
echo ""
echo "  docker-compose restart nextjs_app fastapi_app"
echo ""
echo "==================================================================="
echo " Post-deployment setup complete."
echo "==================================================================="
