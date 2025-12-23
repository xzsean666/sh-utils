#!/usr/bin/env bash
# PostgreSQL dump via docker exec, with optional rclone upload (S3/SSH/remote) via config.env

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="$SCRIPT_DIR/config.env"
DRY_RUN=0
LATEST_BACKUP_FILE=""
UPLOAD_TARGETS=()
RCLONE_BIN="rclone"
RCLONE_GLOBAL_FLAGS=()
RCLONE_CONFIG_FILE=""
SLACK_WEBHOOK_URL=""

usage() {
    cat <<'EOF'
Usage: pgbackup-docker.sh [--config FILE] [--dry-run] [--help]

Required config variables (config.env):
  CONTAINER_NAME   docker container name
  DB_NAME          database to dump
  DB_USER          database user
  DB_PASSWORD      password for DB_USER (used as PGPASSWORD)

Optional:
  BACKUP_DIR       where to store dumps (default: ./backups)
  RETENTION_COUNT  how many newest dumps to keep (default: 7; 0 = keep all)
  BACKUP_PREFIX    prefix for filename (default: pgbackup)
  DOCKER_BIN       docker executable (default: docker)
  PG_DUMP_OPTIONS  extra options passed to pg_dump (e.g., "--clean --if-exists")
  SLACK_WEBHOOK_URL Slack webhook URL for notifications (optional)

Upload targets (optional):
  UPLOAD_TARGETS=(S3_MAIN SSH_MIRROR ...)
  <TARGET>_TYPE     S3 | SSH (SFTP) | REMOTE
  <TARGET>_MODE     copy | sync (default copy; sync mirrors BACKUP_DIR)
  <TARGET>_RCLONE_FLAGS extra flags for rclone
  # For S3
  <TARGET>_S3_PROVIDER=<Cloudflare|Backblaze|AWS|Other>
  <TARGET>_S3_ENDPOINT=<https://...> (required for R2/B2/other)
  <TARGET>_S3_BUCKET=<bucket>
  <TARGET>_S3_PATH=<path/in/bucket> (optional)
  <TARGET>_S3_REGION=<region> (e.g., us-east-1 or auto)
  <TARGET>_S3_ACCESS_KEY=...
  <TARGET>_S3_SECRET_KEY=...
  <TARGET>_S3_SESSION_TOKEN=... (optional)
  <TARGET>_S3_FORCE_PATH_STYLE=true|false (optional)
  <TARGET>_S3_STORAGE_CLASS=STANDARD (optional)
  <TARGET>_S3_ACL=private (optional)
  # For SSH/SFTP
  <TARGET>_SSH_HOST=example.com
  <TARGET>_SSH_PATH=/dest/path
  <TARGET>_SSH_USER=root (optional)
  <TARGET>_SSH_PORT=22 (optional)
  <TARGET>_SSH_KEY_FILE=~/.ssh/id_ed25519 (optional)
  # For REMOTE (pre-configured rclone remote)
  <TARGET>_DESTINATION=myremote:/path
EOF
}

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

send_slack() {
    local status="$1"
    local message="$2"

    if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
        return 0
    fi

    local icon="✅"
    if [ "$status" != "SUCCESS" ]; then
        icon="❌"
    fi

    # Escape double quotes and newlines for JSON
    local safe_message
    safe_message=$(echo "$message" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    local text="$icon *Backup $status* - Host: $(hostname)\n$safe_message"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] Slack: $text"
        return 0
    fi

    curl -s -X POST -H 'Content-type: application/json' --data "{\"text\": \"$text\"}" "$SLACK_WEBHOOK_URL" >/dev/null || true
}

fail() {
    log "ERROR: $*"
    send_slack "FAILURE" "Error: $*"
    exit 1
}

bool_val() {
    local val="${1:-}"
    shopt -s nocasematch
    if [[ "$val" =~ ^(1|true|yes|y|on)$ ]]; then
        echo 1
    else
        echo 0
    fi
    shopt -u nocasematch
}

sanitize_key() {
    local raw=$1
    local upper
    upper=$(echo "$raw" | tr '[:lower:]' '[:upper:]')
    if [[ ! "$upper" =~ ^[A-Z0-9_]+$ ]]; then
        fail "Invalid name '$raw' in UPLOAD_TARGETS (use letters/numbers/underscores)"
    fi
    echo "$upper"
}

job_var() {
    local key=$1
    local suffix=$2
    local var="${key}_${suffix}"
    printf '%s' "${!var-}"
}

require_job_var() {
    local key=$1
    local suffix=$2
    local val
    val=$(job_var "$key" "$suffix")
    [ -n "$val" ] || fail "Target $key missing required field ${key}_${suffix}"
    printf '%s' "$val"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --dry-run|-n)
                DRY_RUN=1
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
}

load_config() {
    [ -f "$CONFIG_FILE" ] || fail "Config file not found: $CONFIG_FILE"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    CONTAINER_NAME=${CONTAINER_NAME:-}
    DB_NAME=${DB_NAME:-}
    DB_USER=${DB_USER:-}
    DB_PASSWORD=${DB_PASSWORD:-}
    BACKUP_DIR=${BACKUP_DIR:-"$SCRIPT_DIR/backups"}
    RETENTION_COUNT=${RETENTION_COUNT:-7}
    BACKUP_PREFIX=${BACKUP_PREFIX:-"pgbackup"}
    DOCKER_BIN=${DOCKER_BIN:-"docker"}
    # Default to highest compression for pg_dump custom format
    PG_DUMP_OPTIONS=${PG_DUMP_OPTIONS:--Z9}
    RCLONE_BIN=${RCLONE_BIN:-"rclone"}
    # shellcheck disable=SC2206
    RCLONE_GLOBAL_FLAGS=(${RCLONE_GLOBAL_FLAGS:-})
    RCLONE_CONFIG_FILE=${RCLONE_CONFIG_FILE:-}
    SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-}
    if [ -z "$RCLONE_CONFIG_FILE" ]; then
        if [ -f "$HOME/.config/rclone/rclone.conf" ]; then
            RCLONE_CONFIG_FILE="$HOME/.config/rclone/rclone.conf"
        else
            RCLONE_CONFIG_FILE="/dev/null"
        fi
    fi
    if declare -p UPLOAD_TARGETS >/dev/null 2>&1; then
        UPLOAD_TARGETS=("${UPLOAD_TARGETS[@]}")
    fi

    [ -n "$CONTAINER_NAME" ] || fail "CONTAINER_NAME is required"
    [ -n "$DB_NAME" ] || fail "DB_NAME is required"
    [ -n "$DB_USER" ] || fail "DB_USER is required"
    [ -n "$DB_PASSWORD" ] || fail "DB_PASSWORD is required"
}

ensure_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

build_filename() {
    local ts
    ts=$(date '+%Y%m%d_%H%M%S')
    printf '%s_%s_%s_%s.dump' "$BACKUP_PREFIX" "$CONTAINER_NAME" "$DB_NAME" "$ts"
}

run_dump() {
    local filename filepath
    filename=$(build_filename)
    filepath="$BACKUP_DIR/$filename"

    log "Starting backup: container=$CONTAINER_NAME db=$DB_NAME dest=$filepath"

    local cmd=("$DOCKER_BIN" exec -e "PGPASSWORD=$DB_PASSWORD" "$CONTAINER_NAME" pg_dump -U "$DB_USER" -Fc)
    if [ -n "$PG_DUMP_OPTIONS" ]; then
        # shellcheck disable=SC2206
        extra_opts=($PG_DUMP_OPTIONS)
        cmd+=("${extra_opts[@]}")
    fi
    cmd+=("$DB_NAME")

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] Would run: ${cmd[*]} > $filepath"
        return 0
    fi

    "${cmd[@]}" > "$filepath"
    log "Backup completed: $filepath"
    LATEST_BACKUP_FILE="$filepath"
}

prune_old_backups() {
    local pattern="$BACKUP_DIR/${BACKUP_PREFIX}_${CONTAINER_NAME}_${DB_NAME}_*.dump"
    local keep=${RETENTION_COUNT:-0}
    if [ "$keep" -le 0 ]; then
        log "Retention disabled (RETENTION_COUNT=$RETENTION_COUNT)"
        return
    fi

    mapfile -t files < <(ls -1t $pattern 2>/dev/null || true)
    local total=${#files[@]}
    if [ "$total" -le "$keep" ]; then
        log "No pruning needed (found $total, keep $keep)"
        return
    fi

    local to_delete=("${files[@]:$keep}")
    log "Pruning ${#to_delete[@]} old backup(s), keep latest $keep"
    local f
    for f in "${to_delete[@]}"; do
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[dry-run] Would delete $f"
        else
            rm -f -- "$f"
            log "Deleted $f"
        fi
    done
}

build_s3_destination() {
    local key=$1
    local provider endpoint_raw endpoint bucket path region ak sk token force_path_style storage_class acl
    provider=$(job_var "$key" "S3_PROVIDER")
    provider=${provider:-S3}
    endpoint_raw=$(job_var "$key" "S3_ENDPOINT")
    endpoint="$endpoint_raw"
    # Avoid double scheme like https://https/... by stripping leading scheme when present
    if [[ "$endpoint" =~ ^https?:// ]]; then
        endpoint="${endpoint#http://}"
        endpoint="${endpoint#https://}"
    fi
    bucket=$(require_job_var "$key" "S3_BUCKET")
    path=$(job_var "$key" "S3_PATH")
    if [ -z "$path" ]; then
        path="${CONTAINER_NAME}_backup"
    fi
    region=$(job_var "$key" "S3_REGION")
    ak=$(require_job_var "$key" "S3_ACCESS_KEY")
    sk=$(require_job_var "$key" "S3_SECRET_KEY")
    token=$(job_var "$key" "S3_SESSION_TOKEN")
    force_path_style=$(job_var "$key" "S3_FORCE_PATH_STYLE")
    storage_class=$(job_var "$key" "S3_STORAGE_CLASS")
    acl=$(job_var "$key" "S3_ACL")

    # Default to path style for common S3-compat providers if not set
    if [ -z "$force_path_style" ]; then
        case "$(echo "$provider" | tr '[:upper:]' '[:lower:]')" in
            cloudflare|backblaze) force_path_style=true ;;
        esac
    fi

    local dest=":s3,provider=${provider},access_key_id=${ak},secret_access_key=${sk}"
    [ -n "$endpoint" ] && dest+=",endpoint=${endpoint}"
    [ -n "$region" ] && dest+=",region=${region}"
    if [ -n "$force_path_style" ] && [ "$(bool_val "$force_path_style")" -eq 1 ]; then
        dest+=",force_path_style=true"
    fi
    [ -n "$storage_class" ] && dest+=",storage_class=${storage_class}"
    [ -n "$acl" ] && dest+=",acl=${acl}"
    [ -n "$token" ] && dest+=",session_token=${token}"

    dest+=":${bucket}"
    if [ -n "$path" ]; then
        dest+="/${path#/}"
    fi
    echo "$dest"
}

build_ssh_destination() {
    local key=$1
    local host path user port key_file
    host=$(require_job_var "$key" "SSH_HOST")
    path=$(require_job_var "$key" "SSH_PATH")
    user=$(job_var "$key" "SSH_USER")
    port=$(job_var "$key" "SSH_PORT")
    key_file=$(job_var "$key" "SSH_KEY_FILE")

    local dest=":sftp,host=${host}"
    [ -n "$user" ] && dest+=",user=${user}"
    [ -n "$port" ] && dest+=",port=${port}"
    [ -n "$key_file" ] && dest+=",key_file=${key_file}"
    dest+=":${path}"
    echo "$dest"
}

build_remote_destination() {
    local key=$1
    local dest
    dest=$(job_var "$key" "DESTINATION")
    [ -n "$dest" ] || dest=$(job_var "$key" "REMOTE")
    [ -n "$dest" ] || fail "Target $key missing DESTINATION/REMOTE for REMOTE type"
    echo "$dest"
}

compute_destination() {
    local key=$1
    local type
    type=$(job_var "$key" "TYPE")
    type=${type:-S3}
    type=$(echo "$type" | tr '[:lower:]' '[:upper:]')
    case "$type" in
        S3) build_s3_destination "$key" ;;
        SSH|SFTP) build_ssh_destination "$key" ;;
        REMOTE) build_remote_destination "$key" ;;
        *)
            fail "Target $key has unsupported TYPE '$type' (expected SSH/S3/REMOTE)"
            ;;
    esac
}

upload_target() {
    local key=$1
    local mode dest extra_flags
    dest=$(compute_destination "$key")
    mode=$(job_var "$key" "MODE")
    mode=${mode:-sync}
    mode=$(echo "$mode" | tr '[:upper:]' '[:lower:]')
    extra_flags=$(job_var "$key" "RCLONE_FLAGS")

    local subcommand source_path
    if [ "$mode" = "sync" ]; then
        subcommand="sync"
        source_path="$BACKUP_DIR"
    else
        subcommand="copy"
        source_path="$LATEST_BACKUP_FILE"
        [ -n "$source_path" ] || fail "LATEST_BACKUP_FILE not set; ensure backup step ran"
    fi

    local dest_masked
    dest_masked=$(echo "$dest" | sed -E 's/(access_key_id=)[^,]+/\1***/g; s/(secret_access_key=)[^,]+/\1***/g; s/(session_token=)[^,]+/\1***/g')
    log "Upload target $key -> $dest_masked ($subcommand)"

    local cmd=("$RCLONE_BIN" "$subcommand" "$source_path" "$dest" --fast-list --create-empty-src-dirs)
    if [ -n "$RCLONE_CONFIG_FILE" ]; then
        cmd+=(--config "$RCLONE_CONFIG_FILE")
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        cmd+=(--dry-run)
    fi
    if [ ${#RCLONE_GLOBAL_FLAGS[@]} -gt 0 ]; then
        cmd+=("${RCLONE_GLOBAL_FLAGS[@]}")
    fi
    if [ -n "$extra_flags" ]; then
        # shellcheck disable=SC2206
        local job_flags=($extra_flags)
        cmd+=("${job_flags[@]}")
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] Would run: ${cmd[*]}"
    else
        "${cmd[@]}"
    fi
}

upload_all_targets() {
    if [ ${#UPLOAD_TARGETS[@]} -eq 0 ]; then
        log "No UPLOAD_TARGETS configured; skip upload"
        return
    fi
    command -v "$RCLONE_BIN" >/dev/null 2>&1 || fail "rclone not found: $RCLONE_BIN"

    local key_raw key
    for key_raw in "${UPLOAD_TARGETS[@]}"; do
        key=$(sanitize_key "$key_raw")
        upload_target "$key"
    done
}

main() {
    parse_args "$@"
    load_config
    ensure_backup_dir
    run_dump
    prune_old_backups
    upload_all_targets
    send_slack "SUCCESS" "Backup completed successfully.\nFile: $(basename "$LATEST_BACKUP_FILE")"
}

main "$@"
