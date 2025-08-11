"""Tests for AI agents functionality."""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch
from datetime import datetime

from agents import BaseAgent, SelfHealingAgent
from message_broker import RabbitMQBroker
from message_broker.schemas import AgentType, MessageType, AgentMessage


class TestBaseAgent:
    """Test the base agent functionality."""
    
    @pytest.fixture
    def mock_broker(self):
        """Create a mock broker."""
        broker = Mock(spec=RabbitMQBroker)
        broker.connect = AsyncMock()
        broker.close = AsyncMock()
        return broker
    
    @pytest.fixture
    def test_agent(self, mock_broker):
        """Create a test agent implementation."""
        class TestAgentImpl(BaseAgent):
            async def _execute_task(self, task_type, parameters):
                return {"status": "completed", "task_type": task_type}
            
            async def _start_agent_tasks(self):
                pass
        
        return TestAgentImpl(
            broker=mock_broker,
            agent_type=AgentType.MONITORING,
            agent_id="test-agent-123"
        )
    
    def test_agent_initialization(self, test_agent):
        """Test agent initialization."""
        assert test_agent.agent_id == "test-agent-123"
        assert test_agent.agent_type == AgentType.MONITORING
        assert test_agent.status == "initializing"
        assert not test_agent.running
        assert test_agent.task_count == 0
        assert test_agent.error_count == 0
        assert isinstance(test_agent.start_time, datetime)
    
    async def test_agent_start(self, test_agent, mock_broker):
        """Test agent startup process."""
        # Mock consumer methods
        test_agent.consumer.start_consuming = AsyncMock()
        test_agent.consumer.send_registration = AsyncMock()
        
        await test_agent.start()
        
        assert test_agent.status == "running"
        assert test_agent.running
        mock_broker.connect.assert_called_once()
        test_agent.consumer.start_consuming.assert_called_once()
        test_agent.consumer.send_registration.assert_called_once()
    
    async def test_agent_stop(self, test_agent, mock_broker):
        """Test agent shutdown process."""
        test_agent.running = True
        test_agent.status = "running"
        
        await test_agent.stop()
        
        assert test_agent.status == "stopped"
        assert not test_agent.running
        mock_broker.close.assert_called_once()
    
    async def test_handle_task_request_success(self, test_agent):
        """Test successful task request handling."""
        # Mock publisher
        test_agent.publisher.send_response = AsyncMock()
        
        # Create test message
        test_message = AgentMessage(
            id="msg-123",
            message_type=MessageType.TASK_REQUEST,
            sender_id="orchestrator",
            sender_type=AgentType.ORCHESTRATOR,
            correlation_id="corr-123",
            payload={
                "task_type": "test_task",
                "parameters": {"param1": "value1"}
            }
        )
        
        # Execute
        await test_agent._handle_task_request(test_message)
        
        # Verify
        assert test_agent.task_count == 1
        test_agent.publisher.send_response.assert_called_once()
        
        # Check response details
        call_args = test_agent.publisher.send_response.call_args[1]
        assert call_args["correlation_id"] == "corr-123"
        assert call_args["status"] == "success"
        assert call_args["result"]["task_type"] == "test_task"
    
    async def test_handle_task_request_error(self, test_agent):
        """Test task request handling with error."""
        # Mock publisher
        test_agent.publisher.send_response = AsyncMock()
        
        # Mock execute_task to raise an error
        async def failing_task(task_type, parameters):
            raise ValueError("Test error")
        
        test_agent._execute_task = failing_task
        
        # Create test message
        test_message = AgentMessage(
            id="msg-123",
            message_type=MessageType.TASK_REQUEST,
            sender_id="orchestrator",
            sender_type=AgentType.ORCHESTRATOR,
            correlation_id="corr-123",
            payload={"task_type": "failing_task", "parameters": {}}
        )
        
        # Execute
        await test_agent._handle_task_request(test_message)
        
        # Verify
        assert test_agent.error_count == 1
        test_agent.publisher.send_response.assert_called_once()
        
        # Check error response
        call_args = test_agent.publisher.send_response.call_args[1]
        assert call_args["status"] == "error"
        assert "Test error" in call_args["error_message"]
    
    async def test_health_check(self, test_agent):
        """Test health check functionality."""
        health_data = await test_agent._perform_health_check()
        
        assert "memory_usage" in health_data
        assert "cpu_usage" in health_data
        assert "status" in health_data
        assert health_data["status"] == "initializing"


class TestSelfHealingAgent:
    """Test the self-healing agent functionality."""
    
    @pytest.fixture
    def mock_broker(self):
        """Create a mock broker."""
        broker = Mock(spec=RabbitMQBroker)
        broker.connect = AsyncMock()
        broker.close = AsyncMock()
        return broker
    
    @pytest.fixture
    def healing_agent(self, mock_broker):
        """Create a self-healing agent."""
        return SelfHealingAgent(broker=mock_broker, agent_id="healer-1")
    
    def test_healing_agent_initialization(self, healing_agent):
        """Test self-healing agent initialization."""
        assert healing_agent.agent_type == AgentType.SELF_HEALING
        assert "healer-1" in healing_agent.agent_id
        assert "service_restart" in healing_agent.healing_rules
        assert "disk_cleanup" in healing_agent.healing_rules
        assert "memory_optimization" in healing_agent.healing_rules
    
    async def test_check_service_health_task(self, healing_agent):
        """Test service health check task."""
        # Mock the service checking methods
        healing_agent._check_docker_services = AsyncMock(return_value={
            "fastapi_app": {"status": "running", "healthy": True},
            "nextjs_app": {"status": "running", "healthy": True}
        })
        
        result = await healing_agent._execute_task(
            "check_service_health",
            {"service": "all"}
        )
        
        assert "fastapi_app" in result
        assert "nextjs_app" in result
        assert result["fastapi_app"]["status"] == "running"
    
    @patch('subprocess.run')
    async def test_restart_service_task(self, mock_subprocess, healing_agent):
        """Test service restart task."""
        # Mock successful subprocess call
        mock_subprocess.return_value.returncode = 0
        
        # Mock service status check
        healing_agent._check_single_service = AsyncMock(return_value={
            "status": "running",
            "healthy": True
        })
        
        result = await healing_agent._execute_task(
            "restart_service",
            {"service": "fastapi_app"}
        )
        
        assert result["action"] == "service_restart"
        assert result["service"] == "fastapi_app"
        assert result["success"] is True
        
        # Verify subprocess was called correctly
        mock_subprocess.assert_called_once()
        call_args = mock_subprocess.call_args[0][0]
        assert "docker-compose" in call_args
        assert "restart" in call_args
        assert "fastapi_app" in call_args
    
    @patch('subprocess.run')
    async def test_cleanup_disk_space_task(self, mock_subprocess, healing_agent):
        """Test disk cleanup task."""
        # Mock successful subprocess calls
        mock_subprocess.return_value.returncode = 0
        
        # Mock helper methods
        healing_agent._clean_directory = AsyncMock(return_value=100)  # 100MB freed
        healing_agent._clean_old_logs = AsyncMock()
        healing_agent._get_disk_usage = AsyncMock(return_value=70.0)  # 70% usage after cleanup
        
        result = await healing_agent._execute_task("cleanup_disk_space", {})
        
        assert result["action"] == "disk_cleanup"
        assert result["space_freed_mb"] >= 100
        assert result["new_disk_usage"] == 70.0
        assert result["success"] is True
        
        # Verify Docker system prune was called
        mock_subprocess.assert_called()
    
    @patch('subprocess.run')
    async def test_optimize_memory_task(self, mock_subprocess, healing_agent):
        """Test memory optimization task."""
        # Mock subprocess calls
        mock_subprocess.return_value.returncode = 0
        
        # Mock helper methods
        healing_agent._get_container_memory_usage = AsyncMock(return_value={
            "fastapi_app": 600,  # High memory usage
            "nextjs_app": 300,   # Normal usage
            "neo4j": 800         # High memory usage
        })
        healing_agent._restart_service = AsyncMock()
        healing_agent._get_memory_usage = AsyncMock(return_value=75.0)
        
        result = await healing_agent._execute_task("optimize_memory", {})
        
        assert result["action"] == "memory_optimization"
        assert result["new_memory_usage"] == 75.0
        assert result["success"] is True
        
        # Verify high-memory containers were restarted
        assert healing_agent._restart_service.call_count >= 1
    
    async def test_handle_service_failure(self, healing_agent):
        """Test service failure handling."""
        # Mock methods
        healing_agent._restart_service = AsyncMock()
        healing_agent.publisher.send_alert = AsyncMock()
        
        # Simulate service failure
        await healing_agent._handle_service_failure(
            "fastapi_app",
            {"status": "stopped", "healthy": False}
        )
        
        # Verify restart was attempted
        healing_agent._restart_service.assert_called_once()
        
        # Verify alert was sent
        healing_agent.publisher.send_alert.assert_called_once()
        call_args = healing_agent.publisher.send_alert.call_args[1]
        assert call_args["alert_type"] == "service_healed"
    
    async def test_handle_service_failure_repeated(self, healing_agent):
        """Test handling repeated service failures."""
        # Mock methods
        healing_agent._restart_service = AsyncMock()
        healing_agent.publisher.send_alert = AsyncMock()
        
        # Simulate first failure
        await healing_agent._handle_service_failure(
            "fastapi_app",
            {"status": "stopped", "healthy": False}
        )
        
        # Simulate immediate second failure (should be ignored due to cooldown)
        await healing_agent._handle_service_failure(
            "fastapi_app",
            {"status": "stopped", "healthy": False}
        )
        
        # Verify restart was only called once
        assert healing_agent._restart_service.call_count == 1
    
    @patch('subprocess.run')
    async def test_get_disk_usage(self, mock_subprocess, healing_agent):
        """Test disk usage monitoring."""
        # Mock df command output
        mock_subprocess.return_value.stdout = "Use%\n85%"
        mock_subprocess.return_value.returncode = 0
        
        usage = await healing_agent._get_disk_usage()
        
        assert usage == 85.0
        mock_subprocess.assert_called_once()
    
    @patch('subprocess.run')
    async def test_get_memory_usage(self, mock_subprocess, healing_agent):
        """Test memory usage monitoring."""
        # Mock free command output
        mock_subprocess.return_value.stdout = (
            "              total        used        free      shared  buff/cache   available\n"
            "Mem:           8000        6000        1000         200         500        1300"
        )
        mock_subprocess.return_value.returncode = 0
        
        usage = await healing_agent._get_memory_usage()
        
        assert usage == 75.0  # 6000/8000 * 100
        mock_subprocess.assert_called_once()
    
    @patch('subprocess.run')
    async def test_check_single_service(self, mock_subprocess, healing_agent):
        """Test checking individual service status."""
        # Mock docker-compose ps output for running service
        mock_subprocess.return_value.stdout = "fastapi_app  Up 2 hours"
        mock_subprocess.return_value.returncode = 0
        
        status = await healing_agent._check_single_service("fastapi_app")
        
        assert status["status"] == "running"
        assert status["healthy"] is True
        
        # Test stopped service
        mock_subprocess.return_value.stdout = "fastapi_app  Exit 1"
        
        status = await healing_agent._check_single_service("fastapi_app")
        
        assert status["status"] == "stopped"
        assert status["healthy"] is False
    
    async def test_healing_rules_configuration(self, healing_agent):
        """Test healing rules are properly configured."""
        rules = healing_agent.healing_rules
        
        # Test service restart rules
        assert rules["service_restart"]["max_attempts"] == 3
        assert "fastapi_app" in rules["service_restart"]["services"]
        assert "nextjs_app" in rules["service_restart"]["services"]
        
        # Test disk cleanup rules
        assert rules["disk_cleanup"]["threshold"] == 85
        assert "/tmp" in rules["disk_cleanup"]["targets"]
        
        # Test memory optimization rules
        assert rules["memory_optimization"]["threshold"] == 90
        assert "container_restart" in rules["memory_optimization"]["actions"]


class TestAgentIntegration:
    """Integration tests for agent functionality."""
    
    @pytest.fixture
    def mock_broker(self):
        """Create a mock broker for integration tests."""
        broker = Mock(spec=RabbitMQBroker)
        broker.connect = AsyncMock()
        broker.close = AsyncMock()
        broker.publish_message = AsyncMock()
        broker.setup_consumer = AsyncMock()
        return broker
    
    async def test_agent_lifecycle(self, mock_broker):
        """Test complete agent lifecycle."""
        # Create agent
        agent = SelfHealingAgent(broker=mock_broker)
        
        # Mock consumer methods
        agent.consumer.start_consuming = AsyncMock()
        agent.consumer.send_registration = AsyncMock()
        
        # Start agent
        await agent.start()
        
        assert agent.running
        assert agent.status == "running"
        
        # Stop agent
        await agent.stop()
        
        assert not agent.running
        assert agent.status == "stopped"
    
    async def test_agent_task_execution_flow(self, mock_broker):
        """Test complete task execution flow."""
        # Create agent
        agent = SelfHealingAgent(broker=mock_broker)
        
        # Mock necessary methods
        agent._check_docker_services = AsyncMock(return_value={
            "fastapi_app": {"status": "running", "healthy": True}
        })
        agent.publisher.send_response = AsyncMock()
        
        # Create task request message
        task_message = AgentMessage(
            id="task-123",
            message_type=MessageType.TASK_REQUEST,
            sender_id="orchestrator",
            sender_type=AgentType.ORCHESTRATOR,
            correlation_id="corr-123",
            payload={
                "task_type": "check_service_health",
                "parameters": {"service": "all"}
            }
        )
        
        # Execute task
        await agent._handle_task_request(task_message)
        
        # Verify response was sent
        agent.publisher.send_response.assert_called_once()
        call_args = agent.publisher.send_response.call_args[1]
        assert call_args["status"] == "success"
        assert call_args["correlation_id"] == "corr-123"
    
    async def test_agent_error_handling(self, mock_broker):
        """Test agent error handling and recovery."""
        # Create agent
        agent = SelfHealingAgent(broker=mock_broker)
        
        # Mock method to raise error
        agent._check_docker_services = AsyncMock(side_effect=RuntimeError("Test error"))
        agent.publisher.send_response = AsyncMock()
        
        # Create task request message
        task_message = AgentMessage(
            id="task-123",
            message_type=MessageType.TASK_REQUEST,
            sender_id="orchestrator",
            sender_type=AgentType.ORCHESTRATOR,
            correlation_id="corr-123",
            payload={
                "task_type": "check_service_health",
                "parameters": {"service": "all"}
            }
        )
        
        # Execute task (should handle error gracefully)
        await agent._handle_task_request(task_message)
        
        # Verify error response was sent
        agent.publisher.send_response.assert_called_once()
        call_args = agent.publisher.send_response.call_args[1]
        assert call_args["status"] == "error"
        assert "Test error" in call_args["error_message"]
        
        # Verify error count was incremented
        assert agent.error_count == 1