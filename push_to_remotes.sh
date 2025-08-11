#!/bin/bash
# Exit on error, undefined variable, and pipe failures
set -euo pipefail

# This script is now configured for user cbwinslow.

# --- Configuration ---
GIT_USER_NAME="cbwinslow"
GIT_USER_EMAIL="blaine.winslow@gmail.com"
REPO_NAME="supa-container"

# --- Construct full URLs ---
GITHUB_URL="https://github.com/${GIT_USER_NAME}/${REPO_NAME}.git"
GITLAB_URL="https://gitlab.com/${GIT_USER_NAME}/${REPO_NAME}.git"

echo "--> Configuring local git user..."
git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"
echo "Git user set to: $(git config user.name) <$(git config user.email)>"

echo "--> Removing existing remotes (if any) to ensure a clean setup..."
git remote remove origin 2>/dev/null || true
git remote remove gitlab 2>/dev/null || true

echo "--> Adding new repository remotes..."
git remote add origin "$GITHUB_URL"
git remote add gitlab "$GITLAB_URL"

echo "Remotes configured:"
git remote -v

echo ""
echo "You will now be prompted to authenticate for GitHub and GitLab."
echo "You can use a Personal Access Token (PAT) in place of your password."
echo ""

echo "--> Pushing to GitHub (origin)..."
git push -u origin master

echo "--> Pushing to GitLab (gitlab)..."
git push -u gitlab master

echo "--> All done. Your code has been pushed to both repositories."
