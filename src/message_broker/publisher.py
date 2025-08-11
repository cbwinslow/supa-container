"""Message publisher utilities."""

import uuid
from datetime import datetime, timedelta
from typing import Any, Dict, Optional

from .broker import RabbitMQBroker
from .schemas import AgentMessage, AgentType, MessageType, Priority


class MessagePublisher:
    """Utility class for publishing messages to agents."""
    
    def __init__(self, broker: RabbitMQBroker, sender_id: str, sender_type: AgentType):
        self.broker = broker
        self.sender_id = sender_id
        self.sender_type = sender_type
    
    async def send_task_request(
        self,
        task_type: str,
        parameters: Dict[str, Any],
        recipient_id: Optional[str] = None,
        recipient_type: Optional[AgentType] = None,
        priority: Priority = Priority.NORMAL,
        deadline: Optional[datetime] = None
    ) -> str:
        """Send a task request to an agent."""
        message_id = str(uuid.uuid4())
        correlation_id = str(uuid.uuid4())
        
        message = AgentMessage(
            id=message_id,
            message_type=MessageType.TASK_REQUEST,
            sender_id=self.sender_id,
            sender_type=self.sender_type,
            recipient_id=recipient_id,
            recipient_type=recipient_type,
            priority=priority,
            correlation_id=correlation_id,
            reply_to=f"agent.{self.sender_id}",
            expires_at=deadline or datetime.utcnow() + timedelta(hours=1),
            payload={
                "task_type": task_type,
                "parameters": parameters,
                "deadline": deadline.isoformat() if deadline else None
            }
        )
        
        await self.broker.publish_message(message)
        return correlation_id
    
    async def send_status_update(
        self,
        status: str,
        details: Dict[str, Any],
        recipient_id: Optional[str] = None
    ):
        """Send a status update message."""
        message = AgentMessage(
            id=str(uuid.uuid4()),
            message_type=MessageType.STATUS_UPDATE,
            sender_id=self.sender_id,
            sender_type=self.sender_type,
            recipient_id=recipient_id,
            payload={
                "status": status,
                "details": details
            }
        )
        
        await self.broker.publish_message(message)
    
    async def send_alert(
        self,
        alert_type: str,
        message: str,
        severity: str = "warning",
        metadata: Optional[Dict[str, Any]] = None
    ):
        """Send an alert message."""
        alert_message = AgentMessage(
            id=str(uuid.uuid4()),
            message_type=MessageType.ALERT,
            sender_id=self.sender_id,
            sender_type=self.sender_type,
            priority=Priority.HIGH if severity in ["error", "critical"] else Priority.NORMAL,
            payload={
                "alert_type": alert_type,
                "message": message,
                "severity": severity,
                "metadata": metadata or {}
            }
        )
        
        await self.broker.publish_message(alert_message)
    
    async def send_log_data(
        self,
        level: str,
        message: str,
        source: str,
        context: Optional[Dict[str, Any]] = None
    ):
        """Send log data to the orchestrator."""
        log_message = AgentMessage(
            id=str(uuid.uuid4()),
            message_type=MessageType.LOG_DATA,
            sender_id=self.sender_id,
            sender_type=self.sender_type,
            recipient_type=AgentType.ORCHESTRATOR,
            payload={
                "level": level,
                "message": message,
                "source": source,
                "context": context or {}
            }
        )
        
        await self.broker.publish_message(log_message)
    
    async def send_metrics_data(
        self,
        metrics: Dict[str, float],
        tags: Optional[Dict[str, str]] = None
    ):
        """Send metrics data to the orchestrator."""
        metrics_message = AgentMessage(
            id=str(uuid.uuid4()),
            message_type=MessageType.METRICS_DATA,
            sender_id=self.sender_id,
            sender_type=self.sender_type,
            recipient_type=AgentType.ORCHESTRATOR,
            payload={
                "metrics": metrics,
                "tags": tags or {}
            }
        )
        
        await self.broker.publish_message(metrics_message)
    
    async def send_response(
        self,
        correlation_id: str,
        status: str,
        result: Optional[Dict[str, Any]] = None,
        error_message: Optional[str] = None,
        recipient_id: Optional[str] = None
    ):
        """Send a response to a previous request."""
        response_message = AgentMessage(
            id=str(uuid.uuid4()),
            message_type=MessageType.TASK_RESPONSE,
            sender_id=self.sender_id,
            sender_type=self.sender_type,
            recipient_id=recipient_id,
            correlation_id=correlation_id,
            payload={
                "status": status,
                "result": result,
                "error_message": error_message
            }
        )
        
        await self.broker.publish_message(response_message)
    
    async def broadcast_message(
        self,
        message_type: MessageType,
        payload: Dict[str, Any],
        priority: Priority = Priority.NORMAL
    ):
        """Broadcast a message to all agents."""
        broadcast_message = AgentMessage(
            id=str(uuid.uuid4()),
            message_type=message_type,
            sender_id=self.sender_id,
            sender_type=self.sender_type,
            priority=priority,
            payload=payload
        )
        
        await self.broker.publish_message(broadcast_message, exchange="broadcast")