FROM debian:bookworm-slim

# Install PostgreSQL client, pgpool2, and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    pgpool2 \
    postgresql-client-15 \
    postgresql-client-common \
    python3 \
    curl \
    jq \
    gosu \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Provide a small pg_md5 shim (produces username:md5<md5(password+username)>) so entrypoint
# can rely on pg_md5 being present. This avoids heavy PostgreSQL server packages in the image.
RUN cat > /usr/local/bin/pg_md5 <<'SH'
#!/bin/sh
# Minimal pg_md5-compatible wrapper: supports `-m -u <user> <password>` and prints `user:md5<hex>`
MODE=""
USERNAME=""
PW=""
while [ $# -gt 0 ]; do
    case "$1" in
        -m) MODE="m"; shift ;;
        -u) USERNAME="$2"; shift 2 ;;
        *) PW="$1"; shift ;;
    esac
done
if [ -z "$USERNAME" ] || [ -z "$PW" ]; then
    echo "Usage: pg_md5 -m -u <user> <password>" >&2; exit 2
fi
hex=$(printf '%s' "$PW$USERNAME" | md5sum | awk '{print $1}')
printf '%s:md5%s\n' "$USERNAME" "$hex"
SH

RUN chmod +x /usr/local/bin/pg_md5

# Create necessary directories
RUN mkdir -p /etc/pgpool-II /var/run/pgpool /var/log/pgpool /config \
    && chown -R postgres:postgres /etc/pgpool-II /var/run/pgpool /var/log/pgpool

# Copy configuration files to /config (will be copied to /etc/pgpool-II at runtime)
COPY pgpool/pgpool.conf /config/
COPY pgpool/pool_hba.conf /config/
COPY pgpool/pcp.conf /config/

# Copy scripts
COPY pgpool/entrypoint.sh /usr/local/bin/
COPY pgpool/monitor.sh /usr/local/bin/
COPY pgpool/failover.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Expose ports
# 5432 - PostgreSQL protocol
# 9898 - PCP (Pgpool Control Protocol)
# 9000 - Watchdog
# 9694 - Heartbeat
EXPOSE 5432 9898 9000 9694

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
