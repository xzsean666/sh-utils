#!/bin/bash

# STARTUP Service Management Script for Ubuntu
# Manages a list of commands that should run at startup

PROJECT_NAME="STARTUP"
SERVICE_FILE="/etc/systemd/system/${PROJECT_NAME}.service"
CONFIG_FILE="$HOME/.startup_commands"

# Create config file if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    touch "$CONFIG_FILE"
fi

# Initialize service on first run or if service doesn't exist
initialize_service() {
    if ! systemctl list-unit-files | grep -q "^${PROJECT_NAME}.service"; then
        echo "Service '${PROJECT_NAME}' not found. Creating default service..."
        
        # Create a basic startup script even if no commands are configured
        STARTUP_SCRIPT="/usr/local/bin/startup-commands.sh"
        
        echo "#!/bin/bash" | sudo tee "$STARTUP_SCRIPT" > /dev/null
        echo "# Auto-generated startup script" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
        echo "echo 'STARTUP service is running...'" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
        
        if [ -s "$CONFIG_FILE" ]; then
            echo "" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
            echo "# Create log directory if it doesn't exist" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
            echo "LOG_DIR=\"\$HOME/.startup_logs\"" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
            echo "mkdir -p \"\$LOG_DIR\"" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
            echo "" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
            while IFS= read -r command; do
                echo "echo \"[\$(date)] Starting: $command\" >> \"\$LOG_DIR/startup.log\"" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
                echo "$command >> \"\$LOG_DIR/startup.log\" 2>&1 &" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
                echo "echo \"[\$(date)] Finished: $command\" >> \"\$LOG_DIR/startup.log\"" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
            done < "$CONFIG_FILE"
            echo "wait" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
        fi
        
        sudo chmod +x "$STARTUP_SCRIPT"

        # Create systemd service
        SERVICE_CONTENT="[Unit]
Description=Startup Commands Service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$STARTUP_SCRIPT
Restart=no
User=$(whoami)

[Install]
WantedBy=multi-user.target"

        echo "$SERVICE_CONTENT" | sudo tee "$SERVICE_FILE" > /dev/null
        
        sudo systemctl daemon-reload
        sudo systemctl enable "${PROJECT_NAME}.service"
        sudo systemctl start "${PROJECT_NAME}.service"
        
        if [ $? -eq 0 ]; then
            echo "Service '${PROJECT_NAME}' created, enabled and started successfully."
        else
            echo "Service '${PROJECT_NAME}' created and enabled, but failed to start. Check logs with option 6."
        fi
    fi
}

# Initialize service
initialize_service

show_menu() {
    echo "=== STARTUP Service Manager ==="
    echo "1. List current startup commands"
    echo "2. Add a new startup command"
    echo "3. Remove a startup command"
    echo "4. Apply changes and restart service"
    echo "5. View service status"
    echo "6. View service logs"
    echo "7. View startup command logs"
    echo "0. Exit"
    echo "================================"
}

list_commands() {
    echo "Current startup commands:"
    if [ -s "$CONFIG_FILE" ]; then
        nl -b a "$CONFIG_FILE"
    else
        echo "No commands configured."
    fi
}

add_command() {
    read -p "Enter command to add: " NEW_COMMAND
    if [ -n "$NEW_COMMAND" ]; then
        echo "$NEW_COMMAND" >> "$CONFIG_FILE"
        echo "Command added successfully."
    else
        echo "No command entered."
    fi
}

remove_command() {
    list_commands
    if [ -s "$CONFIG_FILE" ]; then
        read -p "Enter line number to remove: " LINE_NUM
        if [[ "$LINE_NUM" =~ ^[0-9]+$ ]]; then
            sed -i "${LINE_NUM}d" "$CONFIG_FILE"
            echo "Command removed successfully."
        else
            echo "Invalid line number."
        fi
    fi
}

create_service() {
    if [ ! -s "$CONFIG_FILE" ]; then
        echo "No commands to run. Please add some commands first."
        return 1
    fi

    # Create a script that will run all commands
    STARTUP_SCRIPT="/usr/local/bin/startup-commands.sh"
    
    echo "#!/bin/bash" | sudo tee "$STARTUP_SCRIPT" > /dev/null
    echo "# Auto-generated startup script" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
    echo "" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
    echo "# Create log directory if it doesn't exist" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
    echo "LOG_DIR=\"\$HOME/.startup_logs\"" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
    echo "mkdir -p \"\$LOG_DIR\"" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
    echo "" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
    
    while IFS= read -r command; do
        echo "echo \"[\$(date)] Starting: $command\" >> \"\$LOG_DIR/startup.log\"" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
        echo "$command >> \"\$LOG_DIR/startup.log\" 2>&1 &" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
        echo "echo \"[\$(date)] Finished: $command\" >> \"\$LOG_DIR/startup.log\"" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
    done < "$CONFIG_FILE"
    
    echo "wait" | sudo tee -a "$STARTUP_SCRIPT" > /dev/null
    sudo chmod +x "$STARTUP_SCRIPT"

    # Create systemd service
    SERVICE_CONTENT="[Unit]
Description=Startup Commands Service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$STARTUP_SCRIPT
Restart=no
User=$(whoami)

[Install]
WantedBy=multi-user.target"

    echo "$SERVICE_CONTENT" | sudo tee "$SERVICE_FILE" > /dev/null
    
    sudo systemctl daemon-reload
    sudo systemctl enable "${PROJECT_NAME}.service"
    sudo systemctl restart "${PROJECT_NAME}.service"
    
    if [ $? -eq 0 ]; then
        echo "Service updated and restarted successfully."
    else
        echo "Failed to restart service. Check logs with: journalctl -u ${PROJECT_NAME}.service"
    fi
}

view_status() {
    systemctl status "${PROJECT_NAME}.service"
}

view_logs() {
    journalctl -u "${PROJECT_NAME}.service" -f
}

view_startup_logs() {
    LOG_FILE="$HOME/.startup_logs/startup.log"
    if [ -f "$LOG_FILE" ]; then
        echo "=== Startup Commands Log ==="
        tail -50 "$LOG_FILE"
        echo ""
        read -p "Press 'f' to follow logs in real-time, or Enter to return: " follow_choice
        if [ "$follow_choice" = "f" ]; then
            tail -f "$LOG_FILE"
        fi
    else
        echo "No startup command logs found. Logs will be created after running commands."
        echo "Log file location: $LOG_FILE"
    fi
}

# Main loop
while true; do
    show_menu
    read -p "Choose an option: " choice
    
    case $choice in
        1) list_commands ;;
        2) add_command ;;
        3) remove_command ;;
        4) create_service ;;
        5) view_status ;;
        6) view_logs ;;
        7) view_startup_logs ;;
        0) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
    
    echo
    read -p "Press Enter to continue..."
    clear
done
