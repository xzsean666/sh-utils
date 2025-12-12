#!/usr/bin/env bash
# Simple PostgreSQL dump via docker exec, driven by config.env

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="$SCRIPT_DIR/config.env"
DRY_RUN=0

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
EOF
}

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
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

main() {
    parse_args "$@"
    load_config
    ensure_backup_dir
    run_dump
    prune_old_backups
}

main "$@"
