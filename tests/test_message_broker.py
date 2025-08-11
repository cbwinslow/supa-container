"""Tests for RabbitMQ message broker functionality."""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch
from datetime import datetime, timedelta

from message_broker import RabbitMQBroker, MessagePublisher, MessageConsumer
from message_broker.schemas import AgentMessage, AgentType, MessageType, Priority


class TestRabbitMQBroker:
    """Test the RabbitMQ broker implementation."""
    
    @pytest.fixture
    def broker(self):
        """Create a test broker instance."""
        return RabbitMQBroker(
            host="localhost",
            port=5672,
            username="test",
            password="test"
        )
    
    @pytest.fixture
    def sample_message(self):
        """Create a sample agent message."""
        return AgentMessage(
            id="test-msg-123",
            message_type=MessageType.TASK_REQUEST,
            sender_id="test-agent-1",
            sender_type=AgentType.ORCHESTRATOR,
            recipient_id="test-agent-2",
            recipient_type=AgentType.MONITORING,
            priority=Priority.NORMAL,
            payload={"task": "test_task", "data": "test_data"}
        )
    
    def test_broker_initialization(self, broker):
        """Test broker initialization."""
        assert broker.host == "localhost"
        assert broker.port == 5672
        assert broker.username == "test"
        assert broker.password == "test"
        assert not broker.is_connected
        assert broker.connection is None
    
    @patch('pika.adapters.asyncio_connection.AsyncioConnection')
    async def test_broker_connect(self, mock_connection, broker):
        """Test broker connection."""
        mock_connection.return_value = Mock()
        
        await broker.connect()
        
        mock_connection.assert_called_once()
    
    async def test_message_publishing(self, broker, sample_message):
        """Test message publishing functionality."""
        # Mock the connection and channel
        broker.is_connected = True
        broker.channel = Mock()
        
        await broker.publish_message(sample_message)
        
        # Verify that basic_publish was called
        broker.channel.basic_publish.assert_called_once()
    
    def test_priority_mapping(self, broker):
        """Test priority value mapping."""
        assert broker._get_priority_value("low") == 1
        assert broker._get_priority_value("normal") == 5
        assert broker._get_priority_value("high") == 8
        assert broker._get_priority_value("critical") == 10
        assert broker._get_priority_value("unknown") == 5  # Default


class TestMessagePublisher:
    """Test the message publisher utility."""
    
    @pytest.fixture
    def mock_broker(self):
        """Create a mock broker."""
        broker = Mock(spec=RabbitMQBroker)
        broker.publish_message = AsyncMock()
        return broker
    
    @pytest.fixture
    def publisher(self, mock_broker):
        """Create a test publisher."""
        return MessagePublisher(
            broker=mock_broker,
            sender_id="test-publisher",
            sender_type=AgentType.ORCHESTRATOR
        )
    
    async def test_send_task_request(self, publisher, mock_broker):
        """Test sending task requests."""
        correlation_id = await publisher.send_task_request(
            task_type="test_task",
            parameters={"param1": "value1"},
            recipient_id="target-agent",
            priority=Priority.HIGH
        )
        
        assert correlation_id is not None
        mock_broker.publish_message.assert_called_once()
        
        # Check the message that was sent
        sent_message = mock_broker.publish_message.call_args[0][0]
        assert sent_message.message_type == MessageType.TASK_REQUEST
        assert sent_message.sender_id == "test-publisher"
        assert sent_message.recipient_id == "target-agent"
        assert sent_message.priority == Priority.HIGH
        assert sent_message.payload["task_type"] == "test_task"
    
    async def test_send_alert(self, publisher, mock_broker):
        """Test sending alert messages."""
        await publisher.send_alert(
            alert_type="system_error",
            message="Test alert message",
            severity="critical",
            metadata={"source": "test"}
        )
        
        mock_broker.publish_message.assert_called_once()
        
        sent_message = mock_broker.publish_message.call_args[0][0]
        assert sent_message.message_type == MessageType.ALERT
        assert sent_message.priority == Priority.HIGH  # Critical severity should be high priority
        assert sent_message.payload["alert_type"] == "system_error"
        assert sent_message.payload["severity"] == "critical"
    
    async def test_send_log_data(self, publisher, mock_broker):
        """Test sending log data."""
        await publisher.send_log_data(
            level="ERROR",
            message="Test error message",
            source="test_module",
            context={"user_id": "123"}
        )
        
        mock_broker.publish_message.assert_called_once()
        
        sent_message = mock_broker.publish_message.call_args[0][0]
        assert sent_message.message_type == MessageType.LOG_DATA
        assert sent_message.recipient_type == AgentType.ORCHESTRATOR
        assert sent_message.payload["level"] == "ERROR"
        assert sent_message.payload["source"] == "test_module"
    
    async def test_send_metrics_data(self, publisher, mock_broker):
        """Test sending metrics data."""
        metrics = {
            "cpu_usage": 75.5,
            "memory_usage": 60.2,
            "disk_usage": 45.8
        }
        
        await publisher.send_metrics_data(
            metrics=metrics,
            tags={"host": "test-server"}
        )
        
        mock_broker.publish_message.assert_called_once()
        
        sent_message = mock_broker.publish_message.call_args[0][0]
        assert sent_message.message_type == MessageType.METRICS_DATA
        assert sent_message.payload["metrics"] == metrics
        assert sent_message.payload["tags"]["host"] == "test-server"
    
    async def test_broadcast_message(self, publisher, mock_broker):
        """Test broadcasting messages."""
        await publisher.broadcast_message(
            message_type=MessageType.STATUS_UPDATE,
            payload={"status": "system_shutdown"},
            priority=Priority.CRITICAL
        )
        
        mock_broker.publish_message.assert_called_once()
        
        # Check that exchange parameter was passed
        call_args = mock_broker.publish_message.call_args
        assert call_args[1]["exchange"] == "broadcast"
        
        sent_message = call_args[0][0]
        assert sent_message.priority == Priority.CRITICAL
        assert sent_message.recipient_id is None  # Broadcast message


class TestMessageConsumer:
    """Test the message consumer utility."""
    
    @pytest.fixture
    def mock_broker(self):
        """Create a mock broker."""
        broker = Mock(spec=RabbitMQBroker)
        broker.setup_consumer = AsyncMock()
        return broker
    
    @pytest.fixture
    def consumer(self, mock_broker):
        """Create a test consumer."""
        return MessageConsumer(
            broker=mock_broker,
            agent_id="test-consumer",
            agent_type=AgentType.MONITORING
        )
    
    async def test_start_consuming(self, consumer, mock_broker):
        """Test starting message consumption."""
        await consumer.start_consuming()
        
        mock_broker.setup_consumer.assert_called_once_with(
            "test-consumer",
            AgentType.MONITORING,
            consumer._process_message
        )
    
    def test_register_handler(self, consumer):
        """Test registering message handlers."""
        mock_handler = Mock()
        
        consumer.register_handler(MessageType.ALERT, mock_handler)
        
        assert MessageType.ALERT in consumer.handlers
        assert consumer.handlers[MessageType.ALERT] == mock_handler
    
    async def test_process_message_sync_handler(self, consumer):
        """Test processing messages with synchronous handler."""
        # Setup
        mock_handler = Mock()
        consumer.register_handler(MessageType.STATUS_UPDATE, mock_handler)
        
        test_message = AgentMessage(
            id="test-123",
            message_type=MessageType.STATUS_UPDATE,
            sender_id="sender",
            sender_type=AgentType.MONITORING,
            payload={"status": "test"}
        )
        
        # Execute
        await consumer._process_message(test_message)
        
        # Verify
        mock_handler.assert_called_once_with(test_message)
    
    async def test_process_message_async_handler(self, consumer):
        """Test processing messages with asynchronous handler."""
        # Setup
        mock_handler = AsyncMock()
        consumer.register_handler(MessageType.TASK_REQUEST, mock_handler)
        
        test_message = AgentMessage(
            id="test-123",
            message_type=MessageType.TASK_REQUEST,
            sender_id="sender",
            sender_type=AgentType.ORCHESTRATOR,
            payload={"task": "test_task"}
        )
        
        # Execute
        await consumer._process_message(test_message)
        
        # Verify
        mock_handler.assert_called_once_with(test_message)
    
    async def test_process_unknown_message_type(self, consumer):
        """Test processing messages with no registered handler."""
        test_message = AgentMessage(
            id="test-123",
            message_type=MessageType.ALERT,  # No handler registered
            sender_id="sender",
            sender_type=AgentType.MONITORING,
            payload={"alert": "test"}
        )
        
        # Should not raise an exception
        await consumer._process_message(test_message)
    
    async def test_health_check_handler(self, consumer):
        """Test the default health check handler."""
        test_message = AgentMessage(
            id="test-123",
            message_type=MessageType.HEALTH_CHECK,
            sender_id="orchestrator",
            sender_type=AgentType.ORCHESTRATOR,
            correlation_id="health-check-123",
            reply_to="orchestrator-queue",
            payload={}
        )
        
        # Mock the publisher
        consumer.publisher.send_response = AsyncMock()
        
        # Execute
        await consumer._handle_health_check(test_message)
        
        # Verify response was sent
        consumer.publisher.send_response.assert_called_once()
        call_args = consumer.publisher.send_response.call_args[1]
        assert call_args["correlation_id"] == "health-check-123"
        assert call_args["status"] == "success"
        assert call_args["recipient_id"] == "orchestrator"
    
    async def test_send_registration(self, consumer):
        """Test sending agent registration."""
        consumer.publisher.broadcast_message = AsyncMock()
        
        await consumer.send_registration()
        
        consumer.publisher.broadcast_message.assert_called_once()
        call_args = consumer.publisher.broadcast_message.call_args[0]
        assert call_args[0] == MessageType.AGENT_REGISTRATION


class TestMessageSchemas:
    """Test message schema validation."""
    
    def test_agent_message_creation(self):
        """Test creating valid agent messages."""
        message = AgentMessage(
            id="test-123",
            message_type=MessageType.TASK_REQUEST,
            sender_id="sender-1",
            sender_type=AgentType.ORCHESTRATOR,
            payload={"test": "data"}
        )
        
        assert message.id == "test-123"
        assert message.message_type == MessageType.TASK_REQUEST
        assert message.priority == Priority.NORMAL  # Default
        assert isinstance(message.timestamp, datetime)
    
    def test_agent_message_with_expiration(self):
        """Test message with expiration time."""
        expires_at = datetime.utcnow() + timedelta(hours=1)
        
        message = AgentMessage(
            id="test-123",
            message_type=MessageType.TASK_REQUEST,
            sender_id="sender-1",
            sender_type=AgentType.ORCHESTRATOR,
            expires_at=expires_at,
            payload={}
        )
        
        assert message.expires_at == expires_at
    
    def test_message_type_enum_values(self):
        """Test message type enum values."""
        assert MessageType.TASK_REQUEST == "task_request"
        assert MessageType.TASK_RESPONSE == "task_response"
        assert MessageType.STATUS_UPDATE == "status_update"
        assert MessageType.HEALTH_CHECK == "health_check"
        assert MessageType.LOG_DATA == "log_data"
        assert MessageType.METRICS_DATA == "metrics_data"
        assert MessageType.ALERT == "alert"
        assert MessageType.AGENT_REGISTRATION == "agent_registration"
    
    def test_agent_type_enum_values(self):
        """Test agent type enum values."""
        assert AgentType.ORCHESTRATOR == "orchestrator"
        assert AgentType.SELF_HEALING == "self_healing"
        assert AgentType.MONITORING == "monitoring"
        assert AgentType.TROUBLESHOOTING == "troubleshooting"
        assert AgentType.LEARNING == "learning"
        assert AgentType.IMPROVEMENT == "improvement"
        assert AgentType.DATA_MANAGER == "data_manager"
    
    def test_priority_enum_values(self):
        """Test priority enum values."""
        assert Priority.LOW == "low"
        assert Priority.NORMAL == "normal"
        assert Priority.HIGH == "high"
        assert Priority.CRITICAL == "critical"


class TestIntegration:
    """Integration tests for the message broker system."""
    
    @pytest.fixture
    def mock_broker(self):
        """Create a mock broker for integration tests."""
        broker = Mock(spec=RabbitMQBroker)
        broker.publish_message = AsyncMock()
        broker.setup_consumer = AsyncMock()
        broker.connect = AsyncMock()
        broker.close = AsyncMock()
        return broker
    
    async def test_full_message_flow(self, mock_broker):
        """Test a complete message flow between publisher and consumer."""
        # Setup publisher
        publisher = MessagePublisher(
            broker=mock_broker,
            sender_id="test-sender",
            sender_type=AgentType.ORCHESTRATOR
        )
        
        # Setup consumer
        consumer = MessageConsumer(
            broker=mock_broker,
            agent_id="test-receiver",
            agent_type=AgentType.MONITORING
        )
        
        # Register a test handler
        received_messages = []
        
        async def test_handler(message):
            received_messages.append(message)
        
        consumer.register_handler(MessageType.TASK_REQUEST, test_handler)
        
        # Start consumer
        await consumer.start_consuming()
        
        # Send a message
        await publisher.send_task_request(
            task_type="monitor_system",
            parameters={"interval": 60},
            recipient_id="test-receiver"
        )
        
        # Verify broker interactions
        mock_broker.setup_consumer.assert_called_once()
        mock_broker.publish_message.assert_called_once()
        
        # Simulate message processing
        sent_message = mock_broker.publish_message.call_args[0][0]
        await consumer._process_message(sent_message)
        
        # Verify message was processed
        assert len(received_messages) == 1
        assert received_messages[0].payload["task_type"] == "monitor_system"