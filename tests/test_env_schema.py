#!/usr/bin/env python3
"""
File: test_env_schema.py
Author: CBW + ChatGPT (GPT-5 Thinking)
Date: 2025-08-11
Summary: Validate required environment variables exist and are non-empty.
"""
import os
import re
from pathlib import Path

REQUIRED = [
    "DOMAIN", "LETSENCRYPT_EMAIL", "TRAEFIK_ADMIN_PASSWORD_HASH",
    "POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB",
    "NEO4J_USER", "NEO4J_PASSWORD",
    "LLM_PROVIDER", "LLM_BASE_URL",
    "EMBEDDING_PROVIDER", "EMBEDDING_BASE_URL",
    "N8N_BASIC_AUTH_USER", "N8N_BASIC_AUTH_PASSWORD",
    "FLOWISE_USERNAME", "FLOWISE_PASSWORD",
    "LANGFUSE_NEXTAUTH_SECRET", "LANGFUSE_SALT",
    "SUPABASE_JWT_SECRET",  # anon/service keys come post-deploy
    "APP_ENV", "LOG_LEVEL", "APP_PORT"
]

def test_env_exists_and_complete():
    env = {}
    env_path = Path(".env")
    assert env_path.exists(), ".env not found at project root"
    with env_path.open() as f:
        for line in f:
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.strip().split("=", 1)
                env[k] = v
    missing = [k for k in REQUIRED if not env.get(k)]
    assert not missing, f"Missing required env vars: {missing}"

def test_traefik_hash_format():
    line = next((l for l in Path(".env").read_text().splitlines() if l.startswith("TRAEFIK_ADMIN_PASSWORD_HASH=")), None)
    assert line is not None
    _, val = line.split("=", 1)
    assert ":" in val and "$" in val, "TRAEFIK_ADMIN_PASSWORD_HASH should be htpasswd/MD5 or bcrypt-like"
