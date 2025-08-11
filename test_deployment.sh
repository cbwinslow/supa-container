#!/bin/bash

# =============================================================================
# Comprehensive Testing Script for AI-Enhanced Supa Container
# =============================================================================
# This script performs thorough testing of all platform components to ensure
# proper deployment and functionality.
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
APP_ROOT="${APP_ROOT:-/opt/supa-container}"
ENV_FILE="$APP_ROOT/.env"
TEST_RESULTS_FILE="/tmp/supa_container_test_results.log"

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo -e "${RED}❌ ERROR: .env file not found at $ENV_FILE${NC}"
    exit 1
fi

# Initialize test results
echo "AI-Enhanced Supa Container Test Results - $(date)" > "$TEST_RESULTS_FILE"
echo "=============================================" >> "$TEST_RESULTS_FILE"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to run tests
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -e "${CYAN}Testing: $test_name${NC}"
    
    if eval "$test_command" > /dev/null 2>&1; then
        if [ "$expected_result" = "0" ]; then
            echo -e "  ✅ PASS: $test_name"
            echo "PASS: $test_name" >> "$TEST_RESULTS_FILE"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "  ❌ FAIL: $test_name (unexpected success)"
            echo "FAIL: $test_name (unexpected success)" >> "$TEST_RESULTS_FILE"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        if [ "$expected_result" = "1" ]; then
            echo -e "  ✅ PASS: $test_name (expected failure)"
            echo "PASS: $test_name (expected failure)" >> "$TEST_RESULTS_FILE"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "  ❌ FAIL: $test_name"
            echo "FAIL: $test_name" >> "$TEST_RESULTS_FILE"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    fi
}

# Function to test HTTP endpoint
test_http_endpoint() {
    local endpoint="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-10}"
    
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" "$endpoint" || echo "000")
    
    if [ "$status_code" = "$expected_status" ]; then
        return 0
    else
        return 1
    fi
}

# Display banner
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}🧪 AI-Enhanced Supa Container - Comprehensive Testing Suite${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${CYAN}Domain:${NC} ${GREEN}${DOMAIN}${NC}"
echo -e "${CYAN}Test Results:${NC} ${GREEN}${TEST_RESULTS_FILE}${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo

# Navigate to app directory
cd "$APP_ROOT"

# --- Test 1: Docker Environment ---
echo -e "${PURPLE}[1/10] Testing Docker Environment...${NC}"

run_test "Docker daemon running" "systemctl is-active docker"
run_test "Docker Compose available" "which docker-compose"
run_test "Docker permissions" "docker ps"
run_test "Container runtime" "docker info"

echo

# --- Test 2: Container Status ---
echo -e "${PURPLE}[2/10] Testing Container Status...${NC}"

# Core containers
CORE_CONTAINERS=("traefik" "postgres" "neo4j" "rabbitmq" "redis")
for container in "${CORE_CONTAINERS[@]}"; do
    run_test "$container container running" "docker-compose ps $container | grep -q 'Up'"
done

# Application containers
APP_CONTAINERS=("fastapi_app" "nextjs_app" "localai")
for container in "${APP_CONTAINERS[@]}"; do
    run_test "$container container running" "docker-compose ps $container | grep -q 'Up'"
done

# AI containers
AI_CONTAINERS=("ai_orchestrator" "self_healing_agent" "monitoring_agent" "data_manager_agent")
for container in "${AI_CONTAINERS[@]}"; do
    run_test "$container container running" "docker-compose ps $container | grep -q 'Up'"
done

echo

# --- Test 3: Network Connectivity ---
echo -e "${PURPLE}[3/10] Testing Network Connectivity...${NC}"

run_test "Docker network exists" "docker network ls | grep -q devops-net"
run_test "Traefik HTTP port" "netstat -tlnp | grep -q :80"
run_test "Traefik HTTPS port" "netstat -tlnp | grep -q :443"
run_test "Internal network resolution" "docker exec postgres ping -c 1 rabbitmq"

echo

# --- Test 4: Database Connectivity ---
echo -e "${PURPLE}[4/10] Testing Database Connectivity...${NC}"

run_test "PostgreSQL ready" "docker exec postgres pg_isready -U postgres"
run_test "PostgreSQL connection" "docker exec postgres psql -U postgres -c 'SELECT 1'"
run_test "Neo4j ready" "docker exec neo4j cypher-shell -u neo4j -p ${NEO4J_PASSWORD} 'RETURN 1'"
run_test "Redis ready" "docker exec redis redis-cli ping | grep -q PONG"
run_test "Qdrant ready" "docker exec qdrant curl -s http://localhost:6333/collections"

echo

# --- Test 5: Message Broker ---
echo -e "${PURPLE}[5/10] Testing Message Broker...${NC}"

run_test "RabbitMQ ready" "docker exec rabbitmq rabbitmq-diagnostics ping"
run_test "RabbitMQ management" "docker exec rabbitmq rabbitmqctl status"
run_test "RabbitMQ queues" "docker exec rabbitmq rabbitmqctl list_queues"
run_test "RabbitMQ users" "docker exec rabbitmq rabbitmqctl list_users"

echo

# --- Test 6: HTTP Services ---
echo -e "${PURPLE}[6/10] Testing HTTP Services...${NC}"

# Test internal endpoints
run_test "Traefik internal API" "test_http_endpoint http://localhost:8080/ping 200 5"
run_test "FastAPI health" "test_http_endpoint http://localhost:${APP_PORT}/health 200 10"
run_test "Grafana internal" "test_http_endpoint http://localhost:3000/api/health 200 10"

# Test external endpoints (if DNS is configured)
if nslookup "${DOMAIN}" > /dev/null 2>&1; then
    echo -e "${YELLOW}DNS configured, testing external endpoints...${NC}"
    run_test "Main domain HTTPS redirect" "test_http_endpoint https://${DOMAIN} 200 15"
    run_test "API domain" "test_http_endpoint https://api.${DOMAIN}/docs 200 15"
    run_test "Grafana domain" "test_http_endpoint https://grafana.${DOMAIN} 200 15"
    run_test "Traefik dashboard" "test_http_endpoint https://traefik.${DOMAIN} 401 10"
else
    echo -e "${YELLOW}DNS not configured, skipping external endpoint tests...${NC}"
fi

echo

# --- Test 7: AI Components ---
echo -e "${PURPLE}[7/10] Testing AI Components...${NC}"

# Test AI Orchestrator
run_test "AI Orchestrator health" "docker exec ai_orchestrator python -c 'import requests; requests.get(\"http://localhost:8000/health\", timeout=10)'"

# Test LocalAI
run_test "LocalAI service" "docker exec localai curl -s http://localhost:8080/v1/models"

# Test agent communication
run_test "Agent message queues" "docker exec rabbitmq rabbitmqctl list_queues | grep -E '(self_healing|monitoring|data_manager)'"

echo

# --- Test 8: Monitoring Stack ---
echo -e "${PURPLE}[8/10] Testing Monitoring Stack...${NC}"

run_test "Prometheus metrics" "test_http_endpoint http://localhost:9090/metrics 200 10"
run_test "Grafana API" "test_http_endpoint http://localhost:3000/api/health 200 10"
run_test "Loki ready" "test_http_endpoint http://localhost:3100/ready 200 10"
run_test "Jaeger API" "test_http_endpoint http://localhost:16686/api/services 200 10"

# Test metric collection
run_test "Prometheus targets" "curl -s http://localhost:9090/api/v1/targets | grep -q '\"health\":\"up\"'"

echo

# --- Test 9: Security Features ---
echo -e "${PURPLE}[9/10] Testing Security Features...${NC}"

run_test "UFW firewall active" "ufw status | grep -q 'Status: active'"
run_test "Fail2ban running" "systemctl is-active fail2ban"
run_test "SSL certificates" "test -f $APP_ROOT/traefik/acme.json"

# Test that non-essential ports are closed
run_test "PostgreSQL not exposed" "! netstat -tlnp | grep -q ':5432.*0.0.0.0'" 
run_test "Neo4j not exposed" "! netstat -tlnp | grep -q ':7474.*0.0.0.0'"
run_test "RabbitMQ not exposed" "! netstat -tlnp | grep -q ':5672.*0.0.0.0'"

echo

# --- Test 10: Data Persistence ---
echo -e "${PURPLE}[10/10] Testing Data Persistence...${NC}"

# Test database writes
run_test "PostgreSQL write test" "docker exec postgres psql -U postgres -c 'CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, data TEXT);'"
run_test "PostgreSQL data persistence" "docker exec postgres psql -U postgres -c 'INSERT INTO test_table (data) VALUES (\"test_data\");'"

# Test Neo4j writes
run_test "Neo4j write test" "docker exec neo4j cypher-shell -u neo4j -p ${NEO4J_PASSWORD} 'CREATE (n:TestNode {name: \"test\"}) RETURN n'"

# Test Redis writes
run_test "Redis write test" "docker exec redis redis-cli set test_key test_value"
run_test "Redis read test" "docker exec redis redis-cli get test_key | grep -q test_value"

# Test volume persistence
run_test "Docker volumes exist" "docker volume ls | grep -E '(postgres_data|neo4j_data|redis_data)'"

echo

# --- Performance Tests ---
echo -e "${PURPLE}[BONUS] Running Performance Tests...${NC}"

# Memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [ "$MEMORY_USAGE" -lt 90 ]; then
    echo -e "  ✅ Memory usage: ${MEMORY_USAGE}% (healthy)"
    echo "PASS: Memory usage ${MEMORY_USAGE}%" >> "$TEST_RESULTS_FILE"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  ⚠️  Memory usage: ${MEMORY_USAGE}% (high)"
    echo "WARN: Memory usage ${MEMORY_USAGE}%" >> "$TEST_RESULTS_FILE"
fi

# Disk usage
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    echo -e "  ✅ Disk usage: ${DISK_USAGE}% (healthy)"
    echo "PASS: Disk usage ${DISK_USAGE}%" >> "$TEST_RESULTS_FILE"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  ⚠️  Disk usage: ${DISK_USAGE}% (high)"
    echo "WARN: Disk usage ${DISK_USAGE}%" >> "$TEST_RESULTS_FILE"
fi

TESTS_TOTAL=$((TESTS_TOTAL + 2))

# --- Load Testing ---
echo -e "${PURPLE}[BONUS] Basic Load Testing...${NC}"

if command -v ab > /dev/null 2>&1; then
    echo -e "${YELLOW}Running Apache Bench load test...${NC}"
    if ab -n 100 -c 10 http://localhost:${APP_PORT}/health > /tmp/ab_results.txt 2>&1; then
        REQUESTS_PER_SEC=$(grep "Requests per second" /tmp/ab_results.txt | awk '{print $4}')
        echo -e "  ✅ Load test completed: ${REQUESTS_PER_SEC} req/sec"
        echo "PASS: Load test ${REQUESTS_PER_SEC} req/sec" >> "$TEST_RESULTS_FILE"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ❌ Load test failed"
        echo "FAIL: Load test" >> "$TEST_RESULTS_FILE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
    echo -e "${YELLOW}Apache Bench not available, skipping load test...${NC}"
fi

echo

# --- Test Summary ---
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${GREEN}🧪 Test Results Summary${NC}"
echo -e "${BLUE}=============================================================================${NC}"
echo
echo -e "${CYAN}Total Tests:${NC} $TESTS_TOTAL"
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Failed:${NC} $TESTS_FAILED"

# Calculate success rate
SUCCESS_RATE=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
echo -e "${CYAN}Success Rate:${NC} ${SUCCESS_RATE}%"

echo
echo "=============================================" >> "$TEST_RESULTS_FILE"
echo "SUMMARY: $TESTS_PASSED/$TESTS_TOTAL tests passed (${SUCCESS_RATE}%)" >> "$TEST_RESULTS_FILE"
echo "Test completed at: $(date)" >> "$TEST_RESULTS_FILE"

if [ "$SUCCESS_RATE" -ge 95 ]; then
    echo -e "${GREEN}🎉 Excellent! Your platform is working correctly.${NC}"
    echo -e "${GREEN}✅ All critical systems are operational.${NC}"
elif [ "$SUCCESS_RATE" -ge 85 ]; then
    echo -e "${YELLOW}⚠️  Good! Most systems are working, but some issues detected.${NC}"
    echo -e "${YELLOW}📋 Review the failed tests and consider investigating.${NC}"
else
    echo -e "${RED}❌ Issues detected! Multiple systems need attention.${NC}"
    echo -e "${RED}🔧 Please review the logs and fix the failing components.${NC}"
fi

echo
echo -e "${CYAN}📊 Detailed Results:${NC} ${TEST_RESULTS_FILE}"
echo -e "${CYAN}📋 Next Steps:${NC}"

if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "   1. Review failed tests above"
    echo -e "   2. Check service logs: ${CYAN}cd $APP_ROOT && docker-compose logs${NC}"
    echo -e "   3. Monitor system status: ${CYAN}sudo ./monitor_platform.sh${NC}"
    echo -e "   4. Restart failed services if necessary"
fi

echo -e "   • Monitor ongoing health: ${CYAN}https://grafana.${DOMAIN}${NC}"
echo -e "   • Check application logs regularly"
echo -e "   • Run this test periodically to ensure continued health"

echo
echo -e "${BLUE}=============================================================================${NC}"

# Set exit code based on results
if [ "$SUCCESS_RATE" -ge 85 ]; then
    exit 0
else
    exit 1
fi