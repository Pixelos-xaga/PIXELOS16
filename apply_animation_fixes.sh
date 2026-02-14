#!/bin/bash

# Script to apply AresOS animation jitter fixes to frameworks/base
# Fixes Settings UI stuttering on certain devices

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Commit hashes from AresOS
COMMIT1="016692e508566188718302daf55e162ffa579daa"
COMMIT2="c7cbb45447fd44634bb215879d96799404943d25"
ARESOS_REMOTE="https://github.com/AresOS-AOSP/android_frameworks_base"

echo -e "${GREEN}=== Applying AresOS Animation Jitter Fixes ===${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "core/java/android/view/animation/AnimationUtils.java" ]; then
    echo -e "${RED}Error: Please run this script from frameworks/base directory${NC}"
    exit 1
fi

# Check if frameworks/base is a git repo
if [ ! -d ".git" ]; then
    echo -e "${RED}Error: frameworks/base is not a git repository${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Adding AresOS remote...${NC}"
git remote add aresos "$ARESOS_REMOTE" 2>/dev/null || echo "Remote 'aresos' already exists"

echo -e "${YELLOW}Step 2: Fetching commits from AresOS...${NC}"
git fetch aresos $COMMIT1 $COMMIT2 2>&1 | grep -E "(error|fatal)" && {
    echo -e "${RED}Error fetching from AresOS remote${NC}"
    exit 1
}

echo ""
echo -e "${YELLOW}Step 3: Cherry-picking animation override commit...${NC}"
git cherry-pick "$COMMIT1" --no-commit
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully applied commit $COMMIT1${NC}"
else
    echo -e "${RED}✗ Conflict detected. Resolving...${NC}"
    git checkout --theirs core/java/android/view/animation/AnimationUtils.java
    git add core/java/android/view/animation/AnimationUtils.java
    echo -e "${GREEN}✓ Resolved conflict using AresOS version${NC}"
fi

echo ""
echo -e "${YELLOW}Step 4: Cherry-picking timing fix commit...${NC}"
git cherry-pick "$COMMIT2" --no-commit
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully applied commit $COMMIT2${NC}"
else
    echo -e "${RED}✗ Conflict detected. Resolving...${NC}"
    git checkout --theirs core/java/android/view/animation/AnimationUtils.java
    git add core/java/android/view/animation/AnimationUtils.java
    echo -e "${GREEN}✓ Resolved conflict using AresOS version${NC}"
fi

echo ""
echo -e "${YELLOW}Step 5: Reviewing changes...${NC}"
git diff --cached --stat

echo ""
echo -e "${GREEN}=== Fixes Applied Successfully! ===${NC}"
echo ""
echo "Modified file:"
echo "  - core/java/android/view/animation/AnimationUtils.java"
echo ""
echo "Changes are staged. To commit them, run:"
echo "  git commit -m 'Fix Settings UI jitter with AresOS animation patches'"
echo ""
echo "Optional: Enable the smooth animations by adding to your device tree:"
echo "  persist.sys.activity_anim_perf_override=true"
echo ""

# Clean up remote
git remote remove aresos 2>/dev/null || true

echo -e "${GREEN}Done!${NC}"
