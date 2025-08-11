#!/usr/bin/env bats
# Exit on error, undefined variable, and pipe failures
set -euo pipefail

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
  # Create a dummy config file for testing
  cat > config.sh <<EOF
export DOMAIN="test.local"
export LETSENCRYPT_EMAIL="test@test.local"
export TRAEFIK_ADMIN_PASSWORD="password"
export APP_ROOT="./test_deploy/app"
export WEB_ROOT="./test_deploy/web"
EOF
  mkdir -p test_deploy/app
  mkdir -p test_deploy/web
}

teardown() {
  rm -f config.sh .env
  rm -rf test_deploy
}

@test "populate_secrets.sh creates a .env file with correct variables" {
  run bash ../populate_secrets.sh
  assert_success
  assert [ -f ".env" ]
  assert_output --partial "DOMAIN=test.local"
  assert_output --partial "TRAEFIK_ADMIN_PASSWORD_HASH="
}

@test "deploy.sh creates necessary directories and files" {
  # We need to mock sudo for this test
  run bash -c "sudo() { \"$@\"; }; . ../deploy.sh"
  assert_success
  assert [ -d "./test_deploy/app/traefik" ]
  assert [ -f "./test_deploy/app/docker-compose.yml" ]
  assert [ -f "./test_deploy/app/otel-collector-config.yaml" ]
}

@test "deploy.sh generates a valid docker-compose.yml" {
  run bash -c "sudo() { \"$@\"; }; . ../deploy.sh"
  assert_success
  
  # Check for the presence of key services in the generated docker-compose file
  run grep "traefik:" "./test_deploy/app/docker-compose.yml"
  assert_output --partial "traefik:"
  
  run grep "nextjs_app:" "./test_deploy/app/docker-compose.yml"
  assert_output --partial "nextjs_app:"

  run grep "fastapi_app:" "./test_deploy/app/docker-compose.yml"
  assert_output --partial "fastapi_app:"
}

@test "post-deploy-setup.sh is executable" {
  assert [ -x "../post-deploy-setup.sh" ]
}