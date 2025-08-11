"""Base agent class for all specialized agents."""

import asyncio
import logging
import uuid
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Dict, Any, Optional

from message_broker import RabbitMQBroker, MessageConsumer, MessagePublisher
from message_broker.schemas import AgentType, MessageType, AgentMessage

logger = logging.getLogger(__name__)


class BaseAgent(ABC):
    """
    Base class for all specialized AI agents.
    
    Provides common functionality for:
    - Message handling
    - Status reporting
    - Health monitoring
    - Task execution
    """
    
    def __init__(
        self,
        broker: RabbitMQBroker,
        agent_type: AgentType,
        agent_id: str = None
    ):
        self.agent_id = agent_id or f"{agent_type.value}-{uuid.uuid4().hex[:8]}"
        self.agent_type = agent_type
        self.broker = broker
        
        # Message handling
        self.consumer = MessageConsumer(broker, self.agent_id, agent_type)
        self.publisher = MessagePublisher(broker, self.agent_id, agent_type)
        
        # State tracking
        self.status = "initializing"
        self.running = False
        self.start_time = datetime.utcnow()
        self.task_count = 0
        self.error_count = 0
        
        # Setup message handlers
        self._setup_handlers()
    
    def _setup_handlers(self):
        """Setup message handlers specific to this agent."""
        self.consumer.register_handler(MessageType.TASK_REQUEST, self._handle_task_request)
    
    async def start(self):
        """Start the agent."""
        logger.info(f"Starting {self.agent_type.value} agent: {self.agent_id}")
        
        try:
            # Connect to message broker
            await self.broker.connect()
            
            # Start consuming messages
            await self.consumer.start_consuming()
            
            # Register with orchestrator
            await self.consumer.send_registration()
            
            self.status = "running"
            self.running = True
            
            # Start background tasks
            asyncio.create_task(self._health_monitor())
            asyncio.create_task(self._status_reporter())
            
            # Start agent-specific tasks
            await self._start_agent_tasks()
            
            logger.info(f"{self.agent_type.value} agent started successfully")
            
        except Exception as e:
            logger.error(f"Failed to start {self.agent_type.value} agent: {e}")
            self.status = "error"
            raise
    
    async def stop(self):
        """Stop the agent."""
        logger.info(f"Stopping {self.agent_type.value} agent: {self.agent_id}")
        
        self.running = False
        self.status = "stopping"
        
        # Cleanup resources
        await self._cleanup()
        
        # Close broker connection
        await self.broker.close()
        
        self.status = "stopped"
        logger.info(f"{self.agent_type.value} agent stopped")
    
    async def _handle_task_request(self, message: AgentMessage):
        """Handle incoming task requests."""
        try:
            task_data = message.payload
            task_type = task_data.get("task_type")
            parameters = task_data.get("parameters", {})
            
            logger.info(f"Received task: {task_type}")
            
            # Execute the task
            result = await self._execute_task(task_type, parameters)
            
            # Send response
            await self.publisher.send_response(
                correlation_id=message.correlation_id,
                status="success",
                result=result,
                recipient_id=message.sender_id
            )
            
            self.task_count += 1
            
        except Exception as e:
            logger.error(f"Task execution failed: {e}")
            self.error_count += 1
            
            # Send error response
            await self.publisher.send_response(
                correlation_id=message.correlation_id,
                status="error",
                error_message=str(e),
                recipient_id=message.sender_id
            )
    
    async def _health_monitor(self):
        """Monitor agent health."""
        while self.running:
            try:
                # Perform health check
                health_data = await self._perform_health_check()
                
                # Send health metrics to orchestrator
                await self.publisher.send_metrics_data(
                    metrics={
                        "uptime": (datetime.utcnow() - self.start_time).total_seconds(),
                        "task_count": self.task_count,
                        "error_count": self.error_count,
                        "error_rate": self.error_count / max(self.task_count, 1),
                        **health_data
                    }
                )
                
                await asyncio.sleep(60)  # Report health every minute
                
            except Exception as e:
                logger.error(f"Health monitoring error: {e}")
                await asyncio.sleep(60)
    
    async def _status_reporter(self):
        """Report status updates to orchestrator."""
        while self.running:
            try:
                await self.publisher.send_status_update(
                    status=self.status,
                    details={
                        "tasks_completed": self.task_count,
                        "errors": self.error_count,
                        "uptime": (datetime.utcnow() - self.start_time).total_seconds()
                    }
                )
                
                await asyncio.sleep(300)  # Report status every 5 minutes
                
            except Exception as e:
                logger.error(f"Status reporting error: {e}")
                await asyncio.sleep(300)
    
    @abstractmethod
    async def _execute_task(self, task_type: str, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a specific task - must be implemented by subclasses."""
        pass
    
    @abstractmethod
    async def _start_agent_tasks(self):
        """Start agent-specific background tasks - must be implemented by subclasses."""
        pass
    
    async def _perform_health_check(self) -> Dict[str, Any]:
        """Perform health check - can be overridden by subclasses."""
        return {
            "memory_usage": 0.0,  # Could implement actual memory monitoring
            "cpu_usage": 0.0,     # Could implement actual CPU monitoring
            "status": self.status
        }
    
    async def _cleanup(self):
        """Cleanup resources - can be overridden by subclasses."""
        pass
    
    def _get_capabilities(self) -> Dict[str, Any]:
        """Get agent capabilities - can be overridden by subclasses."""
        return {
            "agent_type": self.agent_type.value,
            "task_handling": True,
            "health_monitoring": True,
            "status_reporting": True
        }