"""Self-healing agent for automatic system recovery and maintenance."""

import asyncio
import logging
import subprocess
from typing import Dict, Any, List
from datetime import datetime, timedelta

from .base_agent import BaseAgent
from message_broker.schemas import AgentType, Priority

logger = logging.getLogger(__name__)


class SelfHealingAgent(BaseAgent):
    """
    Self-healing agent that monitors system health and automatically
    repairs issues, restarts services, and maintains system stability.
    """
    
    def __init__(self, broker, agent_id: str = None):
        super().__init__(broker, AgentType.SELF_HEALING, agent_id)
        
        # Healing configuration
        self.healing_rules = {
            "service_restart": {
                "max_attempts": 3,
                "backoff_multiplier": 2,
                "services": ["fastapi_app", "nextjs_app", "neo4j", "supabase"]
            },
            "disk_cleanup": {
                "threshold": 85,  # Cleanup when disk usage > 85%
                "targets": ["/tmp", "/var/log", "/opt/supabase-super-stack/logs"]
            },
            "memory_optimization": {
                "threshold": 90,  # Optimize when memory usage > 90%
                "actions": ["container_restart", "cache_clear"]
            }
        }
        
        # Issue tracking
        self.detected_issues = {}
        self.healing_history = []
        
    async def _start_agent_tasks(self):
        """Start self-healing monitoring tasks."""
        asyncio.create_task(self._monitor_services())
        asyncio.create_task(self._monitor_resources())
        asyncio.create_task(self._monitor_logs())
        asyncio.create_task(self._proactive_maintenance())
    
    async def _execute_task(self, task_type: str, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Execute self-healing tasks."""
        task_handlers = {
            "check_service_health": self._check_service_health,
            "restart_service": self._restart_service,
            "cleanup_disk_space": self._cleanup_disk_space,
            "optimize_memory": self._optimize_memory,
            "heal_database": self._heal_database,
            "fix_network_issues": self._fix_network_issues,
            "update_configurations": self._update_configurations,
            "perform_backup": self._perform_backup
        }
        
        handler = task_handlers.get(task_type)
        if handler:
            result = await handler(parameters)
            return result
        else:
            raise ValueError(f"Unknown task type: {task_type}")
    
    async def _monitor_services(self):
        """Continuously monitor service health."""
        while self.running:
            try:
                # Check Docker services
                services_status = await self._check_docker_services()
                
                for service, status in services_status.items():
                    if status["status"] != "running":
                        await self._handle_service_failure(service, status)
                
                # Check database connections
                db_status = await self._check_database_health()
                if not db_status["healthy"]:
                    await self._handle_database_issues(db_status)
                
                # Check API endpoints
                api_status = await self._check_api_health()
                if not api_status["healthy"]:
                    await self._handle_api_issues(api_status)
                
                await asyncio.sleep(30)  # Check every 30 seconds
                
            except Exception as e:
                logger.error(f"Service monitoring error: {e}")
                await asyncio.sleep(60)
    
    async def _monitor_resources(self):
        """Monitor system resources and heal issues."""
        while self.running:
            try:
                # Check disk usage
                disk_usage = await self._get_disk_usage()
                if disk_usage > self.healing_rules["disk_cleanup"]["threshold"]:
                    await self._cleanup_disk_space({})
                
                # Check memory usage
                memory_usage = await self._get_memory_usage()
                if memory_usage > self.healing_rules["memory_optimization"]["threshold"]:
                    await self._optimize_memory({})
                
                # Check CPU usage patterns
                cpu_usage = await self._get_cpu_usage()
                if cpu_usage > 95:  # High CPU usage
                    await self._handle_high_cpu_usage()
                
                await asyncio.sleep(120)  # Check every 2 minutes
                
            except Exception as e:
                logger.error(f"Resource monitoring error: {e}")
                await asyncio.sleep(120)
    
    async def _monitor_logs(self):
        """Monitor logs for error patterns and heal automatically."""
        while self.running:
            try:
                # Check application logs for error patterns
                error_patterns = await self._analyze_error_patterns()
                
                for pattern in error_patterns:
                    await self._handle_error_pattern(pattern)
                
                # Check for repeated errors indicating systemic issues
                systemic_issues = await self._detect_systemic_issues()
                
                for issue in systemic_issues:
                    await self._handle_systemic_issue(issue)
                
                await asyncio.sleep(60)  # Check logs every minute
                
            except Exception as e:
                logger.error(f"Log monitoring error: {e}")
                await asyncio.sleep(60)
    
    async def _proactive_maintenance(self):
        """Perform proactive maintenance tasks."""
        while self.running:
            try:
                # Daily maintenance tasks
                if datetime.utcnow().hour == 2:  # 2 AM maintenance window
                    await self._daily_maintenance()
                
                # Weekly maintenance tasks
                if datetime.utcnow().weekday() == 6 and datetime.utcnow().hour == 3:  # Sunday 3 AM
                    await self._weekly_maintenance()
                
                await asyncio.sleep(3600)  # Check every hour
                
            except Exception as e:
                logger.error(f"Proactive maintenance error: {e}")
                await asyncio.sleep(3600)
    
    async def _check_service_health(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Check health of specified service."""
        service_name = parameters.get("service", "all")
        
        if service_name == "all":
            return await self._check_docker_services()
        else:
            status = await self._check_single_service(service_name)
            return {service_name: status}
    
    async def _restart_service(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Restart a specific service."""
        service_name = parameters.get("service")
        if not service_name:
            raise ValueError("Service name required for restart")
        
        logger.info(f"Restarting service: {service_name}")
        
        try:
            # Use docker-compose to restart service
            result = subprocess.run(
                ["docker-compose", "restart", service_name],
                capture_output=True,
                text=True,
                cwd="/opt/supabase-super-stack"
            )
            
            if result.returncode == 0:
                # Wait for service to be ready
                await asyncio.sleep(10)
                
                # Verify service is running
                status = await self._check_single_service(service_name)
                
                healing_record = {
                    "timestamp": datetime.utcnow(),
                    "action": "service_restart",
                    "service": service_name,
                    "success": status.get("status") == "running",
                    "details": status
                }
                
                self.healing_history.append(healing_record)
                
                return healing_record
            else:
                raise RuntimeError(f"Failed to restart service: {result.stderr}")
                
        except Exception as e:
            logger.error(f"Service restart failed: {e}")
            raise
    
    async def _cleanup_disk_space(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Clean up disk space by removing temporary files and old logs."""
        logger.info("Starting disk space cleanup")
        
        cleanup_actions = []
        total_freed = 0
        
        try:
            # Clean Docker system
            result = subprocess.run(
                ["docker", "system", "prune", "-f"],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                cleanup_actions.append("docker_system_prune")
            
            # Clean temporary directories
            for target_dir in self.healing_rules["disk_cleanup"]["targets"]:
                freed_space = await self._clean_directory(target_dir)
                if freed_space > 0:
                    cleanup_actions.append(f"cleaned_{target_dir}")
                    total_freed += freed_space
            
            # Clean old log files
            await self._clean_old_logs()
            cleanup_actions.append("cleaned_old_logs")
            
            # Update disk usage
            new_disk_usage = await self._get_disk_usage()
            
            healing_record = {
                "timestamp": datetime.utcnow(),
                "action": "disk_cleanup",
                "actions_taken": cleanup_actions,
                "space_freed_mb": total_freed,
                "new_disk_usage": new_disk_usage,
                "success": True
            }
            
            self.healing_history.append(healing_record)
            
            logger.info(f"Disk cleanup completed. Freed {total_freed}MB")
            return healing_record
            
        except Exception as e:
            logger.error(f"Disk cleanup failed: {e}")
            raise
    
    async def _optimize_memory(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Optimize memory usage by restarting high-memory containers."""
        logger.info("Starting memory optimization")
        
        try:
            # Get memory usage by container
            container_memory = await self._get_container_memory_usage()
            
            # Sort by memory usage
            high_memory_containers = [
                container for container, usage in container_memory.items()
                if usage > 500  # > 500MB
            ]
            
            restarted_containers = []
            
            # Restart high-memory containers one by one
            for container in high_memory_containers[:3]:  # Limit to 3 containers
                try:
                    await self._restart_service({"service": container})
                    restarted_containers.append(container)
                    await asyncio.sleep(30)  # Wait between restarts
                except Exception as e:
                    logger.error(f"Failed to restart {container}: {e}")
            
            # Clear system caches
            subprocess.run(["sync"], check=False)
            subprocess.run(["echo", "3", ">", "/proc/sys/vm/drop_caches"], 
                         shell=True, check=False)
            
            new_memory_usage = await self._get_memory_usage()
            
            healing_record = {
                "timestamp": datetime.utcnow(),
                "action": "memory_optimization",
                "restarted_containers": restarted_containers,
                "new_memory_usage": new_memory_usage,
                "success": True
            }
            
            self.healing_history.append(healing_record)
            
            logger.info("Memory optimization completed")
            return healing_record
            
        except Exception as e:
            logger.error(f"Memory optimization failed: {e}")
            raise
    
    async def _handle_service_failure(self, service: str, status: Dict):
        """Handle service failure by attempting to restart."""
        issue_key = f"service_failure_{service}"
        
        # Track issue occurrences
        if issue_key not in self.detected_issues:
            self.detected_issues[issue_key] = {
                "first_seen": datetime.utcnow(),
                "count": 0,
                "last_healing_attempt": None
            }
        
        issue = self.detected_issues[issue_key]
        issue["count"] += 1
        issue["last_seen"] = datetime.utcnow()
        
        # Don't heal too frequently
        if issue["last_healing_attempt"]:
            time_since_last = datetime.utcnow() - issue["last_healing_attempt"]
            if time_since_last < timedelta(minutes=5):
                return
        
        # Attempt healing
        try:
            logger.warning(f"Service {service} is not running. Attempting to heal.")
            
            await self._restart_service({"service": service})
            
            issue["last_healing_attempt"] = datetime.utcnow()
            
            # Send alert to orchestrator
            await self.publisher.send_alert(
                alert_type="service_healed",
                message=f"Successfully restarted service {service}",
                severity="info",
                metadata={"service": service, "attempt_count": issue["count"]}
            )
            
        except Exception as e:
            logger.error(f"Failed to heal service {service}: {e}")
            
            # Send alert for failed healing
            await self.publisher.send_alert(
                alert_type="healing_failed",
                message=f"Failed to heal service {service}: {e}",
                severity="error",
                metadata={"service": service, "error": str(e)}
            )
    
    # Helper methods (simplified implementations)
    
    async def _check_docker_services(self) -> Dict[str, Any]:
        """Check status of Docker services."""
        # Simplified implementation
        services = ["fastapi_app", "nextjs_app", "neo4j", "supabase"]
        status = {}
        
        for service in services:
            status[service] = await self._check_single_service(service)
        
        return status
    
    async def _check_single_service(self, service: str) -> Dict[str, Any]:
        """Check status of a single service."""
        try:
            result = subprocess.run(
                ["docker-compose", "ps", service],
                capture_output=True,
                text=True,
                cwd="/opt/supabase-super-stack"
            )
            
            # Parse output to determine status
            if "Up" in result.stdout:
                return {"status": "running", "healthy": True}
            else:
                return {"status": "stopped", "healthy": False}
                
        except Exception as e:
            return {"status": "unknown", "healthy": False, "error": str(e)}
    
    async def _get_disk_usage(self) -> float:
        """Get current disk usage percentage."""
        try:
            result = subprocess.run(
                ["df", "/", "--output=pcent"],
                capture_output=True,
                text=True
            )
            
            lines = result.stdout.strip().split('\n')
            if len(lines) > 1:
                percentage = lines[1].strip('%')
                return float(percentage)
            
        except Exception as e:
            logger.error(f"Failed to get disk usage: {e}")
        
        return 0.0
    
    async def _get_memory_usage(self) -> float:
        """Get current memory usage percentage."""
        try:
            result = subprocess.run(
                ["free", "-m"],
                capture_output=True,
                text=True
            )
            
            lines = result.stdout.strip().split('\n')
            if len(lines) > 1:
                memory_line = lines[1].split()
                total = float(memory_line[1])
                used = float(memory_line[2])
                return (used / total) * 100
                
        except Exception as e:
            logger.error(f"Failed to get memory usage: {e}")
        
        return 0.0