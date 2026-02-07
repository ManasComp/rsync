#!/bin/bash

# --- Configuration ---
TEST_ROOT="/tmp/rsync_ultimate_test"
MOCK_SRC="$TEST_ROOT/source"
MOCK_DEST="$TEST_ROOT/destination"
# RESOLVE SCRIPT PATH
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$TEST_DIR/../start.sh"

LOG_FILE="rsync_vystup.log"

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

# --- Helper Functions ---

generate_test_data() {
    printf "Generating comprehensive test data structure...\n"
    rm -rf "$MOCK_SRC" "$MOCK_DEST"
    mkdir -p "$MOCK_SRC" "$MOCK_DEST"

    # 1. Standard files & Deep nesting
    mkdir -p "$MOCK_SRC/dir_1/subdir_A"
    echo "Content A" > "$MOCK_SRC/file1.txt"
    echo "Deep Content" > "$MOCK_SRC/dir_1/subdir_A/deep_file.txt"
    
    # 2. Files and Folders with spaces (The Script Killer)
    mkdir -p "$MOCK_SRC/Folder With Spaces"
    echo "Secret Content" > "$MOCK_SRC/Folder With Spaces/file with spaces.txt"
    
    # 3. Empty directories for cleanup testing
    mkdir -p "$MOCK_SRC/empty_parent/empty_child/empty_grandchild"
    
    # 4. Large file for sync verification
    dd if=/dev/urandom of="$MOCK_SRC/large_file.bin" bs=1M count=1 2>/dev/null
}

cleanup_env() {
    rm -rf "$TEST_ROOT"
    [ -f "$LOG_FILE" ] && rm "$LOG_FILE"
}

wait_for_rsync() {
    local timeout=15
    local count=0
    while pgrep -f "rsync.*$MOCK_SRC" > /dev/null; do
        if [ $count -ge $timeout ]; then return 1; fi
        sleep 0.5
        ((count++))
    done
    return 0
}

run_test_step() {
    local test_name=$1
    local extra_args=$2
    printf "\n${YELLOW}>>> [EXECUTING]: %s${NC}\n" "$test_name"
    
    if [ ! -f "$SCRIPT_PATH" ]; then
        printf "${RED}Error: Script not found at $SCRIPT_PATH${NC}\n"
        exit 1
    fi

    # Pass source with trailing slash to ensure content sync
    bash "$SCRIPT_PATH" $extra_args "${MOCK_SRC}/" "$MOCK_DEST"
    wait_for_rsync
}

# --- The Ultimate Test Routine ---

cleanup_env
mkdir -p "$TEST_ROOT"

# ---------------------------------------------------------
# STAGE 1: Dry Run Safety
# ---------------------------------------------------------
generate_test_data
run_test_step "Dry Run (No -real flag)" ""

if [ -z "$(ls -A "$MOCK_DEST")" ]; then
    printf "${GREEN}PASS: Dry run respected (Destination empty).${NC}\n"
else
    printf "${RED}FAIL: Dry run failed! Files copied to destination.${NC}\n"
fi

# ---------------------------------------------------------
# STAGE 2: Real Copy & Space Handling
# ---------------------------------------------------------
run_test_step "Real Copy & Space Handling" "-real"

if [ -f "$MOCK_DEST/Folder With Spaces/file with spaces.txt" ] && \
   diff -r "$MOCK_SRC" "$MOCK_DEST" --exclude="zaloha_*" > /dev/null; then
    printf "${GREEN}PASS: Full integrity check passed (including spaces).${NC}\n"
else
    printf "${RED}FAIL: Integrity check failed or spaces caused a crash.${NC}\n"
fi

# ---------------------------------------------------------
# STAGE 3: Incremental Sync & Backup (.old)
# ---------------------------------------------------------
printf "Modifying source file to trigger backup logic...\n"
echo "UPDATED CONTENT" > "$MOCK_SRC/file1.txt"

run_test_step "Backup Verification" "-real"

BACKUP_DIR=$(find "$MOCK_DEST" -maxdepth 1 -type d -name "zaloha_*" | head -n 1)

if [ -n "$BACKUP_DIR" ] && [ -f "$BACKUP_DIR/file1.txt.old" ]; then
    printf "${GREEN}PASS: Backup created successfully in $BACKUP_DIR${NC}\n"
else
    printf "${RED}FAIL: Backup file (.old) not found.${NC}\n"
fi

# ---------------------------------------------------------
# STAGE 4: Move Logic & Recursive Source Cleanup
# ---------------------------------------------------------
generate_test_data # Reset data
run_test_step "Move & Recursive Cleanup" "-real -move"

# Check if files moved
if [ -f "$MOCK_DEST/large_file.bin" ] && [ ! -f "$MOCK_SRC/large_file.bin" ]; then
    printf "${GREEN}PASS: Files moved from Source to Destination.${NC}\n"
else
    printf "${RED}FAIL: Files not moved correctly.${NC}\n"
fi

# Check if source directory tree is truly empty/deleted
if [ ! -d "$MOCK_SRC/empty_parent" ] && [ -z "$(find "$MOCK_SRC" -type f 2>/dev/null)" ]; then
    printf "${GREEN}PASS: Source directory tree cleaned up recursively.${NC}\n"
else
    printf "${RED}FAIL: Source still contains files or empty directories.${NC}\n"
fi

# ---------------------------------------------------------
# STAGE 5: Safety Flag Audit
# ---------------------------------------------------------
printf "\n${YELLOW}>>> [AUDIT]: Checking Script for Safety Flags${NC}\n"
if grep -q "one-file-system" "$SCRIPT_PATH"; then
    printf "${GREEN}PASS: '--one-file-system' flag detected.${NC}\n"
else
    printf "${YELLOW}WARN: '--one-file-system' not found. Recommended for safety.${NC}\n"
fi

# --- Final Report ---
printf "\n${YELLOW}===========================================${NC}\n"
printf "${GREEN}All Integrated Tests Completed.${NC}\n"
printf "${YELLOW}===========================================${NC}\n"

# Final Cleanup
rm -rf "$TEST_ROOT"