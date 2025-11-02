# Railway Quick Reference Card

## 🚀 Deploy Commands (Railway CLI)

### Login & Setup
```bash
railway login
railway init  # Create new project
railway link  # Link to existing project
```

### Environment Variables
```bash
# Set shared variables (run once)
railway variables set POSTGRES_PASSWORD="your_strong_password"
railway variables set REPMGR_PASSWORD="your_repmgr_password"
railway variables set APP_READONLY_PASSWORD="your_readonly_password"
railway variables set APP_READWRITE_PASSWORD="your_readwrite_password"
railway variables set PCP_PASSWORD="your_pcp_password"

# View all variables
railway variables
```

### Service Management
```bash
# List services
railway status

# View logs
railway logs --service pg-1
railway logs --service pgpool-1 --tail 100

# Execute command in service
railway run --service pg-1 -- gosu postgres psql
railway run --service pgpool-1 -- pcp_node_info -h localhost -p 9898 -U admin -w

# Restart service
railway restart --service pg-1
```

### Volume Management
```bash
# List volumes (via Railway dashboard - CLI support limited)
# Go to: Service → Settings → Volumes

# Backup volume (manual)
railway run --service pg-1 -- pg_dump -U postgres postgres > backup.sql
```

---

## 📊 Cluster Health Checks

### Repmgr Cluster Status
```bash
railway run --service pg-1 -- gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

**Expected output:**
```
 ID | Name    | Role    | Status    | Upstream | ...
----+---------+---------+-----------+----------+-----
  1 | pg-1    | primary | * running |          |
  2 | pg-2    | standby |   running | pg-1     |
  3 | pg-3    | standby |   running | pg-1     |
  4 | pg-4    | standby |   running | pg-1     |
100 | witness | witness | * running | pg-1     |
```

### PgPool Backend Status
```bash
railway run --service pgpool-1 -- pcp_node_info -h localhost -p 9898 -U admin -w
```

**Status codes:**
- `0` = Down
- `1` = Connecting
- `2` = Up (healthy)
- `3` = Up (waiting for connections)

### Replication Lag
```bash
railway run --service pg-1 -- gosu postgres psql -c "SELECT application_name, state, replay_lag FROM pg_stat_replication;"
```

**Healthy lag:** < 10 seconds (configurable via `REPMGR_PROMOTE_MAX_LAG_SECS`)

---

## 🔧 Common Operations

### Connect to Database

**Via PgPool (recommended):**
```bash
# From local machine (need public domain)
psql -h pgpool-1-production-xxx.railway.app -p 5432 -U app_readwrite -d postgres

# From Railway service
railway run --service pgpool-1 -- psql -h localhost -U app_readwrite -d postgres
```

**Direct to primary (admin only):**
```bash
railway run --service pg-1 -- gosu postgres psql
```

### Manual Failover

**Promote pg-2 to primary:**
```bash
railway run --service pg-2 -- gosu postgres repmgr standby promote -f /etc/repmgr/repmgr.conf --force
```

**Force standbys to follow new primary:**
```bash
railway run --service pg-3 -- gosu postgres repmgr standby follow -f /etc/repmgr/repmgr.conf --upstream-node-id=2
railway run --service pg-4 -- gosu postgres repmgr standby follow -f /etc/repmgr/repmgr.conf --upstream-node-id=2
```

### PgPool Operations

**Detach backend (maintenance):**
```bash
railway run --service pgpool-1 -- pcp_detach_node -h localhost -p 9898 -U admin -w -n 0  # Detach pg-1
```

**Re-attach backend:**
```bash
railway run --service pgpool-1 -- pcp_attach_node -h localhost -p 9898 -U admin -w -n 0  # Attach pg-1
```

**Reload PgPool config:**
```bash
railway run --service pgpool-1 -- pcp_reload_config -h localhost -p 9898 -U admin -w
```

**View pool processes:**
```bash
railway run --service pgpool-1 -- pcp_proc_info -h localhost -p 9898 -U admin -w
```

---

## 🐛 Troubleshooting

### Service won't start
```bash
# Check logs
railway logs --service pg-1 --tail 200

# Common issues:
# - Missing environment variable → Add in Railway dashboard
# - Volume mount failed → Check mount path is /var/lib/postgresql/data
# - Out of memory → Increase RAM allocation in service settings
```

### PgPool shows "backend down"
```bash
# Test backend connection from PgPool
railway run --service pgpool-1 -- psql -h pg-1.railway.internal -U repmgr -d postgres -c "SELECT 1"

# If fails, check:
# 1. pg-1 is running and healthy
# 2. REPMGR_PASSWORD matches in both services
# 3. pg_hba.conf allows connections (should auto-configure)
```

### Standby stuck cloning
```bash
# Check primary allows replication
railway run --service pg-1 -- cat /var/lib/postgresql/data/pg_hba.conf | grep replication

# Should see: host replication repmgr 0.0.0.0/0 scram-sha-256

# Check repmgr user exists
railway run --service pg-1 -- gosu postgres psql -c "SELECT rolname FROM pg_roles WHERE rolname='repmgr';"
```

### High replication lag
```bash
# Check WAL sender/receiver
railway run --service pg-1 -- gosu postgres psql -c "SELECT * FROM pg_stat_replication;"
railway run --service pg-2 -- gosu postgres psql -c "SELECT * FROM pg_stat_wal_receiver;"

# If lag > 10s consistently:
# - Increase REPMGR_PROMOTE_MAX_LAG_SECS (not recommended)
# - Check network latency between Railway regions
# - Increase standby resources (CPU/RAM)
```

---

## 📈 Performance Tuning

### PgPool Connection Pool
Edit `pgpool/pgpool.conf`:
```conf
num_init_children = 100        # Max concurrent clients (default)
max_pool = 20                  # Connections per backend (default)
child_life_time = 600          # Recycle connections after 10 min
connection_life_time = 0       # Don't time out idle connections
```

Redeploy PgPool services after changes.

### PostgreSQL Tuning
Edit `entrypoint.sh` (search for `write_postgresql_conf`):
```bash
shared_buffers = 256MB         # Default
max_connections = 100          # Default
work_mem = 4MB                 # Default
```

Redeploy PG services after changes.

### Railway Resource Allocation
- **Development**: 512 MB RAM per service
- **Production**: 1-2 GB RAM per PG node, 512 MB for PgPool
- **Volumes**: Start with 10 GB, monitor usage

---

## 🔒 Security

### Rotate Secrets
```bash
# Generate new password
openssl rand -base64 32

# Update in Railway dashboard
# Variables → Shared → Edit POSTGRES_PASSWORD

# Restart all services to pick up new password
railway restart --service pg-1
railway restart --service pg-2
# ... repeat for all services
```

### Check Authentication Method
```bash
railway run --service pg-1 -- gosu postgres psql -c "SELECT rolname, rolpassword FROM pg_authid WHERE rolname IN ('postgres', 'repmgr', 'app_readonly', 'app_readwrite');"
```

All should show `SCRAM-SHA-256$...`

### Review pg_hba.conf
```bash
railway run --service pg-1 -- cat /var/lib/postgresql/data/pg_hba.conf
```

Should restrict network access appropriately.

---

## 💾 Backup & Restore

### Backup (via pg_dump)
```bash
# Logical backup
railway run --service pg-1 -- pg_dump -U postgres -Fc postgres > backup_$(date +%Y%m%d).dump

# Restore
railway run --service pg-1 -- pg_restore -U postgres -d postgres -c backup_20250109.dump
```

### Railway Volume Snapshot
Currently manual via dashboard:
1. Go to service → Settings → Volumes
2. Create snapshot (if available in your plan)

---

## 📚 Useful Links

- **Railway Dashboard**: https://railway.app/dashboard
- **Railway Docs**: https://docs.railway.app
- **PgPool Docs**: https://www.pgpool.net/docs/latest/en/html/
- **Repmgr Docs**: https://repmgr.org/docs/current/
- **PostgreSQL Docs**: https://www.postgresql.org/docs/17/

---

## 🆘 Emergency Procedures

### Full Cluster Down → Restart

1. **Identify last primary** (check logs or repmgr events)
2. **Start last primary first:**
   ```bash
   railway restart --service pg-1  # Assuming pg-1 was last primary
   ```
3. **Wait for pg-1 healthy** (check logs)
4. **Start standbys:**
   ```bash
   railway restart --service pg-2
   railway restart --service pg-3
   railway restart --service pg-4
   ```
5. **Start witness:**
   ```bash
   railway restart --service witness
   ```
6. **Verify cluster:**
   ```bash
   railway run --service pg-1 -- gosu postgres repmgr cluster show
   ```

### Split-Brain (Multiple Primaries)

**Symptoms:** `repmgr cluster show` shows 2+ primaries

**Resolution:**
1. **Identify correct primary** (latest timeline, most data)
2. **Demote false primary(s):**
   ```bash
   railway run --service pg-2 -- pkill -9 postgres
   railway run --service pg-2 -- rm -rf /var/lib/postgresql/data/postmaster.pid
   railway restart --service pg-2
   # pg-2 will re-clone from correct primary
   ```

---

**Print this card for quick reference during operations!**
