FROM postgres:17

# Cài repmgr và tiện ích
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-17-repmgr gosu vim less && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/repmgr && chown postgres:postgres /etc/repmgr

# Copy scripts
COPY postgresql/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/monitor.sh /usr/local/bin/monitor.sh
COPY scripts/promote_guard.sh /usr/local/bin/promote_guard.sh

RUN chmod +x /usr/local/bin/*.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]