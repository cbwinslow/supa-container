#!/bin/bash

# ==============================================================================
# 12_docker_setup.sh
# Summary: Installs Docker and Docker Compose, essential for containerizing
#          most of your AI/LLM and observability tools.
# Author: Gemini
# Date: July 24, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Global Variables ---
USERNAME="cbwinslow" # <--- IMPORTANT: CHANGE THIS TO YOUR DESIRED USERNAME

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\n\e[1;33m[WARN]\e[0m $1"; }
log_success() { echo -e "\n\e[1;32m[SUCCESS]\e[0m $1"; }
log_error() { echo -e "\n\e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }

# --- Main Script Execution ---
log_info "Starting 12_docker_setup.sh: Docker & Docker Compose Installation."

# 1. Install Docker prerequisites
log_info "Installing Docker prerequisites..."
apt update -y || log_error "Failed to update package lists."
apt install -y ca-certificates curl gnupg || log_error "Failed to install Docker prerequisites."
log_success "Docker prerequisites installed."

# 2. Add Docker's official GPG key
log_info "Adding Docker's official GPG key..."
if [ ! -f "/etc/apt/keyrings/docker.gpg" ]; then
    install -m 0755 -d /etc/apt/keyrings || log_error "Failed to create /etc/apt/keyrings directory."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || log_error "Failed to add Docker GPG key."
    log_success "Docker GPG key added."
else
    log_info "Docker GPG key already exists."
fi

# 3. Add Docker repository
log_info "Adding Docker repository..."
if [ ! -f "/etc/apt/sources.list.d/docker.list" ]; then
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null || log_error "Failed to add Docker repository."
    log_success "Docker repository added."
else
    log_info "Docker repository already exists."
fi

# 4. Update apt package index
log_info "Updating apt package index with Docker repository..."
apt update -y || log_error "Failed to update apt package index."
log_success "Apt package index updated."

# 5. Install Docker Engine, CLI, Containerd, and Compose Plugin
log_info "Installing Docker Engine, CLI, Containerd, and Compose Plugin..."
if ! command -v docker &> /dev/null; then
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || log_error "Failed to install Docker components."
    log_success "Docker Engine, CLI, Containerd, and Compose Plugin installed."
else
    log_info "Docker is already installed."
fi

# 6. Add the non-root user to the docker group
log_info "Adding user '$USERNAME' to the 'docker' group..."
if ! id -nG "$USERNAME" | grep -qw "docker"; then
    usermod -aG docker "$USERNAME" || log_error "Failed to add user '$USERNAME' to 'docker' group."
    log_success "User '$USERNAME' added to 'docker' group."
    log_warn "Please log out and log back in as '$USERNAME' for the group changes to take effect and run Docker commands without sudo."
else
    log_info "User '$USERNAME' is already in the 'docker' group."
fi

# 7. Start and enable Docker service
log_info "Starting and enabling Docker service..."
systemctl start docker || log_error "Failed to start Docker service."
systemctl enable docker || log_error "Failed to enable Docker service on boot."
log_success "Docker installed and running."
log_info "Verify Docker installation by running 'sudo docker run hello-world' (or 'docker run hello-world' after re-logging in)."
log_info "Verify Docker Compose installation by running 'docker compose version'."

log_success "12_docker_setup.sh completed."
