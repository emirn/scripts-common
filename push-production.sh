#!/bin/bash
# push-production.sh - Tag and deploy to production
# Usage: ./push-production.sh
#
# Computes next version from latest production tag, creates an annotated tag
# on origin/main HEAD, and pushes it. This triggers the deploy-full-stack
# GitHub Actions workflow.
#
# Does NOT modify the working tree — no stash, pull, commit, or VERSION file changes.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Find repo root (works from any subdirectory)
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Must be on main
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${RED}Error: Must be on 'main' branch. Currently on '$CURRENT_BRANCH'.${NC}"
    exit 1
fi

# Fetch latest from remote (no pull — don't touch working tree)
echo -e "${GREEN}Fetching latest from origin...${NC}"
git fetch origin main --tags --quiet

# Compute next version from latest production tag
LATEST_TAG=$(git tag -l "production-v*" --sort=-version:refname | head -1)
if [ -z "$LATEST_TAG" ]; then
    echo -e "${RED}Error: No existing production-v* tags found.${NC}"
    exit 1
fi

CURRENT_VERSION="${LATEST_TAG#production-v}"
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d. -f3)
VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
TAG="production-v${VERSION}"

echo -e "${BOLD}Current: ${CURRENT_VERSION}${NC}"
echo -e "${BOLD}New:     ${VERSION}${NC}"
echo -e "${BOLD}Tag:     ${TAG}${NC}"

# Collect changelog (commits since last production tag on origin/main)
REMOTE_HEAD=$(git rev-parse origin/main)
CHANGELOG=$(git log --oneline "$LATEST_TAG".."$REMOTE_HEAD" --no-merges --invert-grep --grep='\[version-bump\]' | head -10)

if [ -n "$CHANGELOG" ]; then
    echo -e "${GREEN}Changelog:${NC}"
    echo "$CHANGELOG"
    echo ""
else
    echo -e "${YELLOW}No new commits since ${LATEST_TAG}. Nothing to deploy.${NC}"
    exit 0
fi

# Create annotated tag on origin/main HEAD (not local HEAD)
echo -e "${GREEN}Creating tag ${TAG} on origin/main...${NC}"
git tag -a "$TAG" "$REMOTE_HEAD" -m "$CHANGELOG"

echo -e "${GREEN}Pushing tag to origin...${NC}"
git push origin "$TAG"

echo ""
echo -e "${GREEN}${BOLD}Done! Deployment triggered.${NC}"
echo -e "${GREEN}Monitor: https://github.com/$(git config --get remote.origin.url | sed 's|.*[:/]\([^/]*/[^/]*\)\.git$|\1|; s|.*[:/]\([^/]*/[^/]*\)$|\1|')/actions${NC}"
