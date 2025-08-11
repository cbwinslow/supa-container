"""RabbitMQ broker implementation for agent communication."""

import asyncio
import json
import logging
from typing import Callable, Dict, Optional
import pika
from pika.adapters.asyncio_connection import AsyncioConnection
from pika.exchange_type import ExchangeType

from .schemas import AgentMessage, AgentType, MessageType

logger = logging.getLogger(__name__)


class RabbitMQBroker:
    """RabbitMQ message broker for agent communication."""
    
    def __init__(
        self,
        host: str = "localhost",
        port: int = 5672,
        username: str = "guest",
        password: str = "guest",
        virtual_host: str = "/",
    ):
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.virtual_host = virtual_host
        
        self.connection: Optional[AsyncioConnection] = None
        self.channel = None
        self.message_handlers: Dict[str, Callable] = {}
        self.is_connected = False
        
        # Exchange names
        self.agent_exchange = "agents"
        self.broadcast_exchange = "broadcast"
        self.direct_exchange = "direct"
        
    async def connect(self):
        """Establish connection to RabbitMQ."""
        try:
            credentials = pika.PlainCredentials(self.username, self.password)
            parameters = pika.ConnectionParameters(
                host=self.host,
                port=self.port,
                virtual_host=self.virtual_host,
                credentials=credentials,
                heartbeat=600,
                connection_attempts=5,
                retry_delay=5
            )
            
            self.connection = AsyncioConnection(
                parameters,
                on_open_callback=self._on_connection_open,
                on_open_error_callback=self._on_connection_open_error,
                on_close_callback=self._on_connection_closed
            )
            
            logger.info(f"Connecting to RabbitMQ at {self.host}:{self.port}")
            
        except Exception as e:
            logger.error(f"Failed to connect to RabbitMQ: {e}")
            raise
    
    def _on_connection_open(self, connection):
        """Called when connection is opened."""
        logger.info("RabbitMQ connection opened")
        connection.channel(on_open_callback=self._on_channel_open)
    
    def _on_connection_open_error(self, connection, error):
        """Called when connection fails to open."""
        logger.error(f"RabbitMQ connection failed: {error}")
        self.is_connected = False
    
    def _on_connection_closed(self, connection, reason):
        """Called when connection is closed."""
        logger.warning(f"RabbitMQ connection closed: {reason}")
        self.is_connected = False
    
    def _on_channel_open(self, channel):
        """Called when channel is opened."""
        logger.info("RabbitMQ channel opened")
        self.channel = channel
        self.channel.add_on_close_callback(self._on_channel_closed)
        self._setup_exchanges()
    
    def _on_channel_closed(self, channel, reason):
        """Called when channel is closed."""
        logger.warning(f"RabbitMQ channel closed: {reason}")
        self.connection.close()
    
    def _setup_exchanges(self):
        """Setup exchanges for different message types."""
        exchanges = [
            (self.agent_exchange, ExchangeType.topic),
            (self.broadcast_exchange, ExchangeType.fanout),
            (self.direct_exchange, ExchangeType.direct),
        ]
        
        for exchange_name, exchange_type in exchanges:
            self.channel.exchange_declare(
                exchange=exchange_name,
                exchange_type=exchange_type,
                durable=True,
                callback=self._on_exchange_declared
            )
    
    def _on_exchange_declared(self, method_frame):
        """Called when exchange is declared."""
        logger.info(f"Exchange declared: {method_frame.method.exchange}")
        self.is_connected = True
    
    async def publish_message(
        self,
        message: AgentMessage,
        routing_key: str = "",
        exchange: str = None
    ):
        """Publish a message to RabbitMQ."""
        if not self.is_connected:
            await self.connect()
            
        if exchange is None:
            # Default exchange selection based on message type
            if message.recipient_id:
                exchange = self.direct_exchange
                routing_key = f"agent.{message.recipient_id}"
            elif message.recipient_type:
                exchange = self.agent_exchange
                routing_key = f"agent.{message.recipient_type.value}"
            else:
                exchange = self.broadcast_exchange
                routing_key = ""
        
        try:
            message_body = message.model_dump_json()
            
            properties = pika.BasicProperties(
                content_type="application/json",
                delivery_mode=2,  # Make message persistent
                priority=self._get_priority_value(message.priority),
                correlation_id=message.correlation_id,
                reply_to=message.reply_to,
                expiration=str(int((message.expires_at.timestamp() - message.timestamp.timestamp()) * 1000)) if message.expires_at else None
            )
            
            self.channel.basic_publish(
                exchange=exchange,
                routing_key=routing_key,
                body=message_body.encode(),
                properties=properties
            )
            
            logger.debug(f"Published message {message.id} to {exchange}/{routing_key}")
            
        except Exception as e:
            logger.error(f"Failed to publish message: {e}")
            raise
    
    async def setup_consumer(
        self,
        agent_id: str,
        agent_type: AgentType,
        message_handler: Callable
    ):
        """Setup message consumer for an agent."""
        if not self.is_connected:
            await self.connect()
        
        # Create unique queue for the agent
        queue_name = f"agent.{agent_id}"
        
        self.channel.queue_declare(
            queue=queue_name,
            durable=True,
            exclusive=False,
            auto_delete=False
        )
        
        # Bind to different exchanges based on agent type
        bindings = [
            (self.broadcast_exchange, ""),  # Receive all broadcasts
            (self.direct_exchange, f"agent.{agent_id}"),  # Direct messages
            (self.agent_exchange, f"agent.{agent_type.value}"),  # Type-based messages
        ]
        
        for exchange, routing_key in bindings:
            self.channel.queue_bind(
                exchange=exchange,
                queue=queue_name,
                routing_key=routing_key
            )
        
        # Setup consumer
        self.channel.basic_qos(prefetch_count=10)
        self.channel.basic_consume(
            queue=queue_name,
            on_message_callback=lambda ch, method, properties, body: self._handle_message(
                ch, method, properties, body, message_handler
            ),
            auto_ack=False
        )
        
        self.message_handlers[agent_id] = message_handler
        logger.info(f"Setup consumer for agent {agent_id} ({agent_type.value})")
    
    def _handle_message(self, channel, method, properties, body, handler):
        """Handle incoming message."""
        try:
            message_data = json.loads(body.decode())
            message = AgentMessage(**message_data)
            
            # Process message with handler
            result = handler(message)
            
            # Acknowledge message
            channel.basic_ack(delivery_tag=method.delivery_tag)
            
            logger.debug(f"Processed message {message.id}")
            
        except Exception as e:
            logger.error(f"Error handling message: {e}")
            # Reject and requeue message
            channel.basic_nack(
                delivery_tag=method.delivery_tag,
                requeue=True
            )
    
    def _get_priority_value(self, priority):
        """Convert priority enum to numeric value."""
        priority_map = {
            "low": 1,
            "normal": 5,
            "high": 8,
            "critical": 10
        }
        return priority_map.get(priority, 5)
    
    async def close(self):
        """Close connection to RabbitMQ."""
        if self.connection and not self.connection.is_closed:
            self.connection.close()
            logger.info("RabbitMQ connection closed")
    
    async def health_check(self) -> bool:
        """Check if broker is healthy."""
        try:
            if not self.is_connected:
                return False
            
            # Try to declare a temporary queue to test connection
            self.channel.queue_declare(
                queue="health_check_temp",
                exclusive=True,
                auto_delete=True
            )
            return True
            
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return False