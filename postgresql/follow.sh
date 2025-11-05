#!/bin/bash
# /etc/repmgr/follow.sh
# This script is executed on a standby when it's instructed to follow a new primary.

set -euo pipefail

NEW_PRIMARY_NODE_ID=$1
NEW_PRIMARY_HOST=$2
NEW_PRIMARY_DATA_DIR=$3 # repmgr provides this, though we may not use it directly

REPMGR_CONF="/etc/repmgr/repmgr.conf"

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - follow.sh: $1"
}

log "Instructed to follow new primary (Node ID: ${NEW_PRIMARY_NODE_ID}, Host: ${NEW_PRIMARY_HOST})."

# It's crucial to stop the local PostgreSQL instance before attempting to follow,
# especially if pg_rewind is needed. The 'repmgr standby follow' command
# handles this, but we log it for clarity.
log "Executing 'repmgr standby follow' to sync with new primary..."

# The --log-to-file is important for capturing detailed output from the follow command
# for debugging purposes, without polluting the main repmgrd logs.
if gosu postgres repmgr -f "$REPMGR_CONF" standby follow --log-to-file --upstream-node-id="$NEW_PRIMARY_NODE_ID"; then
    log "Successfully started following new primary."
    # The 'repmgr standby follow' command will restart the PostgreSQL server.
    # No further action is needed here.
    exit 0
else
    log "CRITICAL: 'repmgr standby follow' command failed. The node may be in an inconsistent state."
    # Exiting with a non-zero status will signal failure to repmgrd.
    exit 1
fi
