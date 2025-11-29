#!/bin/bash

# ============================================================================
# PostgreSQL Backup Script using pgBackRest
# Supports full backup, incremental backup, and restore operations
# Uses docker exec to access Bitnami PostgreSQL container
# ============================================================================

# Find the directory where the script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ENV_FILE="$SCRIPT_DIR/.env"

# Load variables from .env file if it exists
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
    echo "Loaded environment variables from $ENV_FILE"
else
    echo "No .env file found at $ENV_FILE. Using default configurations or environment variables."
fi

# Default configuration (will be overridden by .env or environment variables if set)
CONTAINER_NAME="${POSTGRES_CONTAINER:-postgresql}"
LOG_PATH="${LOG_PATH:-/var/log/pgbackup}"
CONFIG_FILE="/etc/pgbackrest/pgbackrest.conf"
PG_PASSWORD="${PG_PASSWORD:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message" | tee -a "$LOG_PATH/pgbackup.log"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" | tee -a "$LOG_PATH/pgbackup.log"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" | tee -a "$LOG_PATH/pgbackup.log"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message" | tee -a "$LOG_PATH/pgbackup.log"
            ;;
    esac
}

# Helper function to run docker exec commands with retry
run_docker_exec_with_retry() {
    local user=$1
    local container=$2
    local cmd=$3
    local retries=10 # Increased retries
    local delay=5 # Increased delay
    local attempt=1
    local output=""
    local error_output=""
    local success=0

    log "DEBUG" "Attempting command (user: $user, container: $container): $cmd"

    while [ $attempt -le $retries ]; do
        # Execute command and capture stdout and stderr separately
        output=$(docker exec -u "$user" "$container" bash -c "$cmd" 2>&1)
        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            success=1
            log "DEBUG" "Command successful on attempt $attempt."
            echo "$output"
            break
        else
            # Check if the error is due to the container restarting
            if echo "$output" | grep -q "is restarting, wait until the container is running"; then
                log "WARN" "Container $container is restarting. Retrying in $delay seconds (Attempt $attempt/$retries)."
                sleep $delay
            else
                log "ERROR" "Command failed on attempt $attempt (exit code $exit_code): $output"
                echo "$output" # Output error to console immediately if not restarting error
                break # Exit if it's a different error
            fi
        fi
        attempt=$((attempt + 1))
    done

    if [ $success -eq 0 ]; then
        log "ERROR" "Command failed after $retries attempts: $cmd"
        return 1 # Indicate failure
    else
        return 0 # Indicate success
    fi
}

# Check if container exists and is running
check_container() {
    local retries=15 # Increased retries for initial check
    local delay=10 # Increased delay
    local attempt=1

    log "INFO" "Checking if container $CONTAINER_NAME is running and ready..."

    while [ $attempt -le $retries ]; do
        # Check if container is running
        if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            log "DEBUG" "Container $CONTAINER_NAME found running on attempt $attempt."
            # Check if container is ready to accept commands
            if docker exec "$CONTAINER_NAME" echo hello &>/dev/null; then
                log "INFO" "Container $CONTAINER_NAME is running and ready."
                return 0 # Success
            else
                log "WARN" "Container $CONTAINER_NAME is running but not ready. Retrying in $delay seconds (Attempt $attempt/$retries)."
                sleep $delay
            fi
        else
            log "WARN" "Container $CONTAINER_NAME is not running. Retrying in $delay seconds (Attempt $attempt/$retries)."
            sleep $delay
        fi
        attempt=$((attempt + 1))
    done

    log "ERROR" "Container $CONTAINER_NAME is not running or not ready after $retries attempts."
    exit 1 # Exit if container is not ready after retries
}

# Initialize pgBackRest configuration
init_pgbackrest() {
    log "INFO" "Initializing pgBackRest configuration..."
    
    # Note: Backups and logs will be stored *inside* the container.
    # This is NOT recommended for production use as data may be lost if the container is removed.

    # Define internal container paths for backup repo and logs
    local CONTAINER_BACKUP_REPO="/bitnami/postgresql/pgbackrest_repo"
    local CONTAINER_LOG_PATH="/bitnami/postgresql/pgbackrest_log"

    # Create backup repository and log directories inside container as root
    docker exec -u root "$CONTAINER_NAME" bash -c "
        mkdir -p /etc/pgbackrest && \
        mkdir -p $CONTAINER_BACKUP_REPO && \
        mkdir -p $CONTAINER_LOG_PATH && \
        cat > $CONFIG_FILE << 'EOF'
[global]
repo1-path=$CONTAINER_BACKUP_REPO
repo1-retention-full=3
repo1-retention-diff=3
log-level-console=info
log-level-file=debug
log-path=$CONTAINER_LOG_PATH
start-fast=y

[main]
pg1-path=/bitnami/postgresql/data
pg1-port=5432
pg1-socket-path=/tmp
pg1-user=postgres
EOF
    "
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to initialize pgBackBackRest configuration and base directories inside container."
        exit 1
    fi

    # --- Attempt to create stanza inside container ---
    log "INFO" "Attempting to create pgBackRest stanza inside container..."
    docker exec -u postgres -e PGPASSWORD="$PG_PASSWORD" "$CONTAINER_NAME" pgbackrest --stanza=main stanza-create
    if [ $? -ne 0 ]; then
        log "WARN" "pgBackRest stanza-create failed or already exists. This might require manual intervention."
    else
        log "INFO" "pgBackRest stanza-create completed."
    fi
    # --- End of stanza creation attempt ---

    # Ensure correct ownership and permissions for the backup repository inside container
    ensure_repo_permissions
    log "INFO" "Container backup repository ownership and permissions setup attempted during init."

    # --- Attempt to configure PostgreSQL WAL archiving inside container ---
    log "INFO" "Checking PostgreSQL WAL archiving mode inside container..."
    
    # Check if archive_mode is already enabled
    ARCHIVE_MODE_STATUS=$(docker exec -u root "$CONTAINER_NAME" bash -c "grep '^archive_mode' /opt/bitnami/postgresql/conf/postgresql.conf 2>/dev/null" || echo '')
    
    if [[ ! "$ARCHIVE_MODE_STATUS" =~ "archive_mode[[:space:]]*=[[:space:]]*on" ]]; then
        log "WARN" "PostgreSQL archive_mode is not enabled. Attempting to configure..."

        # Append archiving configuration to postgresql.conf
        # Note: This modification might be lost if the container is recreated.
        docker exec -u root "$CONTAINER_NAME" bash -c "cat >> /opt/bitnami/postgresql/conf/postgresql.conf << 'EOF'

# pgBackRest Archiving Configuration (added by pgbackup.sh)
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
wal_level = replica # Ensure sufficient WAL detail for archiving
EOF
        "

        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to append WAL archiving configuration to postgresql.conf inside container."
            exit 1
        fi

        # Attempt to reload PostgreSQL configuration
        log "INFO" "Attempting to reload PostgreSQL configuration..."
        # Find the PostgreSQL process ID and send SIGHUP
        PG_PID=$(docker exec -u root "$CONTAINER_NAME" bash -c "pgrep -f '/opt/bitnami/postgresql/bin/postgres -D'")
        if [ -n "$PG_PID" ]; then
            docker exec -u root "$CONTAINER_NAME" kill -SIGHUP "$PG_PID"
            if [ $? -eq 0 ]; then
                log "INFO" "PostgreSQL configuration reload signal sent."
                log "WARN" "Please verify PostgreSQL logs inside the container to confirm successful reload."
            else
                log "WARN" "Failed to send SIGHUP to PostgreSQL process. Configuration may require a manual restart."
            fi
        else
            log "WARN" "Could not find PostgreSQL process ID to send SIGHUP. Configuration may require a manual restart."
        fi

        log "INFO" "PostgreSQL WAL archiving configuration appended. Please verify and potentially restart the container."
    else
        log "INFO" "PostgreSQL archive_mode is already enabled."
    fi
    # --- End of WAL archiving configuration attempt ---
    
    log "INFO" "pgBackRest configuration initialized"
}

# Ensure correct ownership and permissions for the backup repository inside container
ensure_repo_permissions() {
    local CONTAINER_BACKUP_REPO="/bitnami/postgresql/pgbackrest_repo"
    log "INFO" "Ensuring correct ownership and permissions for container backup repository..."

    # Recursively set ownership to postgres:postgres
    run_docker_exec_with_retry root "$CONTAINER_NAME" "chown -R postgres:postgres $CONTAINER_BACKUP_REPO"
    if [ $? -ne 0 ]; then
        log "WARN" "Failed to recursively set ownership for container backup repository. Manual intervention may be required."
    fi

    # Recursively set read/write/execute permissions for the owner
    run_docker_exec_with_retry root "$CONTAINER_NAME" "chmod -R u+rwx $CONTAINER_BACKUP_REPO"
    if [ $? -ne 0 ]; then
        log "WARN" "Failed to recursively set permissions for container backup repository. Manual intervention may be required."
    fi

    # Explicitly set ownership and permissions for archive.info (sometimes created with incorrect permissions)
    # Check if archive.info exists before attempting to change permissions
    if docker exec -u root "$CONTAINER_NAME" [ -f "$CONTAINER_BACKUP_REPO/archive/main/archive.info" ]; then
        log "INFO" "Fixing ownership and permissions for archive.info..."
        run_docker_exec_with_retry root "$CONTAINER_NAME" "chown postgres:postgres $CONTAINER_BACKUP_REPO/archive/main/archive.info"
        if [ $? -ne 0 ]; then
            log "WARN" "Failed to set ownership for archive.info. Manual intervention may be required."
        fi
        run_docker_exec_with_retry root "$CONTAINER_NAME" "chmod u+rw $CONTAINER_BACKUP_REPO/archive/main/archive.info"
        if [ $? -ne 0 ]; then
            log "WARN" "Failed to set permissions for archive.info. Manual intervention may be required."
        fi
    else
        log "WARN" "archive.info not found after stanza-create. Stanza creation might have failed."
    fi

    log "INFO" "Container backup repository ownership and permissions setup attempted."
}

# Perform full backup
full_backup() {
    log "INFO" "Starting full backup..."
    
    check_container
    ensure_repo_permissions
    
    # Execute full backup with password as root user
    if docker exec -u root -e PGPASSWORD="$PG_PASSWORD" "$CONTAINER_NAME" pgbackrest --stanza=main backup --type=full; then
        log "INFO" "Full backup completed successfully"
        
        # List backup info
        docker exec "$CONTAINER_NAME" pgbackrest --stanza=main info
    else
        log "ERROR" "Full backup failed"
        exit 1
    fi
}

# Perform incremental backup
incremental_backup() {
    log "INFO" "Starting incremental backup..."
    
    check_container
    ensure_repo_permissions
    
    # Check if full backup exists
    if ! docker exec -u root -e PGPASSWORD="$PG_PASSWORD" "$CONTAINER_NAME" pgbackrest --stanza=main info | grep -q "full backup"; then
        log "WARN" "No full backup found. Performing full backup first..."
        full_backup
        return
    fi
    
    # Execute incremental backup with password as root user
    if docker exec -u root -e PGPASSWORD="$PG_PASSWORD" "$CONTAINER_NAME" pgbackrest --stanza=main backup --type=incr; then
        log "INFO" "Incremental backup completed successfully"
        
        # List backup info
        docker exec -u root -e PGPASSWORD="$PG_PASSWORD" "$CONTAINER_NAME" pgbackrest --stanza=main info
    else
        log "ERROR" "Incremental backup failed"
        exit 1
    fi
}

# Perform differential backup
differential_backup() {
    log "INFO" "Starting differential backup..."
    
    check_container
    ensure_repo_permissions
    
    # Check if full backup exists
    if ! docker exec -u root -e PGPASSWORD="$PG_PASSWORD" "$CONTAINER_NAME" pgbackrest --stanza=main info | grep -q "full backup"; then
        log "WARN" "No full backup found. Performing full backup first..."
        full_backup
        return
    fi
    
    # Execute differential backup with password as root user
    if docker exec -u root -e PGPASSWORD="$PG_PASSWORD" "$CONTAINER_NAME" pgbackrest --stanza=main backup --type=diff; then
        log "INFO" "Differential backup completed successfully"
        
        # List backup info
        docker exec -u root -e PGPASSWORD="$PG_PASSWORD" "$CONTAINER_NAME" pgbackrest --stanza=main info
    else
        log "ERROR" "Differential backup failed"
        exit 1
    fi
}

# Restore from backup
restore_backup() {
    local restore_target="$1"
    local restore_type="$2"

    log "INFO" "Starting restore operation..."

    if [[ -z "$restore_target" ]]; then
        log "WARN" "No restore target specified. Using latest backup."
    fi

    check_container
    ensure_repo_permissions # Ensure permissions before restore

    log "INFO" "Stopping container $CONTAINER_NAME..."
    # Stop the container
    if docker stop "$CONTAINER_NAME"; then
        log "INFO" "Container $CONTAINER_NAME stopped successfully."
    else
        log "ERROR" "Failed to stop container $CONTAINER_NAME."
        exit 1
    fi

    # Prepare restore command without --force-server-shutdown (unsupported)
    local restore_cmd="pgbackrest --stanza=main restore"

    if [[ -n "$restore_target" ]]; then
        case "$restore_type" in
            "time")
                # Escape quotes in restore_target for the bash -c command
                local escaped_restore_target=$(echo "$restore_target" | sed "s/'/'\\''/g")
                restore_cmd="$restore_cmd --target='$escaped_restore_target' --type=time"
                ;;
            "xid")
                restore_cmd="$restore_cmd --target='$restore_target' --type=xid"
                ;;
            "name")
                restore_cmd="$restore_cmd --target='$restore_target' --type=name"
                ;;
            *) # Default to set if type is not specified or unknown
                restore_cmd="$restore_cmd --set='$restore_target'"
                ;;
        esac
    else
         # If no target is specified, pgbackrest restore defaults to latest with no args
         restore_cmd="pgbackrest --stanza=main restore"
    fi

    # Restore to a temporary directory inside the container first
    local TEMP_RESTORE_PATH="/tmp/pgbackrest_restore_temp"
    restore_cmd="$restore_cmd --target-db-path=$TEMP_RESTORE_PATH"

    # Execute restore command directly on the stopped container as postgres user with password
    # It's expected the container is stopped at this point for offline restore.
    log "INFO" "Executing restore command to temporary directory: $restore_cmd"
    if ! docker exec -u postgres -e PGPASSWORD="$PG_PASSWORD" "$CONTAINER_NAME" bash -c "$restore_cmd"; then
        log "ERROR" "Restore to temporary directory failed"
        exit 1 # Exit if restore fails
    fi

    log "INFO" "Restore to temporary directory completed successfully"

    # Ensure recovery.signal exists in the temporary data directory before moving, 
    # as pgBackRest might not create it in a non-standard target path.
    # This helps ensure PostgreSQL starts correctly in recovery mode after data transfer.
    log "INFO" "Ensuring recovery.signal exists in the temporary data directory..."
    # Use docker exec -u root for touch as postgres might not have permissions in /tmp directly
    if docker exec -u root "$CONTAINER_NAME" touch "$TEMP_RESTORE_PATH/recovery.signal"; then
        log "INFO" "recovery.signal created successfully in temporary directory."
    else
        log "WARN" "Failed to create recovery.signal in temporary directory. Database might not start in recovery mode after transfer."
    fi

    log "INFO" "Clearing actual PostgreSQL data directory: /bitnami/postgresql/data..."
    # Clear the actual data directory as root
    if docker exec -u root "$CONTAINER_NAME" bash -c "rm -rf /bitnami/postgresql/data/*"; then
         log "INFO" "Actual data directory cleared successfully."
    else
        log "ERROR" "Failed to clear actual data directory"
        exit 1
    fi

    log "INFO" "Moving data from temporary directory to actual data directory..."
    # Move data from temporary directory to actual data directory as root
    if docker exec -u root "$CONTAINER_NAME" bash -c "mv $TEMP_RESTORE_PATH/* /bitnami/postgresql/data/"; then
         log "INFO" "Data moved successfully."
    else
         log "ERROR" "Failed to move data from temporary directory. Restore failed."
         exit 1
    fi

    log "INFO" "Starting container $CONTAINER_NAME..."
    # Start the container
    if docker start "$CONTAINER_NAME"; then
        log "INFO" "Container $CONTAINER_NAME started successfully."
    else
        log "ERROR" "Failed to start container $CONTAINER_NAME."
        exit 1
    fi

    # The check_container function will now wait for it to be ready
    check_container # Wait for the container to be ready after restart

    log "INFO" "PostgreSQL restore completed and container restarted."
}

# List available backups
list_backups() {
    log "INFO" "Listing available backups..."
    
    check_container
    
    run_docker_exec_with_retry root "$CONTAINER_NAME" "pgbackrest --stanza=main info"
}

# Clean old backups
clean_backups() {
    local retention_days="$1"
    
    if [[ -z "$retention_days" ]]; then
        retention_days=7
    fi
    
    log "INFO" "Cleaning backups older than $retention_days days..."
    
    check_container
    
    # Expire old backups as root user
    run_docker_exec_with_retry root "$CONTAINER_NAME" "pgbackrest --stanza=main expire"
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to clean old backups"
        exit 1
    fi
}

# Setup pgBackRest stanza
setup_stanza() {
    log "INFO" "Setting up pgBackRest stanza..."

    check_container
    ensure_repo_permissions # Ensure permissions before setting up stanza

    # Create stanza as postgres user with password
    log "INFO" "Attempting to create pgBackRest stanza inside container..."
    if run_docker_exec_with_retry postgres "$CONTAINER_NAME" "export PGPASSWORD=\"$PG_PASSWORD\" && pgbackrest --stanza=main stanza-create"; then
        log "INFO" "Stanza created successfully"
    else
        log "WARN" "Stanza may already exist or creation failed"
    fi

    # Check stanza as postgres user with password
    log "INFO" "Checking pgBackRest stanza inside container..."
    if run_docker_exec_with_retry postgres "$CONTAINER_NAME" "export PGPASSWORD=\"$PG_PASSWORD\" && pgbackrest --stanza=main check"; then
        log "INFO" "Stanza check passed"
    else
        log "ERROR" "Stanza check failed"
        exit 1
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_set="$1"
    
    log "INFO" "Verifying backup integrity..."
    
    check_container
    
    local verify_cmd="pgbackrest --stanza=main verify"
    
    if [[ -n "$backup_set" ]]; then
        # Escape quotes in backup_set for the bash -c command
        local escaped_backup_set=$(echo "$backup_set" | sed "s/'/'\\''/g")
        verify_cmd="$verify_cmd --set='$escaped_backup_set'"
    fi
    
    # Execute verify as root user
    if ! run_docker_exec_with_retry root "$CONTAINER_NAME" "$verify_cmd"; then
        log "ERROR" "Backup verification failed"
        exit 1
    fi

    log "INFO" "Backup verification completed successfully"
}

# Show help
show_help() {
    cat << EOF
PostgreSQL Backup Script using pgBackRest

Usage: $0 [OPTIONS] COMMAND

Commands:
    init                    Initialize pgBackRest configuration
    setup                   Setup pgBackRest stanza
    full                    Perform full backup
    incr|incremental        Perform incremental backup  
    diff|differential       Perform differential backup
    restore [TARGET] [TYPE] Restore from backup
                           TARGET: restore point (time/xid/name/set)
                           TYPE: time|xid|name (default: set)
    list                    List available backups
    verify [SET]            Verify backup integrity
    clean [DAYS]            Clean old backups (default: 7 days)
    help                    Show this help message

Environment Variables:
    POSTGRES_CONTAINER      PostgreSQL container name (default: postgresql)
    LOG_PATH               Log file path (default: /var/log/pgbackup)

Examples:
    $0 init                 # Initialize configuration
    $0 setup                # Setup stanza
    $0 full                 # Full backup
    $0 incr                 # Incremental backup
    $0 restore              # Restore latest backup
    $0 restore "2023-12-01 10:00:00" time  # Point-in-time recovery
    $0 list                 # List backups
    $0 verify               # Verify all backups
    $0 clean 3              # Clean backups older than 3 days

EOF
}

# Main script logic
main() {
    case "${1:-help}" in
        "init")
            init_pgbackrest
            ;;
        "setup")
            setup_stanza
            ;;
        "full")
            full_backup
            ;;
        "incr"|"incremental")
            incremental_backup
            ;;
        "diff"|"differential")
            differential_backup
            ;;
        "restore")
            restore_backup "$2" "$3"
            ;;
        "list")
            list_backups
            ;;
        "verify")
            verify_backup "$2"
            ;;
        "clean")
            clean_backups "$2"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log "ERROR" "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
