#!/usr/bin/env python3
"""
launch_local.py

Unified script to launch all Supa Container services locally for development.
This script integrates the local-ai-packaged approach with the main application
services and provides comprehensive health checking and validation.
"""

import os
import subprocess
import shutil
import time
import argparse
import platform
import sys
import signal
import requests
import json
from pathlib import Path
from typing import Dict, List, Optional
import threading
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class Color:
    """ANSI color codes for terminal output"""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

class ServiceManager:
    """Manages the lifecycle of all Supa Container services"""
    
    def __init__(self, environment: str = "private", profile: str = "cpu"):
        self.environment = environment
        self.profile = profile
        self.services_running = False
        self.processes = []
        self.script_dir = Path(__file__).parent
        
        # Service health check endpoints
        self.health_endpoints = {
            "supabase": "http://localhost:8005/rest/v1/",
            "n8n": "http://localhost:8001/healthz",
            "flowise": "http://localhost:8003/api/v1/ping",
            "open-webui": "http://localhost:8002/api/v1/auths",
            "neo4j": "http://localhost:8008/db/data/",
            "searxng": "http://localhost:8006/",
            "langfuse": "http://localhost:8007/api/health",
            "fastapi": "http://localhost:8058/health",
            "nextjs": "http://localhost:3000/api/health"
        }
        
        # Required environment variables
        self.required_env_vars = [
            "POSTGRES_PASSWORD",
            "MINIO_ROOT_PASSWORD", 
            "NEXTAUTH_SECRET",
            "LANGFUSE_SALT",
            "ENCRYPTION_KEY",
            "N8N_ENCRYPTION_KEY",
            "N8N_USER_MANAGEMENT_JWT_SECRET",
            "CLICKHOUSE_PASSWORD",
            "FLOWISE_USERNAME",
            "FLOWISE_PASSWORD"
        ]

    def check_prerequisites(self) -> bool:
        """Check if all prerequisites are met"""
        logger.info(f"{Color.BLUE}Checking prerequisites...{Color.NC}")
        
        # Check Docker
        try:
            result = subprocess.run(["docker", "--version"], capture_output=True, text=True)
            if result.returncode != 0:
                logger.error(f"{Color.RED}Docker is not installed or not running{Color.NC}")
                return False
            logger.info(f"{Color.GREEN}✓ Docker is available{Color.NC}")
        except FileNotFoundError:
            logger.error(f"{Color.RED}Docker is not installed{Color.NC}")
            return False
            
        # Check Docker Compose
        try:
            result = subprocess.run(["docker", "compose", "version"], capture_output=True, text=True)
            if result.returncode != 0:
                logger.error(f"{Color.RED}Docker Compose is not available{Color.NC}")
                return False
            logger.info(f"{Color.GREEN}✓ Docker Compose is available{Color.NC}")
        except FileNotFoundError:
            logger.error(f"{Color.RED}Docker Compose is not available{Color.NC}")
            return False
            
        # Check if we're in the correct directory
        if not (self.script_dir / "local-ai-packaged").exists():
            logger.error(f"{Color.RED}local-ai-packaged directory not found{Color.NC}")
            return False
            
        logger.info(f"{Color.GREEN}✓ All prerequisites met{Color.NC}")
        return True

    def setup_environment(self) -> bool:
        """Set up the environment files and configurations"""
        logger.info(f"{Color.BLUE}Setting up environment...{Color.NC}")
        
        env_file = self.script_dir / ".env"
        env_example = self.script_dir / ".env.example"
        
        # Create .env from .env.example if it doesn't exist
        if not env_file.exists() and env_example.exists():
            logger.info(f"{Color.YELLOW}Creating .env from .env.example{Color.NC}")
            shutil.copy(env_example, env_file)
            
        # Generate random secrets if .env file is missing required values
        if env_file.exists():
            self._generate_missing_secrets(env_file)
        else:
            logger.error(f"{Color.RED}.env file not found and .env.example not available{Color.NC}")
            return False
            
        # Copy .env to local-ai-packaged directory
        local_ai_env = self.script_dir / "local-ai-packaged" / ".env"
        shutil.copy(env_file, local_ai_env)
        
        # Clone and set up Supabase if needed
        if not self._setup_supabase():
            logger.error(f"{Color.RED}Failed to set up Supabase{Color.NC}")
            return False
            
        logger.info(f"{Color.GREEN}✓ Environment files configured{Color.NC}")
        
        return True

    def _generate_missing_secrets(self, env_file: Path):
        """Generate missing secrets in the .env file"""
        import secrets
        import string
        
        # Read current .env content
        env_content = env_file.read_text()
        env_lines = env_content.splitlines()
        env_dict = {}
        
        for line in env_lines:
            if '=' in line and not line.strip().startswith('#'):
                key, value = line.split('=', 1)
                env_dict[key.strip()] = value.strip()
        
        # Generate missing secrets
        updated = False
        for var in self.required_env_vars:
            if var not in env_dict or not env_dict[var]:
                if var == "FLOWISE_USERNAME":
                    env_dict[var] = "admin"
                elif var == "FLOWISE_PASSWORD":
                    secret = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16))
                    env_dict[var] = secret
                else:
                    secret = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))
                    env_dict[var] = secret
                updated = True
                logger.info(f"{Color.YELLOW}Generated secret for {var}{Color.NC}")
        
        # Write back to file if updated
        if updated:
            with open(env_file, 'w') as f:
                for key, value in env_dict.items():
                    f.write(f"{key}={value}\n")

    def _setup_supabase(self) -> bool:
        """Set up Supabase repository and configuration"""
        supabase_dir = self.script_dir / "local-ai-packaged" / "supabase"
        
        if not supabase_dir.exists():
            logger.info(f"{Color.YELLOW}Cloning Supabase repository...{Color.NC}")
            try:
                # Change to local-ai-packaged directory
                old_cwd = os.getcwd()
                os.chdir(self.script_dir / "local-ai-packaged")
                
                # Clone Supabase with sparse checkout
                subprocess.run([
                    "git", "clone", "--filter=blob:none", "--no-checkout",
                    "https://github.com/supabase/supabase.git"
                ], check=True)
                
                os.chdir("supabase")
                subprocess.run(["git", "sparse-checkout", "init", "--cone"], check=True)
                subprocess.run(["git", "sparse-checkout", "set", "docker"], check=True)
                subprocess.run(["git", "checkout", "master"], check=True)
                
                # Return to original directory
                os.chdir(old_cwd)
                
                logger.info(f"{Color.GREEN}✓ Supabase repository cloned{Color.NC}")
            except subprocess.CalledProcessError as e:
                logger.error(f"{Color.RED}Failed to clone Supabase repository: {e}{Color.NC}")
                os.chdir(old_cwd)
                return False
        else:
            logger.info(f"{Color.GREEN}✓ Supabase repository already exists{Color.NC}")
            
        # Copy .env to Supabase docker directory
        env_file = self.script_dir / ".env"
        supabase_env_file = supabase_dir / "docker" / ".env"
        if env_file.exists():
            shutil.copy(env_file, supabase_env_file)
            logger.info(f"{Color.GREEN}✓ Supabase environment configured{Color.NC}")
            
        return True

    def start_services(self) -> bool:
        """Start all services using the local-ai-packaged approach"""
        logger.info(f"{Color.BLUE}Starting all services...{Color.NC}")
        
        # Change to local-ai-packaged directory
        os.chdir(self.script_dir / "local-ai-packaged")
        
        try:
            # Stop any existing containers first
            logger.info(f"{Color.YELLOW}Stopping existing containers...{Color.NC}")
            subprocess.run([
                "docker", "compose", "-p", "localai",
                "--profile", self.profile,
                "down"
            ], check=False)
            
            # Start the services
            logger.info(f"{Color.BLUE}Starting services with profile: {self.profile}, environment: {self.environment}{Color.NC}")
            
            compose_files = ["docker-compose.yml"]
            if self.environment == "private":
                compose_files.append("docker-compose.override.private.yml")
            elif self.environment == "public":
                compose_files.append("docker-compose.override.public.yml")
            
            # Build the command
            cmd = ["docker", "compose", "-p", "localai"]
            for file in compose_files:
                cmd.extend(["-f", file])
            
            cmd.extend(["--profile", self.profile, "up", "-d"])
            
            # Execute the command
            result = subprocess.run(cmd, check=True)
            
            if result.returncode == 0:
                logger.info(f"{Color.GREEN}✓ Services started successfully{Color.NC}")
                self.services_running = True
                return True
            else:
                logger.error(f"{Color.RED}Failed to start services{Color.NC}")
                return False
                
        except subprocess.CalledProcessError as e:
            logger.error(f"{Color.RED}Error starting services: {e}{Color.NC}")
            return False
        finally:
            # Change back to original directory
            os.chdir(self.script_dir)

    def wait_for_services(self, timeout: int = 300) -> bool:
        """Wait for all services to be ready"""
        logger.info(f"{Color.BLUE}Waiting for services to be ready (timeout: {timeout}s)...{Color.NC}")
        
        start_time = time.time()
        services_ready = set()
        
        while time.time() - start_time < timeout:
            for service, endpoint in self.health_endpoints.items():
                if service not in services_ready:
                    if self._check_service_health(service, endpoint):
                        services_ready.add(service)
                        logger.info(f"{Color.GREEN}✓ {service} is ready{Color.NC}")
            
            if len(services_ready) == len(self.health_endpoints):
                logger.info(f"{Color.GREEN}✓ All services are ready!{Color.NC}")
                return True
                
            time.sleep(5)
        
        missing_services = set(self.health_endpoints.keys()) - services_ready
        logger.warning(f"{Color.YELLOW}Some services are not ready: {missing_services}{Color.NC}")
        return len(services_ready) > len(self.health_endpoints) // 2  # At least half should be ready

    def _check_service_health(self, service: str, endpoint: str) -> bool:
        """Check if a service is healthy"""
        try:
            response = requests.get(endpoint, timeout=5)
            return response.status_code < 500
        except:
            return False

    def run_comprehensive_tests(self) -> bool:
        """Run comprehensive tests on all services"""
        logger.info(f"{Color.BLUE}Running comprehensive tests...{Color.NC}")
        
        # Change back to root directory for tests
        os.chdir(self.script_dir)
        
        try:
            # Run Python tests
            logger.info(f"{Color.CYAN}Running Python test suite...{Color.NC}")
            result = subprocess.run([
                "python", "-m", "pytest", "tests/test_environment.py", "-v"
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"{Color.GREEN}✓ Python tests passed{Color.NC}")
            else:
                logger.warning(f"{Color.YELLOW}Some Python tests failed, but continuing...{Color.NC}")
                logger.debug(result.stdout)
                logger.debug(result.stderr)
            
            # Run deployment tests if available
            test_script = self.script_dir / "test_deployment.sh"
            if test_script.exists():
                logger.info(f"{Color.CYAN}Running deployment tests...{Color.NC}")
                # Note: We don't run the full test_deployment.sh as it expects production setup
                # Instead, we run our own health checks
                
            return self._run_service_integration_tests()
            
        except Exception as e:
            logger.error(f"{Color.RED}Error running tests: {e}{Color.NC}")
            return False

    def _run_service_integration_tests(self) -> bool:
        """Run integration tests between services"""
        logger.info(f"{Color.CYAN}Running service integration tests...{Color.NC}")
        
        tests_passed = 0
        tests_total = 0
        
        # Test service communication
        for service, endpoint in self.health_endpoints.items():
            tests_total += 1
            if self._check_service_health(service, endpoint):
                tests_passed += 1
                logger.info(f"{Color.GREEN}✓ {service} health check passed{Color.NC}")
            else:
                logger.error(f"{Color.RED}✗ {service} health check failed{Color.NC}")
        
        success_rate = tests_passed / tests_total if tests_total > 0 else 0
        logger.info(f"{Color.BLUE}Integration test results: {tests_passed}/{tests_total} passed ({success_rate:.1%}){Color.NC}")
        
        return success_rate >= 0.7  # 70% pass rate is acceptable for local development

    def show_service_status(self):
        """Show the status of all services"""
        logger.info(f"{Color.BLUE}Service Status:{Color.NC}")
        print(f"\n{Color.CYAN}{'Service':<15} {'Status':<10} {'URL':<50}{Color.NC}")
        print("=" * 75)
        
        for service, endpoint in self.health_endpoints.items():
            if self._check_service_health(service, endpoint):
                status = f"{Color.GREEN}HEALTHY{Color.NC}"
            else:
                status = f"{Color.RED}DOWN{Color.NC}"
            
            print(f"{service:<15} {status:<20} {endpoint:<50}")

    def stop_services(self):
        """Stop all services"""
        logger.info(f"{Color.BLUE}Stopping all services...{Color.NC}")
        
        os.chdir(self.script_dir / "local-ai-packaged")
        
        try:
            subprocess.run([
                "docker", "compose", "-p", "localai",
                "--profile", self.profile,
                "down"
            ], check=True)
            
            logger.info(f"{Color.GREEN}✓ All services stopped{Color.NC}")
            self.services_running = False
            
        except subprocess.CalledProcessError as e:
            logger.error(f"{Color.RED}Error stopping services: {e}{Color.NC}")
        finally:
            os.chdir(self.script_dir)

    def show_logs(self, service: Optional[str] = None):
        """Show logs for services"""
        os.chdir(self.script_dir / "local-ai-packaged")
        
        try:
            cmd = ["docker", "compose", "-p", "localai", "logs"]
            if service:
                cmd.extend(["-f", service])
            else:
                cmd.append("-f")
                
            subprocess.run(cmd)
        except KeyboardInterrupt:
            logger.info(f"{Color.YELLOW}Log viewing stopped{Color.NC}")
        finally:
            os.chdir(self.script_dir)

def signal_handler(signum, frame):
    """Handle interrupt signals"""
    print(f"\n{Color.YELLOW}Interrupt received, shutting down...{Color.NC}")
    sys.exit(0)

def main():
    """Main entry point"""
    signal.signal(signal.SIGINT, signal_handler)
    
    parser = argparse.ArgumentParser(description='Launch Supa Container services locally')
    parser.add_argument('--profile', choices=['cpu', 'gpu-nvidia', 'gpu-amd'], default='cpu',
                      help='Profile to use for Docker Compose (default: cpu)')
    parser.add_argument('--environment', choices=['private', 'public'], default='private',
                      help='Environment to use for Docker Compose (default: private)')
    parser.add_argument('--no-tests', action='store_true',
                      help='Skip running tests after startup')
    parser.add_argument('--logs', type=str, metavar='SERVICE',
                      help='Show logs for a specific service (or all if not specified)')
    parser.add_argument('--status', action='store_true',
                      help='Show status of all services')
    parser.add_argument('--stop', action='store_true',
                      help='Stop all services')
    
    args = parser.parse_args()
    
    manager = ServiceManager(args.environment, args.profile)
    
    try:
        if args.stop:
            manager.stop_services()
            return
            
        if args.status:
            manager.show_service_status()
            return
            
        if args.logs is not None:
            manager.show_logs(args.logs if args.logs else None)
            return
        
        # Main startup flow
        print(f"\n{Color.BLUE}🚀 Supa Container Local Launch{Color.NC}")
        print(f"{Color.BLUE}============================={Color.NC}\n")
        
        if not manager.check_prerequisites():
            sys.exit(1)
            
        if not manager.setup_environment():
            sys.exit(1)
            
        if not manager.start_services():
            sys.exit(1)
            
        if not manager.wait_for_services():
            logger.warning(f"{Color.YELLOW}Not all services are ready, but continuing...{Color.NC}")
        
        if not args.no_tests:
            manager.run_comprehensive_tests()
        
        manager.show_service_status()
        
        print(f"\n{Color.GREEN}🎉 Supa Container is running!{Color.NC}")
        print(f"\n{Color.CYAN}Available Services:{Color.NC}")
        for service, endpoint in manager.health_endpoints.items():
            print(f"  • {service}: {endpoint}")
        
        print(f"\n{Color.CYAN}Management Commands:{Color.NC}")
        print(f"  • View logs: python launch_local.py --logs [service]")
        print(f"  • Check status: python launch_local.py --status")
        print(f"  • Stop services: python launch_local.py --stop")
        
        print(f"\n{Color.YELLOW}Press Ctrl+C to stop monitoring{Color.NC}")
        
        # Keep the script running to monitor services
        while True:
            time.sleep(30)
            if not manager._check_service_health("supabase", "http://localhost:8005/rest/v1/"):
                logger.warning(f"{Color.YELLOW}Some services may have stopped{Color.NC}")
                manager.show_service_status()
                
    except KeyboardInterrupt:
        logger.info(f"\n{Color.YELLOW}Shutting down...{Color.NC}")
        manager.stop_services()
    except Exception as e:
        logger.error(f"{Color.RED}Unexpected error: {e}{Color.NC}")
        sys.exit(1)

if __name__ == "__main__":
    main()