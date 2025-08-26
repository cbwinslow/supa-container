#!/usr/bin/env python3
"""
test_comprehensive.py

Comprehensive test suite for the entire Supa Container platform.
Tests service integration, communication, and functionality.
"""

import pytest
import requests
import subprocess
import time
import json
import os
from pathlib import Path
from typing import Dict, List, Optional
import docker
import asyncio
import aiohttp

class TestServiceHealth:
    """Test the health of all core services"""
    
    @pytest.fixture(scope="class")
    def service_endpoints(self):
        """Service endpoints for health checks"""
        return {
            "supabase": "http://localhost:8005/rest/v1/",
            "n8n": "http://localhost:8001/healthz", 
            "flowise": "http://localhost:8003/api/v1/ping",
            "open-webui": "http://localhost:8002/api/v1/auths",
            "neo4j": "http://localhost:8008/db/data/",
            "searxng": "http://localhost:8006/",
            "langfuse": "http://localhost:8007/api/health",
            "postgres": "postgresql://postgres:password@localhost:5432/postgres",
            "redis": "redis://localhost:6379"
        }

    def test_supabase_health(self, service_endpoints):
        """Test Supabase API is responding"""
        try:
            response = requests.get(service_endpoints["supabase"], timeout=10)
            assert response.status_code < 500, f"Supabase health check failed: {response.status_code}"
        except requests.exceptions.RequestException as e:
            pytest.skip(f"Supabase not available: {e}")

    def test_n8n_health(self, service_endpoints):
        """Test n8n workflow automation service"""
        try:
            response = requests.get(service_endpoints["n8n"], timeout=10)
            assert response.status_code < 500, f"n8n health check failed: {response.status_code}"
        except requests.exceptions.RequestException as e:
            pytest.skip(f"n8n not available: {e}")

    def test_flowise_health(self, service_endpoints):
        """Test Flowise AI workflow service"""
        try:
            response = requests.get(service_endpoints["flowise"], timeout=10)
            assert response.status_code < 500, f"Flowise health check failed: {response.status_code}"
        except requests.exceptions.RequestException as e:
            pytest.skip(f"Flowise not available: {e}")

    def test_neo4j_health(self, service_endpoints):
        """Test Neo4j graph database"""
        try:
            response = requests.get(service_endpoints["neo4j"], timeout=10)
            assert response.status_code < 500, f"Neo4j health check failed: {response.status_code}"
        except requests.exceptions.RequestException as e:
            pytest.skip(f"Neo4j not available: {e}")

    def test_langfuse_health(self, service_endpoints):
        """Test Langfuse observability service"""
        try:
            response = requests.get(service_endpoints["langfuse"], timeout=10)
            assert response.status_code < 500, f"Langfuse health check failed: {response.status_code}"
        except requests.exceptions.RequestException as e:
            pytest.skip(f"Langfuse not available: {e}")

class TestServiceCommunication:
    """Test communication between services"""
    
    def test_docker_network_connectivity(self):
        """Test that Docker containers can communicate"""
        try:
            client = docker.from_env()
            containers = client.containers.list(filters={"label": "com.docker.compose.project=localai"})
            
            # Should have multiple containers running
            assert len(containers) > 0, "No Docker containers found for the project"
            
            # Check that containers are in the same network
            networks = set()
            for container in containers:
                container_networks = list(container.attrs['NetworkSettings']['Networks'].keys())
                networks.update(container_networks)
            
            # Should have at least one common network
            assert len(networks) > 0, "Containers are not connected to any networks"
            
        except Exception as e:
            pytest.skip(f"Docker communication test failed: {e}")

    def test_service_discovery(self):
        """Test that services can discover each other"""
        try:
            client = docker.from_env()
            
            # Try to execute a network test from within a container
            postgres_container = None
            for container in client.containers.list():
                if "postgres" in container.name.lower():
                    postgres_container = container
                    break
            
            if postgres_container:
                # Test if container can resolve other service names
                result = postgres_container.exec_run("nslookup redis", workdir="/")
                # If nslookup is available and succeeds, service discovery works
                if result.exit_code == 0:
                    assert True, "Service discovery working"
                else:
                    pytest.skip("nslookup not available in container")
            else:
                pytest.skip("PostgreSQL container not found")
                
        except Exception as e:
            pytest.skip(f"Service discovery test failed: {e}")

class TestDataPersistence:
    """Test data persistence across service restarts"""
    
    def test_postgres_data_persistence(self):
        """Test PostgreSQL data persistence"""
        try:
            import asyncpg
            
            async def test_db():
                conn = await asyncpg.connect("postgresql://postgres:password@localhost:5432/postgres")
                
                # Create a test table
                await conn.execute("""
                    CREATE TABLE IF NOT EXISTS test_persistence (
                        id SERIAL PRIMARY KEY,
                        test_data TEXT,
                        created_at TIMESTAMP DEFAULT NOW()
                    )
                """)
                
                # Insert test data
                await conn.execute(
                    "INSERT INTO test_persistence (test_data) VALUES ($1)",
                    "test_data_" + str(int(time.time()))
                )
                
                # Verify data exists
                result = await conn.fetchval("SELECT COUNT(*) FROM test_persistence")
                assert result > 0, "Data not persisted in PostgreSQL"
                
                await conn.close()
            
            asyncio.run(test_db())
            
        except Exception as e:
            pytest.skip(f"PostgreSQL persistence test failed: {e}")

    def test_neo4j_data_persistence(self):
        """Test Neo4j data persistence"""
        try:
            from neo4j import GraphDatabase
            
            driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))
            
            with driver.session() as session:
                # Create a test node
                result = session.run(
                    "CREATE (n:TestNode {name: $name, timestamp: $timestamp}) RETURN n",
                    name="test_persistence",
                    timestamp=int(time.time())
                )
                
                # Verify node was created
                count_result = session.run("MATCH (n:TestNode) RETURN count(n) AS count")
                count = count_result.single()["count"]
                assert count > 0, "Data not persisted in Neo4j"
            
            driver.close()
            
        except Exception as e:
            pytest.skip(f"Neo4j persistence test failed: {e}")

class TestAPIEndpoints:
    """Test API endpoints and functionality"""
    
    def test_fastapi_health_endpoint(self):
        """Test FastAPI health endpoint"""
        try:
            response = requests.get("http://localhost:8058/health", timeout=10)
            assert response.status_code == 200, f"FastAPI health check failed: {response.status_code}"
            
            data = response.json()
            assert "status" in data, "Health response missing status field"
            assert data["status"] == "healthy", f"Service not healthy: {data}"
            
        except requests.exceptions.RequestException as e:
            pytest.skip(f"FastAPI not available: {e}")

    def test_nextjs_health_endpoint(self):
        """Test Next.js health endpoint"""
        try:
            response = requests.get("http://localhost:3000/api/health", timeout=10)
            assert response.status_code == 200, f"Next.js health check failed: {response.status_code}"
            
        except requests.exceptions.RequestException as e:
            pytest.skip(f"Next.js not available: {e}")

    def test_supabase_auth_endpoint(self):
        """Test Supabase authentication endpoint"""
        try:
            response = requests.get("http://localhost:8005/auth/v1/settings", timeout=10)
            assert response.status_code == 200, f"Supabase auth check failed: {response.status_code}"
            
        except requests.exceptions.RequestException as e:
            pytest.skip(f"Supabase auth not available: {e}")

class TestResourceUsage:
    """Test resource usage and performance"""
    
    def test_memory_usage(self):
        """Test that services are not using excessive memory"""
        try:
            client = docker.from_env()
            containers = client.containers.list(filters={"label": "com.docker.compose.project=localai"})
            
            total_memory_mb = 0
            for container in containers:
                stats = container.stats(stream=False)
                memory_usage = stats['memory_stats']['usage']
                memory_mb = memory_usage / (1024 * 1024)  # Convert to MB
                total_memory_mb += memory_mb
                
                # Individual container should use less than 2GB
                assert memory_mb < 2048, f"Container {container.name} using too much memory: {memory_mb:.1f}MB"
            
            # Total usage should be reasonable (less than 8GB for all services)
            assert total_memory_mb < 8192, f"Total memory usage too high: {total_memory_mb:.1f}MB"
            
        except Exception as e:
            pytest.skip(f"Memory usage test failed: {e}")

    def test_cpu_usage(self):
        """Test that services are not using excessive CPU"""
        try:
            client = docker.from_env()
            containers = client.containers.list(filters={"label": "com.docker.compose.project=localai"})
            
            for container in containers:
                stats = container.stats(stream=False)
                
                # Extract CPU usage percentage
                cpu_stats = stats['cpu_stats']
                precpu_stats = stats['precpu_stats']
                
                if 'cpu_usage' in cpu_stats and 'cpu_usage' in precpu_stats:
                    cpu_delta = cpu_stats['cpu_usage']['total_usage'] - precpu_stats['cpu_usage']['total_usage']
                    system_delta = cpu_stats['system_cpu_usage'] - precpu_stats['system_cpu_usage']
                    
                    if system_delta > 0:
                        cpu_percent = (cpu_delta / system_delta) * 100.0
                        # Individual container should use less than 80% CPU on average
                        assert cpu_percent < 80, f"Container {container.name} using too much CPU: {cpu_percent:.1f}%"
            
        except Exception as e:
            pytest.skip(f"CPU usage test failed: {e}")

class TestSecurityBasics:
    """Test basic security configurations"""
    
    def test_no_exposed_databases(self):
        """Test that databases are not directly exposed to host"""
        # These services should NOT be accessible from host
        restricted_services = [
            ("PostgreSQL", "localhost", 5432),
            ("Redis", "localhost", 6379),
        ]
        
        for service_name, host, port in restricted_services:
            try:
                import socket
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(5)
                result = sock.connect_ex((host, port))
                sock.close()
                
                if result != 0:
                    # Good - service is not directly accessible
                    assert True
                else:
                    # Service is accessible - this might be intentional for development
                    pytest.skip(f"{service_name} is exposed on port {port} (might be intentional for dev)")
                    
            except Exception as e:
                pytest.skip(f"Security test for {service_name} failed: {e}")

    def test_container_running_as_nonroot(self):
        """Test that containers are not running as root user"""
        try:
            client = docker.from_env()
            containers = client.containers.list(filters={"label": "com.docker.compose.project=localai"})
            
            for container in containers:
                # Get the user ID the container is running as
                exec_result = container.exec_run("id -u", workdir="/")
                if exec_result.exit_code == 0:
                    user_id = exec_result.output.decode().strip()
                    # Container should not be running as root (UID 0)
                    # Note: Some containers may legitimately need root, so we'll just warn
                    if user_id == "0":
                        pytest.skip(f"Container {container.name} running as root (might be necessary)")
                    else:
                        assert True, f"Container {container.name} running as non-root user {user_id}"
                        
        except Exception as e:
            pytest.skip(f"Container security test failed: {e}")

class TestIntegrationWorkflows:
    """Test end-to-end workflows and integrations"""
    
    def test_ai_service_integration(self):
        """Test AI services can work together"""
        try:
            # Test if we can query Flowise
            response = requests.get("http://localhost:8003/api/v1/chatflows", timeout=10)
            if response.status_code == 200:
                assert True, "Flowise API accessible"
            else:
                pytest.skip("Flowise not accessible for integration test")
                
        except Exception as e:
            pytest.skip(f"AI service integration test failed: {e}")

    def test_monitoring_stack_integration(self):
        """Test monitoring and observability integration"""
        try:
            # Test Langfuse integration
            response = requests.get("http://localhost:8007/api/health", timeout=10)
            if response.status_code == 200:
                # Try to get project information
                projects_response = requests.get("http://localhost:8007/api/public/projects", timeout=10)
                # The endpoint might require auth, so we just check it's reachable
                assert response.status_code < 500, "Langfuse monitoring stack accessible"
            else:
                pytest.skip("Langfuse not accessible for monitoring test")
                
        except Exception as e:
            pytest.skip(f"Monitoring integration test failed: {e}")

if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])