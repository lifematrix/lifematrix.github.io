#!/bin/bash
# =============================================================================
# publish.sh
#
# Builds the Hugo site and commits + pushes all changes to the remote.
#
# Steps:
#   1. Rebuild public/ with --cleanDestinationDir (removes stale files)
#   2. Stage all tracked and new files (respects .gitignore)
#   3. Commit with the provided message
#   4. Push to origin
#
# Usage:
#   ./shells/publish.sh "your commit message"
#   ./shells/publish.sh -n "msg"     # dry run: build + show diff, no commit/push
#   ./shells/publish.sh --dry-run "msg"
#
# The commit message is mandatory. The script exits with an error if omitted.
# =============================================================================

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Resolve repo root (script may be called from any directory) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT" || { echo -e "${RED}Error:${NC} Cannot cd to repo root."; exit 1; }

# --- Argument parsing ---
DRY_RUN=false
MSG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "Usage:"
            echo "  $(basename "$0") [options] [\"commit message\"]"
            echo ""
            echo "Options:"
            echo "  -n, --dry-run   Build and show what would be committed; do not push"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        -*)
            echo -e "${RED}Error:${NC} Unknown option '$1'"
            exit 1
            ;;
        *)
            if [[ -n "$MSG" ]]; then
                echo -e "${RED}Error:${NC} Unexpected argument '$1'"
                exit 1
            fi
            MSG="$1"
            shift
            ;;
    esac
done

# --- Require commit message ---
if [[ -z "$MSG" ]]; then
    echo -e "${RED}Error:${NC} Commit message is required."
    echo ""
    echo "  Usage: $(basename "$0") [--dry-run] \"your commit message\""
    exit 1
fi

# =============================================================================
# Header
# =============================================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if $DRY_RUN; then
    echo -e "${BOLD} publish.sh — build + stage (dry run)${NC}"
else
    echo -e "${BOLD} publish.sh — build + commit + push${NC}"
fi
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Repo     : ${CYAN}$REPO_ROOT${NC}"
echo -e "  Message  : ${CYAN}$MSG${NC}"
$DRY_RUN && echo -e "  Mode     : ${YELLOW}dry run — will not commit or push${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# =============================================================================
# Step 1: Build
# =============================================================================
echo -e "  ${CYAN}▶ Building${NC}   : hugo --cleanDestinationDir"
if ! hugo --cleanDestinationDir 2>&1 | grep -E "^(Built|ERROR|Error|WARN|Total)"; then
    echo -e "  ${RED}✘ Failed${NC}    : Hugo build error. Aborting."
    exit 1
fi
echo -e "  ${GREEN}✔ Built${NC}      : public/ updated"
echo ""

# =============================================================================
# Step 2: Stage
# =============================================================================
echo -e "  ${CYAN}▶ Staging${NC}    : git add -A"
git add -A

# Show a compact summary of what's staged
STAGED=$(git diff --cached --stat | tail -1)
if [[ -z "$STAGED" ]]; then
    echo -e "  ${YELLOW}⚠ Nothing to commit${NC} — working tree clean."
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}✔ Already up to date.${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
fi
echo -e "  ${GREEN}✔ Staged${NC}     : $STAGED"
echo ""

# In dry-run mode: show what would be committed and exit
if $DRY_RUN; then
    echo -e "  ${YELLOW}Dry run — staged changes:${NC}"
    git diff --cached --name-status | sed 's/^/    /'
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${YELLOW}Dry run complete. Nothing committed or pushed.${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    git reset HEAD 2>/dev/null   # unstage so the tree is clean after dry run
    exit 0
fi

# =============================================================================
# Step 3: Commit
# =============================================================================
echo -e "  ${CYAN}▶ Committing${NC} : $MSG"
if ! git commit -m "$MSG"; then
    echo -e "  ${RED}✘ Failed${NC}    : git commit error. Aborting."
    exit 1
fi
echo ""

# =============================================================================
# Step 4: Push
# =============================================================================
echo -e "  ${CYAN}▶ Pushing${NC}    : git push"
if ! git push; then
    echo -e "  ${RED}✘ Failed${NC}    : git push error."
    echo -e "             Your commit is local. Run 'git push' manually when ready."
    exit 1
fi
echo ""

# =============================================================================
# Done
# =============================================================================
COMMIT_SHA=$(git rev-parse --short HEAD)
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✔ Published${NC}  : commit $COMMIT_SHA pushed to origin"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
