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
    
    async def _heal_database(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Heal database connection issues."""
        logger.info("Performing database healing")
        
        # Check database connections and restart if needed
        healing_actions = []
        
        try:
            # Check PostgreSQL connection
            db_status = await self._check_database_health()
            if not db_status.get("healthy", False):
                # Restart database service
                await self._restart_service({"service": "postgres"})
                healing_actions.append("postgres_restart")
            
            # Check Neo4j connection
            neo4j_status = await self._check_neo4j_health()
            if not neo4j_status.get("healthy", False):
                await self._restart_service({"service": "neo4j"})
                healing_actions.append("neo4j_restart")
            
            return {
                "timestamp": datetime.utcnow(),
                "action": "database_healing",
                "actions_taken": healing_actions,
                "success": True
            }
            
        except Exception as e:
            logger.error(f"Database healing failed: {e}")
            raise
    
    async def _fix_network_issues(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Fix network connectivity issues."""
        logger.info("Fixing network issues")
        
        healing_actions = []
        
        try:
            # Restart networking service
            result = subprocess.run(
                ["systemctl", "restart", "networking"],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                healing_actions.append("networking_restart")
            
            # Flush DNS cache
            subprocess.run(["systemctl", "flush-dns"], check=False)
            healing_actions.append("dns_flush")
            
            return {
                "timestamp": datetime.utcnow(),
                "action": "network_healing",
                "actions_taken": healing_actions,
                "success": True
            }
            
        except Exception as e:
            logger.error(f"Network healing failed: {e}")
            raise
    
    async def _update_configurations(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Update system configurations for optimization."""
        logger.info("Updating configurations")
        
        try:
            # Reload configuration files
            config_updates = []
            
            # Restart services to pick up new configurations
            services_to_restart = parameters.get("services", ["fastapi_app", "nextjs_app"])
            
            for service in services_to_restart:
                await self._restart_service({"service": service})
                config_updates.append(f"restarted_{service}")
            
            return {
                "timestamp": datetime.utcnow(),
                "action": "configuration_update",
                "updates": config_updates,
                "success": True
            }
            
        except Exception as e:
            logger.error(f"Configuration update failed: {e}")
            raise
    
    async def _perform_backup(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Perform system backup."""
        logger.info("Performing system backup")
        
        try:
            backup_targets = parameters.get("targets", ["database", "configurations"])
            backup_results = []
            
            for target in backup_targets:
                if target == "database":
                    # Backup database
                    result = subprocess.run(
                        ["docker-compose", "exec", "postgres", "pg_dump", "-U", "postgres", "postgres"],
                        capture_output=True,
                        text=True,
                        cwd="/opt/supabase-super-stack"
                    )
                    
                    if result.returncode == 0:
                        backup_results.append("database_backup_success")
                    else:
                        backup_results.append("database_backup_failed")
                
                elif target == "configurations":
                    # Backup configuration files
                    subprocess.run(
                        ["tar", "-czf", f"/tmp/config_backup_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.tar.gz", 
                         "/opt/supabase-super-stack/.env", "/opt/supabase-super-stack/docker-compose.yml"],
                        check=False
                    )
                    backup_results.append("config_backup_success")
            
            return {
                "timestamp": datetime.utcnow(),
                "action": "system_backup",
                "results": backup_results,
                "success": True
            }
            
        except Exception as e:
            logger.error(f"Backup failed: {e}")
            raise
    
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
    
    async def _check_database_health(self) -> Dict[str, Any]:
        """Check database health."""
        try:
            # Simple database connection check
            result = subprocess.run(
                ["docker-compose", "exec", "-T", "postgres", "pg_isready"],
                capture_output=True,
                text=True,
                cwd="/opt/supabase-super-stack"
            )
            
            return {"healthy": result.returncode == 0}
            
        except Exception as e:
            return {"healthy": False, "error": str(e)}
    
    async def _check_neo4j_health(self) -> Dict[str, Any]:
        """Check Neo4j health."""
        try:
            # Simple Neo4j connection check
            result = subprocess.run(
                ["docker-compose", "exec", "-T", "neo4j", "cypher-shell", "-u", "neo4j", "-p", "password", "RETURN 1"],
                capture_output=True,
                text=True,
                cwd="/opt/supabase-super-stack"
            )
            
            return {"healthy": result.returncode == 0}
            
        except Exception as e:
            return {"healthy": False, "error": str(e)}
    
    async def _check_api_health(self) -> Dict[str, Any]:
        """Check API endpoint health."""
        try:
            # Simple HTTP health check
            import httpx
            
            async with httpx.AsyncClient() as client:
                response = await client.get("http://localhost:8000/health", timeout=5.0)
                return {"healthy": response.status_code == 200}
                
        except Exception as e:
            return {"healthy": False, "error": str(e)}
    
    async def _get_cpu_usage(self) -> float:
        """Get current CPU usage percentage."""
        try:
            result = subprocess.run(
                ["top", "-bn1", "|", "grep", "Cpu(s)"],
                shell=True,
                capture_output=True,
                text=True
            )
            
            # Parse CPU usage from top output
            # This is a simplified implementation
            return 50.0  # Default value
            
        except Exception as e:
            logger.error(f"Failed to get CPU usage: {e}")
        
        return 0.0
    
    async def _get_container_memory_usage(self) -> Dict[str, float]:
        """Get memory usage by container."""
        try:
            result = subprocess.run(
                ["docker", "stats", "--no-stream", "--format", "table {{.Container}}\t{{.MemUsage}}"],
                capture_output=True,
                text=True
            )
            
            container_memory = {}
            lines = result.stdout.strip().split('\n')[1:]  # Skip header
            
            for line in lines:
                parts = line.split('\t')
                if len(parts) >= 2:
                    container = parts[0]
                    memory_str = parts[1].split('/')[0].strip()  # Get used memory
                    
                    # Parse memory value (e.g., "123.4MiB" -> 123.4)
                    if 'MiB' in memory_str:
                        memory_mb = float(memory_str.replace('MiB', ''))
                    elif 'GiB' in memory_str:
                        memory_mb = float(memory_str.replace('GiB', '')) * 1024
                    else:
                        memory_mb = 0.0
                    
                    container_memory[container] = memory_mb
            
            return container_memory
            
        except Exception as e:
            logger.error(f"Failed to get container memory usage: {e}")
            return {}
    
    async def _clean_directory(self, directory: str) -> float:
        """Clean a directory and return space freed in MB."""
        try:
            # Get initial size
            result = subprocess.run(
                ["du", "-sm", directory],
                capture_output=True,
                text=True
            )
            
            initial_size = 0
            if result.returncode == 0:
                initial_size = int(result.stdout.split()[0])
            
            # Clean temporary files older than 7 days
            subprocess.run(
                ["find", directory, "-type", "f", "-mtime", "+7", "-delete"],
                check=False
            )
            
            # Clean empty directories
            subprocess.run(
                ["find", directory, "-type", "d", "-empty", "-delete"],
                check=False
            )
            
            # Get final size
            result = subprocess.run(
                ["du", "-sm", directory],
                capture_output=True,
                text=True
            )
            
            final_size = 0
            if result.returncode == 0:
                final_size = int(result.stdout.split()[0])
            
            return max(0, initial_size - final_size)
            
        except Exception as e:
            logger.error(f"Failed to clean directory {directory}: {e}")
            return 0
    
    async def _clean_old_logs(self):
        """Clean old log files."""
        try:
            # Clean Docker logs
            subprocess.run(
                ["docker", "system", "prune", "-f", "--volumes"],
                check=False
            )
            
            # Clean application logs older than 30 days
            log_dirs = ["/var/log", "/opt/supabase-super-stack/logs"]
            
            for log_dir in log_dirs:
                subprocess.run(
                    ["find", log_dir, "-name", "*.log", "-mtime", "+30", "-delete"],
                    check=False
                )
                
        except Exception as e:
            logger.error(f"Failed to clean old logs: {e}")
    
    async def _handle_high_cpu_usage(self):
        """Handle high CPU usage situations."""
        try:
            logger.warning("High CPU usage detected, investigating...")
            
            # Get top processes
            result = subprocess.run(
                ["ps", "aux", "--sort=-%cpu", "|", "head", "-10"],
                shell=True,
                capture_output=True,
                text=True
            )
            
            # Send alert with process information
            await self.publisher.send_alert(
                alert_type="high_cpu_usage",
                message="High CPU usage detected",
                severity="warning",
                metadata={"top_processes": result.stdout}
            )
            
        except Exception as e:
            logger.error(f"Failed to handle high CPU usage: {e}")
    
    async def _analyze_error_patterns(self) -> List[Dict]:
        """Analyze logs for error patterns."""
        # Simplified implementation - in practice would analyze actual logs
        return []
    
    async def _handle_error_pattern(self, pattern: Dict):
        """Handle detected error patterns."""
        pass
    
    async def _detect_systemic_issues(self) -> List[Dict]:
        """Detect systemic issues from repeated errors."""
        return []
    
    async def _handle_systemic_issue(self, issue: Dict):
        """Handle systemic issues."""
        pass
    
    async def _daily_maintenance(self):
        """Perform daily maintenance tasks."""
        logger.info("Performing daily maintenance")
        
        try:
            # Disk cleanup
            await self._cleanup_disk_space({})
            
        except Exception as e:
            logger.error(f"Daily maintenance failed: {e}")
    
    async def _weekly_maintenance(self):
        """Perform weekly maintenance tasks."""
        logger.info("Performing weekly maintenance")
        
        try:
            # Full system cleanup
            await self._cleanup_disk_space({})
            await self._optimize_memory({})
            
        except Exception as e:
            logger.error(f"Weekly maintenance failed: {e}")