FROM haproxy:3.0-alpine

# Install utilities for health check scripts
# Split commands to avoid network timeout issues on Railway
RUN apk add --no-cache bash curl socat

# Create necessary directories
RUN mkdir -p /var/lib/haproxy /run/haproxy /usr/local/etc/haproxy

# Copy configuration files
COPY haproxy/haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
COPY haproxy/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose ports
# 5432 - PostgreSQL protocol (primary port for clients)
# 5433 - PostgreSQL read-only port (optional, for explicit RO queries)
# 8404 - HAProxy stats page
EXPOSE 5432 5433 8404

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
