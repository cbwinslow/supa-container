#!/usr/bin/env python3
"""
File: test_stack_smoke.py
Author: CBW + ChatGPT (GPT-5 Thinking)
Date: 2025-08-11
Summary: Basic smoke tests: docker & compose present; optional network probes.
"""
import os
import shutil
import subprocess

def _cmd_ok(cmd):
    return subprocess.call(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0

def test_docker_present():
    assert _cmd_ok("docker --version"), "Docker CLI not available"

def test_compose_present():
    assert _cmd_ok("docker compose version"), "docker compose plugin not available"

def test_compose_file_generated():
    # Many stacks generate compose at deploy; accept either local or /opt location.
    assert os.path.exists("docker-compose.yml") or os.path.exists("/opt/supabase-super-stack/docker-compose.yml"), \
        "docker-compose.yml not found (run deploy once to generate if templated)"
