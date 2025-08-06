#!/bin/bash

# ==============================================================================
# 18_ai_llm_rag_infra_setup.sh
# Summary: Sets up the core infrastructure for AI/LLM/RAG components,
#          focusing on Docker-based deployments for flexibility.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# IMPORTANT: Most AI/LLM tools are best deployed via Docker Compose.
#            This script provides the underlying platforms.
# ==============================================================================

# --- Global Variables ---
USERNAME="cbwinslow" # <--- IMPORTANT: CHANGE THIS TO YOUR DESIRED USERNAME
AI_APP_DIR="/opt/ai-apps" # Directory for AI application Docker Compose files

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 18_ai_llm_rag_infra_setup.sh: AI/LLM/RAG Infrastructure Setup."

# Ensure Docker is installed (prerequisite)
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please run 12_docker_setup.sh first."
fi

# Ensure Python3 and venv are installed for Python-based AI tools
log_info "Ensuring Python3 and python3-venv are installed..."
if ! command -v python3 &> /dev/null || ! dpkg -s python3-venv &> /dev/null; then
    apt install -y python3 python3-venv || log_error "Failed to install Python3 or python3-venv."
    log_success "Python3 and python3-venv installed."
else
    log_info "Python3 and python3-venv are already installed."
fi

# Create AI applications directory
mkdir -p "$AI_APP_DIR" || log_error "Failed to create AI applications directory."
chown -R "$USERNAME":"$USERNAME" "$AI_APP_DIR" || log_error "Failed to set ownership for AI applications directory."
chmod -R 755 "$AI_APP_DIR" || log_error "Failed to set permissions for AI applications directory."
log_success "AI applications directory '$AI_APP_DIR' created and permissions set."

# --- Vector Databases (Qdrant) ---
log_info "Setting up Qdrant (Vector Database) via Docker Compose..."
QDRANT_DIR="$AI_APP_DIR/qdrant"
mkdir -p "$QDRANT_DIR" || log_error "Failed to create Qdrant directory."
QDRANT_COMPOSE_FILE="$QDRANT_DIR/docker-compose.yml"

if [ ! -f "$QDRANT_COMPOSE_FILE" ]; then
    log_info "Creating Qdrant Docker Compose file: $QDRANT_COMPOSE_FILE"
    cat <<EOF > "$QDRANT_COMPOSE_FILE"
version: '3.8'
services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    ports:
      - "6333:6333" # REST API
      - "6334:6334" # gRPC API
    volumes:
      - ./qdrant_data:/qdrant/data
    environment:
      - QDRANT__SERVICE__GRPC_PORT=6334
      - QDRANT__SERVICE__HTTP_PORT=6333
    networks:
      - ai_backend_network

  qdrant-dashboard:
    image: qdrant/qdrant-dashboard:latest
    container_name: qdrant-dashboard
    restart: unless-stopped
    ports:
      - "8080:80" # Dashboard UI
    environment:
      - QDRANT_HOST=qdrant # Connects to the qdrant service within the Docker network
      - QDRANT_PORT=6333
    networks:
      - ai_backend_network

networks:
  ai_backend_network:
    driver: bridge
EOF
    log_success "Qdrant Docker Compose file created."
    log_warn "To start Qdrant and its dashboard, navigate to '$QDRANT_DIR' and run: 'docker compose up -d'"
    log_warn "Qdrant Dashboard will be available on port 8080 (localhost:8080). Access it via Traefik/Cloudflare if exposed."
else
    log_info "Qdrant Docker Compose file already exists. Skipping creation."
fi

# --- LLM Inference Server (LocalAI) ---
log_info "Setting up LocalAI (LLM Inference Server) via Docker Compose..."
LOCALAI_DIR="$AI_APP_DIR/localai"
mkdir -p "$LOCALAI_DIR" || log_error "Failed to create LocalAI directory."
LOCALAI_COMPOSE_FILE="$LOCALAI_DIR/docker-compose.yml"

if [ ! -f "$LOCALAI_COMPOSE_FILE" ]; then
    log_info "Creating LocalAI Docker Compose file: $LOCALAI_COMPOSE_FILE"
    cat <<EOF > "$LOCALAI_COMPOSE_FILE"
version: '3.8'
services:
  localai:
    image: quay.io/go-skynet/local-ai:latest # Or a specific version/GPU image
    container_name: localai
    restart: unless-stopped
    ports:
      - "8080:8080" # LocalAI API port
    volumes:
      - ./models:/models # Mount a local directory for models
      - ./tmp:/tmp # Temporary storage
    environment:
      - DEBUG=true # Set to false for production
      - THREADS=4 # Adjust based on your CPU cores
      # - CUDA_VISIBLE_DEVICES=all # Uncomment for GPU support if NVIDIA drivers are installed
    networks:
      - ai_backend_network

networks:
  ai_backend_network:
    external: true # Connects to the network created by Qdrant or a shared network
EOF
    log_success "LocalAI Docker Compose file created."
    log_warn "To start LocalAI, navigate to '$LOCALAI_DIR' and run: 'docker compose up -d'"
    log_warn "Download LLM models into the '$LOCALAI_DIR/models' directory. Example: 'wget https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf -O ./models/mistral-7b-instruct-v0.2.Q4_K_M.gguf'"
    log_warn "LocalAI API will be available on port 8080 (localhost:8080). Access it via Traefik/Cloudflare if exposed."
else
    log_info "LocalAI Docker Compose file already exists. Skipping creation."
fi

# --- Chatbot UI (OpenWebUI) ---
log_info "Setting up OpenWebUI (Chatbot UI) via Docker Compose..."
OPENWEBUI_DIR="$AI_APP_DIR/openwebui"
mkdir -p "$OPENWEBUI_DIR" || log_error "Failed to create OpenWebUI directory."
OPENWEBUI_COMPOSE_FILE="$OPENWEBUI_DIR/docker-compose.yml"

if [ ! -f "$OPENWEBUI_COMPOSE_FILE" ]; then
    log_info "Creating OpenWebUI Docker Compose file: $OPENWEBUI_COMPOSE_FILE"
    cat <<EOF > "$OPENWEBUI_COMPOSE_FILE"
version: '3.8'
services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    ports:
      - "8080:8080" # Default UI port
    volumes:
      - ./openwebui_data:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://host.docker.internal:11434 # If Ollama is on host
      # - OLLAMA_BASE_URL=http://localai:8080 # If LocalAI is used as Ollama replacement
    networks:
      - web # Connect to Traefik network if you want to expose it
      - ai_backend_network # Connect to backend network for LocalAI/Qdrant

networks:
  web:
    external: true # For Traefik integration
  ai_backend_network:
    external: true # For LocalAI/Qdrant integration
EOF
    log_success "OpenWebUI Docker Compose file created."
    log_warn "To start OpenWebUI, navigate to '$OPENWEBUI_DIR' and run: 'docker compose up -d'"
    log_warn "OpenWebUI will be available on port 8080 (localhost:8080). Configure your OLLAMA_BASE_URL to point to your LLM inference server (LocalAI or Ollama)."
    log_warn "To expose OpenWebUI via Traefik, ensure it's on the 'web' network and add Traefik labels to its service in the compose file."
else
    log_info "OpenWebUI Docker Compose file already exists. Skipping creation."
fi

# --- Guidance for other AI/LLM/RAG Tools ---
log_info "Guidance for other AI/LLM/RAG Tools:"
log_info "Most of the other AI/LLM/RAG tools you mentioned (e.g., adk-python, agent-cli, anythingLLM, Archon, OpenHands dev server, botpress, continue, crawlee, deep-research-agent, fullstack-chat-server, gpt4all, haystack, hakrawler, graphrag, khoj, kilocode, llama_index, litellm, localagi, localrecall, metagpt, agent-zero, langchains, landgraph) are typically deployed as:"
log_info "  - Python applications within isolated virtual environments (using 'python3 -m venv')."
log_info "  - Docker containers, often with their own Dockerfiles and Docker Compose configurations."
log_info "It is highly recommended to use Docker Compose for these, placing each application's compose file in a dedicated subdirectory under '$AI_APP_DIR'."
log_info "This script has set up the foundational Docker environment, Python, and core vector/LLM inference databases."

log_success "18_ai_llm_rag_infra_setup.sh completed."
