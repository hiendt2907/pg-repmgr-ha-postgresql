#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

: "${REPMGR_CONF:=/etc/repmgr/repmgr.conf}"
: "${NODE_NAME:=$(hostname)}"
: "${PGDATA:=/var/lib/postgresql/data}"
: "${LAST_PRIMARY_FILE:="$PGDATA/last_known_primary"}"
: "${EVENT_INTERVAL:=15}"
: "${HEALTH_INTERVAL:=60}"
: "${REFRESH_INTERVAL:=5}"

REPMGR_USER=${REPMGR_USER:-repmgr}
REPMGR_DB=${REPMGR_DB:-repmgr}

log() { echo "[$(date -Iseconds)] [monitor] $*"; }

# Atomic write for last-known-primary (tmp+mv)
function write_last_primary() {
  local primary="$1"
  local tmp="${LAST_PRIMARY_FILE}.tmp"
  printf "%s\n" "$primary" > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  chown postgres:postgres "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$LAST_PRIMARY_FILE"
  sync
  chmod 600 "$LAST_PRIMARY_FILE" 2>/dev/null || true
  chown postgres:postgres "$LAST_PRIMARY_FILE" 2>/dev/null || true
}

trim() {
  local s="${1:-}"
  echo "$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<< "$s")"
}

normalize_status() {
  local s; s="$(trim "${1:-}")"
  s="${s#* }"
  s="$(echo "$s" | tr '[:upper:]' '[:lower:]')"
  echo "$s"
}

get_current_primary() {
  # Try a few ways to detect primary: local role, node status, cluster show
  local local_role
  local_role=$(gosu postgres repmgr -f "$REPMGR_CONF" node status 2>/dev/null | grep -i '^role' | cut -d':' -f2 | tr -d ' ' || echo "")
  if [ "$local_role" = "primary" ]; then
    echo "$NODE_NAME"
    return
  fi

  local result
  result=$(gosu postgres repmgr -f "$REPMGR_CONF" node status 2>/dev/null | grep -i 'primary node' | cut -d':' -f2 | tr -d ' ' || true)
  if [ -n "$result" ]; then
    echo "$result"
    return
  fi

  result=$(gosu postgres repmgr -f "$REPMGR_CONF" cluster show 2>/dev/null | grep -i 'primary' | cut -d'|' -f2 | tr -d '* ' || true)
  echo "$result"
}

check_cluster_health() {
  local status total_nodes=0 online_nodes=0
  status=$(gosu postgres repmgr -f "$REPMGR_CONF" cluster show --csv 2>/dev/null || true)

  if [ -z "$status" ]; then
    echo "UNKNOWN"
    return
  fi

  # CSV format may contain several fields; we will look for lines starting with a numeric node_id
  while IFS=',' read -r node_id role_code status_code rest; do
    node_id="$(trim "$node_id")"
    role_code="$(trim "$role_code")"
    status_code="$(trim "$status_code")"
    if ! [[ "$node_id" =~ ^[0-9]+$ ]]; then
      continue
    fi
    # Skip witness nodes (role_code=2)
    if [ "$role_code" = "2" ]; then
      continue
    fi
    total_nodes=$((total_nodes+1))
    if [ "$status_code" = "1" ]; then
      online_nodes=$((online_nodes+1))
    fi
  done <<< "$status"

  local quorum=$(( total_nodes/2 + 1 ))
  if [ "$total_nodes" -eq 0 ]; then
    echo "UNKNOWN"; return
  fi
  if [ "$total_nodes" -eq 1 ] && [ "$online_nodes" -eq 1 ]; then echo "GREEN"; return; fi
  if [ "$online_nodes" -eq "$total_nodes" ]; then echo "GREEN"
  elif [ "$online_nodes" -ge "$quorum" ]; then echo "YELLOW"
  elif [ "$online_nodes" -eq 1 ] && [ "$total_nodes" -gt 1 ]; then echo "DISASTER"
  else echo "RED"; fi
}

# --- Helpers for safe rejoin / clone ---
CLUSTER_LOCK=${CLUSTER_LOCK:-/var/lib/postgresql/cluster.lock}
acquire_lock() {
  exec 9>"$CLUSTER_LOCK" || return 1
  if flock -n 9; then return 0; fi
  sleep $((RANDOM % 5 + 1))
  flock 9 || return 1
}
release_lock() { exec 9>&- || true; }

safe_stop_postgres() {
  if gosu postgres pg_isready -q; then
    gosu postgres pg_ctl -D "$PGDATA" -m fast -w stop || gosu postgres pg_ctl -D "$PGDATA" -m immediate -w stop || true
  fi
}

try_pg_rewind() {
  local host="$1" port="${2:-5432}"
  log "Attempting pg_rewind from $host:$port"
  safe_stop_postgres
  local escaped_password="${REPMGR_PASSWORD//\'/\'\'}"
  if gosu postgres pg_rewind --target-pgdata="$PGDATA" \
      --source-server="host=$host port=$port user=$REPMGR_USER dbname=$REPMGR_DB password='${escaped_password}'"; then
    log "pg_rewind successful"
    gosu postgres pg_ctl -D "$PGDATA" -w start || true
    write_last_primary "$host"
    return 0
  else
    log "pg_rewind failed"
    return 1
  fi
}

do_full_clone() {
  local host="$1" port="${2:-5432}"
  log "Performing full clone from $host:$port"
  safe_stop_postgres
  rm -rf "$PGDATA"/* || true
  mkdir -p "$PGDATA"; chown -R postgres:postgres "$PGDATA"
  until gosu postgres pg_isready -h "$host" -p "$port" -q; do sleep 1; done
  if gosu postgres repmgr -h "$host" -p "$port" -U "$REPMGR_USER" -d "$REPMGR_DB" -f "$REPMGR_CONF" standby clone --force -D "$PGDATA"; then
    gosu postgres pg_ctl -D "$PGDATA" -w start || true
    gosu postgres repmgr -f "$REPMGR_CONF" standby register --force || true
    write_last_primary "$host"
    log "Full clone + register succeeded"
    return 0
  else
    log "Full clone failed"
    return 1
  fi
}

# --- MAIN LOOP ---
last_event_check=0
last_health_check=0
last_refresh=0

log "Waiting for PostgreSQL to be ready..."
while ! gosu postgres pg_isready -h "$NODE_NAME" -p 5432 >/dev/null 2>&1; do
  sleep 2
done
log "PostgreSQL is ready, starting monitoring loops"

while true; do
  now=$(date +%s)
  if ! gosu postgres pg_isready -h "$NODE_NAME" -p 5432 >/dev/null 2>&1; then
    log "[critical] PostgreSQL is not responding, skipping this iteration"
    sleep 5
    continue
  fi

  # Refresh layer
  if (( now - last_refresh >= REFRESH_INTERVAL )); then
    last_refresh=$now
    current_primary="$(get_current_primary)"
    if [ -n "$current_primary" ]; then
      write_last_primary "$current_primary"
      if [ -f "$LAST_PRIMARY_FILE" ]; then
        prev_primary=$(tail -n 1 "$LAST_PRIMARY_FILE" 2>/dev/null || echo "")
        if [ "$prev_primary" != "$current_primary" ]; then
          log "[refresh] Primary changed: $prev_primary → $current_primary"
        fi
      fi
    else
      log "[refresh] WARNING: Primary not determined from cluster show"
    fi
  fi

  # Event layer
  if (( now - last_event_check >= EVENT_INTERVAL )); then
    last_event_check=$now
    events=$(gosu postgres repmgr -f "$REPMGR_CONF" cluster event --limit=50 2>/dev/null || true)
    if echo "$events" | grep -Eiq 'promote|failover'; then
      log "[event] FAILOVER/PROMOTE detected!"
      echo "$events" | grep -Ei 'promote|failover'
      cluster_info=$(gosu postgres repmgr -f "$REPMGR_CONF" cluster show --compact 2>/dev/null || true)
      echo "$cluster_info"
      promoted_node=$(echo "$events" | grep -m1 'promoted to primary' | grep -o 'node "[^"]*"' | head -1 | cut -d'"' -f2)
      if [ -n "$promoted_node" ]; then
        log "[event] Detected promotion of node $promoted_node → updating last-known-primary"
        write_last_primary "$promoted_node"
      fi

      status=$(gosu postgres repmgr -f "$REPMGR_CONF" cluster show --csv 2>/dev/null || true)
      if [ -n "$status" ]; then
        while IFS=',' read -r node_id node_name role state _; do
          node_id="$(trim "$node_id")"
          node_name="$(trim "$node_name")"
          role="$(normalize_status "$role")"
          state="$(normalize_status "$state")"
          if ! [[ "$node_id" =~ ^[0-9]+$ ]]; then
            continue
          fi
          if [[ "$state" =~ unreachable|failed ]]; then
            log "[event] Detected $node_name (ID:$node_id) is $state"
            if [ "$node_name" = "$NODE_NAME" ] && [ "$role" = "standby" ]; then
              log "[event] This node is standby and unreachable → attempting safe rejoin/rewind"
              if acquire_lock; then
                # Determine primary host to use (prefer last-known-primary)
                p="$( [ -f "$LAST_PRIMARY_FILE" ] && tail -n1 "$LAST_PRIMARY_FILE" || echo "" )"
                pri_host="${p%%:*}"
                pri_port="${p##*:}"
                if [ -z "$pri_port" ] || [ "$pri_port" = "$pri_host" ]; then pri_port=5432; fi
                if try_pg_rewind "$pri_host" "$pri_port"; then
                  gosu postgres repmgr -f "$REPMGR_CONF" node rejoin --force --force-rewind || true
                else
                  do_full_clone "$pri_host" "$pri_port" || log "[event] Full clone also failed; manual intervention required"
                fi
                release_lock
              else
                log "[event] Could not acquire cluster lock; skipping rejoin attempt this round"
              fi
            else
              log "[event] Considering cleanup of metadata for node $node_name"
              if acquire_lock; then
                sleep 1
                s2=$(gosu postgres repmgr -f "$REPMGR_CONF" cluster show --csv 2>/dev/null || true)
                if echo "$s2" | grep -E ",${node_id},|^${node_id}," >/dev/null; then
                  gosu postgres repmgr -f "$REPMGR_CONF" cluster cleanup --node-id="$node_id" || true
                  log "[event] Cleanup attempted for node-id $node_id"
                fi
                release_lock
              else
                log "[event] Could not acquire cluster lock for cleanup; skipping"
              fi
            fi
          fi
        done <<< "$status"
      fi
    fi
  fi

  # Health layer
  if (( now - last_health_check >= HEALTH_INTERVAL )); then
    last_health_check=$now
    health="$(check_cluster_health)"
    if [ "$health" != "GREEN" ]; then
      confirmed="$health"
      for i in $(seq 1 5); do
        sleep 1
        h2="$(check_cluster_health)"
        if [ "$h2" != "$health" ]; then
          confirmed="FLAPPING"; break
        fi
      done
      log "[health] ⚠️  Cluster health: $confirmed (NOT GREEN!)"
      gosu postgres repmgr -f "$REPMGR_CONF" cluster show --compact 2>/dev/null || true
    fi
  fi

  sleep 1
done
