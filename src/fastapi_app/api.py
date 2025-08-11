"""FastAPI endpoints for the agentic RAG system."""

import asyncio
import json
import logging
from contextlib import asynccontextmanager
from typing import Dict, Any, List, Optional, AsyncGenerator
from datetime import datetime
import uuid


from fastapi import FastAPI, HTTPException, Request, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import uvicorn



from fastapi_app.agent import rag_agent, AgentDependencies
from fastapi_app.db_utils import (
    initialize_database,
    close_database,
    create_session,
    get_session,
    add_message,
    get_session_messages,
    test_connection,

)
from fastapi_app.graph_utils import initialize_graph, close_graph, test_graph_connection
from fastapi_app.models import (
    ChatRequest,
    ChatResponse,
    SearchRequest,
    SearchResponse,
    DocumentListRequest,
    DocumentListResponse,
    StreamDelta,
    ErrorResponse,
    HealthStatus,
    ToolCall,
    Session,
)
from fastapi_app.tools import (
    vector_search_tool,
    graph_search_tool,
    hybrid_search_tool,
    list_documents_tool,
    VectorSearchInput,
    GraphSearchInput,
    HybridSearchInput,
    DocumentListInput,
)

from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

# --- OpenTelemetry Instrumentation ---
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.asyncpg import AsyncPGInstrumentor

# Setup OpenTelemetry
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

# Configure the OTLP exporter to send traces to the collector
otlp_exporter = OTLPSpanExporter(endpoint="otel-collector:4317", insecure=True)
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(otlp_exporter))

# Instrument libraries
AsyncPGInstrumentor().instrument()
HTTPXClientInstrumentor().instrument()

# --- Langfuse Instrumentation ---
from langfuse import Langfuse


langfuse = Langfuse()
# --- End Langfuse ---

# --- End OpenTelemetry ---

logger = logging.getLogger(__name__)
limiter = Limiter(key_func=get_remote_address)
security = HTTPBearer()


async def auth_dependency(
    credentials: HTTPAuthorizationCredentials = Depends(security),
):
    """Simple bearer token authentication dependency."""
    token = credentials.credentials
    if not await verify_auth_token(token):
        raise HTTPException(status_code=401, detail="Invalid or missing authentication")
    return token


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Lifespan context manager for FastAPI app."""
    # Startup
    logger.info("Starting up agentic RAG API...")

    try:
        # Initialize database connections
        await initialize_database()
        logger.info("Database initialized")

        # Initialize graph database
        await initialize_graph()
        logger.info("Graph database initialized")

        # Test connections
        db_ok = await test_connection()
        graph_ok = await test_graph_connection()

        if not db_ok:
            logger.error("Database connection failed")
        if not graph_ok:
            logger.error("Graph database connection failed")

        logger.info("Agentic RAG API startup complete")

    except Exception as e:
        logger.error(f"Startup failed: {e}")
        raise

    yield

    # Shutdown
    logger.info("Shutting down agentic RAG API...")

    try:
        await close_database()
        await close_graph()
        logger.info("Connections closed")
    except Exception as e:
        logger.error(f"Shutdown error: {e}")


# Create FastAPI app
app = FastAPI(
    title="Agentic RAG with Knowledge Graph",
    description="AI agent combining vector search and knowledge graph for tech company analysis",
    version="0.1.0",
    lifespan=lifespan,
)

# Attach rate limiter
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)

# Instrument FastAPI app after creation
FastAPIInstrumentor.instrument_app(app)

# Add middleware with flexible CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(GZipMiddleware, minimum_size=1000)


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    """
    Return a 429 JSONResponse when a rate limit is exceeded.
    
    Logs a warning (including the rate-limit key) and returns a JSON body with keys:
    - error: short message,
    - error_type: "RateLimitExceeded",
    - request_id: a new UUID for tracing.
    
    Parameters:
        request: FastAPI Request object for the current request (used to compute the rate-limit key).
        exc: The RateLimitExceeded exception instance (not inspected by this handler).
    
    Returns:
        JSONResponse with status code 429 and the JSON body described above.
    """
    logger.warning(f"Rate limit exceeded: {rate_limit_key(request)}")
    return JSONResponse(
        status_code=429,
        content={
            "error": "Rate limit exceeded",
            "error_type": "RateLimitExceeded",
            "request_id": str(uuid.uuid4()),
        },
    )


# Helper functions for agent execution
async def get_or_create_session(request: ChatRequest) -> str:
    """
    Retrieve an existing session ID from the provided ChatRequest or create a new session.
    
    If request.session_id is present and corresponds to an existing session, that ID is returned.
    Otherwise a new session is created using request.user_id and request.metadata and the new session_id is returned.
    
    Parameters:
        request (ChatRequest): Incoming chat request; uses `session_id` to look up an existing session,
            and `user_id`/`metadata` when creating a new session.
    
    Returns:
        str: The existing or newly created session ID.
    """
    if request.session_id:
        session = await get_session(request.session_id)
        if session:
            return request.session_id

    # Create new session
    return await create_session(user_id=request.user_id, metadata=request.metadata)


async def get_conversation_context(
    session_id: str, max_messages: int = 10
) -> List[Dict[str, str]]:
    """
    Get recent conversation context.

    Args:
        session_id: Session ID
        max_messages: Maximum number of messages to retrieve

    Returns:
        List of messages
    """
    messages = await get_session_messages(session_id, limit=max_messages)

    return [{"role": msg["role"], "content": msg["content"]} for msg in messages]


# Authentication dependency
async def auth_dependency(authorization: Optional[str] = Header(None)) -> str:
    """Simple bearer token authentication."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or missing token")
    token = authorization[7:]  # Extract everything after 'Bearer ' (case-insensitive)
    if not await verify_token(token.strip()):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    return token.strip()


def extract_tool_calls(result: Any) -> List[ToolCall]:
    """
    Extract tool calls from a Pydantic AI result.

    Args:
        result: Result object returned from the agent

    Returns:
        List of ``ToolCall`` objects parsed from the result
    """
    tools_used = []

    try:
        # Get all messages from the result
        messages = result.all_messages()

        for message in messages:
            if hasattr(message, "parts"):
                for part in message.parts:
                    # Check if this is a tool call part
                    if part.__class__.__name__ == "ToolCallPart":
                        try:
                            # Debug logging to understand structure
                            logger.debug(f"ToolCallPart attributes: {dir(part)}")
                            logger.debug(
                                f"ToolCallPart content: tool_name={getattr(part, 'tool_name', None)}"
                            )

                            # Extract tool information safely
                            tool_name = (
                                str(part.tool_name)
                                if hasattr(part, "tool_name")
                                else "unknown"
                            )

                            # Get args - the args field is a JSON string in Pydantic AI
                            tool_args = {}
                            if hasattr(part, "args") and part.args is not None:
                                if isinstance(part.args, str):
                                    # Args is a JSON string, parse it
                                    try:
                                        import json

                                        tool_args = json.loads(part.args)
                                        logger.debug(
                                            f"Parsed args from JSON string: {tool_args}"
                                        )
                                    except json.JSONDecodeError as e:
                                        logger.debug(f"Failed to parse args JSON: {e}")
                                        tool_args = {}
                                elif isinstance(part.args, dict):
                                    tool_args = part.args
                                    logger.debug(f"Args already a dict: {tool_args}")

                            # Alternative: use args_as_dict method if available
                            if hasattr(part, "args_as_dict"):
                                try:
                                    tool_args = part.args_as_dict()
                                    logger.debug(
                                        f"Got args from args_as_dict(): {tool_args}"
                                    )
                                except:
                                    pass

                            # Get tool call ID
                            tool_call_id = None
                            if hasattr(part, "tool_call_id"):
                                tool_call_id = (
                                    str(part.tool_call_id)
                                    if part.tool_call_id
                                    else None
                                )

                            # Create ToolCall with explicit field mapping
                            tool_call_data = {
                                "tool_name": tool_name,
                                "args": tool_args,
                                "tool_call_id": tool_call_id,
                            }
                            logger.debug(
                                f"Creating ToolCall with data: {tool_call_data}"
                            )
                            tools_used.append(ToolCall(**tool_call_data))
                        except Exception as e:
                            logger.debug(f"Failed to parse tool call part: {e}")
                            continue
    except Exception as e:
        logger.warning(f"Failed to extract tool calls: {e}")

    return tools_used


async def save_conversation_turn(
    session_id: str,
    user_message: str,
    assistant_message: str,
    metadata: Optional[Dict[str, Any]] = None,
):
    """
    Save a conversation turn to the database.

    Args:
        session_id: Session ID
        user_message: User's message
        assistant_message: Assistant's response
        metadata: Optional metadata
    """
    # Save user message
    await add_message(
        session_id=session_id,
        role="user",
        content=user_message,
        metadata=metadata or {},
    )

    # Save assistant message
    await add_message(
        session_id=session_id,
        role="assistant",
        content=assistant_message,
        metadata=metadata or {},
    )


async def execute_agent(
    message: str,
    session_id: str,
    user_id: Optional[str] = None,
    save_conversation: bool = True,
) -> tuple[str, List[ToolCall]]:
    """
    Execute the agent with a message.

    Args:
        message: User message
        session_id: Session ID
        user_id: Optional user ID
        save_conversation: Whether to save the conversation

    Returns:
        Tuple of (agent response, tools used)
    """
    try:
        # Create dependencies
        deps = AgentDependencies(session_id=session_id, user_id=user_id)

        # Get conversation context
        context = await get_conversation_context(session_id)

        # Build prompt with context
        full_prompt = message
        if context:
            context_str = "\n".join(
                [
                    f"{msg['role']}: {msg['content']}"
                    for msg in context[-6:]  # Last 3 turns
                ]
            )
            full_prompt = (
                f"Previous conversation:\n{context_str}\n\nCurrent question: {message}"
            )

        # Run the agent
        result = await rag_agent.run(full_prompt, deps=deps)

        response = result.data
        tools_used = extract_tool_calls(result)

        # Save conversation if requested
        if save_conversation:
            await save_conversation_turn(
                session_id=session_id,
                user_message=message,
                assistant_message=response,
                metadata={"user_id": user_id, "tool_calls": len(tools_used)},
            )

        return response, tools_used

    except Exception as e:
        logger.error(f"Agent execution failed: {e}")
        error_response = (
            f"I encountered an error while processing your request: {str(e)}"
        )

        if save_conversation:
            await save_conversation_turn(
                session_id=session_id,
                user_message=message,
                assistant_message=error_response,
                metadata={"error": str(e)},
            )

        return error_response, []


# API Endpoints
@app.get("/health", response_model=HealthStatus)
async def health_check():
    """Health check endpoint."""
    try:
        # Test database connections
        db_status = await test_connection()
        graph_status = await test_graph_connection()

        # Determine overall status
        if db_status and graph_status:
            status = "healthy"
        elif db_status or graph_status:
            status = "degraded"
        else:
            status = "unhealthy"

        return HealthStatus(
            status=status,
            database=db_status,
            graph_database=graph_status,
            llm_connection=True,  # Assume OK if we can respond
            version="0.1.0",
            timestamp=datetime.now(),
        )

    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail="Health check failed")


@app.post("/chat", response_model=ChatResponse)
async def chat(chat_request: ChatRequest):
    """Chat endpoint."""
    try:
        # Get or create session
        session_id = await get_or_create_session(chat_request)

        # Execute agent
        response, tools_used = await execute_agent(
            message=chat_request.message,
            session_id=session_id,
            user_id=chat_request.user_id,
        )

        return ChatResponse(
            message=response,
            session_id=session_id,
            tools_used=tools_used,
            metadata={"search_type": str(chat_request.search_type)},
        )

    except Exception as e:
        logger.error(f"Chat endpoint failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/chat/stream")
async def chat_stream(chat_request: ChatRequest):
    """Streaming chat endpoint using Server-Sent Events."""
    try:
        # Get or create session
        session_id = await get_or_create_session(chat_request)

        async def generate_stream() -> AsyncGenerator[str, None]:
            run = None
            try:
                yield f"data: {json.dumps({'type': 'session', 'session_id': session_id})}\n\n"

                # Create dependencies
                deps = AgentDependencies(
                    session_id=session_id, user_id=chat_request.user_id
                )

                # Get conversation context
                context = await get_conversation_context(session_id)

                # Build input with context
                full_prompt = chat_request.message
                if context:
                    context_str = "\n".join(
                        [f"{msg['role']}: {msg['content']}" for msg in context[-6:]]
                    )
                    full_prompt = (
                        f"Previous conversation:\n{context_str}\n\nCurrent question: {chat_request.message}"
                    )

                # Save user message immediately
                await add_message(
                    session_id=session_id,
                    role="user",
                    content=chat_request.message,
                    metadata={"user_id": chat_request.user_id},
                )

                full_response = ""

                # Stream using agent.iter() pattern
                async with rag_agent.iter(full_prompt, deps=deps) as run:
                    async for node in run:
                        if rag_agent.is_model_request_node(node):
                            async with node.stream(run.ctx) as request_stream:
                                async for event in request_stream:
                                    from pydantic_ai.messages import (
                                        PartStartEvent,
                                        PartDeltaEvent,
                                        TextPartDelta,
                                    )

                                    if (
                                        isinstance(event, PartStartEvent)
                                        and event.part.part_kind == "text"
                                    ):
                                        delta_content = event.part.content
                                        yield f"data: {json.dumps({'type': 'text', 'content': delta_content})}\n\n"
                                        full_response += delta_content

                                    elif (
                                        isinstance(event, PartDeltaEvent)
                                        and isinstance(event.delta, TextPartDelta)
                                    ):
                                        delta_content = event.delta.content_delta
                                        yield f"data: {json.dumps({'type': 'text', 'content': delta_content})}\n\n"
                                        full_response += delta_content

                if run is not None:
                    # Extract tools used from the final result
                    result = run.result
                    tools_used = extract_tool_calls(result)
                else:
                    tools_used = []

                # Send tools used information
                if tools_used:
                    tools_data = [
                        {
                            "tool_name": tool.tool_name,
                            "args": tool.args,
                            "tool_call_id": tool.tool_call_id,
                        }
                        for tool in tools_used
                    ]
                    yield f"data: {json.dumps({'type': 'tools', 'tools': tools_data})}\n\n"

                # Save assistant response
                await add_message(
                    session_id=session_id,
                    role="assistant",
                    content=full_response,
                    metadata={"streamed": True, "tool_calls": len(tools_used)},
                )

            except Exception as e:
                logger.error(f"Stream error: {e}")
                error_chunk = {"type": "error", "content": str(e)}
                yield f"data: {json.dumps(error_chunk)}\n\n"
            finally:
                if run is not None:
                    try:
                        await run.close()
                    except Exception as close_err:
                        logger.error(f"Error closing run: {close_err}")
                yield f"data: {json.dumps({'type': 'end'})}\n\n"

        return StreamingResponse(
            generate_stream(),
            media_type="text/plain",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "Content-Type": "text/event-stream",
            },
        )

    except Exception as e:
        logger.error(f"Streaming chat failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))



    """Vector search endpoint."""
    try:
        input_data = VectorSearchInput(query=request.query, limit=request.limit)

        start_time = datetime.now()
        results = await vector_search_tool(input_data)
        end_time = datetime.now()

        query_time = (end_time - start_time).total_seconds() * 1000

        return SearchResponse(
            results=results,
            total_results=len(results),
            search_type="vector",
            query_time_ms=query_time,
        )

    except Exception as e:
        logger.error(f"Vector search failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

    """Knowledge graph search endpoint."""
    try:
        input_data = GraphSearchInput(query=request.query)

        start_time = datetime.now()
        results = await graph_search_tool(input_data)
        end_time = datetime.now()

        query_time = (end_time - start_time).total_seconds() * 1000

        return SearchResponse(
            graph_results=results,
            total_results=len(results),
            search_type="graph",
            query_time_ms=query_time,
        )

    except Exception as e:
        logger.error(f"Graph search failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))



    """Hybrid search endpoint."""
    try:
        input_data = HybridSearchInput(query=request.query, limit=request.limit)

        start_time = datetime.now()
        results = await hybrid_search_tool(input_data)
        end_time = datetime.now()

        query_time = (end_time - start_time).total_seconds() * 1000

        return SearchResponse(
            results=results,
            total_results=len(results),
            search_type="hybrid",
            query_time_ms=query_time,
        )

    except Exception as e:
        logger.error(f"Hybrid search failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/documents", response_model=DocumentListResponse)
async def list_documents_endpoint(params: DocumentListRequest = Depends()):
    """List documents endpoint."""
    try:
        input_data = DocumentListInput(limit=params.limit, offset=params.offset)
        documents = await list_documents_tool(input_data)

        return DocumentListResponse(
            documents=documents,
            total=len(documents),
            limit=params.limit,
            offset=params.offset,
        )

    except Exception as e:
        logger.error(f"Document listing failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/sessions/{session_id}", response_model=Session)
async def get_session_info(session_id: str):
    """Get session information."""
    try:
        session = await get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")

        return Session(**session)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Session retrieval failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# Exception handlers
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler."""
    logger.error(f"Unhandled exception: {exc}")
    request_id = str(uuid.uuid4())
    details = getattr(exc, "detail", None)
    if details is not None and not isinstance(details, dict):
        details = {"detail": details}

    error_response = ErrorResponse(
        error=str(exc),
        error_type=type(exc).__name__,
        details=details,
        request_id=request_id,
    )

    return JSONResponse(status_code=500, content=error_response.model_dump())


# Development server
if __name__ == "__main__":
    uvicorn.run(
        "agent.api:app",
        host=APP_HOST,
        port=APP_PORT,
        reload=APP_ENV == "development",
        log_level=LOG_LEVEL.lower(),
    )
