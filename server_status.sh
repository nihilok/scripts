#!/usr/bin/env bash

# For a given list of servers, this script will check the status of the server and notify the user if the server is down.
#
# Usage: ./server_status.sh [-i <interval>] [-e <email>] < server_list.txt

set -euo pipefail

# Constants
readonly DEFAULT_INTERVAL=30
readonly LOG_FILE="/var/log/server_status.log"
readonly RED=$(tput setaf 1)
readonly GREEN=$(tput setaf 2)
readonly RESET=$(tput setaf 7)
readonly MAX_RETRIES=3

# Default values
declare -i INTERVAL=$DEFAULT_INTERVAL
declare EMAIL=""

show_usage() {
    echo "Usage: $(basename "$0") [-i <interval>] [-e <email>] < server_list.txt"
    echo
    echo "Options:"
    echo "  -i  Interval between checks in seconds (default: ${DEFAULT_INTERVAL})"
    echo "  -e  Email address for notifications"
    echo "  -h  Show this help message"
    exit 1
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "Invalid email address format: $email" >&2
        exit 1
    fi
}

setup_logging() {
    if [ ! -f "$LOG_FILE" ]; then
        if [ ! -w "$(dirname "$LOG_FILE")" ]; then
            echo "Cannot write to $LOG_FILE; hint: use sudo when running this script for the first time" >&2
            exit 1
        fi
        touch "$LOG_FILE"
        chown "$USER" "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi
}

check_http_server() {
    local server="$1"
    local retry=0
    
    while [ $retry -lt $MAX_RETRIES ]; do
        if ! curl -s -o /dev/null -w "%{http_code}" "$server" | grep -E '(000|4[0-9]{2}|5[0-9]{2})' &>/dev/null; then
            return 0
        fi
        ((retry++))
        sleep 1
    done
    return 1
}

check_ping_server() {
    local server="$1"
    local retry=0
    
    while [ $retry -lt $MAX_RETRIES ]; do
        if ! ping -c 1 "$server" | grep -E '(Destination Host Unreachable|100% packet loss)' &>/dev/null; then
            return 0
        fi
        ((retry++))
        sleep 1
    done
    return 1
}

notify_down_server() {
    local server="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="Server: $server is down - $timestamp"
    
    echo "${RED}${message}${RESET}" | tee -a "$LOG_FILE"
    
    if [[ -n $EMAIL ]]; then
        echo "$message" | mail -s "Server Down Alert: $server" "$EMAIL"
    fi
}

cleanup() {
    echo -e "\nExiting server monitoring..."
    exit 0
}

# Parse command line arguments
while getopts ":i:e:h" opt; do
    case ${opt} in
        i)
            if [[ ! $OPTARG =~ ^[0-9]+$ ]] || [ "$OPTARG" -lt 1 ]; then
                echo "Invalid interval: must be a positive integer" >&2
                exit 1
            fi
            INTERVAL=$OPTARG
            ;;
        e)
            EMAIL=$OPTARG
            validate_email "$EMAIL"
            ;;
        h)
            show_usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            show_usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument" >&2
            show_usage
            ;;
    esac
done

# Setup
setup_logging
trap cleanup INT TERM

# Main loop
while true; do
    clear
    echo 'Server Status Monitor'
    echo 'Status: Scanning ...'
    echo '---------------------------------'
    
    while read -r server_hostname; do
        server_hostname=$(echo "$server_hostname" | tr -d '\r')
        
        # Skip empty lines and comments
        [[ -z $server_hostname || $server_hostname =~ ^[[:space:]]*# ]] && continue
        
        if [[ $server_hostname == http* ]]; then
            if ! check_http_server "$server_hostname"; then
                notify_down_server "$server_hostname"
            else
                echo "${GREEN}Server: $server_hostname is up${RESET}"
            fi
        else
            if ! check_ping_server "$server_hostname"; then
                notify_down_server "$server_hostname"
            else
                echo "${GREEN}Server: $server_hostname is up${RESET}"
            fi
        fi
    done < "${1:-/dev/stdin}"
    
    echo
    echo "Press [CTRL+C] to stop..."
    
    declare -i i
    for ((i = INTERVAL; i > 0; i--)); do
        tput cup 1 0
        echo "Status: Next scan in $i seconds      "
        sleep 1
    done
done
