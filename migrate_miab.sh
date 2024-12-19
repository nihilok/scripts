#!/usr/bin/env bash

# This script is used to migrate a Mail-in-a-Box installation to a new server.
# Usage example:
#
# ./migrate_miab.sh [-i identity-file] [-p ssh-port] [-u user] [-b backup-dir] <old-server-ip> <new-server-ip>
#
# The script will copy the /home/user-data/backups/encrypted directory from the old server to the new server.
# It will also check if the servers are reachable and if they are Mail-in-a-Box installations (you must have already installed Mail-in-a-Box on the new server providing the same hostname and primary user as on the old server).

set -eo pipefail

# Default values
MIAB_USER=${MIAB_USER:-ubuntu}
BACKUP_DIR=${BACKUP_DIR:-/tmp}
SSH_PORT=22
TEST_FILE=/home/user-data/mailinabox.version

# Display usage information
usage() {
	echo "Usage: $0 [-i identity-file] [-p ssh-port] [-u user] [-b backup-dir] <old-server-ip> <new-server-ip>"
	echo "  -i: SSH identity file"
	echo "  -p: SSH port (default: 22)"
	echo "  -u: SSH username (default: ubuntu)"
	echo "  -b: Backup directory (default: /tmp)"
	exit 1
}

# Validate IP address
validate_ip() {
	local ip=$1
	local valid_ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

	if [[ ! $ip =~ $valid_ip_regex ]]; then
		echo "Invalid IP address: $ip"
		exit 1
	fi
}

# Parse command line arguments
while getopts ":i:p:u:b:" opt; do
	case ${opt} in
	i) IDENTITY_FILE=$OPTARG ;;
	p) SSH_PORT=$OPTARG ;;
	u) MIAB_USER=$OPTARG ;;
	b) BACKUP_DIR=$OPTARG ;;
	\?) usage ;;
	esac
done
shift $((OPTIND - 1))

# Require two arguments for server IPs
if [ $# -ne 2 ]; then
	usage
fi

OLD_SERVER_IP="$1"
NEW_SERVER_IP="$2"
ENCRYPTED_BACKUPS_DIR="/home/user-data/backup/encrypted"
SECRET_KEY_FILE="/home/user-data/backup/secret_key.txt"
TEMP_BACKUP_DIR="$BACKUP_DIR/migration"
MIGRATION_LOG_FILE="/tmp/migration.log"

# Validate IPs
validate_ip "$OLD_SERVER_IP"
validate_ip "$NEW_SERVER_IP"

# Construct SSH and SCP commands
if [ -n "$IDENTITY_FILE" ]; then
	SSH="ssh -i $IDENTITY_FILE -p $SSH_PORT"
	SCP="scp -i $IDENTITY_FILE -P $SSH_PORT"
else
	SSH="ssh -p $SSH_PORT"
	SCP="scp -P $SSH_PORT"
fi

if [ -z "$OLD_SERVER_IP" ] || [ -z "$NEW_SERVER_IP" ]; then
	usage
fi

echo "Migrating Mail-in-a-Box from $OLD_SERVER_IP to $NEW_SERVER_IP"

# Check if the user wants to continue
read -p "Do you want to continue? (y/N) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	echo "Operation cancelled by user"
	exit 0
fi

# Check if the old server is reachable
if ! $SSH ${MIAB_USER}@$OLD_SERVER_IP true; then
	echo "Old server is not reachable"
	exit 1
fi

# Check if the new server is reachable
if ! $SSH ${MIAB_USER}@$NEW_SERVER_IP true; then
	echo "New server is not reachable"
	exit 1
fi

# Check if the old server is a Mail-in-a-Box
if ! $SSH ${MIAB_USER}@$OLD_SERVER_IP "test -e $TEST_FILE"; then
	echo "Old server is not a Mail-in-a-Box"
	exit 1
fi

# Check if the new server is a Mail-in-a-Box
if ! $SSH ${MIAB_USER}@$NEW_SERVER_IP "test -e $TEST_FILE"; then
	echo "New server is not a Mail-in-a-Box; please install mailinabox before continuing."
	exit 1
fi

# Copy backups from the old server to the new server
echo "Copying $ENCRYPTED_BACKUPS_DIR from $OLD_SERVER_IP to $NEW_SERVER_IP:$TEMP_BACKUP_DIR; this may take a while..."
$SSH ${MIAB_USER}@$NEW_SERVER_IP "mkdir -p $TEMP_BACKUP_DIR"
$SCP -r ${MIAB_USER}@$OLD_SERVER_IP:$ENCRYPTED_BACKUPS_DIR/* ${MIAB_USER}@$NEW_SERVER_IP:$TEMP_BACKUP_DIR || {
    echo "File transfer failed"
    exit 1
}

# Securely retrieve passphrase
PASSPHRASE=$($SSH ${MIAB_USER}@$OLD_SERVER_IP "sudo cat $SECRET_KEY_FILE")

# Restore from backups on the new server
$SSH ${MIAB_USER}@$NEW_SERVER_IP "bash -c 'export PASSPHRASE=\"$PASSPHRASE\"; sudo -E duplicity restore --force file://$TEMP_BACKUP_DIR /home/user-data > $MIGRATION_LOG_FILE 2>&1'" || {
    echo "Something went wrong restoring files; please check $MIGRATION_LOG_FILE on $NEW_SERVER_IP before trying again."
    exit 1
}

echo "Backups restored successfully."
$SSH ${MIAB_USER}@$NEW_SERVER_IP "sudo rm -rf $MIGRATION_LOG_FILE"

# Cleanup
$SSH ${MIAB_USER}@$NEW_SERVER_IP "sudo rm -rf $TEMP_BACKUP_DIR"
echo -e "Migration complete! Run \`sudo mailinabox\` on the new machine to complete the setup.\n"
exit 0
