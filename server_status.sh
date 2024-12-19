#!/usr/bin/env bash

# For a given list of servers, this script will check the status of the server and notify the user if the server is down.
#
# Usage: ./server_status.sh [-i <interval>] < server_list.txt

declare -i INTERVAL=30 # Default interval is 30 seconds

if [ ! -f /var/log/server_status.log ]; then
        # Check if user has permission to write to /var/log
        if [ ! -w /var/log ]; then
                echo "Cannot write to /var/log/server_status.log; hint: use sudo when running this script for the first time" 1>&2
                exit 1
        fi
        touch /var/log/server_status.log
        chown "$USER" /var/log/server_status.log
        chmod 644 /var/log/server_status.log
fi

while getopts ":i:" opt; do
	case ${opt} in
	i)
		INTERVAL=$OPTARG
		;;
	\?)
		echo "Invalid option: $OPTARG" 1>&2
		;;
	:)
		echo "Invalid option: $OPTARG requires an argument" 1>&2
		;;
	esac
	shift $((OPTIND - 1))
done

while true; do
	clear
	echo 'Server Status Monitor'
	echo 'Status: Scanning ...'
	echo '---------------------------------'
	while read -r server_hostname; do
		server_hostname=$(echo $server_hostname | tr -d '\r')

        if [[ $server_hostname == http* ]]; then
            curl -s -o /dev/null -w "%{http_code}" "$server_hostname" | grep -E '(000|501)' &>/dev/null
            if [ $? -eq 0 ]; then
                tput setaf 1
                echo "Server: $server_hostname is down - $(date)" | tee -a /var/log/server_status.log
                tput setaf 7
            fi
            continue
        fi

		ping -c 1 "$server_hostname" | grep -E '(Destination Host Unreachable|100% packet loss)' &>/dev/null
		if [ $? -eq 0 ]; then
			tput setaf 1
			echo "Server: $server_hostname is down - $(date)" | tee -a /var/log/server_status.log
			tput setaf 7
		fi
	done <"${1:-/dev/stdin}"
	echo ""
	echo "Press [CTRL+C] to stop..."

	declare -i i
	for ((i = $INTERVAL; i > 0; i--)); do
		tput cup 1 0
		echo "Status: Next scan in $i seconds      "
		sleep 1
	done
done
