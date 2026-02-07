#!/bin/bash

# --- Setup Test Environment ---
TEST_ROOT="/tmp/rsync_test_env"
MOCK_SRC="$TEST_ROOT/source"
MOCK_DEST="$TEST_ROOT/destination"
SCRIPT="./backup.sh" # Path to your script

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

setup() {
    rm -rf "$TEST_ROOT"
    mkdir -p "$MOCK_SRC/subdir" "$MOCK_DEST"
    echo "test data" > "$MOCK_SRC/file1.txt"
    echo "sub data" > "$MOCK_SRC/subdir/file2.txt"
    
    # Temporarily override the SRC and DEST in the script for testing
    # We use sed to point the script to our mock folders
    sed -i "s|^SRC=.*|SRC=\"$MOCK_SRC/\"|" "$SCRIPT"
    sed -i "s|^DEST=.*|DEST=\"$MOCK_DEST/\"|" "$SCRIPT"
}

run_test() {
    local name=$1
    local args=$2
    echo -e "Running Test: $name..."
    
    # Run the script and wait for background process
    bash "$SCRIPT" $args
    sleep 2 # Give nohup a moment to finish
}

# --- Test Cases ---

# Test 1: Dry Run (Default)
setup
run_test "Dry Run (Default)" ""
if [ -f "$MOCK_DEST/file1.txt" ]; then
    echo -e "${RED}FAIL: Files copied during dry run${NC}"
else
    echo -e "${GREEN}PASS: Dry run performed correctly${NC}"
fi

# Test 2: Real Copy
setup
run_test "Real Copy" "-real"
if [ -f "$MOCK_DEST/file1.txt" ] && [ -f "$MOCK_SRC/file1.txt" ]; then
    echo -e "${GREEN}PASS: Files copied, source preserved${NC}"
else
    echo -e "${RED}FAIL: Copy failed or source deleted${NC}"
fi

# Test 3: Real Move & Cleanup
setup
run_test "Real Move & Cleanup" "-real -move"
if [ -f "$MOCK_DEST/file1.txt" ] && [ ! -f "$MOCK_SRC/file1.txt" ] && [ ! -d "$MOCK_SRC/subdir" ]; then
    echo -e "${GREEN}PASS: Files moved and empty dirs cleaned up${NC}"
else
    echo -e "${RED}FAIL: Move or Cleanup failed${NC}"
fi

# Cleanup after tests
# rm -rf "$TEST_ROOT"