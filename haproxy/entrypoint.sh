#!/bin/bash
set -e

echo "[$(date)] HAProxy Entrypoint - Starting..."

# Environment variables with defaults
PGPOOL_BACKENDS=${PGPOOL_BACKENDS:-"pgpool-1.railway.internal:5432,pgpool-2.railway.internal:5432"}
HAPROXY_STATS_PORT=${HAPROXY_STATS_PORT:-8404}
HAPROXY_STATS_USER=${HAPROXY_STATS_USER:-admin}
HAPROXY_STATS_PASSWORD=${HAPROXY_STATS_PASSWORD:-adminpass}

# Generate dynamic haproxy.cfg based on environment
echo "[$(date)] Generating HAProxy configuration from environment..."

cat > /usr/local/etc/haproxy/haproxy.cfg <<EOF
#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    log stdout format raw local0 info
    
    # Performance tuning for high-throughput (32 vCPU / 32 GB RAM)
    maxconn 50000                      # Max concurrent connections
    nbthread 32                        # Match vCPU count
    cpu-map auto:1/1-32 0-31          # Pin threads to CPUs
    
    # Buffers and timeouts
    tune.bufsize 32768                 # 32 KB buffer (default 16KB)
    tune.maxrewrite 8192               # Max header rewrite buffer
    
    # SSL/TLS (if needed in future)
    # ssl-default-bind-ciphers ECDHE-RSA-AES128-GCM-SHA256:...
    # ssl-default-bind-options ssl-min-ver TLSv1.2
    
    # Security
    user haproxy
    group haproxy
    
    # Stats socket for runtime API
    stats socket /var/lib/haproxy/stats mode 600 level admin expose-fd listeners
    stats timeout 30s

#---------------------------------------------------------------------
# Defaults
#---------------------------------------------------------------------
defaults
    log global
    mode tcp                           # TCP mode for PostgreSQL
    option tcplog                      # Detailed TCP logging
    option dontlognull                 # Don't log health check probes
    
    # Timeouts optimized for database workloads
    timeout connect 5s                 # Backend connection timeout
    timeout client 1h                  # Client idle timeout (long for transactions)
    timeout server 1h                  # Server idle timeout
    timeout check 5s                   # Health check timeout
    
    # Retries and connection handling
    retries 3                          # Retry failed connections 3 times
    option redispatch                  # Redistribute on server failure
    option tcp-smart-accept            # Delay accept until data arrives
    option tcp-smart-connect           # Delay connect until data ready
    
    # Load balancing
    balance leastconn                  # Route to server with least connections
    
    # Error handling
    default-server inter 3s fall 3 rise 2  # Health check: every 3s, down after 3 fails, up after 2 success

#---------------------------------------------------------------------
# Stats Page (HTTP)
#---------------------------------------------------------------------
listen stats
    bind *:${HAPROXY_STATS_PORT}
    mode http
    stats enable
    stats uri /
    stats refresh 5s
    stats show-legends
    stats show-node
    stats auth ${HAPROXY_STATS_USER}:${HAPROXY_STATS_PASSWORD}

#---------------------------------------------------------------------
# PostgreSQL Frontend (Read/Write via PgPool)
# Port 5432 - Main endpoint for application connections
#---------------------------------------------------------------------
frontend postgres_frontend
    bind *:5432
    mode tcp
    
    # Connection limits
    maxconn 40000                      # Reserve some for health checks
    
    # TCP optimization
    option tcpka                       # Enable TCP keepalive
    
    # Default backend
    default_backend pgpool_backend

#---------------------------------------------------------------------
# PgPool Backend Pool
# PgPool handles read/write splitting, we just load-balance between 2 PgPool nodes
#---------------------------------------------------------------------
backend pgpool_backend
    mode tcp
    
    # Balance algorithm: leastconn (route to PgPool with fewest active connections)
    balance leastconn
    
    # Sticky sessions based on source IP (optional, for connection pooling efficiency)
    # Disabled by default - PgPool handles session state
    # stick-table type ip size 200k expire 30m
    # stick on src
    
    # Health check: TCP connect to port 5432
    option tcp-check
    
    # Advanced health check: Try PostgreSQL protocol handshake
    # This ensures PgPool is not just listening, but actually serving PostgreSQL
    tcp-check connect port 5432
    tcp-check send-binary 00000008   # Length
    tcp-check send-binary 04d2162e   # SSL request
    tcp-check expect binary 4e        # Expect 'N' (SSL not supported, which is OK)
    
EOF

# Parse PGPOOL_BACKENDS and add server entries dynamically
echo "[$(date)] Adding PgPool backends: $PGPOOL_BACKENDS"

IFS=',' read -ra BACKENDS <<< "$PGPOOL_BACKENDS"
SERVER_ID=1
for backend in "\${BACKENDS[@]}"; do
    host=\$(echo "\$backend" | cut -d: -f1)
    port=\$(echo "\$backend" | cut -s -d: -f2)
    if [ -z "\$port" ]; then port=5432; fi
    
    # Add server entry
    cat >> /usr/local/etc/haproxy/haproxy.cfg <<BACKEND_EOF
    # PgPool node $SERVER_ID
    server pgpool-$SERVER_ID \$host:\$port check inter 3s fastinter 1s downinter 5s rise 2 fall 3 maxconn 20000
BACKEND_EOF
    
    SERVER_ID=\$((SERVER_ID + 1))
done

# Display configuration summary
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          HAProxy Configuration Summary                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Mode: TCP (PostgreSQL passthrough)"
echo "  Max Connections: 50,000"
echo "  Threads: 32 (CPU-pinned)"
echo "  Balance Algorithm: leastconn"
echo ""
echo "  Frontends:"
echo "    PostgreSQL: *:5432 → pgpool_backend"
echo "    Stats:      *:${HAPROXY_STATS_PORT} (HTTP)"
echo ""
echo "  Backends (PgPool nodes):"
IFS=',' read -ra BACKENDS <<< "$PGPOOL_BACKENDS"
for backend in "\${BACKENDS[@]}"; do
    echo "    - \$backend (health check: every 3s, TCP)"
done
echo ""
echo "  Health Check:"
echo "    Interval: 3s (fast: 1s when down)"
echo "    Fail threshold: 3 consecutive failures"
echo "    Rise threshold: 2 consecutive successes"
echo ""
echo "══════════════════════════════════════════════════════════"
echo ""

# Validate configuration
echo "[$(date)] Validating HAProxy configuration..."
if haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg; then
    echo "[$(date)] ✓ Configuration is valid"
else
    echo "[$(date)] ✗ Configuration validation FAILED"
    cat /usr/local/etc/haproxy/haproxy.cfg
    exit 1
fi

# Start HAProxy
echo "[$(date)] Starting HAProxy..."
exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg -W -db
