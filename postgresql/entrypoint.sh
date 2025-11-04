#!/usr/bin/env bash
# entrypoint.sh — PostgreSQL HA with repmgr; supports last-known-primary bootstrap after full-cluster outage
set -euo pipefail
IFS=$'\n\t'

: "${PGDATA:=/var/lib/postgresql/data}"
: "${REPMGR_DB:=repmgr}"
: "${REPMGR_USER:=repmgr}"
: "${REPMGR_PASSWORD:?ERROR: REPMGR_PASSWORD not set}"
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_PASSWORD:?ERROR: POSTGRES_PASSWORD not set}"
: "${APP_READONLY_PASSWORD:?ERROR: APP_READONLY_PASSWORD not set}"
: "${APP_READWRITE_PASSWORD:?ERROR: APP_READWRITE_PASSWORD not set}"
: "${PG_PORT:=5432}"
: "${REPMGR_CONF:=/etc/repmgr/repmgr.conf}"
: "${IS_WITNESS:=false}"

# Debug: Check password length (don't print actual password!)
if [ -n "${REPMGR_PASSWORD}" ]; then
  echo "[DEBUG] REPMGR_PASSWORD is set (length: ${#REPMGR_PASSWORD} chars)"
else
  echo "[DEBUG] REPMGR_PASSWORD is EMPTY!"
fi
: "${PRIMARY_HINT:=pg-1}"
: "${RETRY_INTERVAL:=5}"          # seconds between retries
: "${RETRY_ROUNDS:=3}"          # total retries (180 * 5s ≈ 15 minutes)
: "${LAST_PRIMARY_FILE:="$PGDATA/last_known_primary"}"
: "${WITNESS_HOST:=}"

# NODE_NAME and NODE_ID are REQUIRED (must be set via environment variables)
if [ -z "${NODE_NAME:-}" ]; then
  echo "[FATAL] NODE_NAME environment variable is not set. Please set it (e.g., pg-1, pg-2, witness)"
  exit 1
fi

if [ -z "${NODE_ID:-}" ]; then
  echo "[FATAL] NODE_ID environment variable is not set. Please set it (e.g., 1, 2, 3, 99)"
  exit 1
fi

log() { echo "[$(date -Iseconds)] [entrypoint] $*"; }
pgdata_has_db() { [ -f "$PGDATA/PG_VERSION" ]; }

ensure_dirs() {
  mkdir -p /etc/repmgr
  chown -R postgres:postgres /etc/repmgr
  mkdir -p "$PGDATA"
  chown -R postgres:postgres "$PGDATA"
}

write_pgpass() {
  local pgpass="/var/lib/postgresql/.pgpass"
  # Escape special characters in password for .pgpass format
  # According to PostgreSQL docs, \ and : must be escaped
  local escaped_password="${REPMGR_PASSWORD//\\/\\\\}"  # Escape backslash first
  escaped_password="${escaped_password//:/\\:}"          # Then escape colon
  # Use printf to preserve backslashes
  printf '*:*:*:%s:%s\n' "$REPMGR_USER" "$escaped_password" > "$pgpass"
  chmod 600 "$pgpass"
  chown postgres:postgres "$pgpass"
  log "Generated $pgpass for user postgres"
}

# Atomic write for last-known-primary (tmp+mv)
write_last_primary() {
  local host="$1"
  local tmp="${LAST_PRIMARY_FILE}.tmp"
  printf "%s\n" "$host" > "$tmp"
  chmod 600 "$tmp" || true
  chown postgres:postgres "$tmp" || true
  mv -f "$tmp" "$LAST_PRIMARY_FILE"
  sync
  chmod 600 "$LAST_PRIMARY_FILE" || true
  chown postgres:postgres "$LAST_PRIMARY_FILE" || true
  log "Recorded last-known-primary: $host"
}

read_last_primary() {
  if [[ -s "$LAST_PRIMARY_FILE" ]]; then
    tail -n 1 "$LAST_PRIMARY_FILE"
  else
    echo ""
  fi
}

wait_for_port() {
  local host=$1 port=${2:-5432} timeout=${3:-10}
  for _ in $(seq 1 "$timeout"); do
    if gosu postgres pg_isready -h "$host" -p "$port" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

is_primary() {
  local host=$1 port=${2:-5432}
  # First, ensure the port is even open before querying
  if ! gosu postgres pg_isready -h "$host" -p "$port" >/dev/null 2>&1; then
    return 1
  fi
  # Use .pgpass file which has properly escaped password
  gosu postgres psql -h "$host" -p "$port" -U "$REPMGR_USER" -d "$REPMGR_DB" -tAc "SELECT NOT pg_is_in_recovery();" 2>/dev/null | grep -q t
}

# Validate a primary spec string like "host:port" or "host" (port defaults to 5432)
ensure_valid_primary() {
  local primary="$1"
  local host="${primary%:*}"
  if [ -z "$host" ]; then
    log "Invalid primary spec '$primary' (empty host)"
    return 1
  fi
  return 0
}

# Dùng khi init cluster lần đầu
find_primary() {
  IFS=',' read -ra peers <<<"$PEERS"
  for p in "${peers[@]}"; do
    local host=${p%:*}; local port=${p#*:}; [ "$host" = "$port" ] && port=5432
    if wait_for_port "$host" "$port" 3; then
      if is_primary "$host" "$port"; then
        echo "${host}:${port}"; return 0
      fi
    fi
  done
  return 1
}

# Dùng khi fallback (node cũ quay lại)
find_new_primary() {
  IFS=',' read -ra peers <<<"$PEERS"
  for p in "${peers[@]}"; do
    local host=${p%:*}; local port=${p#*:}; [ "$host" = "$port" ] && port=5432
    [ "$host" = "$NODE_NAME" ] && continue
    if wait_for_port "$host" "$port" 3; then
      if is_primary "$host" "$port"; then
        echo "${host}:${port}"; return 0
      fi
    fi
  done
  return 1
}

# Try to discover primary via witness's repmgr metadata (if WITNESS_HOST provided)
discover_primary_via_witness() {
  if [ -z "$WITNESS_HOST" ]; then return 1; fi
  local csv
  csv=$(gosu postgres repmgr -h "$WITNESS_HOST" -p 5432 -U "$REPMGR_USER" -d "$REPMGR_DB" -f "$REPMGR_CONF" cluster show --csv 2>/dev/null || true)
  if [ -z "$csv" ]; then return 1; fi
  # Prefer robust parse: role may be shown as text 'primary' or code 0 depending on version; match both
  # CSV expected columns: node_id,role,status,... or node_id,role_code,status_code
  local line
  line=$(echo "$csv" | grep -Ei ",primary,|,[[:space:]]*0,[[:space:]]*1" | head -n1 || true)
  if [ -z "$line" ]; then return 1; fi
  # Extract node name (second or appropriate field). Fallback: try cut -d, -f2 if it's node_name.
  # If schema differs, attempt to find a hostname pattern like stg-*.railway.internal in the row.
  local host
  host=$(echo "$line" | cut -d, -f2 | tr -d ' ')
  if [ -n "$host" ]; then
    printf "%s:5432\n" "$host"
    return 0
  fi
  return 1
}

# --- Timeline-based Election Functions ---

# Get timeline ID from local PGDATA using pg_controldata (safe, server doesn't need to be running)
get_local_timeline() {
  # Prefer reading from pg_controldata (does not require server running)
  if [ ! -f "$PGDATA/global/pg_control" ]; then
    log "Cannot find local pg_control file, assuming timeline 0" >&2
    echo "0"
    return
  fi

  local tli
  # pg_controldata output format: "Latest checkpoint's TimeLineID:       1"
  # We need to extract just the number after the colon
  tli=$(gosu postgres pg_controldata "$PGDATA" 2>/dev/null | grep "Latest checkpoint's TimeLineID" | awk '{print $NF}' || true)

  # Fallback to querying the running server if parsing failed
  if ! [[ "$tli" =~ ^[0-9]+$ ]]; then
    tli=$(gosu postgres psql -h localhost -p "$PG_PORT" -U "$POSTGRES_USER" -d postgres -tAc "SELECT timeline_id FROM pg_control_checkpoint();" 2>/dev/null || echo "")
  fi

  if ! [[ "$tli" =~ ^[0-9]+$ ]]; then
    log "get_local_timeline: Unable to determine local timeline, defaulting to 0 (got '$tli')" >&2
    echo "0"
  else
    echo "$tli"
  fi
}

# Get timeline ID from a remote, running node
get_remote_timeline() {
  local host="$1"
  local port="${2:-5432}"
  
  # Use a short timeout for pg_isready
  if ! wait_for_port "$host" "$port" 3; then
    log "get_remote_timeline: Node $host is not ready."
    echo "0"
    return
  fi

  # Query the timeline ID. If it fails, return 0.
  local remote_timeline
  remote_timeline=$(gosu postgres psql -h "$host" -p "$port" -U "$REPMGR_USER" -d "$REPMGR_DB" -tAc "SELECT timeline_id FROM pg_control_checkpoint();" 2>/dev/null || echo "0")
  
  # Ensure the result is a number, default to 0 if not
  if ! [[ "$remote_timeline" =~ ^[0-9]+$ ]]; then
    log "get_remote_timeline: Invalid timeline response from $host: '$remote_timeline'"
    echo "0"
  else
    echo "$remote_timeline"
  fi
}

# Elect a primary from all peers based on the highest timeline ID
elect_primary_by_timeline() {
  log "Starting election based on timeline ID..." >&2
  
  local winner_node="$NODE_NAME"
  local max_timeline
  max_timeline=$(get_local_timeline)
  log "Local timeline ID for $NODE_NAME is $max_timeline" >&2

  # Ensure PEERS is not empty
  if [ -z "${PEERS:-}" ]; then
      log "PEERS environment variable is not set. Cannot perform election." >&2
      echo "$winner_node" # Fallback to self
      return
  fi
  
  IFS=',' read -ra peers_to_check <<<"$PEERS"

  for p in "${peers_to_check[@]}"; do
    # Skip empty entries
    [ -z "$p" ] && continue

    local host=${p%:*}; local port=${p#*:}; [ "$host" = "$port" ] && port=5432
    # Skip if host is empty (bad PEERS formatting)
    [ -z "$host" ] && continue
    
    # Don't check against self
    if [ "$host" = "$NODE_NAME" ]; then
      continue
    fi

    log "Querying timeline ID from peer: $host" >&2
    local remote_timeline
    remote_timeline=$(get_remote_timeline "$host" "$port")
    log "Peer $host timeline ID is $remote_timeline" >&2

    # Ensure local max_timeline is numeric for comparison
    if ! [[ "$max_timeline" =~ ^[0-9]+$ ]]; then max_timeline=0; fi

    if [ "$remote_timeline" -gt "$max_timeline" ]; then
      log "New winner found: $host (timeline $remote_timeline > $max_timeline)" >&2
      max_timeline="$remote_timeline"
      winner_node="$host"
    fi
  done

  log "Election winner is: $winner_node with timeline ID $max_timeline" >&2
  echo "$winner_node"
}

# Elect the best peer (exclude self); returns empty string if none available
elect_best_peer_by_timeline() {
  # Ensure PEERS is not empty
  if [ -z "${PEERS:-}" ]; then
    echo ""
    return
  fi

  IFS=',' read -ra peers_to_check <<<"$PEERS"
  local peer_winner=""
  local peer_max=0

  for p in "${peers_to_check[@]}"; do
    [ -z "$p" ] && continue
    local host=${p%:*}; local port=${p#*:}; [ "$host" = "$port" ] && port=5432
    [ -z "$host" ] && continue
    [ "$host" = "$NODE_NAME" ] && continue

    local rt
    rt=$(get_remote_timeline "$host" "$port")
    log "Peer $host has timeline $rt (peer election)" >&2
    if [ "$rt" -gt "$peer_max" ]; then
      peer_max="$rt"
      peer_winner="$host"
    fi
  done

  echo "$peer_winner"
}

write_postgresql_conf() {
  cat > "$PGDATA/postgresql.conf" <<EOF
# Network
listen_addresses = '*'
port = ${PG_PORT}
max_connections = 1000            # Increased for high concurrency (from default 100)

# Replication - Optimized for fast failover (<10s)
wal_level = replica
max_wal_senders = 16              # Support more standbys + archiving
wal_keep_size = '10GB'            # Increased to prevent WAL removal during lag spikes
max_replication_slots = 16
hot_standby = on
hot_standby_feedback = on
wal_log_hints = on
shared_preload_libraries = 'repmgr'

# WAL Performance - Critical for <10s failover
wal_compression = on              # Compress WAL to reduce I/O
wal_buffers = 64MB                # Increased from default 16MB
max_wal_size = 8GB                # Allow larger WAL before checkpoint
min_wal_size = 2GB
checkpoint_timeout = 15min        # More frequent checkpoints (down from 30min)
checkpoint_completion_target = 0.9

# Synchronous replication - Ensure data integrity
# Set to 'off' for async (faster writes), 'remote_write' for durability without flush wait
# 'on' for strongest guarantee but slower writes
synchronous_commit = remote_write  # Wait for WAL write to standby, not fsync (balanced)
# synchronous_standby_names = 'FIRST 1 (pg-2, pg-3, pg-4)'  # Uncomment for sync replication

# Logging - Minimal for normal operation, errors only
log_connections = off
log_disconnections = off
log_line_prefix = '%t [%p]: '
log_statement = 'none'
log_min_duration_statement = 5000
log_min_error_statement = error
log_min_messages = warning
log_checkpoints = on
log_lock_waits = on
log_autovacuum_min_duration = 0
log_replication_commands = on     # Log replication events for failover debugging

# Password Encryption (SCRAM-SHA-256 is more secure than md5)
password_encryption = 'scram-sha-256'

# SSL/TLS (if certificates exist)
ssl = off
# ssl_cert_file = 'server.crt'
# ssl_key_file = 'server.key'
# ssl_ca_file = 'root.crt'

# Performance - Tuned for 32 vCPU / 32 GB RAM
shared_buffers = 8GB              # 25% of RAM (up from 256MB)
work_mem = 64MB                   # Per-operation memory (up from 16MB)
maintenance_work_mem = 2GB        # For VACUUM, CREATE INDEX (up from 128MB)
effective_cache_size = 24GB       # 75% of RAM for query planner estimates
effective_io_concurrency = 200    # For SSD/NVMe
random_page_cost = 1.1            # SSD-optimized

# Parallel query execution (leverage 32 vCPUs)
max_worker_processes = 32         # Match vCPU count
max_parallel_workers_per_gather = 8  # Per query parallelism
max_parallel_workers = 32         # Total parallel workers
max_parallel_maintenance_workers = 8 # For parallel CREATE INDEX, VACUUM

# Autovacuum - Aggressive for high-write workloads
autovacuum = on
autovacuum_max_workers = 8        # More workers for 32 vCPU
autovacuum_naptime = 10s          # Check more frequently (down from 1min)
autovacuum_vacuum_scale_factor = 0.05     # Vacuum when 5% of table is dead (down from 20%)
autovacuum_analyze_scale_factor = 0.025   # Analyze when 2.5% changed

# Connection management
tcp_keepalives_idle = 60          # Send keepalive after 60s idle
tcp_keepalives_interval = 10      # Retry every 10s
tcp_keepalives_count = 6          # Drop after 6 failed keepalives

# Statement timeout (prevent runaway queries)
statement_timeout = 300000
EOF
}

write_pg_hba() {
  cat > "$PGDATA/pg_hba.conf" <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
# Local connections (trusted for admin tasks inside container)
local   all             all                                     trust

# Application users (SCRAM-SHA-256 for strong password encryption)
host    all             app_readonly    0.0.0.0/0               scram-sha-256
host    all             app_readwrite   0.0.0.0/0               scram-sha-256
host    all             app_readonly    ::/0                    scram-sha-256
host    all             app_readwrite   ::/0                    scram-sha-256

# Admin and repmgr users (SCRAM-SHA-256) — remote connections only
host    all             postgres        0.0.0.0/0               scram-sha-256
host    all             postgres        ::/0                    scram-sha-256
host    all             ${REPMGR_USER}  0.0.0.0/0               scram-sha-256
host    all             ${REPMGR_USER}  ::/0                    scram-sha-256

# Replication connections (SCRAM-SHA-256)
host    replication     ${REPMGR_USER}  0.0.0.0/0               scram-sha-256
host    replication     ${REPMGR_USER}  ::/0                    scram-sha-256

# NOTE: For production with SSL/TLS, change 'host' to 'hostssl' and enforce certificates.
# hostssl all             app_readonly    0.0.0.0/0               scram-sha-256
# hostssl all             app_readwrite   0.0.0.0/0               scram-sha-256
EOF
}

write_repmgr_conf() {
  cat > "$REPMGR_CONF" <<EOF
node_id=${NODE_ID}
node_name='${NODE_NAME}'
conninfo='host=${NODE_NAME} port=${PG_PORT} user=${REPMGR_USER} dbname=${REPMGR_DB} password=${REPMGR_PASSWORD} connect_timeout=5'
data_directory='${PGDATA}'

log_level=INFO
log_facility=STDERR
use_replication_slots=yes

# Service control commands
service_start_command='gosu postgres pg_ctl -D ${PGDATA} -w start'
service_stop_command='gosu postgres pg_ctl -D ${PGDATA} -m fast stop'
service_restart_command='/usr/local/bin/safe_restart.sh'
service_reload_command='gosu postgres pg_ctl -D ${PGDATA} reload'

# Monitoring - Optimized for <10s failover detection
monitor_interval_secs=2           # Check every 2s (down from 5s)
connection_check_type=ping        # Fast ping check
reconnect_attempts=3              # Try 3 times (down from 6)
reconnect_interval=2              # Wait 2s between attempts (down from 5s)
                                  # Total detection time: 2s * 3 = 6s worst case

# Failover configuration - Aggressive for <10s total failover
failover=automatic
promote_command='/usr/local/bin/promote_guard.sh'  # Use promotion guard
follow_command='repmgr standby follow -f /etc/repmgr/repmgr.conf --log-to-file --upstream-node-id=%n'

# Promotion settings
priority=$((200 - NODE_ID))       # Higher priority = preferred for promotion
location='default'

# Failover coordination
failover_validation_command=''    # Optional: Add fencing script here
election_rerun_interval=5         # Re-run election if no winner in 5s (down from 15s)
sibling_nodes_disconnect_timeout=10  # Wait 10s for siblings to disconnect from failed primary

# Child process monitoring (repmgrd daemon management)
repmgrd_service_start_command='repmgrd -f /etc/repmgr/repmgr.conf --daemonize=false'
repmgrd_pid_file='/tmp/repmgrd.pid'

# Witness node settings (only used if this IS a witness)
witness_sync_interval=15          # Sync witness metadata every 15s
EOF
}

safe_clear_pgdata() {
  if [ -d "$PGDATA" ]; then
    gosu postgres pg_ctl -D "$PGDATA" -m fast stop || true
    rm -rf "$PGDATA"/*
  fi
  mkdir -p "$PGDATA"
  chown -R postgres:postgres "$PGDATA"
}

wait_for_metadata() {
  local timeout=${1:-30}
  for _ in $(seq 1 "$timeout"); do
    if gosu postgres psql -h "$NODE_NAME" -p "$PG_PORT" -U "$REPMGR_USER" -d "$REPMGR_DB" -tAc \
      "SELECT 1 FROM repmgr.nodes WHERE node_id = ${NODE_ID}" | grep -q 1; then
      log "Metadata for node ${NODE_ID} is visible locally."
      return 0
    fi
    sleep 1
  done
  log "Timeout waiting for metadata to replicate."
  return 1
}

init_primary() {
  log "Initializing primary (fresh PGDATA)..."
  safe_clear_pgdata
  gosu postgres initdb -D "$PGDATA" --data-checksums
  write_pg_hba
  write_postgresql_conf
  write_repmgr_conf

  gosu postgres pg_ctl -D "$PGDATA" -w start

  # Ensure postgres superuser has the provided password (so remote/scram connections work, e.g., from pgpool)
  gosu postgres psql -U "$POSTGRES_USER" -d postgres -c "ALTER USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';"

  gosu postgres psql -U "$POSTGRES_USER" -tc "SELECT 1 FROM pg_roles WHERE rolname='${REPMGR_USER}'" | grep -q 1 \
    || gosu postgres psql -U "$POSTGRES_USER" -c "CREATE ROLE ${REPMGR_USER} WITH LOGIN REPLICATION SUPERUSER PASSWORD '${REPMGR_PASSWORD}';"

  gosu postgres psql -U "$POSTGRES_USER" -tc "SELECT 1 FROM pg_database WHERE datname='${REPMGR_DB}'" | grep -q 1 \
    || gosu postgres psql -U "$POSTGRES_USER" -c "CREATE DATABASE ${REPMGR_DB} OWNER ${REPMGR_USER};"

  # CRITICAL: Test authentication immediately after user creation
  log "Testing repmgr user authentication..."
  if PGPASSWORD="${REPMGR_PASSWORD}" psql -h localhost -U "${REPMGR_USER}" -d "${REPMGR_DB}" -c "SELECT 1" >/dev/null 2>&1; then
    log "✓ repmgr user authentication test PASSED"
  else
    log "✗ ERROR: repmgr user authentication test FAILED!"
    log "  This means the password in database does NOT match REPMGR_PASSWORD environment variable"
    log "  Password length: ${#REPMGR_PASSWORD} chars"
    log "  Troubleshooting:"
    log "    1. Check Railway shared variable REPMGR_PASSWORD value"
    log "    2. Ensure variable hasn't changed between deployments"
    log "    3. Delete all volumes and redeploy from scratch if password was regenerated"
    exit 1
  fi

  # Create application users with limited permissions
  log "Creating application users..."
  
  # Read-only user
  gosu postgres psql -U "$POSTGRES_USER" -tc "SELECT 1 FROM pg_roles WHERE rolname='app_readonly'" | grep -q 1 \
    || gosu postgres psql -U "$POSTGRES_USER" -c "CREATE USER app_readonly WITH PASSWORD '${APP_READONLY_PASSWORD:-$(openssl rand -base64 32)}';"
  
  gosu postgres psql -U "$POSTGRES_USER" <<-EOSQL
    GRANT CONNECT ON DATABASE postgres TO app_readonly;
    GRANT USAGE ON SCHEMA public TO app_readonly;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_readonly;
EOSQL
  
  # Read-write user
  gosu postgres psql -U "$POSTGRES_USER" -tc "SELECT 1 FROM pg_roles WHERE rolname='app_readwrite'" | grep -q 1 \
    || gosu postgres psql -U "$POSTGRES_USER" -c "CREATE USER app_readwrite WITH PASSWORD '${APP_READWRITE_PASSWORD:-$(openssl rand -base64 32)}';"
  
  gosu postgres psql -U "$POSTGRES_USER" <<-EOSQL
    GRANT CONNECT ON DATABASE postgres TO app_readwrite;
    GRANT USAGE ON SCHEMA public TO app_readwrite;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_readwrite;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_readwrite;
EOSQL

  log "Application users created successfully"

  gosu postgres repmgr -f "$REPMGR_CONF" primary register --force
  write_last_primary "$NODE_NAME"
  log "Primary initialized."
}

clone_standby() {
  local primary="$1"
  local host=${primary%:*}
  local port=${primary#*:}
  [ "$host" = "$port" ] && port=5432
  if [ -z "$host" ]; then
    log "Invalid primary spec '$primary' (empty host); refusing to clone"
    return 1
  fi
  log "Cloning standby from $host:$port"

  until wait_for_port "$host" "$port" 10; do sleep 2; done
  safe_clear_pgdata
  
  # Write repmgr.conf before clone (needed for clone operation)
  write_repmgr_conf

  # Clone entire PGDATA from primary (includes users, databases, config)
  log "Running repmgr standby clone from $host:$port"
  gosu postgres repmgr -h "$host" -p "$port" -U "$REPMGR_USER" -d "$REPMGR_DB" -f "$REPMGR_CONF" standby clone --force
  
  # After clone, pg_hba and postgresql.conf are copied from primary
  # We need to regenerate them for this specific standby node
  write_pg_hba
  write_postgresql_conf
  
  gosu postgres pg_ctl -D "$PGDATA" -w start
  gosu postgres repmgr -h "$host" -p "$port" -U "$REPMGR_USER" -d "$REPMGR_DB" -f "$REPMGR_CONF" standby register --force
  wait_for_metadata 30 || true
  write_last_primary "$host"  # Record current primary when joining as standby
  log "Standby registered."
}

attempt_rewind() {
  local primary="$1"
  local host=${primary%:*}
  local port=${primary#*:}
  [ "$host" = "$port" ] && port=5432
  if [ -z "$host" ]; then
    log "Invalid primary spec '$primary' (empty host); aborting rewind"
    return 1
  fi

  log "Checking system identifier compatibility before rewind..."
  # Get system identifier from primary
  local primary_sysid
  primary_sysid=$(gosu postgres psql -h "$host" -p "$port" -U "$REPMGR_USER" -d "$REPMGR_DB" -tAc "SELECT system_identifier FROM pg_control_system();" 2>/dev/null || echo "")

  # Get system identifier locally if possible (only when server is running)
  local local_sysid=""
  if gosu postgres pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
    local_sysid=$(gosu postgres psql -h localhost -p "$PG_PORT" -U "$POSTGRES_USER" -d postgres -tAc "SELECT system_identifier FROM pg_control_system();" 2>/dev/null || echo "")
  fi

  if [ -n "$primary_sysid" ] && [ -n "$local_sysid" ] && [ "$primary_sysid" != "$local_sysid" ]; then
    log "System identifier mismatch detected:"
    log "  Primary: $primary_sysid"
    log "  Local:   $local_sysid"
    log "  → Skipping pg_rewind and forcing full clone"
    return 1
  fi

  log "Attempting pg_rewind from $host:$port"
  gosu postgres pg_ctl -D "$PGDATA" -m fast stop || true
  # Escape single quotes in password for connection string
  local escaped_password="${REPMGR_PASSWORD//\'/\'\'}"
  if gosu postgres pg_rewind --target-pgdata="$PGDATA" \
      --source-server="host=$host port=$port user=$REPMGR_USER dbname=$REPMGR_DB password='${escaped_password}'" --no-sync; then
    log "pg_rewind successful"
    gosu postgres pg_ctl -D "$PGDATA" -w start
    write_last_primary "$host"
    return 0
  else
    log "pg_rewind failed"
    return 1
  fi
}

start_repmgrd() {
  log "Starting repmgrd..."
  gosu postgres repmgrd -f "$REPMGR_CONF" -d
  log "Starting monitor.sh..."
  /usr/local/bin/monitor.sh &
}

# ==== Main ====
ensure_dirs
write_pgpass
write_repmgr_conf

# Accept PRIMARY_HOST if provided (compose may set PRIMARY_HOST)
: "${PRIMARY_HOST:=}"
if [ -n "${PRIMARY_HOST}" ]; then
  # Strip port if present (e.g., pg-1.railway.internal:5432 -> pg-1.railway.internal)
  PRIMARY_HINT="${PRIMARY_HOST%:*}"
else
  PRIMARY_HINT=""
fi

# Validate NODE_ID is numeric (required for repmgr priority calculation)
if ! [[ "${NODE_ID}" =~ ^[0-9]+$ ]]; then
  log "[ERROR] NODE_ID must be a number. Got: '${NODE_ID}'"
  exit 1
fi

log "Node configuration: NAME=${NODE_NAME}, ID=${NODE_ID}"

# Witness node flow
if [ "$IS_WITNESS" = "true" ]; then
  # Witness uses its local PG for repmgr metadata only (can be no volume, but we still need a running PG)
  log "Witness: starting local PostgreSQL for repmgr metadata"
  safe_clear_pgdata
  gosu postgres initdb -D "$PGDATA" --data-checksums
  write_pg_hba
  write_postgresql_conf
  gosu postgres pg_ctl -D "$PGDATA" -w start

  # Resolve primary via last-known-primary or discovery
  lk_primary="$(read_last_primary)"
  if [ -n "$lk_primary" ]; then
    log "Witness prefers last-known-primary: $lk_primary"
    primary_hostport="${lk_primary}:5432"
  else
    primary_hint_host=${PRIMARY_HINT%:*}
    tmp_primary=$(find_primary || true)
    if [ -n "$tmp_primary" ]; then
      primary_hostport="$tmp_primary"
    elif [ -n "$primary_hint_host" ]; then
      primary_hostport="${primary_hint_host}:5432"
    else
      primary_hostport=""
    fi

    # Create repmgr role + database locally so repmgrd can start and witness register can use local metadata
    # Idempotent: only created if missing
    gosu postgres psql -U "$POSTGRES_USER" -tc "SELECT 1 FROM pg_roles WHERE rolname='${REPMGR_USER}'" | grep -q 1 \
      || gosu postgres psql -U "$POSTGRES_USER" -c "CREATE ROLE ${REPMGR_USER} WITH LOGIN REPLICATION SUPERUSER PASSWORD '${REPMGR_PASSWORD}';"
    gosu postgres psql -U "$POSTGRES_USER" -tc "SELECT 1 FROM pg_database WHERE datname='${REPMGR_DB}'" | grep -q 1 \
      || gosu postgres psql -U "$POSTGRES_USER" -c "CREATE DATABASE ${REPMGR_DB} OWNER ${REPMGR_USER};"
    log "Witness: ensured local repmgr role/db (user=${REPMGR_USER}, db=${REPMGR_DB})"
  fi

  log "Registering witness against ${primary_hostport%:*}"
  # Retry until primary responds; dynamically re-discover if unknown
  for _ in $(seq 1 "$RETRY_ROUNDS"); do
    if [ -z "$primary_hostport" ]; then
      tmp_primary=$(find_primary || true)
      if [ -n "$tmp_primary" ]; then
        primary_hostport="$tmp_primary"
        log "Witness discovered primary: $primary_hostport"
      elif [ -n "$primary_hint_host" ]; then
        primary_hostport="${primary_hint_host}:5432"
      fi
    fi
    if [ -n "$primary_hostport" ] && wait_for_port "${primary_hostport%:*}" "${primary_hostport#*:}" 5; then
      gosu postgres repmgr -f "$REPMGR_CONF" witness register \
        -h "${primary_hostport%:*}" -p "${primary_hostport#*:}" \
        -U "$REPMGR_USER" -d "$REPMGR_DB" --force && break || true
    fi
    log "Witness waiting for primary..."
    sleep "$RETRY_INTERVAL"
  done

  start_repmgrd
  sleep infinity
fi

# Normal node flow
if ! pgdata_has_db; then
  # Fresh node init path
  current_primary=$(find_primary || true)

  if [ -n "$current_primary" ]; then
    clone_standby "$current_primary"
  else
    # No primary found; if this node matches PRIMARY_HINT, allow init as primary
    if [ "$NODE_NAME" = "$PRIMARY_HINT" ]; then
      log "No primary detected; ${NODE_NAME} matches PRIMARY_HINT → init as primary"
      init_primary
    else
      log "No primary detected; standby will wait (not promote) for a primary to appear"
      for i in $(seq 1 "$RETRY_ROUNDS"); do
        sleep "$RETRY_INTERVAL"
        current_primary=$(find_primary || true)
        if [ -n "$current_primary" ]; then
          clone_standby "$current_primary"
          break
        fi
        log "Still waiting for primary..."
      done
      if [ -z "$current_primary" ]; then
        log "Primary still not found; exiting to avoid unsafe init"
        exit 1
      fi
    fi
  fi
else
  # Node has previous data, indicating a restart or recovery scenario.
  # We need to distinguish between:
  # 1. Cluster-wide outage (all nodes down) → election needed
  # 2. Single standby restart (primary still running) → rejoin flow
  
  log "Node has existing data. Checking if primary is still alive..."
  lk_primary=$(read_last_primary)
  
  # First, try to find if there's an existing primary running
  existing_primary=$(find_new_primary || true)
  
  if [ -n "$existing_primary" ]; then
    # Scenario: Primary is alive, this is just a standby restart
    log "Detected running primary at '$existing_primary'. This is a standby restart, not cluster outage."
    log "Following standard rejoin flow..."
    
    # Start local PG to check if we can rejoin
    gosu postgres pg_ctl -D "$PGDATA" -w start
    
    # Try rewind first (faster), fall back to clone if needed
    if attempt_rewind "$existing_primary"; then
      log "Rejoining via repmgr node rejoin..."
      gosu postgres repmgr -f "$REPMGR_CONF" node rejoin --force --force-rewind -h "${existing_primary%:*}" -p "${existing_primary#*:}" -U "$REPMGR_USER" -d "$REPMGR_DB" || true
      gosu postgres repmgr -f "$REPMGR_CONF" standby register --force || true
      log "Successfully rejoined cluster as standby."
    else
      log "pg_rewind failed. Falling back to full clone from primary '$existing_primary'."
      clone_standby "$existing_primary"
    fi
  else
    # Scenario: No primary found, this is a cluster-wide outage
    log "No running primary detected. Suspected cluster-wide outage."
    log "Starting election-based recovery..."
    
    # Start PostgreSQL to participate in election
    gosu postgres pg_ctl -D "$PGDATA" -w start

    # Give peers a moment to also start up before holding the election.
    log "Waiting for peers to come online before election... (15 seconds)"
    sleep 15

    election_winner=$(elect_primary_by_timeline)
    log "Election concluded. Winner by timeline: '$election_winner'. Last known primary: '$lk_primary'."

    # The winning condition is strict: a node must BOTH be the last known primary
    # AND have the highest timeline ID to be able to bootstrap itself.
    if [ "$NODE_NAME" = "$lk_primary" ] && [ "$NODE_NAME" = "$election_winner" ]; then
      log "This node WON the election and was the Last Known Primary. Bootstrapping as primary."
      # Use --force because we are certain this is the most up-to-date node.
      if gosu postgres repmgr -f "$REPMGR_CONF" primary register --force; then
          write_last_primary "$NODE_NAME"
          log "Successfully registered as primary after winning election."
      else
          log "CRITICAL: Won election but failed to register as primary. Check repmgr logs."
          sleep infinity
      fi
    else
      # This node lost the election or is not last-known-primary. It must follow the winner.
      # Guard against the case where 'winner' == self but we're not allowed to promote (lk_primary mismatch).
      if [ "$election_winner" = "$NODE_NAME" ]; then
        peer_winner=$(elect_best_peer_by_timeline)
        if [ -n "$peer_winner" ]; then
          log "Election favors self but LKP mismatch; will follow best peer '$peer_winner' instead."
          election_winner="$peer_winner"
        else
          log "No viable peer found to follow; waiting for a primary to appear."
        fi
      fi

      log "This node must follow the winner '$election_winner' (lk_primary='$lk_primary')."

      if [ -z "$election_winner" ]; then
          log "CRITICAL: Election resulted in no winner. Cluster is in an inconsistent state. Halting."
          sleep infinity
      fi

      winner_hostport="${election_winner}:5432"

      # Stop local PG to prepare for rewind/clone only after we have a non-self winner
      if [ "$election_winner" != "$NODE_NAME" ]; then
        gosu postgres pg_ctl -D "$PGDATA" -m fast stop || true
      fi

      # Wait patiently for the winner to be promoted and become a primary.
      log "Waiting for winner '$election_winner' to become primary..."
      winner_is_primary=false
      for i in $(seq 1 60); do # Wait up to 5 minutes
          if wait_for_port "$election_winner" 5432 3 && is_primary "$election_winner" 5432; then
              log "Winner '$election_winner' is now confirmed as primary."
              winner_is_primary=true
              break
          fi
          log "Still waiting for winner '$election_winner' to be promoted... (attempt $i/60)"
          sleep 5
      done

      if [ "$winner_is_primary" = true ]; then
        log "Proceeding to rejoin winner '$election_winner'."
        if attempt_rewind "$winner_hostport"; then
          gosu postgres repmgr -f "$REPMGR_CONF" node rejoin --force --force-rewind || true
          gosu postgres repmgr -f "$REPMGR_CONF" standby register --force || true
          log "Successfully rejoined cluster under new primary '$election_winner'."
        else
          log "pg_rewind failed. Falling back to full clone from winner '$election_winner'."
          clone_standby "$winner_hostport"
        fi
      else
        log "CRITICAL: Winner '$election_winner' did not become primary after extended wait. Cluster is in an inconsistent state. Halting."
        sleep infinity
      fi
    fi
  fi
fi

start_repmgrd
sleep infinity