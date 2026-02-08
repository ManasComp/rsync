#!/bin/bash

# --- Configuration (Defaults) ---
# These are used if no paths are provided as arguments
DEFAULT_SRC="/volume1/zalohaDiskuAKompu/zaloha/"
DEFAULT_DEST="/volume1/homes/OndrejMan/zaloha/"
LOG_FILE="rsync_vystup.log"
ZALOHA_DIR="zaloha_$(date +%Y-%m-%d_%H-%M)"

# --- Argument Parsing ---
MOVE_FLAG=""
DRY_RUN_FLAG="--dry-run"
DO_CLEANUP=false
POSITIONAL_ARGS=()

# Loop through all arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -move)
            MOVE_FLAG="--remove-source-files"
            DO_CLEANUP=true
            shift # Remove -move from processing
            ;;
        -real)
            DRY_RUN_FLAG=""
            shift # Remove -real from processing
            ;;
        *)
            # Save unknown arguments (paths) to an array
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional parameters
set -- "${POSITIONAL_ARGS[@]}"

# --- Path Assignment ---
if [ ${#POSITIONAL_ARGS[@]} -eq 2 ]; then
    # User provided 2 paths
    SRC="${POSITIONAL_ARGS[0]}"
    DEST="${POSITIONAL_ARGS[1]}"
    echo "Using Custom Paths."
elif [ ${#POSITIONAL_ARGS[@]} -eq 0 ]; then
    # User provided 0 paths, use defaults
    SRC="$DEFAULT_SRC"
    DEST="$DEFAULT_DEST"
    echo "Using Default Paths."
else
    # User provided weird number of paths (like 1 or 3)
    echo "Error: You must provide exactly 2 paths (SRC DEST) or 0 paths (to use defaults)."
    echo "Usage: $0 [SRC] [DEST] [-real] [-move]"
    exit 1
fi

# Basic check to ensure Source exists
if [ ! -d "$SRC" ]; then
    echo "Error: Source directory does not exist: $SRC"
    exit 1
fi

# --- SAFETY CHECK: Trailing Slash Warning ---
if [[ "${SRC}" != */ ]]; then
    echo "-------------------------------------------------------------"
    echo -e "\033[0;33m⚠️  WARNING: Source path is missing a trailing slash.\033[0m"
    echo "   Current Source: '$SRC'"
    echo ""
    echo "   • Without a slash, rsync copies the FOLDER itself."
    echo "     (Result: $DEST/$(basename "$SRC")/...)"
    echo "   • With a slash, rsync copies the CONTENTS only."
    echo "     (Result: $DEST/...)"
    echo "-------------------------------------------------------------"
    
    # Read user input (only if running interactively)
    if [ -t 0 ]; then
        read -p "Do you want to append a slash to copy contents only? [Y/n] " -n 1 -r
        echo "" # Move to new line
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            SRC="${SRC}/"
            echo -e "\033[0;32m✅ Slash appended. New source: $SRC\033[0m"
        else
            echo "ℹ️  Keeping original source path (Folder copy mode)."
        fi
    else
        # If running non-interactively (e.g., cron), default to appending slash for safety
        # or remove this else block if you prefer it to fail/keep as is.
        echo "Non-interactive mode detected. Appending slash automatically."
        SRC="${SRC}/"
    fi
fi

# Inform the user of the active mode
echo "----------------------------------------"
echo "Source:      $SRC"
echo "Destination: $DEST"
echo "Mode:        ${DRY_RUN_FLAG:-[REAL EXECUTION]} ${MOVE_FLAG:-[COPY ONLY]}"
echo "----------------------------------------"

# --- Execution ---
# We use 'bash -c' so that the directory cleanup only happens if rsync succeeds (exit code 0)
# Note: Variables are expanded by the current shell before being passed to bash -c
nohup bash -c "rsync -ahc --stats \
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
