#!/bin/bash

# =============================================================================
# Simple Local Launch Script for Supa Container
# =============================================================================
# This script provides a simple interface to launch all Supa Container services
# locally for development and testing.
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to display usage
usage() {
    echo -e "${BLUE}Supa Container Local Launcher${NC}"
    echo -e "${BLUE}============================${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  start     Start all services (default)"
    echo "  stop      Stop all services"
    echo "  restart   Restart all services"
    echo "  status    Show service status"
    echo "  logs      Show service logs [service_name]"
    echo "  test      Run comprehensive tests"
    echo "  clean     Clean up containers and volumes"
    echo ""
    echo "Options:"
    echo "  --profile [cpu|gpu-nvidia|gpu-amd]  Hardware profile (default: cpu)"
    echo "  --env [private|public]              Environment (default: private)"
    echo "  --no-tests                          Skip tests after startup"
    echo "  --help                              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                           # Start with defaults"
    echo "  $0 start --profile gpu-nvidia # Start with NVIDIA GPU support"
    echo "  $0 logs postgres             # Show PostgreSQL logs"
    echo "  $0 test                      # Run comprehensive tests"
}

# Function to check if Python is available
check_python() {
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Error: Python 3 is required but not installed${NC}"
        exit 1
    fi
    
    # Check if required Python packages are available
    if ! python3 -c "import requests" &> /dev/null; then
        echo -e "${YELLOW}Installing required Python packages...${NC}"
        python3 -m pip install requests docker pytest pytest-asyncio &> /dev/null || {
            echo -e "${RED}Failed to install required packages${NC}"
            exit 1
        }
    fi
}

# Function to install missing Python dependencies
install_dependencies() {
    echo -e "${YELLOW}Checking and installing dependencies...${NC}"
    
    # Create a requirements file for the launcher
    cat > /tmp/launcher_requirements.txt << EOF
requests>=2.25.0
docker>=5.0.0
pytest>=6.0.0
pytest-asyncio>=0.18.0
asyncpg>=0.24.0
neo4j>=4.4.0
aiohttp>=3.7.0
EOF
    
    python3 -m pip install -r /tmp/launcher_requirements.txt || {
        echo -e "${YELLOW}Some packages failed to install, continuing anyway...${NC}"
    }
    
    rm -f /tmp/launcher_requirements.txt
}

# Function to run the Python launcher
run_launcher() {
    cd "$SCRIPT_DIR"
    check_python
    
    # Install dependencies if needed
    if [ "$1" = "start" ] || [ "$1" = "test" ]; then
        install_dependencies
    fi
    
    python3 launch_local.py "$@"
}

# Main script logic
main() {
    local command="${1:-start}"
    
    case "$command" in
        "help"|"--help"|"-h")
            usage
            exit 0
            ;;
        "start")
            shift
            echo -e "${GREEN}🚀 Starting Supa Container services...${NC}"
            run_launcher start "$@"
            ;;
        "stop")
            echo -e "${YELLOW}🛑 Stopping Supa Container services...${NC}"
            run_launcher --stop
            ;;
        "restart")
            echo -e "${YELLOW}🔄 Restarting Supa Container services...${NC}"
            run_launcher --stop
            sleep 5
            shift
            run_launcher start "$@"
            ;;
        "status")
            echo -e "${CYAN}📊 Checking service status...${NC}"
            run_launcher --status
            ;;
        "logs")
            shift
            service_name="${1:-}"
            if [ -n "$service_name" ]; then
                echo -e "${CYAN}📜 Showing logs for $service_name...${NC}"
                run_launcher --logs "$service_name"
            else
                echo -e "${CYAN}📜 Showing all service logs...${NC}"
                run_launcher --logs
            fi
            ;;
        "test")
            echo -e "${PURPLE}🧪 Running comprehensive tests...${NC}"
            check_python
            install_dependencies
            cd "$SCRIPT_DIR"
            python3 -m pytest test_comprehensive.py -v
            ;;
        "clean")
            echo -e "${RED}🧹 Cleaning up containers and volumes...${NC}"
            cd "$SCRIPT_DIR/local-ai-packaged"
            docker compose -p localai down -v --remove-orphans || true
            docker system prune -f || true
            echo -e "${GREEN}✅ Cleanup completed${NC}"
            ;;
        *)
            if [[ "$command" =~ ^-- ]]; then
                # Command starts with --, treat as start command with options
                echo -e "${GREEN}🚀 Starting Supa Container services...${NC}"
                run_launcher start "$@"
            else
                echo -e "${RED}Unknown command: $command${NC}"
                usage
                exit 1
            fi
            ;;
    esac
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi