import os
import httpx
import io
from fastapi import FastAPI, UploadFile, File, HTTPException, Depends
from fastapi.security import OAuth2PasswordBearer
from qdrant_client import QdrantClient, models
from langchain.text_splitter import RecursiveCharacterTextSplitter
from pypdf import PdfReader
from jose import JWTError, jwt
from supabase import create_client, Client

# --- Environment & Configuration ---
QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
LOCALAI_URL = os.getenv("LOCALAI_URL", "http://localai:8080")
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY") # Public Anon Key
JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET") # From Supabase JWT settings

# --- Initialize Clients ---
app = FastAPI(title="Secure RAG API")
qdrant_client = QdrantClient(url=QDRANT_URL)
text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token") # Placeholder, Supabase handles tokens

COLLECTION_NAME = "political_documents_prod"

# --- Supabase JWT Authentication ---
async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=401,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        # Supabase uses a different JWT structure, we validate it here
        user_data = supabase.auth.get_user(token)
        if not user_data or not user_data.user:
            raise credentials_exception
        return user_data.user
    except Exception:
        raise credentials_exception

# --- API Endpoints ---
@app.on_event("startup")
def startup_event():
    # Ensure Qdrant collection exists
    try:
        qdrant_client.get_collection(collection_name=COLLECTION_NAME)
    except Exception:
        qdrant_client.recreate_collection(
            collection_name=COLLECTION_NAME,
            vectors_config=models.VectorParams(size=768, distance=models.Distance.COSINE), # Adjust size based on your model
        )

def get_embedding(text: str, model: str = "text-embedding-ada-002"):
    """Get embedding for text from LocalAI."""
    try:
        res = httpx.post(f"{LOCALAI_URL}/v1/embeddings", json={"input": text, "model": model}, timeout=60)
        res.raise_for_status()
        return res.json()["data"][0]["embedding"]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Embedding generation failed: {e}")

@app.post("/api/ingest", dependencies=[Depends(get_current_user)])
async def ingest_document(file: UploadFile = File(...)):
    """Ingests a PDF, chunks it, and stores embeddings in Qdrant."""
    if file.content_type != "application/pdf":
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")
    
    content = await file.read()
    pdf = PdfReader(io.BytesIO(content))
    full_text = "".join(page.extract_text() for page in pdf.pages)
    chunks = text_splitter.split_text(full_text)
    
    points = [
        models.PointStruct(
            id=f"{file.filename}-{i}",
            vector=get_embedding(chunk),
            payload={"text": chunk, "filename": file.filename}
        ) for i, chunk in enumerate(chunks)
    ]
    
    qdrant_client.upsert(collection_name=COLLECTION_NAME, points=points, wait=True)
    return {"status": "success", "message": f"Ingested {len(chunks)} chunks from {file.filename}."}

@app.post("/api/query", dependencies=[Depends(get_current_user)])
async def query_rag(query: str):
    """Queries the RAG system."""
    embedding = get_embedding(query)
    
    search_results = qdrant_client.search(
        collection_name=COLLECTION_NAME,
        query_vector=embedding,
        limit=3
    )
    
    context = " ".join([hit.payload['text'] for hit in search_results])
    prompt = f"Context: {context}\n\nQuestion: {query}\n\nAnswer:"
    
    try:
        res = httpx.post(f"{LOCALAI_URL}/v1/completions", json={"model": "gpt-3.5-turbo", "prompt": prompt}, timeout=120)
        res.raise_for_status()
        answer = res.json()["choices"][0]["text"]
        return {"answer": answer.strip(), "context": search_results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Answer generation failed: {e}")

@app.get("/api/models")
async def get_models():
    """Lists available models from LocalAI."""
    try:
        res = httpx.get(f"{LOCALAI_URL}/v1/models")
        res.raise_for_status()
        return res.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not fetch models from LocalAI: {e}")
