#!/usr/bin/env bash
# rclone_helper.sh
# Drive rclone backups from a config file. Supports SSH directory targets and S3-compatible targets (R2/B2/etc).

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
DELETE_OVERRIDE="" # 1 -> force sync (delete extras), 0 -> force copy, empty -> per job
DRY_RUN=0
SELECTED_JOBS=()
RCLONE_BIN="${RCLONE_BIN:-rclone}"
RCLONE_GLOBAL_FLAGS=()
RCLONE_CONFIG_FILE="${RCLONE_CONFIG_FILE:-}"

usage() {
    cat <<'EOF'
Usage: rclone_helper.sh [options]

Options:
  -c, --config FILE   Path to config.env (default: ./config.env next to script)
  -j, --jobs LIST     Comma-separated job names to run (default: all BACKUP_JOBS)
      --delete        Force delete mode for all jobs (use rclone sync)
      --no-delete     Force copy-only mode for all jobs
  -n, --dry-run       Show what would happen without transferring data
  -h, --help          Show this help

Config:
  BACKUP_JOBS=(JOB_A JOB_B)
  JOB_A_TYPE=SSH|S3|REMOTE   # optional; default S3. SSH builds :sftp, S3 builds :s3, REMOTE uses provided remote string
  JOB_A_SRC=/path/to/source
  JOB_A_MODE=copy|sync       # optional; overrides JOB_A_DELETE
  # SSH
  JOB_A_SSH_HOST=example.com
  JOB_A_SSH_PATH=/srv/backups/job_a
  JOB_A_SSH_USER=root (optional)
  JOB_A_SSH_PORT=22 (optional)
  JOB_A_SSH_KEY_FILE=/path/to/key (optional)
  # S3
  JOB_B_S3_PROVIDER=Cloudflare|Backblaze|AWS|Other
  JOB_B_S3_ENDPOINT=https://accountid.r2.cloudflarestorage.com
  JOB_B_S3_BUCKET=my-bucket
  JOB_B_S3_PATH=prefix/inside/bucket (optional)
  JOB_B_S3_REGION=us-east-1 (optional)
  JOB_B_S3_ACCESS_KEY=xxx
  JOB_B_S3_SECRET_KEY=yyy
  JOB_B_S3_SESSION_TOKEN=... (optional)
  JOB_B_S3_FORCE_PATH_STYLE=true|false (optional)
  JOB_B_S3_STORAGE_CLASS=STANDARD (optional)
  JOB_B_S3_ACL=private (optional)
  # REMOTE (for pre-configured rclone remotes)
  JOB_C_DESTINATION=myremote:/path
  # Common optional flags
  RCLONE_BIN=rclone
  RCLONE_GLOBAL_FLAGS="--transfers 8 --checkers 8"
  RCLONE_CONFIG_FILE=/path/to/rclone.conf (optional)
  JOB_A_DELETE=true|false     # per job delete/sync mode
  JOB_A_RCLONE_FLAGS="--transfers 8 --checkers 8"
EOF
}

log() {
    local level=$1
    shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

fail() {
    log ERROR "$*"
    exit 1
}

require_cmd() {
    local cmd=$1
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
}

require_arg() {
    local opt=$1
    local val=${2-}
    [ -n "$val" ] || fail "Option $opt requires an argument"
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

mask_sensitive() {
    echo "$1" | sed -E 's/(access_key_id=)[^,]+/\1***/g; s/(secret_access_key=)[^,]+/\1***/g; s/(session_token=)[^,]+/\1***/g'
}

job_var() {
    local job_key=$1
    local suffix=$2
    local var="${job_key}_${suffix}"
    printf '%s' "${!var-}"
}

require_job_var() {
    local job_key=$1
    local suffix=$2
    local val
    val=$(job_var "$job_key" "$suffix")
    [ -n "$val" ] || fail "Job $job_key missing required field $job_key"_"$suffix"
    printf '%s' "$val"
}

sanitize_job_key() {
    local raw=$1
    local upper
    upper=$(echo "$raw" | tr '[:lower:]' '[:upper:]')
    if [[ ! "$upper" =~ ^[A-Z0-9_]+$ ]]; then
        fail "Invalid job name '$raw'. Use letters, numbers, underscores."
    fi
    echo "$upper"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                require_arg "$1" "${2-}"
                CONFIG_FILE=$2
                shift 2
                ;;
            -j|--jobs)
                require_arg "$1" "${2-}"
                IFS=',' read -r -a SELECTED_JOBS <<<"$2"
                shift 2
                ;;
            --delete)
                DELETE_OVERRIDE=1
                shift
                ;;
            --no-delete)
                DELETE_OVERRIDE=0
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -h|--help)
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
    RCLONE_BIN=${RCLONE_BIN:-"rclone"}
    # shellcheck disable=SC2206
    RCLONE_GLOBAL_FLAGS=(${RCLONE_GLOBAL_FLAGS:-})
    RCLONE_CONFIG_FILE=${RCLONE_CONFIG_FILE:-}
    local home_dir="${HOME:-}"
    if [ -z "$RCLONE_CONFIG_FILE" ] && [ -n "$home_dir" ] && [ -f "$home_dir/.config/rclone/rclone.conf" ]; then
        RCLONE_CONFIG_FILE="$home_dir/.config/rclone/rclone.conf"
    fi
    if ! declare -p BACKUP_JOBS >/dev/null 2>&1; then
        fail "BACKUP_JOBS array not defined in $CONFIG_FILE"
    fi
}

should_run_job() {
    local job_key=$1
    if [ ${#SELECTED_JOBS[@]} -eq 0 ]; then
        return 0
    fi
    local target
    for target in "${SELECTED_JOBS[@]}"; do
        if [[ "$job_key" == "$(sanitize_job_key "$target")" ]]; then
            return 0
        fi
    done
    return 1
}

build_s3_destination() {
    local job_key=$1
    local provider endpoint_raw endpoint bucket path region ak sk token force_path_style storage_class acl
    provider=$(job_var "$job_key" "S3_PROVIDER")
    provider=${provider:-S3}
    endpoint_raw=$(job_var "$job_key" "S3_ENDPOINT")
    endpoint="$endpoint_raw"
    if [[ "$endpoint" =~ ^https?:// ]]; then
        endpoint="${endpoint#http://}"
        endpoint="${endpoint#https://}"
    fi
    bucket=$(require_job_var "$job_key" "S3_BUCKET")
    path=$(job_var "$job_key" "S3_PATH")
    region=$(job_var "$job_key" "S3_REGION")
    ak=$(require_job_var "$job_key" "S3_ACCESS_KEY")
    sk=$(require_job_var "$job_key" "S3_SECRET_KEY")
    token=$(job_var "$job_key" "S3_SESSION_TOKEN")
    force_path_style=$(job_var "$job_key" "S3_FORCE_PATH_STYLE")
    storage_class=$(job_var "$job_key" "S3_STORAGE_CLASS")
    acl=$(job_var "$job_key" "S3_ACL")

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
    local job_key=$1
    local host path user port key_file
    host=$(require_job_var "$job_key" "SSH_HOST")
    path=$(require_job_var "$job_key" "SSH_PATH")
    user=$(job_var "$job_key" "SSH_USER")
    port=$(job_var "$job_key" "SSH_PORT")
    key_file=$(job_var "$job_key" "SSH_KEY_FILE")

    local dest=":sftp,host=${host}"
    [ -n "$user" ] && dest+=",user=${user}"
    [ -n "$port" ] && dest+=",port=${port}"
    [ -n "$key_file" ] && dest+=",key_file=${key_file}"
    dest+=":${path}"
    echo "$dest"
}

build_remote_destination() {
    local job_key=$1
    local dest
    dest=$(job_var "$job_key" "DESTINATION")
    [ -n "$dest" ] || dest=$(job_var "$job_key" "REMOTE")
    [ -n "$dest" ] || fail "Job $job_key missing DESTINATION/REMOTE for REMOTE type"
    echo "$dest"
}

compute_destination() {
    local job_key=$1
    local type
    type=$(job_var "$job_key" "TYPE")
    type=${type:-S3}
    type=$(echo "$type" | tr '[:lower:]' '[:upper:]')
    case "$type" in
        S3) build_s3_destination "$job_key" ;;
        SSH|SFTP) build_ssh_destination "$job_key" ;;
        REMOTE) build_remote_destination "$job_key" ;;
        *)
            fail "Job $job_key has unsupported TYPE '$type' (expected SSH/S3/REMOTE)"
            ;;
    esac
}

run_job() {
    local job_key=$1
    local src dest mode job_delete rclone_cmd extra_flags
    src=$(require_job_var "$job_key" "SRC")
    dest=$(compute_destination "$job_key")
    extra_flags=$(job_var "$job_key" "RCLONE_FLAGS")

    mode=$(job_var "$job_key" "MODE")
    mode=$(echo "$mode" | tr '[:upper:]' '[:lower:]')
    if [ -n "$DELETE_OVERRIDE" ]; then
        job_delete=$DELETE_OVERRIDE
    elif [ -n "$mode" ]; then
        case "$mode" in
            sync) job_delete=1 ;;
            copy) job_delete=0 ;;
            *)
                fail "Job $job_key has invalid MODE '$mode' (expected copy|sync)"
                ;;
        esac
    else
        job_delete=$(bool_val "$(job_var "$job_key" "DELETE")")
    fi

    if [ "$job_delete" -eq 1 ]; then
        rclone_cmd="sync"
    else
        rclone_cmd="copy"
    fi

    if [ "$rclone_cmd" = "sync" ]; then
        [ -d "$src" ] || fail "Job $job_key source directory not found: $src"
    else
        [ -e "$src" ] || fail "Job $job_key source path not found: $src"
    fi

    local dest_masked
    dest_masked=$(mask_sensitive "$dest")
    log INFO "Job $job_key -> $dest_masked (${rclone_cmd})"

    local cmd=("$RCLONE_BIN" "$rclone_cmd" "$src" "$dest" --fast-list --create-empty-src-dirs)
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

    "${cmd[@]}"
}

main() {
    parse_args "$@"
    load_config
    require_cmd "$RCLONE_BIN"

    local job_raw job_key
    for job_raw in "${BACKUP_JOBS[@]}"; do
        job_key=$(sanitize_job_key "$job_raw")
        if should_run_job "$job_key"; then
            run_job "$job_key"
        else
            log INFO "Skipping job $job_key"
        fi
    done
}

main "$@"
