#!/bin/bash
set -e

echo "[$(date)] Pgpool-II Entrypoint - Starting..."

# IMMEDIATE CLEANUP: Remove any stale pid files and kill processes before doing anything else
echo "[$(date)] Immediate cleanup of stale pgpool processes and pid files..."
pkill -9 pgpool 2>/dev/null || true
pkill -9 -f "pgpool" 2>/dev/null || true
killall -9 pgpool 2>/dev/null || true

# Ensure directories exist before cleanup
mkdir -p /var/run/pgpool /run/pgpool /tmp
chown -R postgres:postgres /var/run/pgpool /run/pgpool

# Remove all PID files from all possible locations
rm -f /var/run/pgpool/pgpool.pid
rm -f /var/run/pgpool/*.pid
rm -f /run/pgpool/pgpool.pid
rm -f /run/pgpool/*.pid
rm -f /tmp/pgpool*.pid
rm -f /var/run/pgpool.pid
rm -f /run/pgpool.pid

sleep 3

# Environment variables with defaults
PGPOOL_NODE_ID=${PGPOOL_NODE_ID:-1}
# Default PGPOOL_HOSTNAME to the container hostname if not provided by the environment
PGPOOL_HOSTNAME=${PGPOOL_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}
# Default other pgpool hostname (can be overridden by env)
OTHER_PGPOOL_HOSTNAME=${OTHER_PGPOOL_HOSTNAME:-pgpool-2.railway.internal}
OTHER_PGPOOL_PORT=${OTHER_PGPOOL_PORT:-5432}

# Passwords: prefer Docker secrets (mounted at /run/secrets/<NAME>), fallback to env
read_secret_or_env() {
  local name="$1" default="$2"
  local secret_path="/run/secrets/${name}"
  if [ -f "$secret_path" ]; then
    # trim newline
    tr -d '\r' < "$secret_path"
  else
    # expand environment variable
    eval echo "\${${name}:-${default}}"
  fi
}

POSTGRES_PASSWORD=$(read_secret_or_env POSTGRES_PASSWORD)
REPMGR_PASSWORD=$(read_secret_or_env REPMGR_PASSWORD)
APP_READONLY_PASSWORD=$(read_secret_or_env APP_READONLY_PASSWORD)
APP_READWRITE_PASSWORD=$(read_secret_or_env APP_READWRITE_PASSWORD)
# PCP / admin password (optional; default kept for backward compatibility)
PCP_PASSWORD=${PCP_PASSWORD:-adminpass}

# Validate required passwords
if [ -z "$POSTGRES_PASSWORD" ] || [ -z "$REPMGR_PASSWORD" ] || [ -z "$APP_READONLY_PASSWORD" ] || [ -z "$APP_READWRITE_PASSWORD" ]; then
  echo "[ERROR] Required password environment variables are not set!"
  echo "  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:+SET}"
  echo "  REPMGR_PASSWORD: ${REPMGR_PASSWORD:+SET}"
  echo "  APP_READONLY_PASSWORD: ${APP_READONLY_PASSWORD:+SET}"
  echo "  APP_READWRITE_PASSWORD: ${APP_READWRITE_PASSWORD:+SET}"
  exit 1
fi

# Create necessary directories
mkdir -p /var/run/pgpool /var/log/pgpool
chown -R postgres:postgres /var/run/pgpool /var/log/pgpool

# Ensure any accidental psql calls that do not specify -U will not default to root
# Many shell utilities (psql/libpq) default to the current OS user; inside containers
# that is often 'root' which causes Postgres to see user 'root'. Set safe defaults.
export PGUSER=${PGUSER:-postgres}
export PGDATABASE=${PGDATABASE:-postgres}

# Ensure runtime tmp dir for sensitive files (may be tmpfs mounted by compose)
mkdir -p /run/pgpool
chown -R postgres:postgres /run/pgpool
chmod 700 /run/pgpool

# Copy configuration files to /etc/pgpool-II if not already there
if [ ! -f /etc/pgpool-II/pgpool.conf ]; then
    echo "[$(date)] Copying configuration files..."
    cp /config/pgpool.conf /etc/pgpool-II/pgpool.conf
    cp /config/pool_hba.conf /etc/pgpool-II/pool_hba.conf
    cp /config/pcp.conf /etc/pgpool-II/pcp.conf
fi

# Create pgpool_node_id file (required for watchdog)
echo "$PGPOOL_NODE_ID" > /etc/pgpool-II/pgpool_node_id
chmod 644 /etc/pgpool-II/pgpool_node_id
echo "[$(date)] Created pgpool_node_id file with ID: $PGPOOL_NODE_ID"

# Create pcp.conf with correct password. Prefer PCP_PASSWORD env var.
# pcp.conf stores username:md5_hash where md5_hash is generated with pg_md5 -m -u <user> <password>
generate_pcp_entry() {
  local user="$1" pw="$2"
  if command -v pg_md5 >/dev/null 2>&1; then
    pg_md5 -m -u "$user" "$pw" 2>/dev/null || return 1
  else
    # Fallback: use openssl to produce md5 hex and format as expected by pcp (best-effort)
    # Note: this is not identical to pg_md5 output but is a fallback when pg_md5 missing.
    # PostgreSQL md5 format is md5(password+username)
    hex=$(echo -n "${pw}${user}" | md5sum | awk '{print $1}')
    echo "${user}:md5${hex}"
  fi
}

echo "[$(date)] Creating /etc/pgpool-II/pcp.conf from PCP_PASSWORD env..."
PCP_HASH=$(generate_pcp_entry admin "$PCP_PASSWORD" || true)
if [ -n "$PCP_HASH" ]; then
  echo "$PCP_HASH" > /etc/pgpool-II/pcp.conf
  chmod 640 /etc/pgpool-II/pcp.conf
  echo "[$(date)] Created pcp.conf for admin"
else
  echo "[$(date)] WARNING: failed to create pcp.conf hash with pg_md5; using precomputed fallback"
  echo "admin:e8a48653851e28c69d0506508fb27fc5" > /etc/pgpool-II/pcp.conf
  chmod 644 /etc/pgpool-II/pcp.conf
fi

# Create .pcppass for monitor script (pcp client convenience)
mkdir -p /var/lib/postgresql
echo "localhost:9898:admin:$PCP_PASSWORD" > /var/lib/postgresql/.pcppass
chown postgres:postgres /var/lib/postgresql/.pcppass
chmod 600 /var/lib/postgresql/.pcppass
echo "[$(date)] Created .pcppass file"

# Also provide .pcppass for root (monitor runs as root)
echo "localhost:9898:admin:$PCP_PASSWORD" > /root/.pcppass
chmod 600 /root/.pcppass

# Update pgpool.conf with runtime values
echo "[$(date)] Configuring pgpool.conf with runtime values..."

# Optionally harden client CIDRs if PGPOOL_CLIENT_CIDRS is provided (comma-separated)
if [ -n "${PGPOOL_CLIENT_CIDRS:-}" ]; then
  echo "[$(date)] Applying client CIDR restrictions to pool_hba.conf: ${PGPOOL_CLIENT_CIDRS}"
  # Comment out overly permissive defaults
  sed -i "s/^host\s\+all\s\+all\s\+0\.0\.0\.0\/0\s\+scram-sha-256/# &/" /etc/pgpool-II/pool_hba.conf || true
  sed -i "s/^host\s\+all\s\+all\s\+::\/0\s\+scram-sha-256/# &/" /etc/pgpool-II/pool_hba.conf || true
  # Also comment docker-wide 172.0.0.0/8 template if present
  sed -i "s/^host\s\+all\s\+all\s\+172\.0\.0\.0\/8\s\+scram-sha-256/# &/" /etc/pgpool-II/pool_hba.conf || true
  # Append explicit allowed CIDRs
  IFS=',' read -ra CIDRS_ARR <<<"$PGPOOL_CLIENT_CIDRS"
  for cidr in "${CIDRS_ARR[@]}"; do
    cidr_trimmed=$(echo "$cidr" | xargs)
    [ -z "$cidr_trimmed" ] && continue
    echo "host    all         all         ${cidr_trimmed}         scram-sha-256" >> /etc/pgpool-II/pool_hba.conf
  done
fi

# Set watchdog hostname and priority based on node ID

# Update default index-0 watchdog entries (backwards compat)
sed -i "s/^wd_hostname0 = .*/wd_hostname0 = '${PGPOOL_HOSTNAME}'/" /etc/pgpool-II/pgpool.conf || true
sed -i "s/^wd_priority0 = .*/wd_priority0 = ${PGPOOL_NODE_ID}/" /etc/pgpool-II/pgpool.conf || true
sed -i "s/^heartbeat_hostname0 = .*/heartbeat_hostname0 = '${PGPOOL_HOSTNAME}'/" /etc/pgpool-II/pgpool.conf || true

# Ensure watchdog entries exist for this node index (pgpool expects wd_hostnameN for node id N)
# Append explicit indexed settings for the current node so pgpool validates configuration correctly.
cat >> /etc/pgpool-II/pgpool.conf <<EOF
wd_hostname${PGPOOL_NODE_ID} = '${PGPOOL_HOSTNAME}'
wd_port${PGPOOL_NODE_ID} = ${OTHER_PGPOOL_PORT:-9000}
wd_priority${PGPOOL_NODE_ID} = ${PGPOOL_NODE_ID}
heartbeat_hostname${PGPOOL_NODE_ID} = '${PGPOOL_HOSTNAME}'
wd_heartbeat_port${PGPOOL_NODE_ID} = 9694
EOF

# Configure other pgpool node for watchdog
sed -i "s/^other_pgpool_hostname0 = .*/other_pgpool_hostname0 = '${OTHER_PGPOOL_HOSTNAME}'/" /etc/pgpool-II/pgpool.conf
sed -i "s/^other_pgpool_port0 = .*/other_pgpool_port0 = ${OTHER_PGPOOL_PORT}/" /etc/pgpool-II/pgpool.conf

# Disable watchdog to avoid conflicts in testing
sed -i "s/^use_watchdog = .*/use_watchdog = off/" /etc/pgpool-II/pgpool.conf

# Allow reads on primary
sed -i "s/^#primary_read_only = off/primary_read_only = off/" /etc/pgpool-II/pgpool.conf || echo "primary_read_only = off" >> /etc/pgpool-II/pgpool.conf

# Note: Password updates moved to AFTER backend rewrite to avoid being overwritten

# Discover and wait for current primary (dynamic discovery)
echo "[$(date)] Discovering current primary in cluster..."

# Backends list can be provided via PG_BACKENDS env var (comma-separated hostname[:port])
# Fallback: if PG_BACKENDS is empty but PG_NODES (hostnames only) is provided, assume port 5432
if [ -z "${PG_BACKENDS:-}" ] && [ -n "${PG_NODES:-}" ]; then
  PG_BACKENDS=$(echo "$PG_NODES" | awk -v RS=',' -v ORS=',' '{gsub(/^[\t ]+|[\t ]+$/,"",$0); printf "%s:5432", $0}' | sed 's/,$//')
fi
PG_BACKENDS=${PG_BACKENDS:-"pg-1:5432,pg-2:5432,pg-3:5432,pg-4:5432"}

# Generate backend entries in pgpool.conf dynamically from PG_BACKENDS
echo "[$(date)] Generating backend entries from PG_BACKENDS: $PG_BACKENDS"
BACKENDS_ARRAY=()
IFS=',' read -ra BACKENDS_ARRAY <<< "$PG_BACKENDS"

# Create a cleaned base config without any existing backend_* lines
TMP_CONF="/etc/pgpool-II/pgpool.conf.tmp"
awk '!/^backend_hostname[0-9]+=|^backend_port[0-9]+=|^backend_weight[0-9]+=|^backend_data_directory[0-9]+=|^backend_flag[0-9]+=|^backend_application_name[0-9]+=/' /etc/pgpool-II/pgpool.conf > "$TMP_CONF"

# Append generated backend entries
i=0
for be in "${BACKENDS_ARRAY[@]}"; do
  host=$(echo "$be" | cut -d: -f1)
  port=$(echo "$be" | cut -s -d: -f2)
  if [ -z "$port" ]; then port=5432; fi
  if [ "$i" -eq 0 ]; then
    # Primary should not be used for load-balanced read queries to avoid writes
    weight=0
  else
    weight=1
  fi
  cat >> "$TMP_CONF" <<EOF
backend_hostname${i} = '${host}'
backend_port${i} = ${port}
backend_weight${i} = ${weight}
backend_data_directory${i} = '/var/lib/postgresql/data'
backend_flag${i} = 'ALLOW_TO_FAILOVER'
backend_application_name${i} = '${host}'
EOF
  i=$((i+1))
done

# Move tmp config into place
mv "$TMP_CONF" /etc/pgpool-II/pgpool.conf
echo "[$(date)] Backend entries written to /etc/pgpool-II/pgpool.conf"

# Update passwords in pgpool.conf AFTER backend rewrite (so they don't get overwritten)
# Using | delimiter to avoid quote escaping issues
sed -i "s|^sr_check_user = .*|sr_check_user = 'repmgr'|" /etc/pgpool-II/pgpool.conf
sed -i "s|^sr_check_password = .*|sr_check_password = '${REPMGR_PASSWORD}'|" /etc/pgpool-II/pgpool.conf
sed -i "s|^health_check_user = .*|health_check_user = 'repmgr'|" /etc/pgpool-II/pgpool.conf
sed -i "s|^health_check_password = .*|health_check_password = '${REPMGR_PASSWORD}'|" /etc/pgpool-II/pgpool.conf
sed -i "s|^wd_lifecheck_user = .*|wd_lifecheck_user = 'repmgr'|" /etc/pgpool-II/pgpool.conf
sed -i "s|^wd_lifecheck_password = .*|wd_lifecheck_password = '${REPMGR_PASSWORD}'|" /etc/pgpool-II/pgpool.conf

# Enforce safe load-balancing settings to avoid routing writes to standbys.
# These settings make sure pgpool does not do statement-level load balancing
# and that any detected write will not be load-balanced to a standby.
cat >> /etc/pgpool-II/pgpool.conf <<'EOF'
# Safety overrides applied at runtime
statement_level_load_balance = off
# When a write is detected, do not allow load balancing for that session/transaction
# 'always' ensures the write-affecting sessions are pinned to the primary.
disable_load_balance_on_write = 'always'
# Optionally prefer session-level balancing (safer than statement-level), but
# we disable statement-level explicitly above.
load_balance_mode = 'session'
EOF


find_primary() {
  # derive hostnames from PG_BACKENDS
  local nodes
  nodes=$(echo "$PG_BACKENDS" | sed 's/,/ /g' | awk -F: '{print $1}')
  for node in $nodes; do
    # Check if PostgreSQL is running
    if ! PGPASSWORD=$REPMGR_PASSWORD psql -h $node -U repmgr -d postgres -c "SELECT 1" > /dev/null 2>&1; then
      continue
    fi

    # Check if this node is primary (NOT in recovery)
    is_primary=$(PGPASSWORD=$REPMGR_PASSWORD psql -h $node -U repmgr -d postgres -tAc "SELECT NOT pg_is_in_recovery();" 2>/dev/null)
    if [ "$is_primary" = "t" ]; then
      echo "$node"
      return 0
    fi
  done
  return 1
}

# Wait for a healthy, writable primary to become available.
#
# Rationale:
#  - In HA clusters the standby nodes answer read-only and will reject write operations
#    (they return errors like "cannot execute ... in a read-only transaction").
#  - pgpool must not start accepting client connections until a writable primary is
#    detected. The original loop only checked for reachability; enhance it to verify
#    that the chosen node is NOT in recovery (i.e. is writable) before proceeding.

RETRY_COUNT=0
PRIMARY_NODE=""
# How many attempts between messages (tunable via env, default 300 -> keep trying)
PGPOOL_WAIT_RETRIES=${PGPOOL_WAIT_RETRIES:-300}
PGPOOL_WAIT_INTERVAL=${PGPOOL_WAIT_INTERVAL:-5}

echo "[$(date)] Waiting for a writable primary (max attempts: $PGPOOL_WAIT_RETRIES, interval: ${PGPOOL_WAIT_INTERVAL}s)"
while true; do
  PRIMARY_NODE=$(find_primary || true)
  if [ -n "$PRIMARY_NODE" ]; then
    # Double-check that this node reports NOT pg_is_in_recovery() (i.e. writable)
    writable=$(PGPASSWORD=$REPMGR_PASSWORD psql -h "$PRIMARY_NODE" -U repmgr -d postgres -tAc "SELECT NOT pg_is_in_recovery();" 2>/dev/null || echo "")
    writable=$(echo "$writable" | tr -d '[:space:]')
    if [ "$writable" = "t" ] || [ "$writable" = "true" ]; then
      echo "  ✓ Found writable primary: $PRIMARY_NODE"
      break
    else
      echo "  ✗ Candidate primary $PRIMARY_NODE is not writable (pg_is_in_recovery() != false). Waiting..."
    fi
  else
    echo "  Waiting for any primary to appear... (attempt $((RETRY_COUNT + 1)))"
  fi

  sleep "$PGPOOL_WAIT_INTERVAL"
  RETRY_COUNT=$((RETRY_COUNT + 1))

  # If retries exceed configured threshold, continue waiting but log more verbosely
  if [ "$RETRY_COUNT" -ge "$PGPOOL_WAIT_RETRIES" ]; then
    echo "[$(date)] Still no writable primary after $RETRY_COUNT attempts; continuing to wait (increase PGPOOL_WAIT_RETRIES to change this)."
    # reset counter so we keep emitting periodic status messages instead of spamming
    RETRY_COUNT=0
  fi
done

echo "[$(date)] Primary node is: $PRIMARY_NODE - proceeding with setup..."

# Function: check whether important roles on the primary use SCRAM-SHA-256
check_roles_scram() {
  local host="$1"
  echo "[$(date)] Checking backend role password storage method on $host..."
  if ! PGPASSWORD=$POSTGRES_PASSWORD psql -h "$host" -U postgres -d postgres -tAc "SELECT 1;" >/dev/null 2>&1; then
    echo "  ✗ Cannot connect to $host as postgres to verify role password methods. Skipping scram check."
    return 1
  fi

  readarray -t role_info < <(PGPASSWORD=$POSTGRES_PASSWORD psql -h "$host" -U postgres -d postgres -tA -c "SELECT rolname || '|' || COALESCE(rolpassword,'') FROM pg_authid WHERE rolname IN ('postgres','repmgr','app_readonly','app_readwrite','pgpool');")

  local non_scram=()
  for line in "${role_info[@]}"; do
    role=
    pw=
    role=
    pw=
    role=
    IFS='|' read -r role pw <<< "$line"
    if [ -z "$role" ]; then
      continue
    fi
    case "$pw" in
      SCRAM-SHA-256*)
        echo "  ✓ $role: SCRAM-SHA-256"
        ;;
      md5*)
        echo "  ⚠ $role: MD5 stored password"
        non_scram+=("$role:MD5")
        ;;
      '')
        echo "  ⚠ $role: no rolpassword set"
        non_scram+=("$role:EMPTY")
        ;;
      *)
        echo "  ⚠ $role: unknown/other password format"
        non_scram+=("$role:OTHER")
        ;;
    esac
  done

  if [ ${#non_scram[@]} -gt 0 ]; then
    echo "\n[WARNING] Some roles are not stored using SCRAM-SHA-256. PgPool was configured to use SCRAM entries for clients."
    echo "Roles needing attention:"
    for r in "${non_scram[@]}"; do echo "  - $r"; done
    echo "\nSuggested actions:"
    echo "  1) On the primary, update role passwords to SCRAM format (example):"
    echo "     PGPASSWORD=<postgres_pw> psql -h $host -U postgres -c \"ALTER ROLE <role> WITH PASSWORD '<password>'\""
    echo "     (Postgres will store SCRAM if server is configured to use it.)"
    echo "  2) After updating, verify 'SELECT rolname, rolpassword FROM pg_authid;' shows 'SCRAM-SHA-256' prefixes."
    echo "  3) Restart or reconfigure pgpool if necessary."
    echo "\nNote: I will NOT change DB role passwords automatically. Perform the update when convenient."
    return 2
  fi
  return 0
}

if [ -n "$PRIMARY_NODE" ]; then
  check_roles_scram "$PRIMARY_NODE" || true
fi


# Create pool_passwd file with user credentials
# For SCRAM-SHA-256, pgpool needs to query backend, so we use text format
echo "[$(date)] Creating pool_passwd with text format for SCRAM-SHA-256..."

# Ensure runtime directory for pool_passwd matches pgpool.conf
mkdir -p /run/pgpool
chown postgres:postgres /run/pgpool

# Create pool_passwd in text format (username:password)
# Pgpool will handle SCRAM authentication with backends
cat > /run/pgpool/pool_passwd <<EOF
postgres:$POSTGRES_PASSWORD
repmgr:$REPMGR_PASSWORD
app_readonly:$APP_READONLY_PASSWORD
app_readwrite:$APP_READWRITE_PASSWORD
pgpool:$REPMGR_PASSWORD
admin:$PCP_PASSWORD
EOF

chmod 600 /run/pgpool/pool_passwd
chown postgres:postgres /run/pgpool/pool_passwd
echo "[$(date)] pool_passwd created with $(wc -l < /run/pgpool/pool_passwd) users"

# Set correct permissions for config files
chown postgres:postgres /etc/pgpool-II/*
chmod 600 /etc/pgpool-II/pcp.conf

# Create pgpool user in PostgreSQL if not exists (on primary node)
echo "[$(date)] Creating pgpool user on primary ($PRIMARY_NODE)..."
PGPASSWORD=$POSTGRES_PASSWORD psql -h $PRIMARY_NODE -U postgres -d postgres <<-EOSQL 2>/dev/null || true
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pgpool') THEN
            CREATE USER pgpool WITH PASSWORD '${REPMGR_PASSWORD}';
        END IF;
    END
    \$\$;
    
    GRANT pg_monitor TO pgpool;
    GRANT CONNECT ON DATABASE postgres TO pgpool;
EOSQL

echo "[$(date)] Pgpool user created/verified on $PRIMARY_NODE"

# Test backend connections (from PG_BACKENDS)
echo "[$(date)] Testing backend connections..."
for be in "${BACKENDS_ARRAY[@]}"; do
  host=$(echo "$be" | cut -d: -f1)
  if PGPASSWORD="$REPMGR_PASSWORD" psql -h "$host" -U repmgr -d postgres -tAc "SELECT 1" > /dev/null 2>&1; then
    echo "  ✓ $host is reachable"
  else
    echo "  ✗ $host is NOT reachable (may come online later)"
  fi
done

# Wait for backends to accept connections (prevent pgpool starting before standbys finish clone)
# Configurable via env:
#  PGPOOL_BACKEND_WAIT (seconds total to wait, default 300)
#  PGPOOL_BACKEND_WAIT_STEP (sleep step in seconds, default 5)
PGPOOL_BACKEND_WAIT=${PGPOOL_BACKEND_WAIT:-300}
PGPOOL_BACKEND_WAIT_STEP=${PGPOOL_BACKEND_WAIT_STEP:-5}
echo "[$(date)] Ensuring backends accept connections before starting pgpool (max ${PGPOOL_BACKEND_WAIT}s)"
TOTAL_WAIT=0
for be in "${BACKENDS_ARRAY[@]}"; do
  host=$(echo "$be" | cut -d: -f1)
  port=$(echo "$be" | cut -s -d: -f2)
  if [ -z "$port" ]; then port=5432; fi
  echo "[$(date)] Waiting for backend ${host}:${port} to accept connections..."
  waited=0
  while true; do
    # Prefer pg_isready if available
    if command -v pg_isready >/dev/null 2>&1; then
      if pg_isready -h "$host" -p "$port" -q; then
        echo "[$(date)] backend ${host}:${port} is accepting connections"
        break
      fi
    else
      # Fallback: simple TCP connect test
      (echo > /dev/tcp/${host}/${port}) >/dev/null 2>&1 && { echo "[$(date)] backend ${host}:${port} is accepting TCP connections"; break; } || true
    fi

    sleep "$PGPOOL_BACKEND_WAIT_STEP"
    waited=$((waited + PGPOOL_BACKEND_WAIT_STEP))
    TOTAL_WAIT=$((TOTAL_WAIT + PGPOOL_BACKEND_WAIT_STEP))
    if [ "$waited" -ge "$PGPOOL_BACKEND_WAIT" ] || [ "$TOTAL_WAIT" -ge "$PGPOOL_BACKEND_WAIT" ]; then
      echo "[$(date)] WARNING: backend ${host}:${port} did not become reachable after ${PGPOOL_BACKEND_WAIT}s; continuing startup (pgpool may mark it down)."
      break
    fi
  done
done

# Display configuration summary
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          Pgpool-II Configuration Summary                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Pgpool Node ID: $PGPOOL_NODE_ID"
echo "  Pgpool Hostname: $PGPOOL_HOSTNAME"
echo "  Watchdog Priority: $PGPOOL_NODE_ID"
echo "  Other Pgpool: ${OTHER_PGPOOL_HOSTNAME}:${OTHER_PGPOOL_PORT}"
echo ""
echo "  Backend Configuration:"
for be in "${BACKENDS_ARRAY[@]}"; do
  host=$(echo "$be" | cut -d: -f1)
  if [ "$host" = "$PRIMARY_NODE" ]; then
    echo "    $host (Primary):  weight=0 (writes only)"
  else
    echo "    $host (Standby):  weight=1 (reads)"
  fi
done
echo ""
echo "  Features:"
echo "    ✓ Load Balancing: ON (session-level; writes pinned to primary)"
echo "    ✓ Streaming Replication Check: ON"
echo "    ✓ Health Check: ON (every 10s)"
echo "    ✓ Watchdog: OFF (disabled to avoid conflicts in this test setup)"
echo "    ✓ Connection Pooling: ON"
echo ""
echo "  Ports:"
echo "    PostgreSQL: 5432"
echo "    PCP: 9898"
echo "    Watchdog: 9000"
echo "    Heartbeat: 9694"
echo ""
echo "══════════════════════════════════════════════════════════"
echo ""

# Start monitoring script in background if exists
if [ -f /usr/local/bin/monitor.sh ]; then
  echo "[$(date)] Starting monitoring script (with dynamic backends)..."
  # Provide both pgpool and backend credentials
  PGPASSWORD="${POSTGRES_PASSWORD}" REPMGR_PASSWORD="${REPMGR_PASSWORD}" /usr/local/bin/monitor.sh &
fi

# Clean up any stale pid file and kill any running pgpool processes
echo "[$(date)] Cleaning up stale pgpool processes and pid files..."
# Kill all pgpool processes aggressively
pkill -9 pgpool || true
pkill -9 -f "pgpool" || true

# Remove all possible pid files from ALL locations
rm -f /var/run/pgpool/pgpool.pid
rm -f /var/run/pgpool/*.pid
rm -f /var/run/pgpool.pid
rm -f /tmp/pgpool*.pid
rm -f /run/pgpool/pgpool.pid
rm -f /run/pgpool/*.pid

# Wait for processes to die
sleep 2

# Double check no pgpool processes running
if pgrep -f pgpool > /dev/null; then
  echo "[$(date)] WARNING: pgpool processes still running, forcing kill..."
  pgrep -f pgpool | xargs kill -9 || true
  sleep 2
fi

# Aggressive cleanup of ALL possible PID file locations (including subdirs)
echo "[$(date)] Final PID file cleanup before start..."
find /var/run -name "*pgpool*.pid" -delete 2>/dev/null || true
find /run -name "*pgpool*.pid" -delete 2>/dev/null || true
find /tmp -name "pgpool*.pid" -delete 2>/dev/null || true

# Ensure clean slate
rm -f /var/run/pgpool/pgpool.pid /var/run/pgpool.pid /run/pgpool/pgpool.pid /run/pgpool.pid 2>/dev/null || true

# Start pgpool-II
echo "[$(date)] Starting pgpool-II..."
exec gosu postgres pgpool -n -f /etc/pgpool-II/pgpool.conf -F /etc/pgpool-II/pcp.conf -a /etc/pgpool-II/pool_hba.conf
