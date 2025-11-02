# Railway Deployment Guide - Step by Step

## Prerequisites

✅ Railway CLI installed and authenticated
✅ Credentials generated (via `setup-variables.sh`)

## Option 1: Deploy via Railway Dashboard (Recommended)

### Step 1: Create Project & Services

1. **Go to Railway Dashboard**: https://railway.app/dashboard
2. **Create New Project** or use existing "hiendt" project
3. **Create 8 Services** with these names:
   - `pg-1` (PostgreSQL primary)
   - `pg-2` (PostgreSQL standby)
   - `pg-3` (PostgreSQL standby)
   - `pg-4` (PostgreSQL standby)
   - `witness` (PostgreSQL witness)
   - `pgpool-1` (PgPool instance 1)
   - `pgpool-2` (PgPool instance 2)
   - `haproxy` (HAProxy load balancer)

### Step 2: Set Shared Variables

In **Project Settings → Shared Variables**, add:

```
POSTGRES_PASSWORD=<from credentials file>
REPMGR_PASSWORD=<from credentials file>
APP_READONLY_PASSWORD=<from credentials file>
APP_READWRITE_PASSWORD=<from credentials file>
PCP_PASSWORD=<from credentials file>
HAPROXY_STATS_PASSWORD=<from credentials file>
REPMGR_PROMOTE_MAX_LAG_SECS=5
```

### Step 3: Configure Each Service

#### For `pg-1` service:

**Settings → Source:**
- Source: GitHub repository `hiendt2907/pg-ha-repo`
- Build: Docker
- Dockerfile Path: `postgresql-cluster/postgresql/Dockerfile`
- Root Directory: `/`

**Settings → Variables:**
```
NODE_NAME=pg-1
REPMGR_NODE_ID=1
NODE_PRIORITY=100
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
PRIMARY_HOST=pg-1.railway.internal
```

**Settings → Volume:**
- Mount Path: `/var/lib/postgresql/data`
- Size: 100 GB

**Settings → Resources:**
- vCPU: 32
- Memory: 32 GB

#### For `pg-2` service:

**Settings → Source:**
- Same as pg-1

**Settings → Variables:**
```
NODE_NAME=pg-2
REPMGR_NODE_ID=2
NODE_PRIORITY=90
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
PRIMARY_HOST=pg-1.railway.internal
```

**Settings → Volume:**
- Mount Path: `/var/lib/postgresql/data`
- Size: 100 GB

**Settings → Resources:**
- vCPU: 32
- Memory: 32 GB

#### For `pg-3` service:

**Settings → Source:**
- Same as pg-1

**Settings → Variables:**
```
NODE_NAME=pg-3
REPMGR_NODE_ID=3
NODE_PRIORITY=80
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
PRIMARY_HOST=pg-1.railway.internal
```

**Settings → Volume:**
- Mount Path: `/var/lib/postgresql/data`
- Size: 100 GB

**Settings → Resources:**
- vCPU: 32
- Memory: 32 GB

#### For `pg-4` service:

**Settings → Source:**
- Same as pg-1

**Settings → Variables:**
```
NODE_NAME=pg-4
REPMGR_NODE_ID=4
NODE_PRIORITY=70
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
PRIMARY_HOST=pg-1.railway.internal
```

**Settings → Volume:**
- Mount Path: `/var/lib/postgresql/data`
- Size: 100 GB

**Settings → Resources:**
- vCPU: 32
- Memory: 32 GB

#### For `witness` service:

**Settings → Source:**
- Same as pg-1

**Settings → Variables:**
```
NODE_NAME=witness
REPMGR_NODE_ID=100
NODE_PRIORITY=0
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
PRIMARY_HOST=pg-1.railway.internal
```

**Settings → Volume:**
- Mount Path: `/var/lib/postgresql/data`
- Size: 10 GB

**Settings → Resources:**
- vCPU: 2
- Memory: 2 GB

#### For `pgpool-1` service:

**Settings → Source:**
- Source: GitHub repository `hiendt2907/pg-ha-repo`
- Build: Docker
- Dockerfile Path: `postgresql-cluster/pgpool/Dockerfile`
- Root Directory: `/`

**Settings → Variables:**
```
PGPOOL_NODE_ID=0
PGPOOL_HOSTNAME=pgpool-1.railway.internal
PG_BACKENDS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432
EXPORT_PLAINTEXT_POOLPWD=false
OTHER_PGPOOL_HOSTNAME=pgpool-2.railway.internal
OTHER_PGPOOL_PORT=5432
PGPOOL_WAIT_RETRIES=600
PGPOOL_WAIT_INTERVAL=2
```

**Settings → Resources:**
- vCPU: 16
- Memory: 32 GB

#### For `pgpool-2` service:

**Settings → Source:**
- Same as pgpool-1

**Settings → Variables:**
```
PGPOOL_NODE_ID=1
PGPOOL_HOSTNAME=pgpool-2.railway.internal
PG_BACKENDS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432
EXPORT_PLAINTEXT_POOLPWD=false
OTHER_PGPOOL_HOSTNAME=pgpool-1.railway.internal
OTHER_PGPOOL_PORT=5432
PGPOOL_WAIT_RETRIES=600
PGPOOL_WAIT_INTERVAL=2
```

**Settings → Resources:**
- vCPU: 16
- Memory: 32 GB

#### For `haproxy` service:

**Settings → Source:**
- Source: GitHub repository `hiendt2907/pg-ha-repo`
- Build: Docker
- Dockerfile Path: `postgresql-cluster/haproxy/Dockerfile`
- Root Directory: `/`

**Settings → Variables:**
```
PGPOOL_BACKENDS=pgpool-1.railway.internal:5432,pgpool-2.railway.internal:5432
HAPROXY_STATS_PORT=8404
HAPROXY_STATS_USER=admin
```

**Settings → Networking:**
- Enable **Public Domain** ✅

**Settings → Resources:**
- vCPU: 8
- Memory: 4 GB

### Step 4: Deploy in Order

**IMPORTANT**: Deploy services in this specific order to ensure proper cluster initialization.

1. **Deploy `pg-1` first**
   - Click "Deploy" on pg-1 service
   - Wait until status shows "Active" (healthy)
   - Check logs for: "PostgreSQL init process complete; ready for start up"

2. **Deploy `pg-2`, `pg-3`, `pg-4` together**
   - Deploy all three standby nodes
   - Wait until all show "Active"
   - Check logs for: "repmgr standby clone completed successfully"

3. **Deploy `witness`**
   - Deploy witness node
   - Wait until "Active"

4. **Verify PostgreSQL cluster**
   ```bash
   railway run --service pg-1 -- su - postgres -c "repmgr cluster show"
   ```
   
   Expected output:
   ```
    ID | Name    | Role    | Status    | Upstream | Location | Priority
   ----+---------+---------+-----------+----------+----------+----------
    1  | pg-1    | primary | * running |          | default  | 100
    2  | pg-2    | standby |   running | pg-1     | default  | 90
    3  | pg-3    | standby |   running | pg-1     | default  | 80
    4  | pg-4    | standby |   running | pg-1     | default  | 70
   100 | witness | witness | * running | pg-1     | default  | 0
   ```

5. **Deploy `pgpool-1` and `pgpool-2`**
   - Deploy both PgPool instances together
   - Wait until both are "Active"

6. **Deploy `haproxy` last**
   - Deploy HAProxy service
   - Wait until "Active"
   - Note the generated public domain (e.g., `haproxy-production.up.railway.app`)

### Step 5: Test Connection

```bash
# Via HAProxy public domain
psql "postgresql://app_readwrite:<PASSWORD>@haproxy-production.up.railway.app:5432/postgres"

# Check HAProxy stats
curl http://haproxy-production.up.railway.app:8404
# Login: admin / <HAPROXY_STATS_PASSWORD>
```

## Option 2: Deploy via Railway CLI (Advanced)

Railway CLI v3+ doesn't support creating services directly. You must:

1. Create services via Dashboard first
2. Link each service locally:
   ```bash
   railway link --service pg-1
   ```

3. Deploy using:
   ```bash
   railway up --service pg-1 --detach
   ```

## Monitoring

### Check Cluster Status
```bash
# PostgreSQL replication status
railway run --service pg-1 -- su - postgres -c "repmgr cluster show"

# PgPool status
railway run --service pgpool-1 -- pcp_node_count -h localhost -p 9898 -U admin -w

# HAProxy stats via curl
curl http://<haproxy-domain>:8404/stats
```

### View Logs
```bash
railway logs --service pg-1
railway logs --service pgpool-1
railway logs --service haproxy
```

## Troubleshooting

### Service won't start
1. Check logs: `railway logs --service <name>`
2. Verify all shared variables are set
3. Ensure service-specific variables are correct
4. Check volume is mounted at `/var/lib/postgresql/data`

### Replication not working
1. Verify all PostgreSQL nodes are healthy
2. Check network connectivity between nodes
3. Verify PEERS variable includes all nodes
4. Check repmgr logs: `railway run --service pg-1 -- cat /var/log/repmgr/repmgrd.log`

### PgPool connection issues
1. Ensure PostgreSQL nodes are deployed first
2. Check PG_BACKENDS includes all nodes
3. Verify shared passwords match
4. Check pgpool logs for backend connection errors

### HAProxy not routing
1. Ensure PgPool nodes are healthy
2. Verify PGPOOL_BACKENDS variable
3. Check HAProxy stats page for backend status
4. Review HAProxy logs

## Resource Costs

Based on Railway pricing (approximate):

- 4× PostgreSQL nodes: 32 vCPU × 32 GB × 4 = 128 vCPU, 128 GB RAM
- 1× Witness: 2 vCPU × 2 GB = 2 vCPU, 2 GB RAM
- 2× PgPool: 16 vCPU × 32 GB × 2 = 32 vCPU, 64 GB RAM
- 1× HAProxy: 8 vCPU × 4 GB = 8 vCPU, 4 GB RAM

**Total**: 170 vCPU, 198 GB RAM, 410 GB storage

Estimated cost: ~$XXX/month (check Railway pricing for current rates)

## Next Steps

1. Complete deployment following steps above
2. Configure backups (Railway volumes support snapshots)
3. Set up monitoring alerts
4. Configure application to use HAProxy public domain
5. Test failover scenarios

## Support Files

- Credentials: `railway-credentials-<timestamp>.txt`
- Service config: `railway-config/railway-services.json`
- This guide: `railway-config/DEPLOYMENT_GUIDE.md`
