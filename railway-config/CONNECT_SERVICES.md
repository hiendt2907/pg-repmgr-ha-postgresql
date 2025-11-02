# Connect GitHub Repo to Railway Services

After running `create-services.sh`, you need to connect the GitHub repository to each service manually via Railway Dashboard.

## Prerequisites

✅ Services created via `create-services.sh`  
✅ Variables set (shared + service-specific)  
✅ Volumes added to PostgreSQL nodes

## Step-by-Step Guide

### 1. Open Railway Dashboard

Go to: https://railway.app/dashboard

Select your project (the one you linked with `railway link`)

---

### 2. Connect PostgreSQL Services

For each PostgreSQL service: **pg-1**, **pg-2**, **pg-3**, **pg-4**, **witness**

#### Steps:
1. Click on the service (e.g., `pg-1`)
2. Go to **Settings** tab
3. Find **Source** section
4. Click **Connect Repo**
5. Select: `hiendt2907/pg-repmgr-ha-postgresql`
6. Configure:
   - **Branch**: `main`
   - **Root Directory**: `/` (leave empty or set to root)
   - **Dockerfile Path**: `postgresql/Dockerfile`
7. Click **Save**

#### Quick Reference:
```
Service: pg-1, pg-2, pg-3, pg-4, witness
├─ Repo: hiendt2907/pg-repmgr-ha-postgresql
├─ Branch: main
├─ Root Directory: /
└─ Dockerfile Path: postgresql/Dockerfile
```

---

### 3. Connect PgPool Services

For each PgPool service: **pgpool-1**, **pgpool-2**

#### Steps:
1. Click on the service (e.g., `pgpool-1`)
2. Go to **Settings** tab
3. Find **Source** section
4. Click **Connect Repo**
5. Select: `hiendt2907/pg-repmgr-ha-postgresql`
6. Configure:
   - **Branch**: `main`
   - **Root Directory**: `/`
   - **Dockerfile Path**: `pgpool/Dockerfile`
7. Click **Save**

#### Quick Reference:
```
Service: pgpool-1, pgpool-2
├─ Repo: hiendt2907/pg-repmgr-ha-postgresql
├─ Branch: main
├─ Root Directory: /
└─ Dockerfile Path: pgpool/Dockerfile
```

---

### 4. Connect HAProxy Service

For service: **haproxy**

#### Steps:
1. Click on the service `haproxy`
2. Go to **Settings** tab
3. Find **Source** section
4. Click **Connect Repo**
5. Select: `hiendt2907/pg-repmgr-ha-postgresql`
6. Configure:
   - **Branch**: `main`
   - **Root Directory**: `/`
   - **Dockerfile Path**: `haproxy/Dockerfile`
7. Click **Save**

#### Quick Reference:
```
Service: haproxy
├─ Repo: hiendt2907/pg-repmgr-ha-postgresql
├─ Branch: main
├─ Root Directory: /
└─ Dockerfile Path: haproxy/Dockerfile
```

---

### 5. Enable Public Domain for HAProxy

HAProxy is the **only service** that needs a public domain (client entry point).

#### Steps:
1. Click on `haproxy` service
2. Go to **Settings** tab
3. Find **Networking** section
4. Click **Generate Domain**
5. Copy the generated domain (e.g., `haproxy-production-xxxx.up.railway.app`)
6. **Save this URL** - this is your PostgreSQL cluster entry point!

---

## Deployment Order

After connecting all repos, deploy services in this order:

### Phase 1: PostgreSQL Cluster Bootstrap
```bash
1. Deploy pg-1 (primary node)
   Wait for: "repmgr: node 'pg-1' (ID: 1) registered as primary"
   
2. Deploy pg-2, pg-3, pg-4 in parallel
   Wait for: All nodes show "standby clone from primary"
   
3. Deploy witness
   Wait for: "witness registered successfully"
```

### Phase 2: Connection Layer
```bash
4. Deploy pgpool-1, pgpool-2 in parallel
   Wait for: Both show "PgPool-II successfully started"
   
5. Deploy haproxy
   Wait for: Health checks pass on both PgPool backends
```

---

## Verification

### Check Service Logs

1. **pg-1 (Primary)**:
   ```
   ✅ "PostgreSQL init process complete; ready for start up"
   ✅ "repmgr: node 'pg-1' registered as primary"
   ```

2. **pg-2, pg-3, pg-4 (Standbys)**:
   ```
   ✅ "standby clone (from primary) complete"
   ✅ "repmgr: node 'pg-X' registered as standby"
   ```

3. **witness**:
   ```
   ✅ "witness node registered successfully"
   ```

4. **pgpool-1, pgpool-2**:
   ```
   ✅ "PgPool-II successfully started"
   ✅ "find_primary_node: primary node is X"
   ```

5. **haproxy**:
   ```
   ✅ "HAProxy started"
   ✅ "Proxy postgresql started"
   ✅ "Health check for backend pgpool-1 passed"
   ```

### Test Connection

From your local machine:
```bash
# Get HAProxy public domain
HAPROXY_URL="<your-haproxy-domain>.up.railway.app"

# Test connection
psql "postgresql://postgres:<password>@${HAPROXY_URL}:5432/postgres"

# Check cluster status (inside psql)
\c repmgr
SELECT * FROM repmgr.nodes;
SELECT * FROM repmgr.show_nodes;
```

Expected output:
```
 node_id | node_name |  role   | status    | upstream_node_name
---------+-----------+---------+-----------+--------------------
    1    | pg-1      | primary | running   | -
    2    | pg-2      | standby | running   | pg-1
    3    | pg-3      | standby | running   | pg-1
    4    | pg-4      | standby | running   | pg-1
  100    | witness   | witness | running   | -
```

---

## Troubleshooting

### Service won't build
- Check Dockerfile path is correct
- Verify branch is `main`
- Check build logs for errors

### Service crashes on startup
- Check environment variables are set
- Verify shared variables exist in project
- Check service logs for specific errors

### Can't connect to database
- Verify HAProxy has public domain enabled
- Check all services are healthy
- Verify POSTGRES_PASSWORD matches in client connection

### PgPool can't find backends
- Verify all PostgreSQL services are running
- Check `PG_BACKENDS` variable format
- Ensure Railway internal DNS is working (`.railway.internal`)

---

## Summary

| Service | Dockerfile Path | Public Domain |
|---------|----------------|---------------|
| pg-1, pg-2, pg-3, pg-4, witness | `postgresql/Dockerfile` | ❌ No |
| pgpool-1, pgpool-2 | `pgpool/Dockerfile` | ❌ No |
| haproxy | `haproxy/Dockerfile` | ✅ **Yes** |

**Total Time**: ~10-15 minutes for full deployment

**Next Step**: After all services are connected and deployed, proceed to failover testing as documented in `DEPLOYMENT_GUIDE.md`
