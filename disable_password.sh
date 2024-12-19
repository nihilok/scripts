#!/bin/bash

# Script to disable SSH password authentication and root login
# Usage: Run as root or with sudo

set -euo pipefail
IFS=$'\n\t'

# Logging
LOG_FILE="/var/log/disable_ssh.sh.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to display error messages
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root. Use sudo or switch to the root user."
fi

# Display warning and prompt for confirmation
echo "************************************************************"
echo "WARNING: This script will disable SSH password authentication"
echo "         and root login. Ensure you have SSH key-based access"
echo "         configured for all necessary user accounts."
echo "         Disabling these settings without proper SSH keys"
echo "         can lock you out of the server."
echo "************************************************************"
read -p "Do you want to proceed? (y/N): " confirm

# Check user confirmation
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled by the user."
    exit 0
fi

# Variables
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.backup_$(date +%F_%T)"

# Backup the current SSH configuration
cp "$SSHD_CONFIG" "$BACKUP_FILE" || error_exit "Failed to create backup of $SSHD_CONFIG."
echo "Backup of sshd_config created at $BACKUP_FILE"

# Function to update or add a configuration directive
update_config() {
    local directive="$1"
    local value="$2"
    
    if grep -q "^\s*#\?\s*${directive}\s\+" "$SSHD_CONFIG"; then
        # Uncomment and set the directive
        sed -i "s|^\s*#\?\s*${directive}\s\+.*|${directive} ${value}|g" "$SSHD_CONFIG"
    else
        # Append the directive at the end of the file
        echo "${directive} ${value}" >> "$SSHD_CONFIG"
    fi
}

# Disable password authentication
update_config "PasswordAuthentication" "no"

# Disable root login
update_config "PermitRootLogin" "no"

# Disable empty passwords for added security
update_config "PermitEmptyPasswords" "no"

# Disable challenge-response authentication
update_config "ChallengeResponseAuthentication" "no"

# Check SSH configuration syntax
echo "Checking SSH configuration syntax..."
if ! sshd -t; then
    echo "SSH configuration syntax is invalid. Restoring the original configuration."
    cp "$BACKUP_FILE" "$SSHD_CONFIG" || error_exit "Failed to restore the original sshd_config."
    exit 1
fi

# Function to restart SSH service
restart_sshd() {
    local services=("sshd" "ssh")
    for service in "${services[@]}"; do
        if systemctl list-units --type=service | grep -q "${service}.service"; then
            systemctl restart "$service" && return 0
        elif service --status-all 2>/dev/null | grep -q "$service"; then
            service "$service" restart && return 0
        fi
    done
    return 1
}

# Prompt to restart SSH service
read -p "Do you want to restart the SSH service now? (y/N): " restart_confirm
if [[ "$restart_confirm" =~ ^[Yy]$ ]]; then
    echo "Restarting SSH service..."
    if ! restart_sshd; then
        error_exit "Failed to restart SSH service. Please restart it manually."
    fi
else
    echo "Please restart the SSH service manually when ready."
fi

echo "SSH password authentication and root login have been successfully disabled."
echo "Please verify that you can log in using SSH keys before closing your current session."

exit 0
