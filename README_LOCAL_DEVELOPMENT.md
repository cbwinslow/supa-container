# Supa Container - Local Development Guide

This guide helps you get the entire Supa Container platform running locally for development and testing.

## Quick Start

The simplest way to get everything running:

```bash
# Clone and navigate to the repository
git clone https://github.com/cbwinslow/supa-container.git
cd supa-container

# Launch all services (this will install dependencies and start everything)
./launch.sh
```

That's it! The script will:
- ✅ Check prerequisites (Docker, Docker Compose)
- ✅ Set up environment files and generate secrets
- ✅ Start all services using Docker Compose
- ✅ Wait for services to be ready
- ✅ Run comprehensive health checks
- ✅ Show service status and URLs

## Available Commands

### Basic Commands
```bash
./launch.sh start              # Start all services (default)
./launch.sh stop               # Stop all services  
./launch.sh restart            # Restart all services
./launch.sh status             # Show service status
./launch.sh logs [service]     # Show logs (optionally for specific service)
./launch.sh test               # Run comprehensive tests
./launch.sh clean              # Clean up containers and volumes
```

### Advanced Options
```bash
./launch.sh start --profile gpu-nvidia    # Use NVIDIA GPU support
./launch.sh start --profile gpu-amd       # Use AMD GPU support  
./launch.sh start --env public            # Use public environment config
./launch.sh start --no-tests              # Skip tests after startup
```

## Services and URLs

Once running, these services will be available:

| Service | URL | Description |
|---------|-----|-------------|
| **Main App** | http://localhost:3000 | Next.js frontend application |
| **API** | http://localhost:8058 | FastAPI backend API |
| **Supabase** | http://localhost:8005 | Database and auth backend |
| **n8n** | http://localhost:8001 | Workflow automation |
| **Flowise** | http://localhost:8003 | AI workflow builder |
| **Open WebUI** | http://localhost:8002 | Chat interface for AI models |
| **Neo4j** | http://localhost:8008 | Graph database browser |
| **SearXNG** | http://localhost:8006 | Privacy-focused search |
| **Langfuse** | http://localhost:8007 | LLM observability |

## Architecture Overview

The platform consists of several integrated components:

### Core Services
- **FastAPI Backend**: Agentic RAG system with knowledge graph integration
- **Next.js Frontend**: Modern web interface with chat functionality
- **Supabase**: Authentication, database, and real-time features
- **Neo4j**: Knowledge graph database for contextual AI
- **PostgreSQL**: Primary relational database
- **Redis**: Caching and session storage

### AI & ML Services  
- **Ollama**: Local LLM inference (with model variants)
- **Qdrant**: Vector database for embeddings
- **Flowise**: Visual AI workflow builder
- **Open WebUI**: Chat interface for language models
- **Langfuse**: LLM monitoring and observability

### Development & Operations
- **n8n**: Workflow automation and integration
- **SearXNG**: Privacy-focused web search
- **Caddy**: Reverse proxy and load balancer
- **ClickHouse**: Analytics database
- **MinIO**: S3-compatible object storage

## Development Workflow

### Making Changes

1. **Backend Changes** (FastAPI):
   ```bash
   # Edit files in src/fastapi_app/
   # Restart just the FastAPI service
   docker compose -p localai restart fastapi_app
   ```

2. **Frontend Changes** (Next.js):
   ```bash
   # Edit files in nextjs_app/
   # Or run in development mode for hot reload
   cd nextjs_app && npm run dev
   ```

3. **Configuration Changes**:
   ```bash
   # Edit .env file, then restart
   ./launch.sh restart
   ```

### Running Tests

```bash
# Run all tests
./launch.sh test

# Run specific test categories
python -m pytest test_comprehensive.py::TestServiceHealth -v
python -m pytest test_comprehensive.py::TestAPIEndpoints -v
python -m pytest test_comprehensive.py::TestIntegrationWorkflows -v
```

### Debugging

```bash
# Check service status
./launch.sh status

# View logs for all services
./launch.sh logs

# View logs for specific service
./launch.sh logs postgres
./launch.sh logs fastapi_app

# Check Docker containers
docker compose -p localai ps
docker compose -p localai logs -f [service_name]
```

## Troubleshooting

### Common Issues

**Services not starting:**
```bash
# Check Docker is running
docker --version
docker compose version

# Clean up and restart
./launch.sh clean
./launch.sh start
```

**Port conflicts:**
```bash
# Check what's using ports
netstat -tulpn | grep :8005
lsof -i :8005

# Stop conflicting services or change ports in .env
```

**Database connection issues:**
```bash
# Check database containers
docker compose -p localai logs postgres
docker compose -p localai logs neo4j

# Reset database volumes
./launch.sh clean
./launch.sh start
```

**SSL/Certificate issues:**
```bash
# For local development, these can usually be ignored
# Check logs for specific SSL errors
./launch.sh logs caddy
```

### Getting Help

1. Check service status: `./launch.sh status`
2. View logs: `./launch.sh logs`
3. Run tests: `./launch.sh test`
4. Clean and restart: `./launch.sh clean && ./launch.sh start`

## Configuration

### Environment Variables

The platform uses environment variables in `.env` for configuration. Key variables:

```bash
# Domain and SSL
DOMAIN=localhost
LETSENCRYPT_EMAIL=admin@localhost

# Database passwords (auto-generated)
POSTGRES_PASSWORD=<auto-generated>
MINIO_ROOT_PASSWORD=<auto-generated>

# Service secrets (auto-generated)
NEXTAUTH_SECRET=<auto-generated>
LANGFUSE_SALT=<auto-generated>
ENCRYPTION_KEY=<auto-generated>
```

### Hardware Profiles

Choose the appropriate profile based on your hardware:

- **cpu**: Standard CPU-only deployment (default)
- **gpu-nvidia**: NVIDIA GPU acceleration for AI models
- **gpu-amd**: AMD GPU acceleration for AI models

### Environment Modes

- **private**: Local development (default)
- **public**: Public-facing deployment with additional security

## Production Deployment

For production deployment, see:
- [Hetzner Deployment Guide](README_HETZNER_DEPLOYMENT.md)
- [Production Deployment Guide](README-DEPLOYMENT.md)

The local development setup is optimized for development and testing, not production use.