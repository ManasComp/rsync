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
    # We use [r]sync as a regex trick so grep doesn't find its own process
    while ps aux | grep -v grep | grep -q "rsync.*$MOCK_SRC"; do
        if [ $count -ge $((timeout * 2)) ]; then 
            return 1 
        fi
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

# ---------------------------------------------------------
# Test 5: The "Nightmare" Filenames (Special Characters)
# ---------------------------------------------------------
generate_test_data
printf "Adding nightmare filenames...\n"
touch "$MOCK_SRC/-dashfile.txt"
touch "$MOCK_SRC/file with \$dollar.txt"
touch "$MOCK_SRC/file!exclamation.txt"
touch "$MOCK_SRC/bracket[test].txt"

run_test_step "Special Character Handling" "-real"

if [ -f "$MOCK_DEST/-dashfile.txt" ] && [ -f "$MOCK_DEST/file with \$dollar.txt" ]; then
    printf "${GREEN}PASS: Special characters and leading dashes handled.${NC}\n"
else
    printf "${RED}FAIL: Special characters caused a failure.${NC}\n"
fi

# ---------------------------------------------------------
# Test 6: Hidden Files (Dotfiles)
# ---------------------------------------------------------
printf "Adding hidden files...\n"
echo "secret" > "$MOCK_SRC/.hidden_config"
mkdir -p "$MOCK_SRC/.hidden_dir"
echo "secret" > "$MOCK_SRC/.hidden_dir/data.db"

run_test_step "Hidden Files Sync" "-real"

if [ -f "$MOCK_DEST/.hidden_config" ] && [ -d "$MOCK_DEST/.hidden_dir" ]; then
    printf "${GREEN}PASS: Hidden files and directories synced.${NC}\n"
else
    printf "${RED}FAIL: Hidden files were ignored.${NC}\n"
fi

# ---------------------------------------------------------
# Test 7: Symlink Behavior
# ---------------------------------------------------------
# Note: By default, rsync copies the link itself. 
# This tests if your script handles links without crashing.
printf "Creating symbolic links...\n"
ln -s "$MOCK_SRC/file1.txt" "$MOCK_SRC/link_to_file1"

run_test_step "Symlink Handling" "-real"

if [ -L "$MOCK_DEST/link_to_file1" ]; then
    printf "${GREEN}PASS: Symbolic link preserved.${NC}\n"
else
    printf "${YELLOW}WARN: Symlink not found as link (Check rsync flags if -l or -a is used).${NC}\n"
fi

# ---------------------------------------------------------
# Test 8: "Flat" Source Structure (No Subdirs)
# ---------------------------------------------------------
# Sometimes scripts fail when there are no subdirectories to recurse into.
rm -rf "$MOCK_SRC"/*
echo "flat" > "$MOCK_SRC/only_one_file.txt"

run_test_step "Flat Structure" "-real -move"

if [ -f "$MOCK_DEST/only_one_file.txt" ] && [ ! -f "$MOCK_SRC/only_one_file.txt" ]; then
    printf "${GREEN}PASS: Flat structure moved correctly.${NC}\n"
else
    printf "${RED}FAIL: Flat structure move failed.${NC}\n"
fi

# ---------------------------------------------------------
# Test 9: Permission Preservation (Read-Only)
# ---------------------------------------------------------
echo "readonly" > "$MOCK_SRC/locked.txt"
chmod 444 "$MOCK_SRC/locked.txt"

run_test_step "Permissions Preservation" "-real"

if [ -r "$MOCK_DEST/locked.txt" ]; then
    # Check if it kept the 444 permission (if -a or -p flag is in your script)
    PERMS=$(stat -c "%a" "$MOCK_DEST/locked.txt")
    if [ "$PERMS" = "444" ]; then
        printf "${GREEN}PASS: Permissions (444) preserved.${NC}\n"
    else
        printf "${YELLOW}INFO: Permissions changed to $PERMS (Expected if -a is not used).${NC}\n"
    fi
else
    printf "${RED}FAIL: Read-only file failed to sync.${NC}\n"
fi


# --- Helper to reset environment between cases ---
reset_mock_dirs() {
    mkdir -p "$MOCK_SRC" "$MOCK_DEST"
}

# ---------------------------------------------------------
# Test 10: The "Deep Sea" (Extreme Nesting)
# ---------------------------------------------------------
reset_mock_dirs
printf "Creating 10-level deep directory structure...\n"
DEEP_PATH="$MOCK_SRC/1/2/3/4/5/6/7/8/9/10"
mkdir -p "$DEEP_PATH"
echo "Deep Water" > "$DEEP_PATH/abyss.txt"

run_test_step "Extreme Nesting" "-real -move"

if [ -f "$MOCK_DEST/1/2/3/4/5/6/7/8/9/10/abyss.txt" ]; then
    printf "${GREEN}PASS: 10-level recursion successful.${NC}\n"
else
    printf "${RED}FAIL: Deep recursion failed.${NC}\n"
fi

# ---------------------------------------------------------
# Test 11: The "Chaos" Load Test (100 Files)
# ---------------------------------------------------------
reset_mock_dirs
printf "Generating 100 random files...\n"
for i in {1..100}; do
    touch "$MOCK_SRC/file_$i.tmp"
done

run_test_step "High File Count" "-real"

COUNT=$(ls -1 "$MOCK_DEST" | grep ".tmp" | wc -l)
if [ "$COUNT" -eq 100 ]; then
    printf "${GREEN}PASS: Verified all 100 files transferred.${NC}\n"
else
    printf "${RED}FAIL: Only $COUNT/100 files transferred.${NC}\n"
fi

# ---------------------------------------------------------
# Test 12: The "Overwrite" (Timestamp Sensitivity)
# ---------------------------------------------------------
reset_mock_dirs
echo "Old Content" > "$MOCK_SRC/update_test.txt"
run_test_step "Initial Sync" "-real"

sleep 1 # Ensure timestamp difference
echo "Newer Content" > "$MOCK_SRC/update_test.txt"
run_test_step "Update Sync" "-real"

if grep -q "Newer Content" "$MOCK_DEST/update_test.txt"; then
    printf "${GREEN}PASS: Newer file correctly overwrote old destination file.${NC}\n"
else
    printf "${RED}FAIL: Destination still has old content.${NC}\n"
fi

# --- Final Report ---
printf "\n${YELLOW}===========================================${NC}\n"
printf "${GREEN}All Integrated Tests Completed.${NC}\n"
printf "${YELLOW}===========================================${NC}\n"

# Final Cleanup
rm -rf "$TEST_ROOT"