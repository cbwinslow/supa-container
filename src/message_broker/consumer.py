"""Message consumer utilities."""

import asyncio
import logging
from typing import Callable, Dict, Optional

from .broker import RabbitMQBroker
from .schemas import AgentMessage, AgentType, MessageType
from .publisher import MessagePublisher

logger = logging.getLogger(__name__)


class MessageConsumer:
    """Message consumer for agent communication."""
    
    def __init__(
        self,
        broker: RabbitMQBroker,
        agent_id: str,
        agent_type: AgentType
    ):
        self.broker = broker
        self.agent_id = agent_id
        self.agent_type = agent_type
        self.publisher = MessagePublisher(broker, agent_id, agent_type)
        
        # Message handlers by type
        self.handlers: Dict[MessageType, Callable] = {}
        
        # Default handlers
        self.handlers[MessageType.HEALTH_CHECK] = self._handle_health_check
        self.handlers[MessageType.TASK_REQUEST] = self._handle_task_request
    
    async def start_consuming(self):
        """Start consuming messages."""
        await self.broker.setup_consumer(
            self.agent_id,
            self.agent_type,
            self._process_message
        )
        logger.info(f"Agent {self.agent_id} started consuming messages")
    
    def register_handler(self, message_type: MessageType, handler: Callable):
        """Register a message handler for a specific message type."""
        self.handlers[message_type] = handler
        logger.info(f"Registered handler for {message_type.value}")
    
    async def _process_message(self, message: AgentMessage):
        """Process incoming message."""
        try:
            logger.debug(f"Processing message {message.id} of type {message.message_type}")
            
            # Find appropriate handler
            handler = self.handlers.get(message.message_type)
            
            if handler:
                # Execute handler
                if asyncio.iscoroutinefunction(handler):
                    await handler(message)
                else:
                    handler(message)
            else:
                logger.warning(f"No handler registered for message type {message.message_type}")
                
        except Exception as e:
            logger.error(f"Error processing message {message.id}: {e}")
            
            # Send error response if this was a request
            if message.reply_to and message.correlation_id:
                await self.publisher.send_response(
                    correlation_id=message.correlation_id,
                    status="error",
                    error_message=str(e),
                    recipient_id=message.sender_id
                )
    
    async def _handle_health_check(self, message: AgentMessage):
        """Handle health check request."""
        try:
            # Perform health check
            health_status = await self._perform_health_check()
            
            # Send response
            if message.reply_to and message.correlation_id:
                await self.publisher.send_response(
                    correlation_id=message.correlation_id,
                    status="success",
                    result=health_status,
                    recipient_id=message.sender_id
                )
                
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            if message.reply_to and message.correlation_id:
                await self.publisher.send_response(
                    correlation_id=message.correlation_id,
                    status="error",
                    error_message=str(e),
                    recipient_id=message.sender_id
                )
    
    async def _handle_task_request(self, message: AgentMessage):
        """Handle task request - override in subclasses."""
        logger.warning(f"Task request received but no handler implemented in {self.agent_type.value} agent")
        
        if message.reply_to and message.correlation_id:
            await self.publisher.send_response(
                correlation_id=message.correlation_id,
                status="error",
                error_message="Task handling not implemented",
                recipient_id=message.sender_id
            )
    
    async def _perform_health_check(self) -> Dict:
        """Perform health check - override in subclasses."""
        return {
            "agent_id": self.agent_id,
            "agent_type": self.agent_type.value,
            "status": "healthy",
            "timestamp": logger.info("Health check performed")
        }
    
    async def send_registration(self):
        """Send agent registration message."""
        registration_message = {
            "agent_id": self.agent_id,
            "agent_type": self.agent_type.value,
            "capabilities": self._get_capabilities(),
            "status": "online"
        }
        
        await self.publisher.broadcast_message(
            MessageType.AGENT_REGISTRATION,
            registration_message
        )
        
        logger.info(f"Agent {self.agent_id} registered")
    
    def _get_capabilities(self) -> Dict:
        """Get agent capabilities - override in subclasses."""
        return {
            "message_handling": list(self.handlers.keys()),
            "health_check": True
        }