#!/usr/bin/env python3
"""
launch_simple.py

Simplified launcher that starts core services without all the complex dependencies.
This is designed to get the FastAPI backend and core services running quickly.
"""

import os
import subprocess
import time
import argparse
import requests
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class Color:
    """ANSI color codes for terminal output"""

    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    PURPLE = "\033[0;35m"
    CYAN = "\033[0;36m"
    NC = "\033[0m"  # No Color


def run_command(cmd, cwd=None, check=True):
    """Run a command and return the result"""
    logger.info(f"Running: {' '.join(cmd)}")
    return subprocess.run(cmd, cwd=cwd, check=check, capture_output=True, text=True)


def check_prerequisites():
    """Check if Docker and Docker Compose are available"""
    try:
        run_command(["docker", "--version"])
        run_command(["docker", "compose", "version"])
        logger.info(f"{Color.GREEN}✓ Docker and Docker Compose are available{Color.NC}")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        logger.error(
            f"{Color.RED}Docker or Docker Compose not available: {e}{Color.NC}"
        )
        return False


def start_core_services():
    """Start core services using individual Docker commands"""
    logger.info(f"{Color.BLUE}Starting core services...{Color.NC}")

    # Create a network for our services
    try:
        run_command(["docker", "network", "create", "supa-network"], check=False)
    except:
        pass  # Network might already exist

    services_started = []

    # Start PostgreSQL
    try:
        logger.info(f"{Color.CYAN}Starting PostgreSQL...{Color.NC}")
        run_command(
            [
                "docker",
                "run",
                "-d",
                "--name",
                "supa-postgres",
                "--network",
                "supa-network",
                "-e",
                "POSTGRES_PASSWORD=password",
                "-e",
                "POSTGRES_DB=postgres",
                "-p",
                "5432:5432",
                "postgres:15",
            ],
            check=False,
        )
        services_started.append("PostgreSQL")
        logger.info(f"{Color.GREEN}✓ PostgreSQL started{Color.NC}")
    except Exception as e:
        logger.warning(
            f"{Color.YELLOW}PostgreSQL might already be running: {e}{Color.NC}"
        )

    # Start Redis
    try:
        logger.info(f"{Color.CYAN}Starting Redis...{Color.NC}")
        run_command(
            [
                "docker",
                "run",
                "-d",
                "--name",
                "supa-redis",
                "--network",
                "supa-network",
                "-p",
                "6379:6379",
                "redis:7-alpine",
            ],
            check=False,
        )
        services_started.append("Redis")
        logger.info(f"{Color.GREEN}✓ Redis started{Color.NC}")
    except Exception as e:
        logger.warning(f"{Color.YELLOW}Redis might already be running: {e}{Color.NC}")

    # Start Neo4j
    try:
        logger.info(f"{Color.CYAN}Starting Neo4j...{Color.NC}")
        run_command(
            [
                "docker",
                "run",
                "-d",
                "--name",
                "supa-neo4j",
                "--network",
                "supa-network",
                "-e",
                "NEO4J_AUTH=neo4j/password",
                "-p",
                "7474:7474",
                "-p",
                "7687:7687",
                "neo4j:latest",
            ],
            check=False,
        )
        services_started.append("Neo4j")
        logger.info(f"{Color.GREEN}✓ Neo4j started{Color.NC}")
    except Exception as e:
        logger.warning(f"{Color.YELLOW}Neo4j might already be running: {e}{Color.NC}")

    return services_started


def wait_for_services():
    """Wait for services to be ready"""
    logger.info(f"{Color.BLUE}Waiting for services to be ready...{Color.NC}")

    services = {
        "PostgreSQL": ("localhost", 5432),
        "Redis": ("localhost", 6379),
        "Neo4j": ("http://localhost:7474", None),
    }

    for service_name, (host, port) in services.items():
        if port:
            # TCP port check
            import socket

            for attempt in range(30):
                try:
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.settimeout(1)
                    result = sock.connect_ex((host, port))
                    sock.close()
                    if result == 0:
                        logger.info(f"{Color.GREEN}✓ {service_name} is ready{Color.NC}")
                        break
                except:
                    pass
                time.sleep(2)
            else:
                logger.warning(
                    f"{Color.YELLOW}{service_name} might not be ready{Color.NC}"
                )
        else:
            # HTTP check
            for attempt in range(30):
                try:
                    response = requests.get(host, timeout=5)
                    if response.status_code < 500:
                        logger.info(f"{Color.GREEN}✓ {service_name} is ready{Color.NC}")
                        break
                except:
                    pass
                time.sleep(2)
            else:
                logger.warning(
                    f"{Color.YELLOW}{service_name} might not be ready{Color.NC}"
                )


def start_fastapi():
    """Start the FastAPI application"""
    logger.info(f"{Color.BLUE}Starting FastAPI application...{Color.NC}")

    script_dir = Path(__file__).parent

    # Set environment variables
    env = os.environ.copy()
    env.update(
        {
            "DATABASE_URL": "postgresql://postgres:password@localhost:5432/postgres",
            "REDIS_URL": "redis://localhost:6379",
            "NEO4J_URI": "bolt://localhost:7687",
            "NEO4J_USER": "neo4j",
            "NEO4J_PASSWORD": "password",
        }
    )

    # Start FastAPI with uvicorn
    try:
        logger.info(f"{Color.CYAN}Installing FastAPI dependencies...{Color.NC}")
        subprocess.run(
            ["pip", "install", "-r", "src/fastapi_app/requirements.txt"],
            cwd=script_dir,
            env=env,
            check=False,
            capture_output=True,
        )

        logger.info(f"{Color.CYAN}Starting FastAPI server on port 8058...{Color.NC}")
        process = subprocess.Popen(
            [
                "python",
                "-m",
                "uvicorn",
                "api:app",
                "--host",
                "0.0.0.0",
                "--port",
                "8058",
                "--reload",
            ],
            cwd=script_dir / "src" / "fastapi_app",
            env=env,
        )

        # Wait a bit for startup
        time.sleep(5)

        # Check if FastAPI is responding
        try:
            response = requests.get("http://localhost:8058/health", timeout=10)
            if response.status_code == 200:
                logger.info(f"{Color.GREEN}✓ FastAPI is running and healthy{Color.NC}")
                return process
            else:
                logger.warning(
                    f"{Color.YELLOW}FastAPI responded with status {response.status_code}{Color.NC}"
                )
                return process
        except Exception as e:
            logger.warning(
                f"{Color.YELLOW}Could not check FastAPI health: {e}{Color.NC}"
            )
            return process

    except Exception as e:
        logger.error(f"{Color.RED}Failed to start FastAPI: {e}{Color.NC}")
        return None


def stop_services():
    """Stop all services"""
    logger.info(f"{Color.BLUE}Stopping services...{Color.NC}")

    containers = ["supa-postgres", "supa-redis", "supa-neo4j"]

    for container in containers:
        try:
            run_command(["docker", "stop", container], check=False)
            run_command(["docker", "rm", container], check=False)
            logger.info(f"{Color.GREEN}✓ Stopped {container}{Color.NC}")
        except:
            pass


def show_status():
    """Show service status"""
    logger.info(f"{Color.BLUE}Service Status:{Color.NC}")

    services = {
        "PostgreSQL": "http://localhost:5432",
        "Redis": "http://localhost:6379",
        "Neo4j": "http://localhost:7474",
        "FastAPI": "http://localhost:8058/health",
    }

    for service, url in services.items():
        try:
            if service == "FastAPI":
                response = requests.get(url, timeout=5)
                status = (
                    f"{Color.GREEN}HEALTHY{Color.NC}"
                    if response.status_code == 200
                    else f"{Color.YELLOW}RESPONDING{Color.NC}"
                )
            else:
                # For other services, check if port is open
                import socket

                host, port = url.replace("http://", "").split(":")
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(2)
                result = sock.connect_ex((host, int(port)))
                sock.close()
                status = (
                    f"{Color.GREEN}RUNNING{Color.NC}"
                    if result == 0
                    else f"{Color.RED}DOWN{Color.NC}"
                )
        except Exception as e:
            status = f"{Color.RED}DOWN{Color.NC}"

        print(f"{service:<15} {status}")


def main():
    parser = argparse.ArgumentParser(description="Simple Supa Container launcher")
    parser.add_argument(
        "command",
        nargs="?",
        default="start",
        choices=["start", "stop", "status", "restart"],
        help="Command to execute",
    )

    args = parser.parse_args()

    if args.command == "stop":
        stop_services()
        return

    if args.command == "status":
        show_status()
        return

    if args.command == "restart":
        stop_services()
        time.sleep(3)
        args.command = "start"

    if args.command == "start":
        print(f"\n{Color.BLUE}🚀 Simple Supa Container Launcher{Color.NC}")
        print(f"{Color.BLUE}================================={Color.NC}\n")

        if not check_prerequisites():
            return 1

        # Stop existing services first
        stop_services()
        time.sleep(2)

        services_started = start_core_services()
        wait_for_services()

        fastapi_process = start_fastapi()

        print(f"\n{Color.GREEN}🎉 Core services are running!{Color.NC}")
        print(f"\n{Color.CYAN}Available Services:{Color.NC}")
        print(f"  • FastAPI Backend: http://localhost:8058")
        print(f"  • FastAPI Docs: http://localhost:8058/docs")
        print(f"  • PostgreSQL: localhost:5432")
        print(f"  • Redis: localhost:6379")
        print(f"  • Neo4j Browser: http://localhost:7474")

        print(f"\n{Color.CYAN}Database Credentials:{Color.NC}")
        print(f"  • PostgreSQL: postgres/password")
        print(f"  • Neo4j: neo4j/password")

        print(f"\n{Color.YELLOW}Press Ctrl+C to stop all services{Color.NC}")

        try:
            while True:
                time.sleep(10)
                # Check if FastAPI is still running
                if fastapi_process and fastapi_process.poll() is not None:
                    logger.warning(
                        f"{Color.YELLOW}FastAPI process has stopped{Color.NC}"
                    )
                    break
        except KeyboardInterrupt:
            logger.info(f"\n{Color.YELLOW}Shutting down...{Color.NC}")
            if fastapi_process:
                fastapi_process.terminate()
            stop_services()


if __name__ == "__main__":
    main()
