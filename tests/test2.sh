#!/bin/bash

# --- Configuration ---
TEST_ROOT="/tmp/rsync_test_env"
MOCK_SRC="$TEST_ROOT/source"
MOCK_DEST="$TEST_ROOT/destination"
# RESOLVE SCRIPT PATH (Assumes test is in a subfolder or same folder)
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../start.sh"

LOG_FILE="rsync_vystup.log"

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

# --- Helper Functions ---

generate_test_data() {
    printf "Generating test data structure...\n"
    rm -rf "$MOCK_SRC" "$MOCK_DEST"
    mkdir -p "$MOCK_SRC" "$MOCK_DEST"

    # 1. Standard files
    echo "Content A" > "$MOCK_SRC/file1.txt"
    
    # 2. Files with spaces (The "NEMESIS" of scripts)
    mkdir -p "$MOCK_SRC/Folder With Spaces"
    echo "Secret Content" > "$MOCK_SRC/Folder With Spaces/file with spaces.txt"
    
    # 3. Deeply nested empty directories (to test cleanup)
    mkdir -p "$MOCK_SRC/empty_parent/empty_child/empty_grandchild"
    
    # 4. A large file to simulate work
    dd if=/dev/urandom of="$MOCK_SRC/large_file.bin" bs=1M count=2 2>/dev/null
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

run_test() {
    local test_name=$1
    local extra_args=$2
    printf "\n${YELLOW}>>> [TEST]: %s${NC}\n" "$test_name"
    
    # Execute (Non-interactive mode handled by script's [ -t 0 ] check)
    bash "$SCRIPT_PATH" $extra_args "${MOCK_SRC}/" "$MOCK_DEST"
    
    wait_for_rsync
}

# --- Expanded Test Cases ---

cleanup_env() { rm -rf "$TEST_ROOT"; [ -f "$LOG_FILE" ] && rm "$LOG_FILE"; }

# Initialize
cleanup_env
mkdir -p "$TEST_ROOT"

# ---------------------------------------------------------
# Test 1: Space Handling & Content Integrity
# ---------------------------------------------------------
generate_test_data
run_test "Space Handling & Integrity" "-real"

if [ -f "$MOCK_DEST/Folder With Spaces/file with spaces.txt" ]; then
    printf "${GREEN}PASS: Files with spaces copied correctly.${NC}\n"
else
    printf "${RED}FAIL: Spaces broke the copy process.${NC}\n"
fi

# ---------------------------------------------------------
# Test 2: Backup Mechanism (Zaloha)
# ---------------------------------------------------------
# We already have data in DEST. Let's modify SRC and sync again.
printf "Modifying source file to trigger backup...\n"
echo "NEW CONTENT" > "$MOCK_SRC/file1.txt"

run_test "Backup Verification" "-real"

# Look for the backup directory created by your script (zaloha_YYYY-MM-DD...)
BACKUP_DIR=$(find "$MOCK_DEST" -maxdepth 1 -type d -name "zaloha_*" | head -n 1)

if [ -f "$BACKUP_DIR/file1.txt.old" ]; then
    printf "${GREEN}PASS: Backup created in $BACKUP_DIR with .old suffix.${NC}\n"
else
    printf "${RED}FAIL: Backup file not found.${NC}\n"
fi

# ---------------------------------------------------------
# Test 3: The Move & Recursive Cleanup
# ---------------------------------------------------------
generate_test_data
run_test "Move & Empty Dir Cleanup" "-real -move"

# Verify files are in DEST
if [ -f "$MOCK_DEST/large_file.bin" ] && [ ! -f "$MOCK_SRC/large_file.bin" ]; then
    printf "${GREEN}PASS: Files moved successfully.${NC}\n"
else
    printf "${RED}FAIL: Files still in source or missing from dest.${NC}\n"
fi

# Verify Empty Dirs are GONE (Recursive check)
if [ -d "$MOCK_SRC/empty_parent" ]; then
    printf "${RED}FAIL: Empty directories were not cleaned up.${NC}\n"
else
    printf "${GREEN}PASS: Empty directory tree deleted.${NC}\n"
fi

# ---------------------------------------------------------
# Test 4: One-File-System Safety (Mount simulation)
# ---------------------------------------------------------
# This tests the --one-file-system flag in your script.
mkdir -p "$MOCK_SRC/external_mount"
# We can't actually mount without sudo, but we can check if rsync 
# is called with the flag.
if grep -q "one-file-system" "$SCRIPT_PATH"; then
    printf "${GREEN}PASS: Safety flag '--one-file-system' is present in script.${NC}\n"
fi

printf "\n${YELLOW}Robustness Check Finished.${NC}\n"