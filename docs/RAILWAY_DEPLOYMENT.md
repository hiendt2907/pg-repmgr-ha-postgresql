# Railway Deployment Guide - PostgreSQL HA Cluster with PgPool

Step-by-step guide to deploy a production-ready PostgreSQL HA cluster (4 nodes + witness + 2 PgPool) on Railway.

---

## Prerequisites

1. **Railway Account**: Sign up at https://railway.app
2. **Railway CLI** (optional but recommended):
   ```bash
   npm install -g @railway/cli
   railway login
   ```
3. **GitHub Account**: To push your repo and link to Railway

---

## Architecture Summary

You will deploy **7 services** in total:

| Service | Purpose | Public Domain? | Volume |
|---------|---------|----------------|--------|
| `pg-1` | Primary PostgreSQL node | No | Yes (pg-1-data) |
| `pg-2` | Standby PostgreSQL node | No | Yes (pg-2-data) |
| `pg-3` | Standby PostgreSQL node | No | Yes (pg-3-data) |
| `pg-4` | Standby PostgreSQL node | No | Yes (pg-4-data) |
| `witness` | Quorum witness node | No | Yes (witness-data) |
| `pgpool-1` | PgPool-II load balancer #1 | **Yes** | No |
| `pgpool-2` | PgPool-II load balancer #2 | **Yes** | No |

**Clients connect to:** `pgpool-1` or `pgpool-2` public domains

---

## Step 1: Push Code to GitHub

```bash
# Fork/clone this repo
git clone https://github.com/hiendt2907/pg-ha-repo.git
cd pg-ha-repo

# Create your own repo on GitHub and push
git remote set-url origin https://github.com/YOUR_USERNAME/pg-ha-repo.git
git push -u origin main
```

---

## Step 2: Create Railway Project

### Option A: Via Railway Dashboard (Web UI)

1. Go to https://railway.app/new
2. Click **"Deploy from GitHub repo"**
3. Select your forked `pg-ha-repo`
4. Railway will create a project (don't deploy yet - we need to configure)

### Option B: Via Railway CLI

```bash
cd pg-ha-repo
railway init
# Follow prompts to create a new project
```

---

## Step 3: Set Shared Environment Variables

All services share these 5 secrets. Set them **once at the project level**:

### Via Railway Dashboard

1. Go to your project → **Variables** tab (top nav)
2. Click **"Shared Variables"**
3. Add these variables:

| Variable | Value (example - **use strong passwords!**) |
|----------|---------------------------------------------|
| `POSTGRES_PASSWORD` | `P@ssw0rd!Sup3rStr0ng` |
| `REPMGR_PASSWORD` | `Repmgr!S3cureP@ss` |
| `APP_READONLY_PASSWORD` | `ReadOnly!Pass123` |
| `APP_READWRITE_PASSWORD` | `ReadWrite!Pass456` |
| `PCP_PASSWORD` | `PCP!AdminP@ss789` |

**⚠️ Security Best Practice:**
- Use a password manager to generate strong, unique passwords
- Each password should be 16+ characters with mixed case, numbers, symbols
- Railway encrypts these at rest

### Via Railway CLI

```bash
railway variables set POSTGRES_PASSWORD="YOUR_STRONG_PASSWORD_HERE"
railway variables set REPMGR_PASSWORD="YOUR_REPMGR_PASSWORD"
railway variables set APP_READONLY_PASSWORD="YOUR_READONLY_PASSWORD"
railway variables set APP_READWRITE_PASSWORD="YOUR_READWRITE_PASSWORD"
railway variables set PCP_PASSWORD="YOUR_PCP_PASSWORD"
```

---

## Step 4: Deploy PostgreSQL Nodes (pg-1 through pg-4)

### Deploy pg-1 (Primary)

1. In Railway dashboard → Click **"New Service"**
2. Select **"Deploy from Dockerfile"**
3. Choose your GitHub repo: `pg-ha-repo`
4. Service name: `pg-1`
5. **Dockerfile path**: `Dockerfile` (root)
6. Click **"Add Variables"** (service-specific):

| Variable | Value |
|----------|-------|
| `NODE_NAME` | `pg-1` |
| `REPMGR_NODE_ID` | `1` |
| `NODE_PRIORITY` | `100` |
| `PEERS` | `pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal` |
| `PRIMARY_HOST` | `pg-1.railway.internal` |
| `POSTGRES_PASSWORD` | `${{shared.POSTGRES_PASSWORD}}` |
| `REPMGR_PASSWORD` | `${{shared.REPMGR_PASSWORD}}` |
| `APP_READONLY_PASSWORD` | `${{shared.APP_READONLY_PASSWORD}}` |
| `APP_READWRITE_PASSWORD` | `${{shared.APP_READWRITE_PASSWORD}}` |
| `REPMGR_PROMOTE_MAX_LAG_SECS` | `10` |

7. **Add Volume**:
   - Name: `pg-1-data`
   - Mount path: `/var/lib/postgresql/data`

8. Click **"Deploy"**

9. Wait for pg-1 to reach "healthy" status (check logs for `database system is ready to accept connections`)

### Deploy pg-2, pg-3, pg-4 (Standbys)

Repeat the above steps for `pg-2`, `pg-3`, `pg-4` with these **differences**:

**pg-2:**
- `NODE_NAME`: `pg-2`
- `REPMGR_NODE_ID`: `2`
- `NODE_PRIORITY`: `90`
- Volume name: `pg-2-data`

**pg-3:**
- `NODE_NAME`: `pg-3`
- `REPMGR_NODE_ID`: `3`
- `NODE_PRIORITY`: `80`
- Volume name: `pg-3-data`

**pg-4:**
- `NODE_NAME`: `pg-4`
- `REPMGR_NODE_ID`: `4`
- `NODE_PRIORITY`: `70`
- Volume name: `pg-4-data`

**All other variables remain the same** (same PEERS, PRIMARY_HOST, shared passwords).

---

## Step 5: Deploy Witness Node

1. **New Service** → `witness`
2. **Dockerfile path**: `Dockerfile`
3. **Variables**:

| Variable | Value |
|----------|-------|
| `NODE_NAME` | `witness` |
| `REPMGR_NODE_ID` | `100` |
| `NODE_PRIORITY` | `0` |
| `PEERS` | `pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal` |
| `PRIMARY_HOST` | `pg-1.railway.internal` |
| `POSTGRES_PASSWORD` | `${{shared.POSTGRES_PASSWORD}}` |
| `REPMGR_PASSWORD` | `${{shared.REPMGR_PASSWORD}}` |

4. **Volume**:
   - Name: `witness-data`
   - Mount path: `/var/lib/postgresql/data`

5. Deploy

---

## Step 6: Deploy PgPool Nodes

### Deploy pgpool-1

1. **New Service** → `pgpool-1`
2. **Dockerfile path**: `pgpool/Dockerfile`
3. **Build context**: `.` (root - important!)
4. **Variables**:

| Variable | Value |
|----------|-------|
| `PGPOOL_NODE_ID` | `0` |
| `PGPOOL_HOSTNAME` | `pgpool-1.railway.internal` |
| `PG_BACKENDS` | `pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432` |
| `POSTGRES_PASSWORD` | `${{shared.POSTGRES_PASSWORD}}` |
| `REPMGR_PASSWORD` | `${{shared.REPMGR_PASSWORD}}` |
| `APP_READONLY_PASSWORD` | `${{shared.APP_READONLY_PASSWORD}}` |
| `APP_READWRITE_PASSWORD` | `${{shared.APP_READWRITE_PASSWORD}}` |
| `PCP_PASSWORD` | `${{shared.PCP_PASSWORD}}` |
| `EXPORT_PLAINTEXT_POOLPWD` | `false` |
| `OTHER_PGPOOL_HOSTNAME` | `pgpool-2.railway.internal` |
| `OTHER_PGPOOL_PORT` | `5432` |
| `PGPOOL_WAIT_RETRIES` | `600` |
| `PGPOOL_WAIT_INTERVAL` | `5` |

5. **NO VOLUME** (PgPool is stateless)

6. **Settings → Networking → Generate Domain** (enable public access)

7. Deploy

### Deploy pgpool-2

Repeat for `pgpool-2` with these changes:
- `PGPOOL_NODE_ID`: `1`
- `PGPOOL_HOSTNAME`: `pgpool-2.railway.internal`
- `OTHER_PGPOOL_HOSTNAME`: `pgpool-1.railway.internal`

Everything else identical. **Also generate public domain** for pgpool-2.

---

## Step 7: Verify Deployment

### Check Service Health

In Railway dashboard:
- All 7 services should show **green "Active"** status
- Check logs for errors

### Check Repmgr Cluster

```bash
# Via Railway CLI
railway run --service pg-1 -- gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

Expected output:
```
 ID | Name    | Role    | Status    | Upstream | ...
----+---------+---------+-----------+----------+-----
  1 | pg-1    | primary | * running |          |
  2 | pg-2    | standby |   running | pg-1     |
  3 | pg-3    | standby |   running | pg-1     |
  4 | pg-4    | standby |   running | pg-1     |
100 | witness | witness | * running | pg-1     |
```

### Check PgPool Backend Status

```bash
railway run --service pgpool-1 -- pcp_node_info -h localhost -p 9898 -U admin -w
```

Expected: All 4 backends should show status `2` (up) or `3` (up, waiting)

---

## Step 8: Get Connection Strings

1. Go to `pgpool-1` service → **Settings → Networking**
2. Copy the **public domain** (e.g., `pgpool-1-production-abc123.railway.app`)
3. Your connection string:

```
postgresql://app_readwrite:YOUR_APP_READWRITE_PASSWORD@pgpool-1-production-abc123.railway.app:5432/postgres
```

**For high availability:** Configure your app to failover between both PgPool domains:

```python
# Python example
DATABASE_URLS = [
    "postgresql://app_readwrite:pass@pgpool-1-production-abc123.railway.app:5432/postgres",
    "postgresql://app_readwrite:pass@pgpool-2-production-xyz456.railway.app:5432/postgres"
]
```

---

## Step 9: Test Failover (Optional)

### Test Primary Failure

```bash
# Kill pg-1 postgres process
railway run --service pg-1 -- pkill -9 postgres

# Watch logs on pg-2 (should auto-promote)
railway logs --service pg-2

# Check cluster status (pg-2 should be new primary)
railway run --service pg-2 -- gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

# Check pgpool (should detect new primary)
railway run --service pgpool-1 -- pcp_node_info -h localhost -p 9898 -U admin -w
```

Expected:
1. pg-2 promotes to primary in ~30 seconds
2. pg-3, pg-4 follow new primary
3. PgPool routes writes to pg-2
4. When pg-1 recovers, it rejoins as standby via `pg_rewind`

---

## Troubleshooting

### "Service crashed" / "Container exited"

**Check logs:**
```bash
railway logs --service pg-1
```

Common issues:
- Missing environment variable → Add it in service settings
- Volume mount failed → Check mount path is `/var/lib/postgresql/data`
- Network timeout → Railway private networking takes ~30s to stabilize after deploy

### PgPool shows "backend down"

**Test backend connectivity:**
```bash
railway run --service pgpool-1 -- psql -h pg-1.railway.internal -U repmgr -d postgres -c "SELECT 1"
```

If fails:
- Check pg-1 is running and healthy
- Verify `REPMGR_PASSWORD` matches in both PostgreSQL and PgPool services
- Check `pool_passwd` was generated correctly:
  ```bash
  railway run --service pgpool-1 -- cat /etc/pgpool-II/pool_passwd
  ```

### Standbys stuck "cloning"

**Symptom:** `pg-2` logs show endless `pg_basebackup` retries

**Cause:** Primary not accepting replication connections

**Fix:**
```bash
# Check pg_hba.conf on primary
railway run --service pg-1 -- cat /var/lib/postgresql/data/pg_hba.conf | grep replication

# Should contain:
# host replication repmgr 0.0.0.0/0 scram-sha-256
```

If missing, entrypoint may have failed. Redeploy pg-1.

---

## Cost Optimization Tips

1. **Use Railway Free Tier**: 
   - 512 MB RAM per service
   - $5/month credit
   - Good for staging/testing

2. **Scale down non-critical nodes**:
   - Run with 2 PG nodes + witness for dev (1 primary + 1 standby)
   - Disable pgpool-2 for dev (use only pgpool-1)

3. **Use Railway's sleep mode**:
   - Enable auto-sleep for dev environments
   - Services sleep after 5 min inactivity

4. **Monitor volume usage**:
   - Railway charges for storage beyond free tier
   - Regularly clean up old WAL files (PostgreSQL auto-manages this)

---

## Next Steps

- **Monitoring**: Integrate with Railway's built-in metrics or add external monitoring (Prometheus/Grafana)
- **Backups**: Set up automated backups (pg_dump to S3, or Railway volume snapshots)
- **SSL/TLS**: Enable SSL for client connections (see README security section)
- **Scaling**: Add more standbys by repeating Step 4 with new node IDs

---

**Questions?** File an issue at https://github.com/hiendt2907/pg-ha-repo/issues
