"""Message schemas for inter-agent communication."""

from datetime import datetime
from enum import Enum
from typing import Any, Dict, Optional
from pydantic import BaseModel, Field


class MessageType(str, Enum):
    """Types of messages that can be sent between agents."""
    TASK_REQUEST = "task_request"
    TASK_RESPONSE = "task_response"
    STATUS_UPDATE = "status_update"
    HEALTH_CHECK = "health_check"
    LOG_DATA = "log_data"
    METRICS_DATA = "metrics_data"
    ALERT = "alert"
    AGENT_REGISTRATION = "agent_registration"


class Priority(str, Enum):
    """Message priority levels."""
    LOW = "low"
    NORMAL = "normal"
    HIGH = "high"
    CRITICAL = "critical"


class AgentType(str, Enum):
    """Types of agents in the system."""
    ORCHESTRATOR = "orchestrator"
    SELF_HEALING = "self_healing"
    MONITORING = "monitoring"
    TROUBLESHOOTING = "troubleshooting"
    LEARNING = "learning"
    IMPROVEMENT = "improvement"
    FEATURE_BUILDER = "feature_builder"
    DATA_MANAGER = "data_manager"
    DEPLOYMENT = "deployment"
    TESTING = "testing"


class AgentMessage(BaseModel):
    """Base message structure for agent communication."""
    id: str = Field(..., description="Unique message ID")
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    message_type: MessageType
    sender_id: str = Field(..., description="ID of the sending agent")
    sender_type: AgentType
    recipient_id: Optional[str] = Field(None, description="Specific recipient ID, None for broadcast")
    recipient_type: Optional[AgentType] = Field(None, description="Type of recipient agent")
    priority: Priority = Priority.NORMAL
    payload: Dict[str, Any] = Field(default_factory=dict)
    correlation_id: Optional[str] = Field(None, description="For request-response tracking")
    reply_to: Optional[str] = Field(None, description="Queue to reply to")
    expires_at: Optional[datetime] = Field(None, description="Message expiration time")


class AgentTask(BaseModel):
    """Task assignment message for agents."""
    task_id: str
    task_type: str
    description: str
    parameters: Dict[str, Any] = Field(default_factory=dict)
    deadline: Optional[datetime] = None
    retry_count: int = 0
    max_retries: int = 3
    assigned_to: Optional[str] = None
    dependencies: list[str] = Field(default_factory=list)


class AgentResponse(BaseModel):
    """Response message from agents."""
    task_id: str
    status: str  # success, error, in_progress, failed
    result: Optional[Dict[str, Any]] = None
    error_message: Optional[str] = None
    execution_time: Optional[float] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)


class HealthCheckMessage(BaseModel):
    """Health check status message."""
    agent_id: str
    agent_type: AgentType
    status: str  # healthy, degraded, unhealthy
    uptime: float
    memory_usage: float
    cpu_usage: float
    last_activity: datetime
    services_status: Dict[str, str] = Field(default_factory=dict)


class LogMessage(BaseModel):
    """Log data message."""
    level: str
    message: str
    source: str
    timestamp: datetime
    context: Dict[str, Any] = Field(default_factory=dict)


class MetricsMessage(BaseModel):
    """Metrics data message."""
    metric_name: str
    value: float
    unit: str
    tags: Dict[str, str] = Field(default_factory=dict)
    timestamp: datetime