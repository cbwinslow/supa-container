"""AI Orchestrator Brain - Central intelligence for managing all agents and data flows."""

import asyncio
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import uuid

from message_broker import RabbitMQBroker, MessageConsumer, MessagePublisher
from message_broker.schemas import AgentType, MessageType, AgentMessage, Priority
from .agent_manager import AgentManager
from .task_scheduler import TaskScheduler
from .data_analyzer import DataAnalyzer

logger = logging.getLogger(__name__)


class OrchestratorBrain:
    """
    Central AI Orchestrator Brain that manages all agents and ensures no data is wasted.
    
    Responsibilities:
    - Monitor all system components and data flows
    - Deploy specialized agents for specific tasks
    - Ensure all data is utilized and analyzed
    - Coordinate agent communication and task distribution
    - Implement self-healing and improvement mechanisms
    """
    
    def __init__(
        self,
        broker: RabbitMQBroker,
        orchestrator_id: str = None
    ):
        self.orchestrator_id = orchestrator_id or f"orchestrator-{uuid.uuid4().hex[:8]}"
        self.broker = broker
        
        # Core components
        self.agent_manager = AgentManager(self.orchestrator_id)
        self.task_scheduler = TaskScheduler()
        self.data_analyzer = DataAnalyzer()
        
        # Message handling
        self.consumer = MessageConsumer(broker, self.orchestrator_id, AgentType.ORCHESTRATOR)
        self.publisher = MessagePublisher(broker, self.orchestrator_id, AgentType.ORCHESTRATOR)
        
        # State tracking
        self.active_agents: Dict[str, Dict] = {}
        self.system_metrics: Dict[str, Any] = {}
        self.data_flows: Dict[str, Dict] = {}
        self.running = False
        
        # Data utilization tracking
        self.processed_data_count = 0
        self.unused_data_count = 0
        self.data_efficiency_threshold = 0.95  # 95% data utilization target
        
        self._setup_message_handlers()
    
    def _setup_message_handlers(self):
        """Setup message handlers for different types of messages."""
        self.consumer.register_handler(MessageType.AGENT_REGISTRATION, self._handle_agent_registration)
        self.consumer.register_handler(MessageType.STATUS_UPDATE, self._handle_status_update)
        self.consumer.register_handler(MessageType.LOG_DATA, self._handle_log_data)
        self.consumer.register_handler(MessageType.METRICS_DATA, self._handle_metrics_data)
        self.consumer.register_handler(MessageType.ALERT, self._handle_alert)
        self.consumer.register_handler(MessageType.TASK_RESPONSE, self._handle_task_response)
    
    async def start(self):
        """Start the orchestrator brain."""
        logger.info(f"Starting AI Orchestrator Brain: {self.orchestrator_id}")
        
        # Connect to message broker
        await self.broker.connect()
        
        # Start consuming messages
        await self.consumer.start_consuming()
        
        # Register ourselves
        await self.consumer.send_registration()
        
        self.running = True
        
        # Start background tasks
        asyncio.create_task(self._monitor_system())
        asyncio.create_task(self._analyze_data_flows())
        asyncio.create_task(self._manage_agents())
        asyncio.create_task(self._optimize_system())
        
        logger.info("AI Orchestrator Brain started successfully")
    
    async def stop(self):
        """Stop the orchestrator brain."""
        logger.info("Stopping AI Orchestrator Brain")
        self.running = False
        await self.broker.close()
    
    async def _handle_agent_registration(self, message: AgentMessage):
        """Handle agent registration messages."""
        payload = message.payload
        agent_id = payload.get("agent_id")
        agent_type = payload.get("agent_type")
        
        if agent_id and agent_type:
            self.active_agents[agent_id] = {
                "type": agent_type,
                "capabilities": payload.get("capabilities", {}),
                "status": payload.get("status", "unknown"),
                "last_seen": datetime.utcnow(),
                "metrics": {}
            }
            
            logger.info(f"Registered new agent: {agent_id} ({agent_type})")
            
            # Send welcome message with initial tasks
            await self._assign_initial_tasks(agent_id, agent_type)
    
    async def _handle_status_update(self, message: AgentMessage):
        """Handle status update messages."""
        agent_id = message.sender_id
        status_data = message.payload
        
        if agent_id in self.active_agents:
            self.active_agents[agent_id].update({
                "status": status_data.get("status", "unknown"),
                "last_seen": datetime.utcnow(),
                "details": status_data.get("details", {})
            })
            
            # Analyze status for potential issues
            await self._analyze_agent_status(agent_id, status_data)
    
    async def _handle_log_data(self, message: AgentMessage):
        """Handle log data - ensure all logs are processed and analyzed."""
        log_data = message.payload
        
        # Store log data for analysis
        await self.data_analyzer.process_log_data(
            agent_id=message.sender_id,
            log_data=log_data
        )
        
        # Check for anomalies or issues
        await self._analyze_log_patterns(log_data)
        
        # Increment processed data count
        self.processed_data_count += 1
        
        # If log indicates an error, trigger appropriate agents
        if log_data.get("level") in ["ERROR", "CRITICAL"]:
            await self._trigger_healing_agents(log_data)
    
    async def _handle_metrics_data(self, message: AgentMessage):
        """Handle metrics data - ensure all metrics contribute to system improvement."""
        metrics_data = message.payload
        agent_id = message.sender_id
        
        # Store metrics for analysis
        if agent_id in self.active_agents:
            self.active_agents[agent_id]["metrics"] = metrics_data
        
        # Analyze metrics for optimization opportunities
        await self._analyze_system_metrics(agent_id, metrics_data)
        
        # Update system-wide metrics
        await self._update_system_metrics(metrics_data)
        
        self.processed_data_count += 1
    
    async def _handle_alert(self, message: AgentMessage):
        """Handle alert messages - deploy appropriate response agents."""
        alert_data = message.payload
        severity = alert_data.get("severity", "warning")
        
        logger.warning(f"Alert received from {message.sender_id}: {alert_data}")
        
        # Determine response strategy based on alert type and severity
        response_agents = await self._determine_response_agents(alert_data)
        
        # Deploy or assign tasks to response agents
        for agent_type in response_agents:
            await self._deploy_response_agent(agent_type, alert_data)
    
    async def _handle_task_response(self, message: AgentMessage):
        """Handle task completion responses."""
        response_data = message.payload
        correlation_id = message.correlation_id
        
        # Update task status in scheduler
        await self.task_scheduler.update_task_status(
            correlation_id,
            response_data.get("status"),
            response_data.get("result"),
            response_data.get("error_message")
        )
        
        # Analyze task results for learning opportunities
        await self._analyze_task_results(response_data)
    
    async def _monitor_system(self):
        """Continuous system monitoring loop."""
        while self.running:
            try:
                # Check agent health
                await self._check_agent_health()
                
                # Monitor data flow efficiency
                await self._monitor_data_efficiency()
                
                # Check for resource utilization
                await self._monitor_resources()
                
                # Sleep for monitoring interval
                await asyncio.sleep(30)  # Monitor every 30 seconds
                
            except Exception as e:
                logger.error(f"Error in system monitoring: {e}")
                await asyncio.sleep(60)  # Back off on error
    
    async def _analyze_data_flows(self):
        """Analyze all data flows to ensure nothing is wasted."""
        while self.running:
            try:
                # Calculate data efficiency
                total_data = self.processed_data_count + self.unused_data_count
                if total_data > 0:
                    efficiency = self.processed_data_count / total_data
                    
                    if efficiency < self.data_efficiency_threshold:
                        logger.warning(f"Data efficiency below threshold: {efficiency:.2%}")
                        await self._improve_data_utilization()
                
                # Identify data patterns and opportunities
                await self._identify_data_opportunities()
                
                await asyncio.sleep(300)  # Analyze every 5 minutes
                
            except Exception as e:
                logger.error(f"Error in data flow analysis: {e}")
                await asyncio.sleep(300)
    
    async def _manage_agents(self):
        """Manage agent lifecycle and deployment."""
        while self.running:
            try:
                # Check if we need additional agents
                await self._assess_agent_needs()
                
                # Optimize agent distribution
                await self._optimize_agent_allocation()
                
                # Clean up inactive agents
                await self._cleanup_inactive_agents()
                
                await asyncio.sleep(120)  # Manage every 2 minutes
                
            except Exception as e:
                logger.error(f"Error in agent management: {e}")
                await asyncio.sleep(120)
    
    async def _optimize_system(self):
        """Continuous system optimization."""
        while self.running:
            try:
                # Analyze system performance
                performance_metrics = await self._collect_performance_metrics()
                
                # Identify optimization opportunities
                optimizations = await self._identify_optimizations(performance_metrics)
                
                # Deploy improvement agents if needed
                for optimization in optimizations:
                    await self._deploy_improvement_agent(optimization)
                
                await asyncio.sleep(600)  # Optimize every 10 minutes
                
            except Exception as e:
                logger.error(f"Error in system optimization: {e}")
                await asyncio.sleep(600)
    
    async def _assign_initial_tasks(self, agent_id: str, agent_type: str):
        """Assign initial tasks to newly registered agents."""
        initial_tasks = {
            "monitoring": ["collect_system_metrics", "monitor_services"],
            "self_healing": ["check_service_health", "monitor_error_rates"],
            "troubleshooting": ["analyze_logs", "diagnose_issues"],
            "learning": ["analyze_patterns", "build_knowledge_base"],
            "improvement": ["identify_bottlenecks", "suggest_optimizations"],
            "data_manager": ["organize_data", "compress_old_data"],
            "testing": ["run_health_checks", "validate_deployments"],
            "deployment": ["monitor_deployments", "update_services"]
        }
        
        tasks = initial_tasks.get(agent_type, ["send_status_update"])
        
        for task in tasks:
            await self.publisher.send_task_request(
                task_type=task,
                parameters={"agent_type": agent_type},
                recipient_id=agent_id,
                priority=Priority.NORMAL
            )
    
    async def _check_agent_health(self):
        """Check health of all registered agents."""
        current_time = datetime.utcnow()
        
        for agent_id, agent_info in self.active_agents.items():
            last_seen = agent_info.get("last_seen", current_time)
            
            # If agent hasn't been seen for more than 5 minutes
            if (current_time - last_seen).total_seconds() > 300:
                logger.warning(f"Agent {agent_id} appears to be unresponsive")
                
                # Try to restart or replace the agent
                await self._handle_unresponsive_agent(agent_id, agent_info)
    
    async def _handle_unresponsive_agent(self, agent_id: str, agent_info: Dict):
        """Handle unresponsive agents."""
        agent_type = agent_info.get("type")
        
        # Mark agent as inactive
        agent_info["status"] = "unresponsive"
        
        # Deploy replacement agent if this is a critical type
        critical_types = ["monitoring", "self_healing", "orchestrator"]
        
        if agent_type in critical_types:
            await self._deploy_replacement_agent(agent_type)
        
        # Alert administrators
        await self.publisher.send_alert(
            alert_type="agent_unresponsive",
            message=f"Agent {agent_id} ({agent_type}) is unresponsive",
            severity="warning",
            metadata={"agent_id": agent_id, "agent_type": agent_type}
        )
    
    async def _deploy_replacement_agent(self, agent_type: str):
        """Deploy a replacement agent."""
        # This would typically involve container orchestration
        # For now, we'll log the need for deployment
        logger.info(f"Deploying replacement agent of type: {agent_type}")
        
        # In a real implementation, this would:
        # 1. Create new container/process for the agent
        # 2. Configure it with appropriate settings
        # 3. Start the agent and wait for registration
        
    async def _improve_data_utilization(self):
        """Improve data utilization efficiency."""
        # Deploy data analysis agents to process unused data
        await self.publisher.send_task_request(
            task_type="analyze_unused_data",
            parameters={"threshold": self.data_efficiency_threshold},
            recipient_type=AgentType.DATA_MANAGER,
            priority=Priority.HIGH
        )
        
        # Deploy learning agents to extract insights from all data
        await self.publisher.send_task_request(
            task_type="extract_insights_from_all_data",
            parameters={"include_historical": True},
            recipient_type=AgentType.LEARNING,
            priority=Priority.NORMAL
        )