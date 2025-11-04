#!/usr/bin/env bash
# Pgpool-II monitor & dynamic backend maintainer

set -u

log() { echo "[$(date -Iseconds)] [pgpool-monitor] $*"; }

# Config
PGPOOL_CONF=${PGPOOL_CONF:-/etc/pgpool-II/pgpool.conf}
PCP_PORT=${PCP_PORT:-9898}
# Prefer PG_BACKENDS; if empty but PG_NODES is provided (hostnames only), assume :5432
if [ -z "${PG_BACKENDS:-}" ] && [ -n "${PG_NODES:-}" ]; then
    PG_BACKENDS=$(echo "$PG_NODES" | awk -v RS=',' -v ORS=',' '{gsub(/^[\t ]+|[\t ]+$/,"",$0); printf "%s:5432", $0}' | sed 's/,$//')
fi
PG_BACKENDS=${PG_BACKENDS:-"pg-1:5432,pg-2:5432,pg-3:5432,pg-4:5432"}
CHECK_INTERVAL=${CHECK_INTERVAL:-30}

# Prefer repmgr password for backend probing; fallback to postgres
BACKEND_USER=${BACKEND_USER:-repmgr}
BACKEND_PW=${REPMGR_PASSWORD:-${POSTGRES_PASSWORD:-}}

if [ -z "${BACKEND_PW}" ]; then
    log "WARNING: No password available for backend checks; dynamic updates disabled"
    DYNAMIC_DISABLED=1
else
    DYNAMIC_DISABLED=0
fi

parse_nodes() {
    echo "$PG_BACKENDS" | tr ',' ' ' | awk -F: '{print $1}'
}

find_primary() {
    for node in $(parse_nodes); do
        if PGPASSWORD="$BACKEND_PW" psql -h "$node" -U "$BACKEND_USER" -d postgres -tAc "SELECT NOT pg_is_in_recovery();" 2>/dev/null | grep -q 't'; then
            echo "$node"; return 0
        fi
    done
    return 1
}

rewrite_backends() {
    local primary="$1"
    local tmp="$PGPOOL_CONF.tmp"
    cp "$PGPOOL_CONF" "$tmp" 2>/dev/null || return 1
    # Drop existing backend_* lines
    sed -i "/^backend_hostname[0-9]\+ *=/d" "$tmp"
    sed -i "/^backend_port[0-9]\+ *=/d" "$tmp"
    sed -i "/^backend_weight[0-9]\+ *=/d" "$tmp"
    sed -i "/^backend_data_directory[0-9]\+ *=/d" "$tmp"
    sed -i "/^backend_flag[0-9]\+ *=/d" "$tmp"
    sed -i "/^backend_application_name[0-9]\+ *=/d" "$tmp"

    local i=0 host port weight
    IFS=',' read -ra arr <<<"$PG_BACKENDS"
    for be in "${arr[@]}"; do
        host=${be%%:*}; port=${be##*:}; [ "$host" = "$port" ] && port=5432
        if [ "$host" = "$primary" ]; then weight=0; else weight=1; fi
        {
            echo "backend_hostname${i} = '${host}'"
            echo "backend_port${i} = ${port}"
            echo "backend_weight${i} = ${weight}"
            echo "backend_data_directory${i} = '/var/lib/postgresql/data'"
            echo "backend_flag${i} = 'ALLOW_TO_FAILOVER'"
            echo "backend_application_name${i} = '${host}'"
        } >> "$tmp"
        i=$((i+1))
    done

    # Only move if changed
    if ! diff -q "$PGPOOL_CONF" "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$PGPOOL_CONF"
        log "Updated backend weights (primary=$primary); reloading pgpool"
        if command -v pcp_reload >/dev/null 2>&1; then
            pcp_reload -h 127.0.0.1 -p "$PCP_PORT" -U admin -w || true
        elif command -v pcp_reload_config >/dev/null 2>&1; then
            pcp_reload_config -h 127.0.0.1 -p "$PCP_PORT" -U admin -w || true
        elif command -v pcp_reloadcfg >/dev/null 2>&1; then
            pcp_reloadcfg -h 127.0.0.1 -p "$PCP_PORT" -U admin -w || true
        elif pid=$(pgrep -x pgpool | head -n1); then
            kill -HUP "$pid" || true
        fi
    else
        rm -f "$tmp" 2>/dev/null || true
    fi
}

CURRENT_PRIMARY=""

while true; do
    sleep "$CHECK_INTERVAL"

    # Process check
    if ! pgrep -x pgpool >/dev/null 2>&1; then
        log "WARNING: pgpool process not running; will retry"
        continue
        fi

    # Pgpool local health
    if ! PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h localhost -p 5432 -U postgres -d postgres -tAc "SELECT 1" >/dev/null 2>&1; then
        log "WARNING: Cannot connect to local pgpool"
    fi

    # Dynamic backend maintenance
    if [ "$DYNAMIC_DISABLED" -eq 0 ]; then
        new_primary=$(find_primary || echo "")
        if [ -n "$new_primary" ] && [ "$new_primary" != "$CURRENT_PRIMARY" ]; then
            rewrite_backends "$new_primary" || log "WARNING: failed to rewrite backends"
            CURRENT_PRIMARY="$new_primary"
        fi
    fi

    # Heartbeat log every 5 minutes
    if [ $(( $(date +%s) % 300 )) -eq 0 ]; then
        log "✓ Pgpool monitoring active (primary=$CURRENT_PRIMARY)"
    fi
done
