#!/usr/bin/env bash
#===============================================================================
# Script Name  : cbw-dual-push.sh
# Author       : CBW + ChatGPT (GPT-5 Thinking)
# Date         : 2025-08-11
# Version      : 1.0.0
# Summary      : Robust one-click script to push the CURRENT FOLDER to BOTH
#                GitHub and GitLab, on branch `master`, handling setup, remotes,
#                first commits, branch renames, and common errors.
#-------------------------------------------------------------------------------
# Defaults
#   - Username: cbwinslow
#   - Email   : blaine.winslow@gmail.com
#   - Branch  : master (per request)
#   - Remotes : origin (GitHub), gitlab (GitLab)
#-------------------------------------------------------------------------------
# Features
#   • Initializes repo if missing, sets user.name/email (local).
#   • Ensures branch is `master` (renames current or creates it).
#   • Creates remote repos via gh/glab when available (optional flags).
#   • Adds remotes (SSH by default; HTTPS optional).
#   • Pushes to both remotes; auto-fixes common errors (rebase/pull).
#   • Safe by default (no force). Use --force to override.
#   • Idempotent: re-running won’t break things.
#   • Verbose logging to /tmp/CBW-dual-push.log
#-------------------------------------------------------------------------------
# Usage
#   ./cbw-dual-push.sh [options]
# Options
#   --repo <name>          Repository name (default: current folder name)
#   --branch <name>        Target branch (default: master)
#   --gh-owner <owner>     GitHub owner/user (default: cbwinslow)
#   --glab-namespace <ns>  GitLab namespace/group (default: cbwinslow)
#   --ssh                  Use SSH remotes (default)
#   --https                Use HTTPS remotes
#   --create-remote        Create remote repos with gh/glab if missing
#   --private              Create remotes as private (default public)
#   --force                Allow force-with-lease push if necessary
#   --global-identity      Set user.name/email globally instead of locally
#   --no-commit            Do NOT auto-create initial commit if empty
#   --noninteractive       Auto-yes where safe
#   --verbose              Extra logging
#   -h|--help              Show help
#-------------------------------------------------------------------------------
set -Eeuo pipefail
IFS=$'\n\t'

# --- Config -------------------------------------------------------------------
DEFAULT_USER="cbwinslow"
DEFAULT_EMAIL="blaine.winslow@gmail.com"
DEFAULT_BRANCH="master"
GITHUB_REMOTE="origin"
GITLAB_REMOTE="gitlab"
LOG_FILE="/tmp/CBW-dual-push.log"

# --- CLI args -----------------------------------------------------------------
REPO_NAME=""
TARGET_BRANCH="$DEFAULT_BRANCH"
GH_OWNER="$DEFAULT_USER"
GL_NAMESPACE="$DEFAULT_USER"
REMOTE_PROTO="ssh" # ssh|https
CREATE_REMOTE=0
PRIVATE=0
ALLOW_FORCE=0
GLOBAL_ID=0
DO_COMMIT=1
NONINTERACTIVE=0
VERBOSE=0

say()   { echo -e "[INFO] $*" | tee -a "$LOG_FILE"; }
ok()    { echo -e "[ OK ] $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "[WARN] $*" | tee -a "$LOG_FILE"; }
fail()  { echo -e "[ERR ] $*" | tee -a "$LOG_FILE"; exit 1; }
vecho() { [[ $VERBOSE -eq 1 ]] && echo -e "[VERB] $*" | tee -a "$LOG_FILE"; }
ask()   { [[ $NONINTERACTIVE -eq 1 ]] && { warn "AUTO-YES: $*"; return 0; }; read -r -p "$* [y/N]: " a || a=""; [[ $a == y || $a == Y || $a == yes ]]; }

show_help() { sed -n '1,120p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_NAME="$2"; shift 2;;
    --branch) TARGET_BRANCH="$2"; shift 2;;
    --gh-owner) GH_OWNER="$2"; shift 2;;
    --glab-namespace) GL_NAMESPACE="$2"; shift 2;;
    --ssh) REMOTE_PROTO="ssh"; shift;;
    --https) REMOTE_PROTO="https"; shift;;
    --create-remote) CREATE_REMOTE=1; shift;;
    --private) PRIVATE=1; shift;;
    --force) ALLOW_FORCE=1; shift;;
    --global-identity) GLOBAL_ID=1; shift;;
    --no-commit) DO_COMMIT=0; shift;;
    --noninteractive) NONINTERACTIVE=1; shift;;
    --verbose) VERBOSE=1; shift;;
    -h|--help) show_help; exit 0;;
    *) warn "Unknown arg: $1"; shift;;
  esac
done

trap 'warn "An error occurred. See $LOG_FILE"' ERR

# --- Preflight ----------------------------------------------------------------
command -v git >/dev/null 2>&1 || fail "git not found"
[[ -n "$REPO_NAME" ]] || REPO_NAME="$(basename "$PWD")"

say "Repo: $REPO_NAME | Branch: $TARGET_BRANCH | Protocol: $REMOTE_PROTO"

# --- Ensure repo exists -------------------------------------------------------
if [[ ! -d .git ]]; then
  say "No .git found -> initializing repo"
  git init
fi

# --- Identity -----------------------------------------------------------------
if [[ $GLOBAL_ID -eq 1 ]]; then
  git config --global user.name  "$DEFAULT_USER"
  git config --global user.email "$DEFAULT_EMAIL"
  ok "Global identity set: $DEFAULT_USER <$DEFAULT_EMAIL>"
else
  git config user.name  "$DEFAULT_USER"
  git config user.email "$DEFAULT_EMAIL"
  ok "Local identity set: $DEFAULT_USER <$DEFAULT_EMAIL>"
fi

# --- Create first commit if empty --------------------------------------------
current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")"
if [[ "$current_branch" == "HEAD" ]]; then
  say "Repo has no commits yet"
  if [[ $DO_COMMIT -eq 1 ]]; then
    [[ -f README.md ]] || echo "# $REPO_NAME" > README.md
    git add -A
    git commit -m "chore: initial commit"
    ok "Initial commit created"
  else
    warn "--no-commit specified; leaving repo without commits"
  fi
fi

# --- Ensure branch is TARGET_BRANCH (master) ----------------------------------
current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "$TARGET_BRANCH" ]]; then
  say "Switching/renaming branch -> $TARGET_BRANCH"
  if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    git checkout "$TARGET_BRANCH"
  else
    # if current has commits, rename; else create new
    if [[ -n "$(git rev-parse --verify HEAD 2>/dev/null || true)" ]]; then
      git branch -m "$TARGET_BRANCH"
    else
      git checkout -b "$TARGET_BRANCH"
    fi
  fi
fi
ok "On branch $(git rev-parse --abbrev-ref HEAD)"

# --- Build remote URLs --------------------------------------------------------
if [[ "$REMOTE_PROTO" == "ssh" ]]; then
  GH_URL="git@github.com:$GH_OWNER/$REPO_NAME.git"
  GL_URL="git@gitlab.com:$GL_NAMESPACE/$REPO_NAME.git"
else
  GH_URL="https://github.com/$GH_OWNER/$REPO_NAME.git"
  GL_URL="https://gitlab.com/$GL_NAMESPACE/$REPO_NAME.git"
fi

# --- (Optional) Create remote repos ------------------------------------------
if [[ $CREATE_REMOTE -eq 1 ]]; then
  # GitHub
  if command -v gh >/dev/null 2>&1; then
    if ! gh repo view "$GH_OWNER/$REPO_NAME" >/dev/null 2>&1; then
      vis=$([[ $PRIVATE -eq 1 ]] && echo private || echo public)
      say "Creating GitHub repo $GH_OWNER/$REPO_NAME ($vis)"
      gh repo create "$GH_OWNER/$REPO_NAME" --$vis --source . --push || warn "gh create failed (continuing)"
    else
      vecho "GitHub repo exists"
    fi
  else
    warn "gh not found; skipping GitHub create"
  fi
  # GitLab
  if command -v glab >/dev/null 2>&1; then
    if ! glab repo view "$GL_NAMESPACE/$REPO_NAME" >/dev/null 2>&1; then
      vis=$([[ $PRIVATE -eq 1 ]] && echo private || echo public)
      say "Creating GitLab project $GL_NAMESPACE/$REPO_NAME ($vis)"
      glab project create "$REPO_NAME" --group "$GL_NAMESPACE" --visibility "$vis" --readme || warn "glab create failed (continuing)"
    else
      vecho "GitLab project exists"
    fi
  else
    warn "glab not found; skipping GitLab create"
  fi
fi

# --- Add/update remotes -------------------------------------------------------
add_or_set_remote() {
  local name="$1" url="$2"
  if git remote get-url "$name" >/dev/null 2>&1; then
    git remote set-url "$name" "$url"
  else
    git remote add "$name" "$url"
  fi
}
add_or_set_remote "$GITHUB_REMOTE" "$GH_URL"
add_or_set_remote "$GITLAB_REMOTE" "$GL_URL"
ok "Remotes configured:\n$(git remote -v)"

# --- Push helper --------------------------------------------------------------
try_push() {
  local remote="$1" branch="$2"
  say "Pushing to $remote/$branch"
  set +e
  git push -u "$remote" "$branch"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    warn "Initial push failed to $remote ($rc). Attempting auto-fix (pull --rebase)."
    # Try to align with remote
    set +e
    git fetch "$remote" --prune
    git pull --rebase "$remote" "$branch"
    rc_pull=$?
    set -e
    if [[ $rc_pull -ne 0 ]]; then
      warn "Rebase pull failed. Trying pull with --allow-unrelated-histories."
      set +e
      git pull "$remote" "$branch" --allow-unrelated-histories
      rc_allow=$?
      set -e
      if [[ $rc_allow -ne 0 ]]; then
        if [[ $ALLOW_FORCE -eq 1 ]]; then
          warn "Forcing push with --force-with-lease (as requested)."
          git push --force-with-lease "$remote" "$branch" || fail "Force push failed to $remote"
          ok "Force push succeeded to $remote"
          return 0
        else
          fail "Push failed to $remote. Re-run with --force to override after review."
        fi
      fi
    fi
    # Try push again after successful pull
    git push -u "$remote" "$branch" || {
      if [[ $ALLOW_FORCE -eq 1 ]]; then
        warn "Last push attempt failed; forcing with lease."
        git push --force-with-lease "$remote" "$branch" || fail "Force push failed to $remote"
      else
        fail "Push failed to $remote after rebase. Use --force if acceptable."
      fi
    }
  fi
  ok "Pushed to $remote/$branch"
}

# --- Execute pushes -----------------------------------------------------------
try_push "$GITHUB_REMOTE" "$TARGET_BRANCH"
try_push "$GITLAB_REMOTE" "$TARGET_BRANCH"

ok "All done. Repo '$REPO_NAME' is on GitHub AND GitLab (branch: $TARGET_BRANCH)."
