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

# Fetch latest from remote (no pull — don't touch working tree).
# Works from any branch — always tags origin/main HEAD, never uses local branch.
CURRENT_BRANCH=$(git branch --show-current)
echo -e "${GREEN}Fetching refs from origin (origin/main + tags, no pull)... ${YELLOW}(on branch: ${CURRENT_BRANCH}, tagging: origin/main)${NC}"
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

REPO_SLUG=$(git config --get remote.origin.url | sed 's|.*[:/]\([^/]*/[^/]*\)\.git$|\1|; s|.*[:/]\([^/]*/[^/]*\)$|\1|')

echo ""
echo -e "${GREEN}${BOLD}Done! Deployment triggered.${NC}"
echo -e "${GREEN}Tagged origin/main (${REMOTE_HEAD:0:8}) as ${TAG}${NC}"
echo -e "${GREEN}Monitor: https://github.com/${REPO_SLUG}/actions${NC}"
echo ""
echo -e "${BOLD}Manual alternatives:${NC}"
echo -e "  ${YELLOW}# One-liner to tag and push:${NC}"
echo -e "  git tag -a ${TAG} origin/main -m \"deploy\" && git push origin ${TAG}"
echo -e ""
echo -e "  ${YELLOW}# Via GitHub UI:${NC}"
echo -e "  https://github.com/${REPO_SLUG}/releases/new?tag=${TAG}&target=main"
