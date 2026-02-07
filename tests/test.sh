#!/bin/bash

# --- Configuration ---
TEST_ROOT="/tmp/rsync_test_env"
MOCK_SRC="$TEST_ROOT/source"
MOCK_DEST="$TEST_ROOT/destination"

# SCRIPT PATH RESOLUTION
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$TEST_DIR/../start.sh" # <--- Verified from your logs that your script is 'start.sh'

LOG_FILE="rsync_vystup.log"

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

# --- Helper Functions ---

generate_test_data() {
    printf "Generating random test data...\n"
    local depth=3
    local files_per_dir=3
    
    rm -rf "$MOCK_SRC" "$MOCK_DEST"
    mkdir -p "$MOCK_SRC" "$MOCK_DEST"

    for i in $(seq 1 $depth); do
        local dir_name="dir_$i"
        local subdir_path="$MOCK_SRC/$dir_name/sub_${RANDOM}"
        mkdir -p "$subdir_path"
        for j in $(seq 1 $files_per_dir); do
            echo "Random Content $RANDOM" > "$MOCK_SRC/root_file_$j.txt"
            echo "Deep Content $RANDOM" > "$subdir_path/deep file $j.txt"
        done
    done
}

cleanup_env() {
    rm -rf "$TEST_ROOT"
    [ -f "$LOG_FILE" ] && rm "$LOG_FILE"
}

wait_for_rsync() {
    printf "Waiting for rsync to finish..."
    local timeout=30
    local count=0
    
    # Check if rsync is running specifically on our mock source
    while pgrep -f "rsync.*$MOCK_SRC" > /dev/null; do
        if [ $count -ge $timeout ]; then
            printf " ${RED}TIMEOUT${NC}\n"
            return 1
        fi
        sleep 1
        printf "."
        ((count++))
    done
    printf " Done.\n"
}

run_test() {
    local test_name=$1
    local extra_args=$2
    
    printf "\n${YELLOW}=== Running Test: %s ===${NC}\n" "$test_name"
    
    if [ ! -f "$SCRIPT_PATH" ]; then
        printf "${RED}Error: Cannot find script at: %s${NC}\n" "$SCRIPT_PATH"
        return 1
    fi

    # IMPORTANT: We add a trailing slash (/) to MOCK_SRC.
    # This ensures rsync copies the CONTENTS of source, not the directory itself.
    printf "DEBUG: Executing -> bash %s %s %s/ %s\n" "$(basename "$SCRIPT_PATH")" "$extra_args" "$MOCK_SRC" "$MOCK_DEST"
    
    bash "$SCRIPT_PATH" $extra_args "${MOCK_SRC}/" "$MOCK_DEST"
    
    if ! wait_for_rsync; then
        printf "${RED}Test Failed: Rsync process timed out.${NC}\n"
        return 1
    fi
}

# --- Test Execution ---

cleanup_env

# ---------------------------------------------------------
# Test 1: Dry Run
# ---------------------------------------------------------
generate_test_data
run_test "Dry Run (Default)" "" 

if [ -z "$(ls -A $MOCK_DEST)" ]; then
    printf "${GREEN}PASS: Destination is empty (Dry run respected)${NC}\n"
else
    printf "${RED}FAIL: Files were copied in dry run!${NC}\n"
    ls -R "$MOCK_DEST"
fi

cleanup_env

# ---------------------------------------------------------
# Test 2: Real Copy
# ---------------------------------------------------------
generate_test_data
run_test "Real Copy" "-real"

# Compare content. 
if diff -r "$MOCK_SRC" "$MOCK_DEST" > /dev/null; then
    printf "${GREEN}PASS: Source and Destination match perfectly.${NC}\n"
else
    printf "${RED}FAIL: Content mismatch.${NC}\n"
    # Show the diff to help debug
    diff -r "$MOCK_SRC" "$MOCK_DEST" | head -n 5
fi

# Check Source existence
if [ -d "$MOCK_SRC" ] && [ "$(ls -A $MOCK_SRC)" ]; then
     printf "${GREEN}PASS: Source files preserved.${NC}\n"
else
     printf "${RED}FAIL: Source files were deleted during copy!${NC}\n"
fi

cleanup_env

# ---------------------------------------------------------
# Test 3: Real Move & Cleanup
# ---------------------------------------------------------
generate_test_data
file_count_before=$(find "$MOCK_SRC" -type f | wc -l)

run_test "Real Move & Cleanup" "-real -move"

# Check Destination
if [ "$(find "$MOCK_DEST" -type f | wc -l)" -eq "$file_count_before" ]; then
    printf "${GREEN}PASS: All files moved to destination.${NC}\n"
else
    printf "${RED}FAIL: File count mismatch in destination.${NC}\n"
fi

# Check Source Files (Should be gone). We redirect stderr to hide "No such file" errors.
if [ -z "$(find "$MOCK_SRC" -type f 2>/dev/null)" ]; then
    printf "${GREEN}PASS: Source files removed.${NC}\n"
else
    printf "${RED}FAIL: Source files still exist!${NC}\n"
    find "$MOCK_SRC" -type f
fi

# Check Source Dirs
if [ ! -d "$MOCK_SRC" ] || [ -z "$(ls -A "$MOCK_SRC" 2>/dev/null)" ]; then
    printf "${GREEN}PASS: Source cleaned up correctly.${NC}\n"
else
    printf "${RED}FAIL: Stray directories left behind.${NC}\n"
    ls -R "$MOCK_SRC"
fi

# --- Final Cleanup ---
printf "\n${YELLOW}Tests Finished.${NC}\n"
rm -rf "$TEST_ROOT"