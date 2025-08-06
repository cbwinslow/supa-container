#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

@test "populate_secrets.sh creates a .env file" {
  # Run the script
  run bash populate_secrets.sh
  
  # Check that the script succeeded
  assert_success
  
  # Check that the .env file was created
  assert [ -f ".env" ]
  
  # Check that the .env file contains a key variable
  assert_output --partial "DOMAIN="
  
  # Cleanup
  rm .env
}

# Add more tests for deploy.sh, post-deploy-setup.sh, etc.
