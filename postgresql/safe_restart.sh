#!/usr/bin/env bash
# safe_restart.sh - Safely restarts or starts PostgreSQL for repmgr
set -euo pipefail

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
LOG_FILE="/var/log/postgresql/repmgr-safe-restart.log"

log() {
    echo "[$(date -Iseconds)] [safe_restart] $*" >> "$LOG_FILE"
}

log "Executing safe restart/start..."

# Check if PostgreSQL is running by checking the postmaster.pid file
if [ -f "$PGDATA/postmaster.pid" ]; then
    # PID file exists, check if the process is actually running
    if ps -p "$(head -n 1 "$PGDATA/postmaster.pid")" > /dev/null; then
        log "PostgreSQL is running. Attempting graceful restart..."
        if gosu postgres pg_ctl -D "$PGDATA" -w restart -m fast; then
            log "Restart successful."
            exit 0
        else
            log "ERROR: Restart command failed."
            exit 1
        fi
    else
        log "Postmaster PID file is stale. Removing and attempting to start."
        rm -f "$PGDATA/postmaster.pid"
    fi
fi

# If we reach here, PostgreSQL is not running
log "PostgreSQL is not running. Attempting to start..."
if gosu postgres pg_ctl -D "$PGDATA" -w start; then
    log "Start successful."
    exit 0
else
    log "ERROR: Start command failed."
    exit 1
fi
