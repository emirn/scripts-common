#!/bin/bash
# push-production.sh - Tag and deploy current VERSION to production
# Usage: ./push-production.sh
#
# Reads VERSION file, creates production-v{version} tag, pushes it.
# This triggers the deploy-full-stack GitHub Actions workflow.

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

# Must be clean
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${RED}Error: Working directory not clean. Commit or stash changes first.${NC}"
    exit 1
fi

# Pull latest
echo -e "${GREEN}Pulling latest from main...${NC}"
git pull

# Bump patch version
CURRENT_VERSION=$(cat VERSION | tr -d '[:space:]')
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d. -f3)
VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
echo "$VERSION" > VERSION

TAG="production-v${VERSION}"

echo -e "${BOLD}Current: ${CURRENT_VERSION}${NC}"
echo -e "${BOLD}New:     ${VERSION}${NC}"
echo -e "${BOLD}Tag:     ${TAG}${NC}"

# Confirm
echo ""
echo -e "${YELLOW}This will bump version ${BOLD}${CURRENT_VERSION} → ${VERSION}${NC}${YELLOW} and deploy to production.${NC}"
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Commit and push version bump
echo -e "${GREEN}Committing version bump...${NC}"
git add VERSION
git commit -m "Bump version to ${VERSION} [version-bump]"
git push

# Create and push tag
echo -e "${GREEN}Creating tag ${TAG}...${NC}"
git tag "$TAG"
echo -e "${GREEN}Pushing tag to origin...${NC}"
git push origin "$TAG"

echo ""
echo -e "${GREEN}${BOLD}Done! Deployment triggered.${NC}"
echo -e "${GREEN}Monitor: https://github.com/$(git config --get remote.origin.url | sed 's|.*[:/]\([^/]*/[^/]*\)\.git$|\1|; s|.*[:/]\([^/]*/[^/]*\)$|\1|')/actions${NC}"
