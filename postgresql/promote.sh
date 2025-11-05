#!/bin/bash
# /etc/repmgr/promote.sh
# This script is executed on a standby that is being promoted to primary.

set -euo pipefail

NEW_PRIMARY_NODE_ID=$1
NEW_PRIMARY_HOST=$2

REPMGR_CONF="/etc/repmgr/repmgr.conf"
PGPOOL_SERVICE_HOST=${PGPOOL_SERVICE_HOST:-"pgpool"}
PCP_PORT=${PCP_PORT:-9898}
PCP_USER=${PCP_USER:-"pcp_user"}
PCP_PASSWORD=${PCP_PASSWORD:-"postgres"}

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - promote.sh: $1"
}

log "This node (ID: ${NEW_PRIMARY_NODE_ID}, Host: ${NEW_PRIMARY_HOST}) is being promoted to primary."

# 1. Execute the promotion with repmgr
# This command will convert the standby to a primary.
log "Executing 'repmgr standby promote'..."
if ! gosu postgres repmgr -f "$REPMGR_CONF" standby promote; then
    log "CRITICAL: 'repmgr standby promote' failed. Manual intervention required."
    exit 1
fi
log "Node successfully promoted to primary."

# 2. Notify pgpool about the new primary
# The node ID from repmgr is 1-based, pgpool node index is 0-based.
PGPOOL_NODE_INDEX=$((NEW_PRIMARY_NODE_ID - 1))

log "Notifying pgpool to promote its backend node index ${PGPOOL_NODE_INDEX}."

# Create a temporary pcppass file for security
PCP_PASS_FILE=$(mktemp)
chmod 600 "$PCP_PASS_FILE"
echo "${PGPOOL_SERVICE_HOST}:${PCP_PORT}:${PCP_USER}:${PCP_PASSWORD}" > "$PCP_PASS_FILE"
export PCPPASSFILE="$PCP_PASS_FILE"

# Execute the pcp_promote_node command
pcp_promote_node -h "$PGPOOL_SERVICE_HOST" -p "$PCP_PORT" -U "$PCP_USER" -w "$PGPOOL_NODE_INDEX"
PCP_EXIT_CODE=$?

# Clean up
rm -f "$PCP_PASS_FILE"

if [ $PCP_EXIT_CODE -eq 0 ]; then
    log "Successfully notified pgpool to promote backend node ${PGPOOL_NODE_INDEX}."
else
    log "WARNING: Failed to notify pgpool. Exit code: ${PCP_EXIT_CODE}. pgpool may not be directing traffic correctly."
    # We don't exit with an error, as the PostgreSQL promotion itself was successful.
    # This failure should be logged and alerted for manual pgpool correction.
fi

log "Promotion script finished."
exit 0
