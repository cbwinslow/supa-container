"""Agent manager for tracking and coordinating agents."""

import asyncio
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any

from message_broker.schemas import AgentType, MessageType, Priority

logger = logging.getLogger(__name__)


class AgentManager:
    """Manages agent lifecycle, deployment, and coordination."""
    
    def __init__(self, orchestrator_id: str):
        self.orchestrator_id = orchestrator_id
        
        # Agent tracking
        self.registered_agents: Dict[str, Dict] = {}
        self.agent_capabilities: Dict[str, List[str]] = {}
        self.agent_workloads: Dict[str, int] = {}  # Track current task count per agent
        
        # Deployment targets
        self.desired_agent_counts = {
            AgentType.MONITORING: 2,
            AgentType.SELF_HEALING: 1, 
            AgentType.TROUBLESHOOTING: 1,
            AgentType.LEARNING: 1,
            AgentType.DATA_MANAGER: 1,
            AgentType.IMPROVEMENT: 1,
            AgentType.TESTING: 1,
            AgentType.DEPLOYMENT: 1
        }
        
        # Health tracking
        self.agent_health_history: Dict[str, List[Dict]] = {}
    
    def register_agent(self, agent_id: str, agent_data: Dict) -> bool:
        """Register a new agent."""
        try:
            agent_type = agent_data.get("type")
            capabilities = agent_data.get("capabilities", {})
            
            self.registered_agents[agent_id] = {
                "type": agent_type,
                "status": agent_data.get("status", "unknown"),
                "capabilities": capabilities,
                "registered_at": datetime.utcnow(),
                "last_seen": datetime.utcnow(),
                "task_count": 0,
                "error_count": 0,
                "health_score": 100.0
            }
            
            # Track capabilities
            if agent_type not in self.agent_capabilities:
                self.agent_capabilities[agent_type] = []
            
            if agent_id not in self.agent_capabilities[agent_type]:
                self.agent_capabilities[agent_type].append(agent_id)
            
            # Initialize workload tracking
            self.agent_workloads[agent_id] = 0
            
            logger.info(f"Registered agent {agent_id} of type {agent_type}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to register agent {agent_id}: {e}")
            return False
    
    def update_agent_status(self, agent_id: str, status_data: Dict):
        """Update agent status and health metrics."""
        if agent_id not in self.registered_agents:
            logger.warning(f"Received status update for unregistered agent: {agent_id}")
            return
        
        agent = self.registered_agents[agent_id]
        agent["status"] = status_data.get("status", "unknown")
        agent["last_seen"] = datetime.utcnow()
        
        # Update metrics if provided
        details = status_data.get("details", {})
        if "tasks_completed" in details:
            agent["task_count"] = details["tasks_completed"]
        if "errors" in details:
            agent["error_count"] = details["errors"]
        
        # Calculate health score
        agent["health_score"] = self._calculate_health_score(agent_id, status_data)
    
    def update_agent_metrics(self, agent_id: str, metrics: Dict):
        """Update agent performance metrics."""
        if agent_id not in self.registered_agents:
            return
        
        agent = self.registered_agents[agent_id]
        agent["last_seen"] = datetime.utcnow()
        
        # Store metrics history
        if agent_id not in self.agent_health_history:
            self.agent_health_history[agent_id] = []
        
        health_record = {
            "timestamp": datetime.utcnow(),
            "metrics": metrics,
            "health_score": agent["health_score"]
        }
        
        self.agent_health_history[agent_id].append(health_record)
        
        # Keep only last 100 records
        if len(self.agent_health_history[agent_id]) > 100:
            self.agent_health_history[agent_id] = self.agent_health_history[agent_id][-100:]
    
    def get_available_agents(self, agent_type: AgentType = None) -> List[str]:
        """Get list of available agents, optionally filtered by type."""
        available = []
        
        for agent_id, agent_data in self.registered_agents.items():
            # Check if agent is healthy and available
            if (agent_data.get("status") == "running" and 
                agent_data.get("health_score", 0) > 50):
                
                # Filter by type if specified
                if agent_type is None or agent_data.get("type") == agent_type.value:
                    available.append(agent_id)
        
        return available
    
    def get_best_agent_for_task(self, task_type: str, agent_type: AgentType = None) -> Optional[str]:
        """Find the best agent for a specific task."""
        available_agents = self.get_available_agents(agent_type)
        
        if not available_agents:
            return None
        
        # Score agents based on workload and health
        agent_scores = []
        
        for agent_id in available_agents:
            agent = self.registered_agents[agent_id]
            workload = self.agent_workloads.get(agent_id, 0)
            health_score = agent.get("health_score", 0)
            
            # Check if agent has capability for this task
            capabilities = agent.get("capabilities", {})
            task_handling = capabilities.get("message_handling", [])
            
            capability_score = 1.0
            if task_type in str(task_handling):
                capability_score = 2.0  # Prefer agents with specific capability
            
            # Calculate composite score (lower workload + higher health = better)
            score = (health_score / 100.0) * capability_score * (1.0 / (workload + 1))
            
            agent_scores.append((agent_id, score))
        
        # Return agent with highest score
        agent_scores.sort(key=lambda x: x[1], reverse=True)
        return agent_scores[0][0]
    
    def assign_task(self, agent_id: str, task_id: str):
        """Assign a task to an agent and update workload."""
        if agent_id in self.agent_workloads:
            self.agent_workloads[agent_id] += 1
        else:
            self.agent_workloads[agent_id] = 1
    
    def complete_task(self, agent_id: str, task_id: str, success: bool):
        """Mark task as completed and update agent metrics."""
        if agent_id in self.agent_workloads:
            self.agent_workloads[agent_id] = max(0, self.agent_workloads[agent_id] - 1)
        
        if agent_id in self.registered_agents:
            agent = self.registered_agents[agent_id]
            agent["task_count"] += 1
            
            if not success:
                agent["error_count"] += 1
                # Decrease health score for errors
                agent["health_score"] = max(0, agent["health_score"] - 5)
            else:
                # Slowly improve health score for successful tasks
                agent["health_score"] = min(100, agent["health_score"] + 1)
    
    def get_inactive_agents(self, timeout_minutes: int = 5) -> List[str]:
        """Get list of agents that haven't been seen recently."""
        cutoff_time = datetime.utcnow() - timedelta(minutes=timeout_minutes)
        inactive = []
        
        for agent_id, agent_data in self.registered_agents.items():
            last_seen = agent_data.get("last_seen", datetime.min)
            if last_seen < cutoff_time:
                inactive.append(agent_id)
        
        return inactive
    
    def remove_agent(self, agent_id: str):
        """Remove an agent from tracking."""
        if agent_id in self.registered_agents:
            agent_type = self.registered_agents[agent_id].get("type")
            
            # Remove from all tracking structures
            del self.registered_agents[agent_id]
            
            if agent_id in self.agent_workloads:
                del self.agent_workloads[agent_id]
            
            if agent_id in self.agent_health_history:
                del self.agent_health_history[agent_id]
            
            # Remove from capabilities tracking
            if agent_type and agent_type in self.agent_capabilities:
                if agent_id in self.agent_capabilities[agent_type]:
                    self.agent_capabilities[agent_type].remove(agent_id)
            
            logger.info(f"Removed agent {agent_id}")
    
    def get_agent_deployment_needs(self) -> Dict[AgentType, int]:
        """Determine how many agents of each type need to be deployed."""
        needs = {}
        
        for agent_type, desired_count in self.desired_agent_counts.items():
            current_agents = self.get_available_agents(agent_type)
            current_count = len(current_agents)
            
            if current_count < desired_count:
                needs[agent_type] = desired_count - current_count
        
        return needs
    
    def get_system_health_summary(self) -> Dict[str, Any]:
        """Get overall system health summary."""
        total_agents = len(self.registered_agents)
        healthy_agents = len([
            a for a in self.registered_agents.values()
            if a.get("health_score", 0) > 75
        ])
        
        avg_health = 0
        if total_agents > 0:
            avg_health = sum(
                a.get("health_score", 0) for a in self.registered_agents.values()
            ) / total_agents
        
        # Calculate workload distribution
        total_tasks = sum(self.agent_workloads.values())
        avg_workload = total_tasks / max(1, total_agents)
        
        return {
            "total_agents": total_agents,
            "healthy_agents": healthy_agents,
            "health_percentage": (healthy_agents / max(1, total_agents)) * 100,
            "average_health_score": avg_health,
            "total_active_tasks": total_tasks,
            "average_workload": avg_workload,
            "agent_types": {
                agent_type.value: len(self.get_available_agents(agent_type))
                for agent_type in AgentType
            }
        }
    
    def _calculate_health_score(self, agent_id: str, status_data: Dict) -> float:
        """Calculate health score for an agent based on various metrics."""
        agent = self.registered_agents.get(agent_id, {})
        
        # Base score
        score = 100.0
        
        # Factor in error rate
        task_count = agent.get("task_count", 0)
        error_count = agent.get("error_count", 0)
        
        if task_count > 0:
            error_rate = error_count / task_count
            score -= error_rate * 50  # Up to 50 point penalty for high error rate
        
        # Factor in uptime/responsiveness
        last_seen = agent.get("last_seen", datetime.utcnow())
        time_since_seen = (datetime.utcnow() - last_seen).total_seconds()
        
        if time_since_seen > 300:  # More than 5 minutes
            score -= min(40, time_since_seen / 60)  # Up to 40 point penalty
        
        # Factor in resource usage if available
        details = status_data.get("details", {})
        if "memory_usage" in details:
            memory_usage = details["memory_usage"]
            if memory_usage > 90:
                score -= 20
            elif memory_usage > 80:
                score -= 10
        
        return max(0.0, min(100.0, score))