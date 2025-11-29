#!/bin/bash

# Advanced SSH file transfer script with compression, splitting, and resumable transfers
# Usage: ./ssh-copy.sh --input <source_file> --output <destination_path> --ssh <ssh_connection_string>
# Example: ./ssh-copy.sh --input /data/large-directory --output /remote/path/ --ssh "ssh -i ~/.ssh/id_rsa user@host"
# Check status: ./ssh-copy.sh --status <task_id>
# View logs: ./ssh-copy.sh --logs <task_id>
# List tasks: ./ssh-copy.sh --list

set -e

# Initialize variables
input_path=""
output_path=""
ssh_string=""
ssh_key=""
ssh_port=""
ssh_user=""
ssh_host=""
ssh_extra_opts=""
check_status=""
view_logs=""
list_tasks=false
auto_install=false

# Configuration
SPLIT_SIZE="500M"  # Split files larger than 500MB
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
COMPRESS_THREADS=$((CPU_CORES / 2))
[ "$COMPRESS_THREADS" -lt 1 ] && COMPRESS_THREADS=1

# Directory for storing task information
TASK_DIR="/tmp/ssh-copy-tasks"
TEMP_DIR="/tmp/ssh-copy-temp"
mkdir -p "$TASK_DIR"
mkdir -p "$TEMP_DIR"

# Detect OS type
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
    elif [ "$(uname)" = "Darwin" ]; then
        OS="macos"
    else
        OS="unknown"
    fi
    echo "$OS"
}

# Function to check if running as root or with sudo
can_install() {
    if [ "$EUID" -eq 0 ]; then
        return 0
    elif command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to install packages based on OS
install_package() {
    local package=$1
    local os_type=$(detect_os)
    
    echo "Installing $package..."
    
    case "$os_type" in
        ubuntu|debian|pop)
            if [ "$EUID" -eq 0 ]; then
                apt-get update -qq && apt-get install -y "$package"
            else
                sudo apt-get update -qq && sudo apt-get install -y "$package"
            fi
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if [ "$EUID" -eq 0 ]; then
                yum install -y "$package" || dnf install -y "$package"
            else
                sudo yum install -y "$package" || sudo dnf install -y "$package"
            fi
            ;;
        arch|manjaro)
            if [ "$EUID" -eq 0 ]; then
                pacman -Sy --noconfirm "$package"
            else
                sudo pacman -Sy --noconfirm "$package"
            fi
            ;;
        macos)
            if command -v brew &> /dev/null; then
                brew install "$package"
            else
                echo "Error: Homebrew not found. Please install Homebrew first:"
                echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                return 1
            fi
            ;;
        *)
            echo "Error: Unsupported OS type: $os_type"
            echo "Please install $package manually"
            return 1
            ;;
    esac
}

# Function to check and install dependencies
check_and_install_dependencies() {
    local missing_deps=()
    local optional_deps=()
    
    # Required dependencies
    local required_tools=("tmux" "rsync" "tar" "md5sum" "openssl")
    
    # Optional but recommended dependencies
    local optional_tools=("pigz" "pbzip2")
    
    echo "Checking dependencies..."
    
    # Check required tools
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            # Special case for md5sum on macOS
            if [ "$tool" = "md5sum" ] && [ "$(uname)" = "Darwin" ]; then
                if command_exists "md5"; then
                    echo "  ✓ md5 (macOS equivalent of md5sum) found"
                    continue
                fi
            fi
            missing_deps+=("$tool")
            echo "  ✗ $tool not found"
        else
            echo "  ✓ $tool found"
        fi
    done
    
    # Check optional tools
    local has_compressor=false
    for tool in "${optional_tools[@]}"; do
        if command_exists "$tool"; then
            echo "  ✓ $tool found (optional, for faster compression)"
            has_compressor=true
        fi
    done
    
    if [ "$has_compressor" = false ]; then
        echo "  ℹ pigz/pbzip2 not found (optional, will use standard gzip)"
        optional_deps+=("pigz")
    fi
    
    # Install missing dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo ""
        echo "Missing required dependencies: ${missing_deps[*]}"
        
        if can_install; then
            echo "Attempting to install missing dependencies..."
            for dep in "${missing_deps[@]}"; do
                # Map tool names to package names
                case "$dep" in
                    md5sum)
                        # md5sum is usually in coreutils
                        install_package "coreutils" || {
                            echo "Warning: Failed to install $dep"
                            exit 1
                        }
                        ;;
                    *)
                        install_package "$dep" || {
                            echo "Warning: Failed to install $dep"
                            exit 1
                        }
                        ;;
                esac
            done
            echo "✓ All required dependencies installed successfully"
        else
            echo ""
            echo "Error: Cannot install dependencies automatically."
            echo "Please run this script with sudo or install manually:"
            echo ""
            local os_type=$(detect_os)
            case "$os_type" in
                ubuntu|debian|pop)
                    echo "  sudo apt-get install ${missing_deps[*]}"
                    ;;
                centos|rhel|fedora|rocky|almalinux)
                    echo "  sudo yum install ${missing_deps[*]}"
                    ;;
                arch|manjaro)
                    echo "  sudo pacman -S ${missing_deps[*]}"
                    ;;
                macos)
                    echo "  brew install ${missing_deps[*]}"
                    ;;
                *)
                    echo "  Please install: ${missing_deps[*]}"
                    ;;
            esac
            exit 1
        fi
    fi
    
    # Ask about optional dependencies
    if [ ${#optional_deps[@]} -gt 0 ]; then
        echo ""
        echo "Optional dependencies available for better performance:"
        echo "  - pigz: Multi-threaded compression (much faster than gzip)"
        echo ""
        
        if can_install; then
            if [ "$auto_install" = true ]; then
                echo "Auto-install enabled, installing optional dependencies..."
                for dep in "${optional_deps[@]}"; do
                    install_package "$dep" || echo "Warning: Failed to install $dep (optional)"
                done
            else
                read -p "Install optional dependencies? [y/N] " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    for dep in "${optional_deps[@]}"; do
                        install_package "$dep" || echo "Warning: Failed to install $dep (optional)"
                    done
                fi
            fi
        fi
    fi
    
    echo ""
    echo "✓ Dependency check completed"
    echo ""
}

# Function to generate random task ID
generate_task_id() {
    echo "task_$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4)"
}

# Function to check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to get file size in bytes
get_file_size() {
    stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null
}

# Function to convert size string to bytes
size_to_bytes() {
    local size_str="$1"
    local number="${size_str%[A-Za-z]*}"
    local unit="${size_str#$number}"
    
    case "$unit" in
        K|k) echo $((number * 1024)) ;;
        M|m) echo $((number * 1024 * 1024)) ;;
        G|g) echo $((number * 1024 * 1024 * 1024)) ;;
        *) echo "$number" ;;
    esac
}

# Function to create remote receiver script
create_remote_receiver() {
    local remote_path="$1"
    local archive_name="$2"
    local is_split="$3"
    
    cat << 'REMOTE_SCRIPT_EOF'
#!/bin/bash
set -e

REMOTE_PATH="__REMOTE_PATH__"
ARCHIVE_NAME="__ARCHIVE_NAME__"
IS_SPLIT="__IS_SPLIT__"

cd "$REMOTE_PATH"

echo "Received file(s) at: $REMOTE_PATH"

if [ "$IS_SPLIT" = "true" ]; then
    echo "Merging split files..."
    cat ${ARCHIVE_NAME}.part.* > "$ARCHIVE_NAME"
    
    echo "Verifying merged file..."
    if [ -f "${ARCHIVE_NAME}.md5" ]; then
        md5sum -c "${ARCHIVE_NAME}.md5"
    fi
    
    echo "Removing split files..."
    rm -f ${ARCHIVE_NAME}.part.*
fi

echo "Extracting archive..."
if [[ "$ARCHIVE_NAME" == *.tar.gz ]]; then
    tar -xzf "$ARCHIVE_NAME"
elif [[ "$ARCHIVE_NAME" == *.tar.bz2 ]]; then
    tar -xjf "$ARCHIVE_NAME"
elif [[ "$ARCHIVE_NAME" == *.tar ]]; then
    tar -xf "$ARCHIVE_NAME"
fi

echo "Removing archive..."
rm -f "$ARCHIVE_NAME" "${ARCHIVE_NAME}.md5"

echo "✓ Transfer and extraction completed successfully!"
REMOTE_SCRIPT_EOF
}

# Function to display usage
usage() {
    echo "Usage: $0 [MODE] [OPTIONS]"
    echo ""
    echo "Modes:"
    echo "  Transfer mode (runs in tmux background):"
    echo "    $0 --input <source_file> --output <destination_path> --ssh <ssh_connection_string>"
    echo ""
    echo "  Status mode:"
    echo "    $0 --status <task_id>"
    echo ""
    echo "  Logs mode:"
    echo "    $0 --logs <task_id>"
    echo ""
    echo "  List mode:"
    echo "    $0 --list"
    echo ""
    echo "Options:"
    echo "  --input          Source file or directory path to transfer"
    echo "  --output         Destination path on remote server"
    echo "  --ssh            SSH connection string (e.g., 'user@host' or 'ssh -i key -p 2222 user@host')"
    echo "  --status         Check status of a task"
    echo "  --logs           View logs of a task"
    echo "  --list           List all tasks"
    echo "  --auto-install   Automatically install missing dependencies without prompting"
    echo ""
    echo "Examples:"
    echo "  # Start transfer (returns task ID immediately)"
    echo "  $0 --input file.tar.gz --output /remote/path/ --ssh 'root@198.50.126.194'"
    echo ""
    echo "  # With SSH key and port"
    echo "  $0 --input file.tar.gz --output /remote/path/ --ssh 'ssh -i ~/.ssh/id_rsa -p 2222 user@host'"
    echo ""
    echo "  # Auto-install dependencies and start transfer"
    echo "  $0 --input /data/mydir --output /remote/path/ --ssh 'user@host' --auto-install"
    echo ""
    echo "  # Check task status"
    echo "  $0 --status task_20251016_143052_a1b2c3d4"
    echo ""
    echo "  # View task logs"
    echo "  $0 --logs task_20251016_143052_a1b2c3d4"
    echo ""
    echo "  # List all tasks"
    echo "  $0 --list"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --input)
            input_path="$2"
            shift 2
            ;;
        --output)
            output_path="$2"
            shift 2
            ;;
        --ssh)
            ssh_string="$2"
            shift 2
            ;;
        --status)
            check_status="$2"
            shift 2
            ;;
        --logs)
            view_logs="$2"
            shift 2
            ;;
        --list)
            list_tasks=true
            shift
            ;;
        --auto-install)
            auto_install=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Handle status check mode
if [ -n "$check_status" ]; then
    task_info_file="$TASK_DIR/$check_status/info.txt"
    task_log_file="$TASK_DIR/$check_status/transfer.log"
    
    if [ ! -f "$task_info_file" ]; then
        echo "Error: Task '$check_status' not found"
        exit 1
    fi
    
    echo "=========================================="
    echo "Task Status: $check_status"
    echo "=========================================="
    cat "$task_info_file"
    echo ""
    
    # Check if tmux session exists
    session_name="ssh-copy-$check_status"
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "Status: Running"
    else
        if grep -q "✓ Transfer completed successfully!" "$task_log_file" 2>/dev/null; then
            echo "Status: Completed Successfully"
        elif grep -q "✗ Transfer failed!" "$task_log_file" 2>/dev/null; then
            echo "Status: Failed"
        else
            echo "Status: Unknown (session ended)"
        fi
    fi
    echo "=========================================="
    echo ""
    echo "To view full logs: $0 --logs $check_status"
    echo "To attach to session: tmux attach -t $session_name"
    exit 0
fi

# Handle logs view mode
if [ -n "$view_logs" ]; then
    task_log_file="$TASK_DIR/$view_logs/transfer.log"
    
    if [ ! -f "$task_log_file" ]; then
        echo "Error: Logs for task '$view_logs' not found"
        exit 1
    fi
    
    echo "=========================================="
    echo "Task Logs: $view_logs"
    echo "=========================================="
    cat "$task_log_file"
    exit 0
fi

# Handle list tasks mode
if [ "$list_tasks" = true ]; then
    echo "=========================================="
    echo "All SSH Copy Tasks"
    echo "=========================================="
    echo ""
    
    if [ -z "$(ls -A "$TASK_DIR" 2>/dev/null)" ]; then
        echo "No tasks found."
        exit 0
    fi
    
    for task_dir in "$TASK_DIR"/task_*; do
        if [ -d "$task_dir" ]; then
            task_id=$(basename "$task_dir")
            task_info_file="$task_dir/info.txt"
            task_log_file="$task_dir/transfer.log"
            session_name="ssh-copy-$task_id"
            
            echo "Task ID: $task_id"
            
            if [ -f "$task_info_file" ]; then
                echo "---"
                cat "$task_info_file"
            fi
            
            # Check status
            if tmux has-session -t "$session_name" 2>/dev/null; then
                echo "Status:  ⏳ Running"
            else
                if grep -q "✓ Transfer completed successfully!" "$task_log_file" 2>/dev/null; then
                    echo "Status:  ✓ Completed"
                elif grep -q "✗ Transfer failed!" "$task_log_file" 2>/dev/null; then
                    echo "Status:  ✗ Failed"
                else
                    echo "Status:  ? Unknown"
                fi
            fi
            
            echo ""
            echo "----------------------------------------"
            echo ""
        fi
    done
    
    exit 0
fi

# Validate required parameters for transfer mode
if [ -z "$input_path" ] || [ -z "$output_path" ] || [ -z "$ssh_string" ]; then
    echo "Error: Missing required parameters"
    usage
fi

# Check if input file exists
if [ ! -e "$input_path" ]; then
    echo "Error: Input file/directory '$input_path' does not exist"
    exit 1
fi

# Check and install dependencies before proceeding
check_and_install_dependencies

# Parse SSH connection string
# Remove 'ssh' prefix if present
ssh_string=$(echo "$ssh_string" | sed 's/^ssh[[:space:]]*//')

# Extract SSH key path (if -i or --identity specified)
if echo "$ssh_string" | grep -q -E '\-i[[:space:]]+'; then
    ssh_key=$(echo "$ssh_string" | grep -oP '\-i\s+\K[^\s]+')
    ssh_string=$(echo "$ssh_string" | sed -E 's/\-i[[:space:]]+[^\s]+//g')
fi

# Extract port (if -p or --port specified)
if echo "$ssh_string" | grep -q -E '\-p[[:space:]]+'; then
    ssh_port=$(echo "$ssh_string" | grep -oP '\-p\s+\K[0-9]+')
    ssh_string=$(echo "$ssh_string" | sed -E 's/\-p[[:space:]]+[0-9]+//g')
fi

# Extract other SSH options (like -o StrictHostKeyChecking=no)
ssh_extra_opts=$(echo "$ssh_string" | grep -oP '\-o\s+[^\s]+' || true)
ssh_string=$(echo "$ssh_string" | sed -E 's/\-o[[:space:]]+[^\s]+//g')

# Extract user@host (should be the last remaining part)
ssh_connection=$(echo "$ssh_string" | xargs | awk '{print $NF}')

if [[ $ssh_connection =~ ^([^@]+)@([^@]+)$ ]]; then
    ssh_user="${BASH_REMATCH[1]}"
    ssh_host="${BASH_REMATCH[2]}"
elif [[ $ssh_connection =~ ^[^@]+$ ]]; then
    # Only host provided, use current user
    ssh_host="$ssh_connection"
    ssh_user="$USER"
else
    echo "Error: Invalid SSH connection string format"
    echo "Expected format: [user@]host or ssh [options] [user@]host"
    exit 1
fi

# Expand SSH key path
if [ -n "$ssh_key" ]; then
    ssh_key="${ssh_key/#\~/$HOME}"
    if [ ! -f "$ssh_key" ]; then
        echo "Error: SSH key file '$ssh_key' does not exist"
        exit 1
    fi
fi

# Build SSH command base
ssh_cmd="ssh"
[ -n "$ssh_key" ] && ssh_cmd="$ssh_cmd -i \"$ssh_key\""
[ -n "$ssh_port" ] && ssh_cmd="$ssh_cmd -p $ssh_port"
if [ -n "$ssh_extra_opts" ]; then
    ssh_cmd="$ssh_cmd $ssh_extra_opts"
else
    ssh_cmd="$ssh_cmd -o StrictHostKeyChecking=no"
fi
ssh_cmd="$ssh_cmd ${ssh_user}@${ssh_host}"

# Build rsync command base (for resumable transfers)
rsync_cmd="rsync -avz --progress --partial"
[ -n "$ssh_key" ] && rsync_cmd="$rsync_cmd -e 'ssh -i \"$ssh_key\"'"
[ -n "$ssh_port" ] && rsync_cmd="$rsync_cmd -e 'ssh -p $ssh_port'"

# Prepare transfer variables
needs_compression=false
needs_split=false
transfer_file="$input_path"
archive_name=""
is_directory=false

# Check if input is a directory - needs compression
if [ -d "$input_path" ]; then
    is_directory=true
    needs_compression=true
    archive_name="$(basename "$input_path").tar.gz"
    echo "Input is a directory - will compress before transfer"
fi

# Check for compression tools
if [ "$needs_compression" = true ]; then
    if command_exists pigz; then
        compress_cmd="pigz -p $COMPRESS_THREADS"
        compress_type="gz"
    elif command_exists pbzip2; then
        compress_cmd="pbzip2 -p$COMPRESS_THREADS"
        compress_type="bz2"
        archive_name="${archive_name%.tar.gz}.tar.bz2"
    else
        compress_cmd="gzip"
        compress_type="gz"
        echo "Warning: pigz not found, using single-threaded gzip"
    fi
fi

# Generate task ID and prepare directories
task_id=$(generate_task_id)
task_dir="$TASK_DIR/$task_id"
task_work_dir="$TEMP_DIR/$task_id"
mkdir -p "$task_dir"
mkdir -p "$task_work_dir"

task_info_file="$task_dir/info.txt"
task_log_file="$task_dir/transfer.log"
task_cmd_file="$task_dir/command.sh"

# Determine final archive name and check if splitting is needed
if [ "$needs_compression" = true ]; then
    transfer_file="$task_work_dir/$archive_name"
else
    archive_name=$(basename "$input_path")
    # Check if file needs splitting
    file_size=$(get_file_size "$input_path")
    split_threshold=$(size_to_bytes "$SPLIT_SIZE")
    if [ "$file_size" -gt "$split_threshold" ]; then
        needs_split=true
        transfer_file="$input_path"
        echo "File is large ($(numfmt --to=iec-i --suffix=B $file_size)), will split for transfer"
    fi
fi

# Save task information
cat > "$task_info_file" << EOF
Source:      $input_path
Destination: ${ssh_user}@${ssh_host}:${output_path}
SSH Key:     ${ssh_key:-N/A}
Port:        ${ssh_port:-22}
Compression: $([ "$needs_compression" = true ] && echo "Yes ($COMPRESS_THREADS threads)" || echo "No")
Split:       $([ "$needs_split" = true ] && echo "Yes ($SPLIT_SIZE chunks)" || echo "No")
Created:     $(date '+%Y-%m-%d %H:%M:%S')
EOF

# Create wrapper script for tmux
cat > "$task_cmd_file" << 'TASK_SCRIPT_EOF'
#!/bin/bash
set -e

TASK_ID="__TASK_ID__"
INPUT_PATH="__INPUT_PATH__"
OUTPUT_PATH="__OUTPUT_PATH__"
SSH_USER="__SSH_USER__"
SSH_HOST="__SSH_HOST__"
SSH_KEY="__SSH_KEY__"
SSH_PORT="__SSH_PORT__"
SSH_CMD="__SSH_CMD__"
NEEDS_COMPRESSION=__NEEDS_COMPRESSION__
NEEDS_SPLIT=__NEEDS_SPLIT__
ARCHIVE_NAME="__ARCHIVE_NAME__"
TRANSFER_FILE="__TRANSFER_FILE__"
TASK_WORK_DIR="__TASK_WORK_DIR__"
COMPRESS_CMD="__COMPRESS_CMD__"
COMPRESS_THREADS=__COMPRESS_THREADS__
SPLIT_SIZE="__SPLIT_SIZE__"

cd "$(pwd)"

echo "=========================================="
echo "Advanced SSH File Transfer"
echo "=========================================="
echo "Task ID:     $TASK_ID"
echo "Source:      $INPUT_PATH"
echo "Destination: ${SSH_USER}@${SSH_HOST}:${OUTPUT_PATH}"
[ -n "$SSH_KEY" ] && [ "$SSH_KEY" != "N/A" ] && echo "SSH Key:     $SSH_KEY"
[ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "N/A" ] && echo "Port:        $SSH_PORT"
echo "Compression: $([ "$NEEDS_COMPRESSION" = true ] && echo "Yes ($COMPRESS_THREADS threads)" || echo "No")"
echo "Split:       $([ "$NEEDS_SPLIT" = true ] && echo "Yes ($SPLIT_SIZE chunks)" || echo "No")"
echo "=========================================="
echo ""
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Step 1: Compress directory if needed
if [ "$NEEDS_COMPRESSION" = true ]; then
    echo "[1/5] Compressing directory..."
    echo "Using $COMPRESS_THREADS CPU cores for compression"
    
    cd "$(dirname "$INPUT_PATH")"
    tar -cf - "$(basename "$INPUT_PATH")" | $COMPRESS_CMD > "$TRANSFER_FILE"
    
    echo "Compressed size: $(du -h "$TRANSFER_FILE" | cut -f1)"
    echo "✓ Compression completed"
    echo ""
else
    echo "[1/5] Skipping compression (file already compressed or single file)"
    echo ""
fi

# Step 2: Check if splitting is needed
if [ "$NEEDS_SPLIT" = true ] || ([ -f "$TRANSFER_FILE" ] && [ $(stat -f%z "$TRANSFER_FILE" 2>/dev/null || stat -c%s "$TRANSFER_FILE") -gt $(echo "$SPLIT_SIZE" | numfmt --from=iec) ]); then
    NEEDS_SPLIT=true
    echo "[2/5] Splitting file into chunks..."
    
    # Generate MD5 checksum
    cd "$(dirname "$TRANSFER_FILE")"
    md5sum "$(basename "$TRANSFER_FILE")" > "${ARCHIVE_NAME}.md5"
    
    # Split file
    split -b $SPLIT_SIZE -d "$TRANSFER_FILE" "${TRANSFER_FILE}.part."
    
    part_count=$(ls -1 "${TRANSFER_FILE}.part."* 2>/dev/null | wc -l)
    echo "Split into $part_count parts"
    echo "✓ Splitting completed"
    echo ""
else
    echo "[2/5] Skipping splitting (file size is manageable)"
    echo ""
fi

# Step 3: Create remote directory and upload receiver script
echo "[3/5] Preparing remote destination..."

# Ensure remote directory exists
eval $SSH_CMD "mkdir -p '${OUTPUT_PATH}'"

# Create and upload receiver script
REMOTE_SCRIPT="/tmp/receiver_${TASK_ID}.sh"
cat > "${TASK_WORK_DIR}/receiver.sh" << 'RECEIVER_EOF'
#!/bin/bash
set -e

REMOTE_PATH="__REMOTE_OUTPUT_PATH__"
ARCHIVE_NAME="__REMOTE_ARCHIVE_NAME__"
IS_SPLIT="__REMOTE_IS_SPLIT__"

cd "$REMOTE_PATH"

if [ "$IS_SPLIT" = "true" ]; then
    echo "Merging split files..."
    cat ${ARCHIVE_NAME}.part.* > "$ARCHIVE_NAME"
    
    if [ -f "${ARCHIVE_NAME}.md5" ]; then
        echo "Verifying checksum..."
        md5sum -c "${ARCHIVE_NAME}.md5" || { echo "Checksum verification failed!"; exit 1; }
        echo "✓ Checksum verified"
    fi
    
    echo "Cleaning up split files..."
    rm -f ${ARCHIVE_NAME}.part.* "${ARCHIVE_NAME}.md5"
fi

echo "Extracting archive..."
if [[ "$ARCHIVE_NAME" == *.tar.gz ]]; then
    tar -xzf "$ARCHIVE_NAME"
elif [[ "$ARCHIVE_NAME" == *.tar.bz2 ]]; then
    tar -xjf "$ARCHIVE_NAME"
elif [[ "$ARCHIVE_NAME" == *.tar ]]; then
    tar -xf "$ARCHIVE_NAME"
fi

echo "Cleaning up archive..."
rm -f "$ARCHIVE_NAME"

echo "✓ Extraction completed successfully!"
RECEIVER_EOF

# Replace placeholders
sed -i.bak "s|__REMOTE_OUTPUT_PATH__|${OUTPUT_PATH}|g" "${TASK_WORK_DIR}/receiver.sh"
sed -i.bak "s|__REMOTE_ARCHIVE_NAME__|${ARCHIVE_NAME}|g" "${TASK_WORK_DIR}/receiver.sh"
sed -i.bak "s|__REMOTE_IS_SPLIT__|${NEEDS_SPLIT}|g" "${TASK_WORK_DIR}/receiver.sh"

# Build rsync SSH options
RSYNC_SSH_OPTS="ssh"
[ -n "$SSH_KEY" ] && [ "$SSH_KEY" != "N/A" ] && RSYNC_SSH_OPTS="$RSYNC_SSH_OPTS -i $SSH_KEY"
[ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "N/A" ] && RSYNC_SSH_OPTS="$RSYNC_SSH_OPTS -p $SSH_PORT"
RSYNC_SSH_OPTS="$RSYNC_SSH_OPTS -o StrictHostKeyChecking=no"

# Upload receiver script
rsync -avz -e "$RSYNC_SSH_OPTS" ${TASK_WORK_DIR}/receiver.sh ${SSH_USER}@${SSH_HOST}:${REMOTE_SCRIPT}
eval $SSH_CMD "chmod +x ${REMOTE_SCRIPT}"

echo "✓ Remote preparation completed"
echo ""

# Step 4: Transfer files with rsync (resumable)
echo "[4/5] Transferring files..."
echo "Using rsync for resumable transfer..."
echo ""

if [ "$NEEDS_SPLIT" = true ]; then
    # Transfer split parts
    for part_file in "${TRANSFER_FILE}.part."*; do
        part_name=$(basename "$part_file")
        echo "Transferring $part_name..."
        rsync -avz --progress --partial -e "$RSYNC_SSH_OPTS" "$part_file" ${SSH_USER}@${SSH_HOST}:${OUTPUT_PATH}/${ARCHIVE_NAME}.part.$(echo $part_name | grep -oP 'part\.\K.*')
    done
    
    # Transfer MD5 checksum
    rsync -avz -e "$RSYNC_SSH_OPTS" "${TRANSFER_FILE}.md5" ${SSH_USER}@${SSH_HOST}:${OUTPUT_PATH}/${ARCHIVE_NAME}.md5
else
    # Transfer single file
    rsync -avz --progress --partial -e "$RSYNC_SSH_OPTS" "$TRANSFER_FILE" ${SSH_USER}@${SSH_HOST}:${OUTPUT_PATH}/$ARCHIVE_NAME
fi

echo ""
echo "✓ Transfer completed"
echo ""

# Step 5: Execute remote receiver script
echo "[5/5] Extracting on remote server..."
eval $SSH_CMD "bash ${REMOTE_SCRIPT}"

# Cleanup remote receiver script
eval $SSH_CMD "rm -f ${REMOTE_SCRIPT}"

echo ""
echo "✓ Remote extraction completed"
echo ""

# Cleanup local temporary files
echo "Cleaning up local temporary files..."
rm -rf "$TASK_WORK_DIR"

echo ""
echo "=========================================="
echo "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "✓ Transfer completed successfully!"
echo "=========================================="
echo ""
echo "Session will close in 30 seconds..."
sleep 30
TASK_SCRIPT_EOF

# Replace placeholders in the script
sed -i.bak "s|__TASK_ID__|${task_id}|g" "$task_cmd_file"
sed -i.bak "s|__INPUT_PATH__|${input_path}|g" "$task_cmd_file"
sed -i.bak "s|__OUTPUT_PATH__|${output_path}|g" "$task_cmd_file"
sed -i.bak "s|__SSH_USER__|${ssh_user}|g" "$task_cmd_file"
sed -i.bak "s|__SSH_HOST__|${ssh_host}|g" "$task_cmd_file"
sed -i.bak "s|__SSH_KEY__|${ssh_key:-N/A}|g" "$task_cmd_file"
sed -i.bak "s|__SSH_PORT__|${ssh_port:-N/A}|g" "$task_cmd_file"
sed -i.bak "s|__SSH_CMD__|${ssh_cmd}|g" "$task_cmd_file"
sed -i.bak "s|__NEEDS_COMPRESSION__|${needs_compression}|g" "$task_cmd_file"
sed -i.bak "s|__NEEDS_SPLIT__|${needs_split}|g" "$task_cmd_file"
sed -i.bak "s|__ARCHIVE_NAME__|${archive_name}|g" "$task_cmd_file"
sed -i.bak "s|__TRANSFER_FILE__|${transfer_file}|g" "$task_cmd_file"
sed -i.bak "s|__TASK_WORK_DIR__|${task_work_dir}|g" "$task_cmd_file"
sed -i.bak "s|__COMPRESS_CMD__|${compress_cmd:-gzip}|g" "$task_cmd_file"
sed -i.bak "s|__COMPRESS_THREADS__|${COMPRESS_THREADS}|g" "$task_cmd_file"
sed -i.bak "s|__SPLIT_SIZE__|${SPLIT_SIZE}|g" "$task_cmd_file"
rm -f "${task_cmd_file}.bak"

chmod +x "$task_cmd_file"

# Start tmux session in background
session_name="ssh-copy-$task_id"
tmux new-session -d -s "$session_name" "bash -c '$task_cmd_file 2>&1 | tee $task_log_file'"

# Return task ID immediately
echo "$task_id"