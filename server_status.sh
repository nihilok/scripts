#!/usr/bin/env bash

# For a given list of servers, this script will check the status of the server and notify the user if the server is down.
#
# Usage: ./server_status.sh [-i <interval>] [-e <email>] < server_list.txt

# Constants
readonly DEFAULT_INTERVAL=30
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

send_mail() {
    local to_email="$1"
    local subject="$2"
    local body="$3"

    python3 -c "
import sys
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

smtp_server = '${MAIL_SERVER}'
smtp_port = int('${MAIL_PORT}')
smtp_user = '${MAIL_USER}'
smtp_password = '${MAIL_PASSWD}'
from_email = '${MAIL_USER}'
to_email = '${to_email}'
subject = '${subject}'
body = '${body}'

msg = MIMEMultipart()
msg['From'] = from_email
msg['To'] = to_email
msg['Subject'] = subject
msg.attach(MIMEText(body, 'plain'))

try:
    server = smtplib.SMTP_SSL(smtp_server, smtp_port)
    server.login(smtp_user, smtp_password)
    server.sendmail(from_email, to_email, msg.as_string())
    server.quit()
except Exception as e:
    print(f'Failed to send email: {e}', file=sys.stderr)
"
}

check_http_server() {
    local server="$1"
    local retry=0
    
    while [ $retry -lt $MAX_RETRIES ]; do
        if ! curl -s -o /dev/null -w "%{http_code}" "$server" | grep -E '(000|501)' &>/dev/null; then
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
        ping_output=$(ping -c 1 "$server")
        ping_status=$?

        if [ $ping_status -gt 0 ]; then
            return 1
        fi

        if echo "$ping_output" | grep -E '(Destination Host Unreachable|100% packet loss)' &>/dev/null; then
            return 1
        fi
        ((retry++))
        sleep 1
    done
    return 0
}

notify_down_server() {
    local server="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="Server: $server is down - $timestamp"
    
    echo "${RED}${message}${RESET}" >&2
    
    if [[ -n $EMAIL ]]; then
        send_mail "$EMAIL" "Server Status Alert: $server" "$message"
    fi
}

cleanup() {
    clear
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
