#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# 显示菜单
show_menu() {
    echo "=== Linux User Management ==="
    echo "1. Create new user"
    echo "2. List all users"
    echo "3. Check user permissions"
    echo "4. Modify user permissions"
    echo "5. Generate SSH key for existing user"
    echo "6. Delete user"
    echo "7. Exit"
    echo "=========================="
}

# 安装并配置 Docker
install_docker() {
    echo "Checking Docker installation..."
    if command -v docker &>/dev/null; then
        echo "Docker is already installed"
    else
        echo "Installing Docker..."
        if command -v apt &>/dev/null; then
            # Ubuntu/Debian
            apt update
            apt install -y docker.io
            systemctl enable --now docker
        elif command -v yum &>/dev/null; then
            # CentOS/RHEL
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            systemctl enable --now docker
        else
            echo "Unsupported distribution"
            return 1
        fi
    fi

    # 确保 docker 组存在
    if ! getent group docker >/dev/null; then
        groupadd docker
    fi

    echo "Docker installation completed"
}

# 创建新用户和 SSH 密钥
create_user() {
    read -p "Enter username: " username
    
    # 检查用户是否已存在
    if id "$username" &>/dev/null; then
        echo "User $username already exists!"
        return 1
    fi
    
    # 创建用户
    useradd -m -s /bin/bash "$username"
    
    # 设置密码
    passwd "$username"
    
    # 如果 docker 组存在，将用户添加到 docker 组
    if getent group docker >/dev/null; then
        usermod -aG docker "$username"
        echo "Added $username to docker group"
    fi
    
    # 创建 .ssh 目录和当前目录下的密钥存储目录
    user_home="/home/$username"
    ssh_dir="$user_home/.ssh"
    local_key_dir="./$username"
    mkdir -p "$ssh_dir"
    mkdir -p "$local_key_dir"
    
    # 生成 SSH 密钥对
    ssh-keygen -t rsa -b 4096 -f "$ssh_dir/id_rsa" -N "" -C "$username@$(hostname)"
    
    # 复制密钥到当前目录
    cp "$ssh_dir/id_rsa" "$local_key_dir/"
    cp "$ssh_dir/id_rsa.pub" "$local_key_dir/"
    
    # 设置权限
    cp "$ssh_dir/id_rsa.pub" "$ssh_dir/authorized_keys"
    chmod 700 "$ssh_dir"
    chmod 600 "$ssh_dir/id_rsa"
    chmod 644 "$ssh_dir/id_rsa.pub"
    chmod 644 "$ssh_dir/authorized_keys"
    chown -R "$username:$username" "$ssh_dir"
    
    # 设置本地密钥文件权限
    chmod 600 "$local_key_dir/id_rsa"
    chmod 644 "$local_key_dir/id_rsa.pub"
    # 允许当前用户访问密钥文件
    chown $SUDO_USER:$SUDO_USER "$local_key_dir/id_rsa" "$local_key_dir/id_rsa.pub"
    
    echo "User $username created successfully with SSH keys"
    echo "Private key location: $local_key_dir/id_rsa"
    echo "Public key location: $local_key_dir/id_rsa.pub"
}

# 列出所有用户
list_users() {
    echo "List of all users:"
    echo "=================="
    cat /etc/passwd | cut -d: -f1,3,4,6,7 | column -t -s:
}

# 检查用户权限
check_permissions() {
    read -p "Enter username to check permissions: " username
    
    if ! id "$username" &>/dev/null; then
        echo "User $username does not exist!"
        return 1
    fi
    
    echo "User details for $username:"
    echo "=========================="
    id "$username"
    echo -e "\nGroup memberships:"
    groups "$username"
    echo -e "\nSudo privileges:"
    sudo -l -U "$username" 2>/dev/null || echo "No sudo privileges"
}

# 修改用户权限
modify_permissions() {
    read -p "Enter username to modify permissions: " username
    
    if ! id "$username" &>/dev/null; then
        echo "User $username does not exist!"
        return 1
    fi
    
    echo "Select permission to modify:"
    echo "1. Add to sudo group"
    echo "2. Remove from sudo group"
    echo "3. Add to specific group"
    echo "4. Remove from specific group"
    echo "5. Add to docker group"
    echo "6. Remove from docker group"
    
    read -p "Enter your choice (1-6): " perm_choice
    
    case $perm_choice in
        1)
            usermod -aG sudo "$username"
            echo "Added $username to sudo group"
            ;;
        2)
            deluser "$username" sudo
            echo "Removed $username from sudo group"
            ;;
        3)
            read -p "Enter group name: " groupname
            if ! getent group "$groupname" >/dev/null; then
                read -p "Group doesn't exist. Create it? (y/n): " create_group
                if [ "$create_group" = "y" ]; then
                    groupadd "$groupname"
                else
                    return 1
                fi
            fi
            usermod -aG "$groupname" "$username"
            echo "Added $username to $groupname group"
            ;;
        4)
            read -p "Enter group name: " groupname
            deluser "$username" "$groupname"
            echo "Removed $username from $groupname group"
            ;;
        5)
            if ! getent group docker >/dev/null; then
                echo "Docker group doesn't exist. Please make sure Docker is installed."
                return 1
            fi
            usermod -aG docker "$username"
            echo "Added $username to docker group"
            ;;
        6)
            deluser "$username" docker
            echo "Removed $username from docker group"
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
}

# 为现有用户生成 SSH 密钥
generate_ssh_key() {
    read -p "Enter username: " username
    
    if ! id "$username" &>/dev/null; then
        echo "User $username does not exist!"
        return 1
    fi
    
    user_home="/home/$username"
    ssh_dir="$user_home/.ssh"
    local_key_dir="./$username"
    mkdir -p "$ssh_dir"
    mkdir -p "$local_key_dir"
    
    # 生成 SSH 密钥对
    ssh-keygen -t rsa -b 4096 -f "$ssh_dir/id_rsa" -N "" -C "$username@$(hostname)"
    
    # 复制密钥到当前目录
    cp "$ssh_dir/id_rsa" "$local_key_dir/"
    cp "$ssh_dir/id_rsa.pub" "$local_key_dir/"
    
    # 设置权限
    cp "$ssh_dir/id_rsa.pub" "$ssh_dir/authorized_keys"
    chmod 700 "$ssh_dir"
    chmod 600 "$ssh_dir/id_rsa"
    chmod 644 "$ssh_dir/id_rsa.pub"
    chmod 644 "$ssh_dir/authorized_keys"
    chown -R "$username:$username" "$ssh_dir"
    
    # 设置本地密钥文件权限
    chmod 600 "$local_key_dir/id_rsa"
    chmod 644 "$local_key_dir/id_rsa.pub"
    
    echo "SSH keys generated successfully for $username"
    echo "Private key location: $local_key_dir/id_rsa"
    echo "Public key location: $local_key_dir/id_rsa.pub"
}

# 删除用户
delete_user() {
    read -p "Enter username to delete: " username
    
    if ! id "$username" &>/dev/null; then
        echo "User $username does not exist!"
        return 1
    fi
    
    read -p "Delete home directory and mail spool? (y/n): " del_home
    if [ "$del_home" = "y" ]; then
        userdel -r "$username"
        rm -rf "./$username"  # 删除本地保存的SSH密钥目录
        echo "User $username and their home directory have been deleted"
    else
        userdel "$username"
        rm -rf "./$username"  # 删除本地保存的SSH密钥目录
        echo "User $username has been deleted (home directory preserved)"
    fi
}

# 主循环
while true; do
    show_menu
    read -p "Enter your choice (1-7): " choice
    
    case $choice in
        1) create_user ;;
        2) list_users ;;
        3) check_permissions ;;
        4) modify_permissions ;;
        5) generate_ssh_key ;;
        6) delete_user ;;
        7) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid choice. Please try again." ;;
    esac
    
    echo -e "\nPress Enter to continue..."
    read
    clear
done
