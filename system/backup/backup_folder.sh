#!/bin/bash

# ==============================================================================
# Folder Backup Script with ZSTD Compression
# ==============================================================================

# Default Configuration (Can be overridden by config file)
# ------------------------------------------------------------------------------
SOURCE_DIR=""
BACKUP_ROOT_DIR=""
MAX_BACKUPS=7
EXCLUDE_PARAMS=()
COMPRESSION_LEVEL=3

# Function to show usage
usage() {
    echo "Usage: $0 --config <path_to_config_file>"
    echo ""
    echo "Arguments:"
    echo "  --config    Path to the configuration file (required)"
    echo ""
    echo "Example:"
    echo "  $0 --config ./my_backup_config.env"
    exit 1
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --config) SOURCE_CONFIG="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate config file
if [ -z "$SOURCE_CONFIG" ]; then
    echo "Error: Configuration file not specified."
    usage
fi

if [ ! -f "$SOURCE_CONFIG" ]; then
    echo "Error: Configuration file '$SOURCE_CONFIG' not found."
    exit 1
fi

# Load configuration
echo "Loading configuration from: $SOURCE_CONFIG"
source "$SOURCE_CONFIG"

# Validate required variables
if [ -z "$SOURCE_DIR" ]; then
    echo "Error: SOURCE_DIR is not set in the configuration file."
    exit 1
fi

if [ -z "$BACKUP_ROOT_DIR" ]; then
    echo "Error: BACKUP_ROOT_DIR is not set in the configuration file."
    exit 1
fi

# ==============================================================================
# Script Logic (Do not modify unless you know what you are doing)
# ==============================================================================

# Check if zstd is installed
if ! command -v zstd &> /dev/null; then
    echo "Error: zstd is not installed. Please install it first."
    echo "  Ubuntu/Debian: sudo apt install zstd"
    echo "  CentOS/RHEL:   sudo yum install zstd"
    exit 1
fi

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

# Get the base name of the source directory (e.g., "my_project")
SOURCE_BASENAME=$(basename "$SOURCE_DIR")

# Define the specific backup directory (e.g., "/backups/my_project_backup")
BACKUP_DIR="${BACKUP_ROOT_DIR}/${SOURCE_BASENAME}_backup"

# Create backup directory if it doesn't exist
if [ ! -d "$BACKUP_DIR" ]; then
    echo "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi

# Generate timestamp for the filename
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILENAME="${SOURCE_BASENAME}_${TIMESTAMP}.tar.zst"
BACKUP_FILEPATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

echo "----------------------------------------------------------------"
echo "Starting backup..."
echo "Source:      $SOURCE_DIR"
echo "Destination: $BACKUP_FILEPATH"
echo "----------------------------------------------------------------"

# Run tar with zstd compression
# -I "zstd -${COMPRESSION_LEVEL} -T0": Use zstd with specified compression level and auto-detected thread count
# -cf: Create archive file
# -C: Change directory before archiving (to keep paths relative in the archive)
tar "${EXCLUDE_PARAMS[@]}" -I "zstd -${COMPRESSION_LEVEL} -T0" -cf "$BACKUP_FILEPATH" -C "$(dirname "$SOURCE_DIR")" "$SOURCE_BASENAME"

if [ $? -eq 0 ]; then
    echo "✅ Backup completed successfully."
    
    # Get file size
    FILE_SIZE=$(du -h "$BACKUP_FILEPATH" | cut -f1)
    echo "Backup Size: $FILE_SIZE"
else
    echo "❌ Backup failed!"
    exit 1
fi

# Cleanup old backups
echo "----------------------------------------------------------------"
echo "Checking for old backups (Limit: $MAX_BACKUPS)..."

# Find existing backups in the directory
# ls -1tr: List one file per line, sorted by modification time (reverse), so oldest is first
EXISTING_BACKUPS=($(ls -1tr "$BACKUP_DIR"/*.tar.zst 2>/dev/null))
BACKUP_COUNT=${#EXISTING_BACKUPS[@]}

if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    REMOVE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))
    echo "Found $BACKUP_COUNT backups. Removing oldest $REMOVE_COUNT..."
    
    for ((i=0; i<REMOVE_COUNT; i++)); do
        FILE_TO_REMOVE="${EXISTING_BACKUPS[$i]}"
        echo "Removing: $FILE_TO_REMOVE"
        rm -f "$FILE_TO_REMOVE"
    done
    
    echo "Cleanup complete."
else
    echo "Backup count ($BACKUP_COUNT) is within limit ($MAX_BACKUPS). No cleanup needed."
fi

echo "----------------------------------------------------------------"
echo "Done."
