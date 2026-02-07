#!/bin/bash

# --- Configuration ---
SRC="/volume1/zalohaDiskuAKompu/zaloha/"
DEST="/volume1/homes/OndrejMan/zaloha/"
LOG_FILE="rsync_vystup.log"
ZALOHA_DIR="zaloha_$(date +%Y-%m-%d_%H-%M)"

# --- Argument Parsing ---
MOVE_FLAG=""
DRY_RUN_FLAG="--dry-run"
DO_CLEANUP=false

for arg in "$@"; do
    case $arg in
        -move)
            MOVE_FLAG="--remove-source-files"
            DO_CLEANUP=true
            ;;
        -real)
            DRY_RUN_FLAG=""
            ;;
    esac
done

# Inform the user of the active mode
echo "Running rsync with: ${DRY_RUN_FLAG:-[REAL MODE]} ${MOVE_FLAG:-[COPY ONLY]}"

# --- Execution ---
# We use 'bash -c' so that the directory cleanup only happens if rsync succeeds (exit code 0)
nohup bash -c "rsync -ahc -v --stats \
    --one-file-system \
    --backup \
    --backup-dir='$ZALOHA_DIR' \
    --suffix='.old' \
    $MOVE_FLAG \
    $DRY_RUN_FLAG \
    '$SRC' \
    '$DEST' \
    && if [ '$DO_CLEANUP' = true ] && [ -z '$DRY_RUN_FLAG' ]; then \
        find '$SRC' -type d -empty -delete; \
    fi" > "$LOG_FILE" 2>&1 &

echo "Process started in background. Monitor with: tail -f $LOG_FILE"