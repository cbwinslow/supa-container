#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
APP_ROOT="/opt/supabase-super-stack"
WEB_ROOT="/var/www/html/super-stack"
DOMAIN="your-domain.com" # IMPORTANT: Change this to your actual domain
LETSENCRYPT_EMAIL="your-email@your-domain.com" # IMPORTANT: Change this to your email for Let's Encrypt

# --- Check for Root Privileges ---
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

echo "==================================================================="
echo " Deploying Production-Ready Supabase Super Stack"
echo "==================================================================="
echo "Domain: $DOMAIN"
echo "Web App Root: $WEB_ROOT"
echo "Service Config Root: $APP_ROOT"
echo "==================================================================="

# --- Section 1: Create Directories and Set Permissions ---
echo "--> [1/5] Creating installation directories..."
mkdir -p "$WEB_ROOT"
mkdir -p "$APP_ROOT"/{traefik,kong/declarative,fastapi_app,nextjs_app,prometheus,grafana/provisioning/{datasources,dashboards},loki,promtail,opensearch/config,opensearch-dashboards/config,rabbitmq,supabase}
# Create the acme.json for Let's Encrypt and set permissions
touch "$APP_ROOT/traefik/acme.json"
chmod 600 "$APP_ROOT/traefik/acme.json"
chown -R www-data:www-data "$WEB_ROOT"
echo "Directories created."

# --- Section 2: Create Production .env File ---
echo "--> [2/5] Creating secure .env file..."
cat <<EOF > "$APP_ROOT/.env"
# --- Production Environment Variables ---
# Replace placeholder passwords with your own secure, generated values.
DOMAIN=$DOMAIN
# Supabase
SUPABASE_DB_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
SUPABASE_JWT_SECRET=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 64)
# Neo4j
NEO4J_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
# Kong
KONG_DB_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
# Grafana
GRAFANA_ADMIN_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
# RabbitMQ
RABBITMQ_DEFAULT_USER=user
RABBITMQ_DEFAULT_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
# OpenSearch
OPENSEARCH_INITIAL_ADMIN_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
# FastAPI
JWT_SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 64)
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
EOF
echo ".env file created in $APP_ROOT/.env. REVIEW AND SAVE THESE PASSWORDS."

# --- Section 3: Create Hardened Docker Compose ---
echo "--> [3/5] Creating production docker-compose.yml..."
cat <<EOF > "$APP_ROOT/docker-compose.yml"
version: '3.8'

networks:
  devops-net:
    driver: bridge

volumes:
  supabase_data:
  qdrant_data:
  weaviate_data:
  neo4j_data:
  localai_models:
  prometheus_data:
  grafana_data:
  loki_data:
  opensearch_data:
  kong_db_data:

services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.myresolver.acme.tlschallenge=true
      - --certificatesresolvers.myresolver.acme.email=$LETSENCRYPT_EMAIL
      - --certificatesresolvers.myresolver.acme.storage=/etc/traefik/acme.json
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - $APP_ROOT/traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - $APP_ROOT/traefik/acme.json:/etc/traefik/acme.json
    networks: [devops-net]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik-dashboard.rule=Host(\`traefik.\
$DOMAIN\
`)"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
      - "traefik.http.routers.traefik-dashboard.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=admin:\
$(echo 
${TRAEFIK_ADMIN_PASSWORD} 
| htpasswd -n -i admin)"

  nextjs_app:
    build:
      context: $WEB_ROOT
      dockerfile: Dockerfile
    container_name: nextjs_app
    networks: [devops-net]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nextjs.rule=Host(
`$DOMAIN`
) || Host(
`www.
$DOMAIN`
)"
      - "traefik.http.routers.nextjs.entrypoints=websecure"
      - "traefik.http.routers.nextjs.tls.certresolver=myresolver"
      - "traefik.http.services.nextjs.loadbalancer.server.port=3000"

  fastapi_app:
    build:
      context: $APP_ROOT/fastapi_app
    container_name: fastapi_app
    networks: [devops-net]
    environment:
      - SUPABASE_URL=http://supabase:54321
      - SUPABASE_ANON_KEY=
${SUPABASE_ANON_KEY}
      - JWT_SECRET_KEY=
${JWT_SECRET_KEY}
      - QDRANT_URL=http://qdrant:6333
      - LOCALAI_URL=http://localai:8080
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.fastapi.rule=Host(
`api.
$DOMAIN`
)"
      - "traefik.http.routers.fastapi.entrypoints=websecure"
      - "traefik.http.routers.fastapi.tls.certresolver=myresolver"
      - "traefik.http.services.fastapi.loadbalancer.server.port=8000"

  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    volumes: [qdrant_data:/qdrant/storage]
    networks: [devops-net]

  localai:
    image: quay.io/go-skynet/local-ai:latest
    container_name: localai
    volumes: [localai_models:/models]
    command: ["/usr/bin/local-ai", "--models-path", "/models"]
    networks: [devops-net]

  # Add other services (Supabase, OpenSearch, etc.) here as needed,
  # ensuring they are NOT exposed to the internet via ports.
  # Example for a non-exposed database:
  opensearch:
    image: opensearchproject/opensearch:2.12.0
    container_name: opensearch
    environment:
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
      - OPENSEARCH_INITIAL_ADMIN_PASSWORD=
${OPENSEARCH_INITIAL_ADMIN_PASSWORD}
    volumes: [opensearch_data:/usr/share/opensearch/data]
    networks: [devops-net]
    # NO PORTS - Not exposed to the web

EOF
echo "docker-compose.yml created."

# --- Section 4: Create Application Code ---
echo "--> [4/5] Creating application code (Next.js & FastAPI)..."
# FastAPI App with RAG logic
cat <<EOF > "$APP_ROOT/fastapi_app/Dockerfile"
FROM python:3.10-slim-buster
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
cat <<EOF > "$APP_ROOT/fastapi_app/requirements.txt"
fastapi
uvicorn
python-dotenv
httpx
qdrant-client
pypdf
langchain
EOF
cat <<EOF > "$APP_ROOT/fastapi_app/main.py"
import os
import httpx
from fastapi import FastAPI, UploadFile, File, HTTPException
from qdrant_client import QdrantClient, models
from langchain.text_splitter import RecursiveCharacterTextSplitter
from pypdf import PdfReader
import io

# --- Initialize Clients ---
app = FastAPI(title="RAG API")
qdrant_client = QdrantClient(url=os.getenv("QDRANT_URL", "http://qdrant:6333"))
text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
COLLECTION_NAME = "political_docs"

# Ensure collection exists
qdrant_client.recreate_collection(
    collection_name=COLLECTION_NAME,
    vectors_config=models.VectorParams(size=768, distance=models.Distance.COSINE), # size depends on embedding model
)

def get_embedding(text):
    """Get embedding for text from LocalAI."""
    try:
        response = httpx.post(f"{os.getenv('LOCALAI_URL')}/v1/embeddings", json={"input": text, "model": "text-embedding-ada-002"}, timeout=60)
        response.raise_for_status()
        embedding = response.json()["data"][0]["embedding"]
        return embedding
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get embedding: {e}")

@app.post("/ingest")
async def ingest_document(file: UploadFile = File(...)):
    """Ingests a PDF document, chunks it, and stores embeddings in Qdrant."""
    if file.content_type != "application/pdf":
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")
    
    file_content = await file.read()
    pdf_reader = PdfReader(io.BytesIO(file_content))
    full_text = "".join(page.extract_text() for page in pdf_reader.pages)
    chunks = text_splitter.split_text(full_text)
    
    points = []
    for i, chunk in enumerate(chunks):
        embedding = get_embedding(chunk)
        point = models.PointStruct(
            id=f"{file.filename}-{i}",
            vector=embedding,
            payload={"text": chunk, "filename": file.filename}
        )
        points.append(point)
        
    qdrant_client.upsert(collection_name=COLLECTION_NAME, points=points, wait=True)
    return {"status": "success", "message": f"Ingested {len(chunks)} chunks from {file.filename}."}

@app.get("/query")
async def query_rag(q: str):
    """Queries the RAG system."""
    query_embedding = get_embedding(q)
    
    search_result = qdrant_client.search(
        collection_name=COLLECTION_NAME,
        query_vector=query_embedding,
        limit=3
    )
    
    context = " ".join([hit.payload['text'] for hit in search_result])
    prompt = f"Context: {context}\n\nQuestion: {q}\n\nAnswer:"
    
    try:
        response = httpx.post(f"{os.getenv('LOCALAI_URL')}/v1/completions", json={"model": "gpt-3.5-turbo", "prompt": prompt, "temperature": 0.7}, timeout=120)
        response.raise_for_status()
        answer = response.json()["choices"][0]["text"]
        return {"answer": answer, "context_used": search_result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate answer: {e}")
EOF

# Next.js App
# (Assuming a simple placeholder, as the focus is backend)
cat <<EOF > "$WEB_ROOT/Dockerfile"
FROM oven/bun:1.0-alpine
WORKDIR /app
COPY package.json .
RUN bun install
COPY . .
CMD ["bun", "run", "dev", "--host", "0.0.0.0"]
EOF
cat <<EOF > "$WEB_ROOT/package.json"
{ "name": "rag-frontend", "scripts": { "dev": "next dev" }, "dependencies": { "next": "latest", "react": "latest", "react-dom": "latest" } }
EOF
mkdir -p "$WEB_ROOT/pages"
cat <<EOF > "$WEB_ROOT/pages/index.js"
export default function Home() { return <h1>RAG Application Frontend</h1>; }
EOF
chown -R www-data:www-data "$WEB_ROOT"
echo "Application code created."

# --- Section 5: Create Firewall and Git Scripts ---
echo "--> [5/5] Creating helper scripts..."
# Firewall Script
cat <<EOF > "/usr/local/bin/setup_firewall.sh"
#!/bin/bash
echo "Configuring firewall (ufw)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable
echo "Firewall enabled. Only SSH, HTTP, and HTTPS are allowed."
EOF
chmod +x "/usr/local/bin/setup_firewall.sh"

# Git Setup Script
cat <<EOF > "$APP_ROOT/setup_git.sh"
#!/bin/bash
echo "Initializing Git repository..."
git init
cat <<EOG > .gitignore
# Environments
.env
.env*.local
# Docker
acme.json
# Python
__pycache__/
*.pyc
# Node
node_modules/
.next/
EOG
git add .
git commit -m "Initial commit: Production-ready RAG stack"
echo "Git repository initialized."
echo "Next steps:"
echo "1. Create a new repository on GitHub or GitLab."
echo "2. Run: git remote add origin <your-repo-url>"
echo "3. Run: git push -u origin main"
EOF
chmod +x "$APP_ROOT/setup_git.sh"
echo "Helper scripts created."

echo "==================================================================="
echo " Deployment Script Finished"
echo "==================================================================="
echo "CRITICAL NEXT STEPS:"
echo "1. Review and UPDATE the domain and email in this script if you haven't."
echo "2. Review and SAVE the generated passwords in: $APP_ROOT/.env"
echo "3. Run the firewall setup script ONCE: /usr/local/bin/setup_firewall.sh"
echo "4. Navigate to the app root: cd $APP_ROOT"
echo "5. Run the Git setup script: ./setup_git.sh"
echo "6. Start the services: docker-compose up -d"
echo "==================================================================="
