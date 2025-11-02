# PostgreSQL High Availability Cluster for Railway# PostgreSQL HA Cluster for Railway# PostgreSQL High Availability Cluster with repmgr



Production-ready PostgreSQL HA cluster with **automatic failover (repmgr)** + **connection pooling & load balancing (PgPool-II)**, optimized for Railway.app deployment.



[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new)Production-ready PostgreSQL High Availability cluster optimized for **Railway** deployment with automatic failover using **repmgr**.Production-ready PostgreSQL HA cluster optimized for **Railway deployment** with automatic failover using **repmgr**.



---



## 🏗️ Architecture Overview[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new)## 🚀 Quick Deploy to Railway



```

┌──────────────────────────────────────────────────────────────────────┐

│                         Railway Project                              │---[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new)

├──────────────────────────────────────────────────────────────────────┤

│                                                                      │

│  ┌──────────────┐           ┌──────────────┐                        │

│  │  pgpool-1    │◄─────────►│  pgpool-2    │  ← Client Apps        │## ✨ Features**One-click deploy coming soon. For now, use manual deployment below.**

│  │ (Pool+LB)    │  Watchdog │ (Pool+LB)    │    Connect Here       │

│  │ Port 5432    │  (HA)     │ Port 5432    │    (Public Domain)    │

│  └──────┬───────┘           └──────┬───────┘                        │

│         │                          │                                │### High Availability & Resilience**Built with:** PostgreSQL 17.6 • Repmgr • Docker Compose

│         └──────────┬───────────────┘                                │

│                    │ Smart Connection Pooling                       │- ⚡ **Automatic Failover** - Detects failures and promotes standbys in ~30s

│         ┌──────────┴──────────────────────────┐                     │

│         │                                     │                     │- 🔄 **4 PostgreSQL nodes** + 1 witness node for robust quorum---

│  ┌──────▼──┐  ┌─────────┐  ┌─────────┐  ┌───▼─────┐               │

│  │  pg-1   │  │  pg-2   │  │  pg-3   │  │  pg-4   │               │- 🛡️ **Promotion Guard** - Prevents promotion of heavily lagged standbys  

│  │ PRIMARY │◄─┤ STANDBY │◄─┤ STANDBY │◄─┤ STANDBY │               │

│  │ (Write) │  │ (Read)  │  │ (Read)  │  │ (Read)  │               │- 🔁 **Auto-Rejoin** - Uses `pg_rewind` to automatically rejoin demoted primaries## 🔧 Recent changes (quick summary)

│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘               │

│       │   repmgr   │    repmgr  │    repmgr  │                     │- 📝 **Last-Known-Primary** - Smooth recovery after full cluster outages

│       │   monitor  │   monitor  │   monitor  │                     │

│       └────────────┴────────────┴────────────┘                     │- ♻️ **Self-Healing** - Failed nodes auto-recover without manual intervention- entrypoint and init logic: all initdb calls now use --data-checksums to enable page checksums and improve failure detection.

│                        │                                            │

│                   ┌────▼────┐                                       │- monitor.sh: replaced with a lock-based, event-driven monitor that serializes destructive operations (flock), tries pg_rewind on returning nodes and falls back to a safe full clone when rewind is not possible. This avoids race conditions and split-brain on simultaneous restarts.

│                   │ WITNESS │                                       │

│                   │  Node   │  (Quorum for auto-failover)           │### Security & Best Practices- repmgr usage: repmgr commands are now executed under the postgres user (gosu) and the clone/registration arguments were corrected.

│                   └─────────┘                                       │

│                                                                      │- 🔐 **SCRAM-SHA-256** - Modern authentication (default)- Tests: manual failover / rejoin / full-cluster-down tests were executed and validated (promotion, pg_rewind, clone fallback, last-known-primary logic).

│  Railway Private Network: *.railway.internal (IPv6)                 │

└──────────────────────────────────────────────────────────────────────┘- 🔒 **Hardened pg_hba.conf** - Peer auth for local, SCRAM for network

```

- 🎯 **Minimal Variables** - Only ~30 vars for entire clusterNote: this repository intentionally omits PgPool-II configuration by request — the README and examples below focus on direct node operations, cluster failover logic, and operator tooling. If you need PgPool integration later, see docs/PGPOOL_DEPLOYMENT.md for guidance.

### Component Breakdown

- 🔑 **Secrets Management** - Railway's built-in secure credential storage

| Component | Count | Purpose | Railway Domain |

|-----------|-------|---------|----------------|- ✅ **Data Checksums** - Enabled for corruption detectionSee the "Files changed" section below for exact files touched and the "Test scenarios" section for example commands.

| **PostgreSQL Nodes** | 4 | Data storage + replication | `pg-1..pg-4.railway.internal` |

| **Witness Node** | 1 | Quorum for failover voting | `witness.railway.internal` |

| **PgPool-II Nodes** | 2 | Connection pooling + load balancing | `pgpool-1,pgpool-2.railway.internal` |

### Railway-Optimized

**Total: 7 Railway services**

- ☁️ **Private Networking** - IPv6-only internal communication via `*.railway.internal`## 🎯 What This Cluster Does

---

- 💾 **Persistent Volumes** - Automatic volume management per service

## ✨ Features

- 📊 **Monitoring** - Railway metrics + repmgr event history### ✅ Core Features

### High Availability & Resilience

- ⚡ **Automatic Failover** - Repmgr detects failures and promotes standbys in ~30s- 💰 **Cost-Effective** - Pay only for resources used- **Automatic Failover**: Primary fails → Standby promoted automatically (15-30s)

- 🔄 **4 PostgreSQL nodes** + 1 witness node for robust quorum

- 🛡️ **Promotion Guard** - Prevents promotion of heavily lagged standbys (configurable lag threshold)- 🚀 **Zero-Config Deploy** - Works out of the box with minimal setup- **Self-Healing**: Failed nodes auto-rejoin cluster with pg_rewind

- 🔁 **Auto-Rejoin** - Uses `pg_rewind` to automatically rejoin demoted primaries

- 📝 **Last-Known-Primary** - Smooth recovery after full cluster outages- **Full Cluster Recovery**: Entire cluster down → Auto-bootstrap from last-known-primary

- ♻️ **Self-Healing** - Failed nodes auto-recover without manual intervention

**Technology Stack:** PostgreSQL 17.6 | repmgr 5.4 | Railway- **Direct Connections (no pool)**: Examples and scripts assume direct connections to nodes; pooling is intentionally omitted in this branch

### Connection Pooling & Load Balancing (PgPool-II)

- 🎯 **Smart Query Routing**- **Zero Data Loss**: Synchronous replication available (optional)

  - **Writes** → Always routed to PRIMARY

  - **Reads** → Load-balanced across STANDBY nodes (round-robin)---- **Special Characters Support**: Passwords with `:;#*!` work correctly

  - **Session-level balancing** - Sticky connections for transaction safety

- 🔌 **Connection Pooling** - Reduces overhead, improves throughput

- 🏥 **Health Checks** - Automatic backend node detection and failover

- 📊 **Monitoring** - PCP protocol for real-time pool status## 🏗️ Architecture### 📊 Cluster Topology

- 🔄 **PgPool HA** - 2 PgPool nodes with watchdog support (optional)

```

### Security & Best Practices

- 🔐 **SCRAM-SHA-256** - Modern authentication (enforced)```Applications

- 🔒 **Hardened pg_hba.conf** - Peer auth for local, SCRAM for network

- 🎯 **Minimal Variables** - Only 5 shared secrets for entire cluster┌─────────────────────────────────────────────────────┐  │

- 🔑 **Secrets Management** - Railway's built-in secure credential storage

- ✅ **Data Checksums** - Enabled for corruption detection│      Railway Project (Private Network IPv6)         │  └── Direct connections to nodes (no PgPool configured in this repo)

- 🚫 **No Plaintext Passwords** - All pool_passwd entries use SCRAM hashes

├─────────────────────────────────────────────────────┤                ├── pg-1 (PRIMARY)   Priority: 199

### Railway-Optimized

- 🌐 **Private Networking** - Services communicate via `.railway.internal` (IPv6)│                                                      │                ├── pg-2 (STANDBY)  Priority: 198

- 💾 **Persistent Volumes** - Each PostgreSQL node has dedicated storage

- 📦 **Minimal Footprint** - Optimized Docker images│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌────────┐│                ├── pg-3 (STANDBY)  Priority: 197

- 🔧 **Zero Docker Compose** - Pure Railway service definitions

- ⚙️ **Auto-Discovery** - Services discover each other via Railway DNS│  │ pg-1 │  │ pg-2 │  │ pg-3 │  │ pg-4 │  │witness ││                ├── pg-4 (STANDBY)  Priority: 196



---│  │(Pri) │  │(Stby)│  │(Stby)│  │(Stby)│  │(Quorum)││                └── witness (Quorum only)



## 🚀 Quick Start│  │ P:199│  │ P:198│  │ P:197│  │ P:196│  │  P:99  ││```



### Prerequisites│  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘  └───┬────┘│

- Railway account ([sign up free](https://railway.app))

- Railway CLI installed: `npm i -g @railway/cli`│     │         │         │         │          │     │**Total Capacity**: 4 data nodes + 1 witness



### Deployment Steps│     └─────────┴─────────┴─────────┴──────────┘     │



#### 1. Create Railway Project│         repmgr cluster (auto-failover)              │---

```bash

# Clone this repo│                                                      │

git clone https://github.com/hiendt2907/pg-ha-repo.git

cd pg-ha-repo│  Internal DNS:                                       │## 🚀 Quick Start (5 minutes)



# Login to Railway│  - pg-1.railway.internal:5432                       │

railway login

│  - pg-2.railway.internal:5432                       │```bash

# Create new project

railway init│  - pg-3.railway.internal:5432                       │# 1. Clone repo

```

│  - pg-4.railway.internal:5432                       │git clone <repo-url> && cd pg_ha_cluster_production

#### 2. Set Shared Environment Variables

│  - witness.railway.internal:5432                    │

Create shared variables in Railway dashboard or via CLI:

└──────────────────────────────────────────────────────┘# 2. Generate passwords

```bash

# Required secrets (generate strong passwords!)```./scripts/generate-passwords.sh

railway variables set POSTGRES_PASSWORD=your_strong_password_here

railway variables set REPMGR_PASSWORD=your_repmgr_password_here

railway variables set APP_READONLY_PASSWORD=your_readonly_password_here

railway variables set APP_READWRITE_PASSWORD=your_readwrite_password_here**Failover Flow:**# 3. Start cluster

railway variables set PCP_PASSWORD=your_pcp_admin_password_here

```1. Primary (pg-1) failsdocker-compose up -d



**⚠️ SECURITY:** Use strong, unique passwords. Railway encrypts these at rest.2. Witness + 3 standbys vote



#### 3. Deploy Services3. Highest-priority standby (pg-2) promoted# 4. Check status (wait ~30s for cluster to form)



Use the provided Railway config template:4. Other standbys automatically follow new primarydocker exec pg-1 gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show



```bash5. Old primary (pg-1) rejoins as standby via pg_rewind

# Deploy all 7 services using railway-config/railway-services.json

# Railway CLI currently requires manual service creation# 5. Get connection info

# Follow the config template in railway-config/railway-services.json

---./scripts/show-credentials.sh

# Alternative: Use Railway Dashboard UI

# 1. Go to your Railway project```

# 2. Click "New Service" → "From Dockerfile"

# 3. Configure according to railway-services.json## 🚀 Quick Deploy

# 4. Repeat for all 7 services

```**Expected output (step 4):**



**Service Deployment Order (recommended):**### Prerequisites```

1. `pg-1` (Primary)

2. `pg-2`, `pg-3`, `pg-4` (Standbys - can be parallel)- Railway account ([sign up free](https://railway.app)) ID | Name | Role    | Status    | Upstream | Priority

3. `witness`

4. `pgpool-1`, `pgpool-2` (Wait for PG nodes to be healthy)- Railway CLI installed (optional, recommended)----+------+---------+-----------+----------+----------



#### 4. Configure Public Domains 1  | pg-1 | primary | * running |          | 199



Enable public domains for PgPool services:```bash 2  | pg-2 | standby |   running | pg-1     | 198



```bash# Install Railway CLI (optional) 3  | pg-3 | standby |   running | pg-1     | 197

# In Railway Dashboard:

# pgpool-1 → Settings → Networking → Generate Domainnpm i -g @railway/cli 4  | pg-4 | standby |   running | pg-1     | 196

# pgpool-2 → Settings → Networking → Generate Domain

```# or: brew install railway```



Your connection string will be:

```

postgresql://app_readwrite:password@pgpool-1-production-xxxx.railway.app:5432/postgres# Login---

```

railway login

#### 5. Verify Cluster Health

```## 💻 How to Connect

```bash

# Check repmgr cluster status

railway run --service pg-1 -- gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

### Option 1: Automated Deployment (Recommended)### Direct to Primary (Admin/Monitoring)

# Check pgpool backend status

railway run --service pgpool-1 -- pcp_node_info -h localhost -p 9898 -U admin -w```bash

```

```bash# Connection string

---

# Clone repopostgresql://postgres:<password>@localhost:5401/postgres

## 📊 Connection Strategies

git clone https://github.com/hiendt2907/pg-ha-repo.git

### For Application Clients

cd pg-ha-repo# psql

**Recommended: Connect via PgPool (Read/Write Splitting)**

PGPASSWORD=<password> psql -h localhost -p 5401 -U postgres

```python

# Python example with psycopg2/3# Run deployment script```

import psycopg2

./railway-config/deploy-railway.sh

# PgPool automatically routes queries

conn = psycopg2.connect(```**Get passwords:** Run `./scripts/show-credentials.sh`

    host="pgpool-1-production-xxxx.railway.app",

    port=5432,

    database="postgres",

    user="app_readwrite",  # Has read+write permissionsThis script will:---

    password="your_app_readwrite_password"

)1. ✅ Generate secure random passwords



# Writes go to primary automatically2. ✅ Create Railway project## 🔐 Security & Credentials

cursor.execute("INSERT INTO users (name) VALUES ('Alice')")

3. ✅ Set shared variables

# Reads load-balanced across standbys automatically

cursor.execute("SELECT * FROM users")4. ✅ Configure all 5 servicesAll passwords auto-generated (24 chars, random):

```

5. ✅ Save credentials to secure file```bash

### Connection String Examples

./scripts/generate-passwords.sh   # Creates .env file

| Use Case | Connection String | Description |

|----------|-------------------|-------------|**Then manually:**./scripts/show-credentials.sh     # View all credentials

| **App (RW)** | `postgresql://app_readwrite:pass@pgpool-1-xxx.railway.app:5432/postgres` | Read+Write via PgPool |

| **App (RO)** | `postgresql://app_readonly:pass@pgpool-1-xxx.railway.app:5432/postgres` | Read-only via PgPool |1. Add volumes to each service (see output instructions)```

| **Direct Primary** | `postgresql://postgres:pass@pg-1.railway.internal:5432/postgres` | Direct write (not recommended) |

| **Admin** | `postgresql://postgres:pass@pg-1.railway.internal:5432/postgres` | Admin operations |2. Deploy in order: `pg-1` → `pg-2,pg-3,pg-4` → `witness`



### PgPool Features Configuration**Users created:**



**Query Routing (Automatic):**### Option 2: Manual Setup (via Railway Dashboard)- `postgres` - Superuser (admin only)

- `SELECT`, `COPY TO`, read-only functions → Standbys (load-balanced)

- `INSERT`, `UPDATE`, `DELETE`, `DDL` → Primary only- `repmgr` - Replication manager

- Blacklisted functions (`nextval`, `setval`) → Always Primary

📖 **Full guide:** See [`railway-config/RAILWAY_DEPLOYMENT.md`](railway-config/RAILWAY_DEPLOYMENT.md)- `app_readwrite` - Application user (read/write)

**Session Behavior:**

- Once a write occurs in a session, all subsequent queries go to Primary- `app_readonly` - Application user (read-only)

- `disable_load_balance_on_write = 'always'` ensures no data inconsistency

**Summary:**- `pgpool` - PgPool monitoring

---

1. Create new Railway project

## 🔧 Configuration

2. Set shared variables (4 passwords + optional configs)**Security features:**

### Environment Variables

3. Create 5 services: `pg-1`, `pg-2`, `pg-3`, `pg-4`, `witness`- ✅ SCRAM-SHA-256 authentication

#### Shared Variables (Set once, used by all services)

4. Add volume to each service: `/var/lib/postgresql/data`- ✅ Passwords never in Git (.env in .gitignore)

| Variable | Required | Default | Description |

|----------|----------|---------|-------------|5. Set service-specific variables (NODE_NAME, NODE_ID, etc.)- ✅ TLS-ready (configure in pgpool.conf)

| `POSTGRES_PASSWORD` | ✅ | - | Superuser password (SCRAM) |

| `REPMGR_PASSWORD` | ✅ | - | Repmgr user password (SCRAM) |6. Deploy sequentially- ✅ Network isolation via Docker networks

| `APP_READONLY_PASSWORD` | ✅ | - | Read-only app user password |

| `APP_READWRITE_PASSWORD` | ✅ | - | Read-write app user password |

| `PCP_PASSWORD` | ✅ | - | PgPool admin (PCP) password |

------

#### Per-Service Variables (Auto-configured via railway-services.json)



**PostgreSQL Nodes:**

- `NODE_NAME` - Service name (pg-1, pg-2, etc.)## 📋 Variables Configuration## 🧪 Test Scenarios

- `REPMGR_NODE_ID` - Unique ID (1-4, 100 for witness)

- `NODE_PRIORITY` - Failover priority (100=highest)

- `PEERS` - Comma-separated list of all nodes

- `PRIMARY_HOST` - Initial primary hostname### Minimal Required Variables### 1. Test Automatic Failover

- `REPMGR_PROMOTE_MAX_LAG_SECS` - Max lag for promotion (default: 10s)

```bash

**PgPool Nodes:**

- `PGPOOL_NODE_ID` - PgPool instance ID (0 or 1)**Project-level (Shared) - Set once:**# Kill primary

- `PGPOOL_HOSTNAME` - This PgPool's hostname

- `PG_BACKENDS` - Comma-separated PostgreSQL backends```bashdocker stop pg-1

- `OTHER_PGPOOL_HOSTNAME` - Peer PgPool for watchdog

- `EXPORT_PLAINTEXT_POOLPWD` - Set to `false` for securityPOSTGRES_PASSWORD=<your-strong-password>



### Advanced TuningREPMGR_PASSWORD=<your-repmgr-password># Watch promotion (15-30s)



Edit `pgpool/pgpool.conf` for:APP_READONLY_PASSWORD=<your-readonly-password>watch -n 1 'docker exec pg-2 gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show'

- `num_init_children` - Max concurrent connections (default: 100)

- `max_pool` - Connections per backend per process (default: 20)APP_READWRITE_PASSWORD=<your-readwrite-password>

- `sr_check_period` - Streaming replication check interval (default: 10s)

- `health_check_period` - Backend health check interval (default: 30s)```# Restart old primary (auto-rejoin as standby)



Edit `entrypoint.sh` for:docker start pg-1

- `REPMGR_PROMOTE_MAX_LAG_SECS` - Max acceptable lag for promotion

- Checkpoint/tuning parameters**Per Service (example for pg-1):**```



---```bash



## 🧪 Testing FailoverNODE_NAME=pg-1**Expected:** pg-2 becomes primary, pg-1 rejoins as standby



### Scenario 1: Primary Node FailureNODE_ID=1



```bashPRIMARY_HINT=pg-1.railway.internal### 2. Test Full Cluster Recovery

# Simulate primary crash

railway run --service pg-1 -- pkill -9 postgresIS_WITNESS=false```bash



# Watch automatic promotion (should complete in ~30s)PEERS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432,witness.railway.internal:5432# Kill all nodes

railway run --service pg-2 -- gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

```docker-compose down

# PgPool automatically detects new primary

railway run --service pgpool-1 -- pcp_node_info -h localhost -p 9898 -U admin -w

```

📖 **Full variables guide:** See [`railway-config/VARIABLES.md`](railway-config/VARIABLES.md)# Restart (auto-bootstrap from last-known-primary)

**Expected Behavior:**

1. Witness + standbys detect pg-1 downdocker-compose up -d

2. pg-2 (highest priority standby) auto-promotes to primary

3. pg-3, pg-4 follow new primary (pg-2)**Total: ~30 variables** (vs 100+ in Docker Compose)

4. PgPool detects primary change, routes writes to pg-2

5. When pg-1 recovers, it uses `pg_rewind` to rejoin as standby# Check status (wait ~60s)



### Scenario 2: Standby Node Failure---docker exec pg-2 gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show



```bash```

# Simulate standby crash

railway run --service pg-3 -- pkill -9 postgres## 🔌 Connecting to Database



# PgPool marks backend down, continues serving from remaining standbys**Expected:** Last primary (pg-2) bootstraps, others follow

railway run --service pgpool-1 -- pcp_node_info -h localhost -p 9898 -U admin -w

### Internal (from other Railway services in same project)

# When pg-3 recovers, it auto-rejoins

railway logs --service pg-3### 3. Test Direct Queries

```

**Using Reference Variables:**```bash

### Scenario 3: PgPool Failover

```bash# Run a few SELECT queries directly against the primary

```bash

# Stop pgpool-1# In your app service, set:for i in {1..5}; do

railway run --service pgpool-1 -- pkill -9 pgpool

DATABASE_URL=postgresql://app_readwrite:${{shared.APP_READWRITE_PASSWORD}}@pg-1.railway.internal:5432/postgres  PGPASSWORD=<password> psql -h localhost -p 5401 -U app_readwrite -d postgres -c "SELECT inet_server_addr();"

# Clients automatically reconnect to pgpool-2

# Watchdog promotes pgpool-2 to active (if watchdog enabled)done

```

# Or for read-only:```

---

DATABASE_READONLY_URL=postgresql://app_readonly:${{shared.APP_READONLY_PASSWORD}}@pg-2.railway.internal:5432/postgres

## 📈 Monitoring & Operations

```**Expected:** Responses from the primary node

### Check Cluster Status



```bash

# Repmgr cluster view**Direct connection string:**---

railway run --service pg-1 -- gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show --compact

```

# PgPool backend status

railway run --service pgpool-1 -- pcp_node_info -h localhost -p 9898 -U admin -wpostgresql://postgres:<password>@pg-1.railway.internal:5432/postgres## � Monitoring



# PgPool process pool```

railway run --service pgpool-1 -- pcp_proc_info -h localhost -p 9898 -U admin -w

```### View Cluster Status



### Check Replication Lag### External (from internet)```bash



```bash# Repmgr cluster view

# On primary

railway run --service pg-1 -- gosu postgres psql -c "SELECT application_name, state, sync_state, replay_lag FROM pg_stat_replication;"1. **Enable TCP Proxy** on `pg-1` service (Settings → Networking)docker exec pg-1 gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show



# Via PgPool2. Get proxy details:

railway run --service pgpool-1 -- psql -h localhost -U repmgr -d postgres -c "SELECT application_name, state, replay_lag FROM pg_stat_replication;"

```   ```bash# Individual node logs



### Manual Failover (if needed)   railway variables --service pg-1 | grep TCPdocker logs -f pg-1



```bash   ``````

# Promote specific standby manually

railway run --service pg-2 -- gosu postgres repmgr standby promote -f /etc/repmgr/repmgr.conf --force3. Connect to:```



# Force other standbys to follow new primary   ```

railway run --service pg-3 -- gosu postgres repmgr standby follow -f /etc/repmgr/repmgr.conf --upstream-node-id=2

```   postgresql://postgres:<password>@<RAILWAY_TCP_PROXY_DOMAIN>:<RAILWAY_TCP_PROXY_PORT>/postgres### Grafana Dashboards



### PCP Commands (PgPool Control)   ``````bash



```bash# Start monitoring stack

# Attach/detach backend node

railway run --service pgpool-1 -- pcp_detach_node -h localhost -p 9898 -U admin -w -n 0  # Detach backend 0 (pg-1)⚠️ **Note:** TCP Proxy incurs Network Egress charges. Use private networking when possible.cd monitoring && ./start.sh

railway run --service pgpool-1 -- pcp_attach_node -h localhost -p 9898 -U admin -w -n 0  # Re-attach backend 0



# Stop/reload pgpool

railway run --service pgpool-1 -- pcp_stop_pgpool -h localhost -p 9898 -U admin -w---# Access Grafana

railway run --service pgpool-1 -- pcp_reload_config -h localhost -p 9898 -U admin -w

```http://localhost:3001



---## 🧪 Testing & Verification# Login: admin/admin (change on first login)



## 🛡️ Security Hardening```



### Current Security Posture### Check Cluster Status



✅ **Implemented:****Dashboards included:**

- SCRAM-SHA-256 authentication enforced

- `pg_hba.conf` restricts local admin to `peer` auth```bash- PostgreSQL Performance

- No plaintext passwords in `pool_passwd` (SCRAM hashes only)

- Railway private networking (services isolated from internet)# Via Railway CLI- Replication Lag

- Data checksums enabled (detects corruption)

railway run --service pg-1 \- PgPool Metrics

⚠️ **Recommended Improvements:**

  psql -U repmgr -d repmgr -c "SELECT * FROM repmgr.show_nodes();"- Node Health

1. **Restrict `pool_hba.conf`** (PgPool)

   ```conf```

   # Current (too open):

   host all all 0.0.0.0/0 scram-sha-256---



   # Recommended:**Expected output:**

   host all all 172.18.0.0/16 scram-sha-256  # Railway internal network only

   ``````## 🛠️ Common Operations



2. **Create dedicated health-check user** node_id | node_name | active | upstream_node_name | priority

   ```sql

   -- Instead of using 'repmgr' for health checks, create minimal-privilege user:---------+-----------+--------+--------------------+----------### Add a New Standby Node

   CREATE USER pgpool_check WITH PASSWORD 'secure_password';

   GRANT CONNECT ON DATABASE postgres TO pgpool_check;       1 | pg-1      | t      | -                  |      199```bash

   GRANT pg_monitor TO pgpool_check;

   ```       2 | pg-2      | t      | pg-1               |      198# See docs/SCALING_GUIDE.md



3. **Use Railway Secrets** (already recommended above)       3 | pg-3      | t      | pg-1               |      197./scripts/add-node.sh pg-5 195

   - Never commit passwords to git

   - Rotate secrets periodically via Railway dashboard       4 | pg-4      | t      | pg-1               |      196```



4. **Enable SSL/TLS** (future work)      99 | witness   | t      | pg-1               |       99

   - Generate certs via Let's Encrypt

   - Configure `ssl = on` in `postgresql.conf````### Manual Switchover (No Downtime)

   - Update `pg_hba.conf` to require `hostssl`

```bash

---

### Test Failover# Promote pg-2 to primary (pg-1 becomes standby)

## 📚 Architecture Deep Dive

docker exec pg-2 gosu postgres repmgr standby switchover -f /etc/repmgr/repmgr.conf

### Failover Decision Flow

**1. Stop Standby (pg-4):**```

```

┌──────────────────────────────────────────────────────────────┐```bash

│ Primary Failure Detected                                     │

│ (repmgrd monitors via health checks)                         │# Via Railway dashboard: Stop pg-4 service### Backup & Restore

└───────────────────────────┬──────────────────────────────────┘

                            │# Cluster continues normally```bash

                            ▼

┌──────────────────────────────────────────────────────────────┐# Restart pg-4 → auto-rejoins# Backup (from primary)

│ Witness + Standbys Vote                                      │

│ (requires majority quorum)                                   │```docker exec pg-1 gosu postgres pg_basebackup -D /backup -Ft -z -P

└───────────────────────────┬──────────────────────────────────┘

                            │

                            ▼

┌──────────────────────────────────────────────────────────────┐**2. Stop Primary (pg-1) - Automatic Promotion:**# Restore

│ Promotion Guard Executes                                     │

│ (/usr/local/bin/promote_guard.sh)                            │```bash# See docs/DEPLOYMENT.md for PITR setup

│                                                               │

│ 1. Query pg_stat_replication on all standbys                 │# Via Railway dashboard: Stop pg-1 service```

│ 2. Calculate replay lag (pg_last_xact_replay_timestamp)      │

│ 3. Check if candidate lag < REPMGR_PROMOTE_MAX_LAG_SECS      │# Wait ~30 seconds

│ 4. If acceptable: ALLOW promotion                            │

│ 5. If too lagged but highest priority: ALLOW (avoid lockout) │# Check logs: pg-2 or pg-3 will be promoted to primary---

│ 6. If force file exists: ALLOW (manual override)             │

└───────────────────────────┬──────────────────────────────────┘# Restart pg-1 → auto-rejoins as standby via pg_rewind

                            │

                            ▼```## 📁 Project Structure

┌──────────────────────────────────────────────────────────────┐

│ Standby Promotes to Primary                                  │

│ (repmgr standby promote)                                     │

└───────────────────────────┬──────────────────────────────────┘### View Logs```

                            │

                            ▼pg_ha_cluster_production/

┌──────────────────────────────────────────────────────────────┐

│ Other Standbys Auto-Follow New Primary                       │```bash├── docker-compose.yml          # Main orchestration

│ (repmgr standby follow)                                      │

└───────────────────────────┬──────────────────────────────────┘# All services├── .env                        # Passwords (generated, not in Git)

                            │

                            ▼railway logs├── entrypoint.sh               # Core cluster logic (shared by all nodes)

┌──────────────────────────────────────────────────────────────┐

│ PgPool Detects Primary Change                                │├── monitor.sh                  # Health monitoring & last-known-primary tracking

│ (sr_check_period health checks)                              │

│                                                               │# Specific service│

│ - Marks old primary as down                                  │

│ - Marks new primary, updates backend status                  │railway logs --service pg-1├── pg-1/, pg-2/, pg-3/, pg-4/  # Node-specific configs

│ - Routes writes to new primary                               │

└──────────────────────────────────────────────────────────────┘```│   ├── Dockerfile              # PostgreSQL + repmgr

```

│   ├── entrypoint.sh           # Symlink to root entrypoint.sh

### PgPool Query Routing Logic

### Check Repmgr Events│   └── monitor.sh              # Symlink to root monitor.sh

```python

# Pseudo-code for PgPool decision tree│



if query.is_write() or query.uses_blacklisted_function():```bash├── (pgpool/)                   # PgPool configuration is omitted in this branch

    route_to(PRIMARY)

elif session.has_written_in_this_session():railway run --service pg-1 \│   ├── pgpool.conf             # Load balancing, health check (not included)

    route_to(PRIMARY)  # disable_load_balance_on_write = 'always'

elif query.is_read():  psql -U repmgr -d repmgr -c \│   ├── pool_hba.conf           # Authentication (not included)

    candidate_standbys = [s for s in standbys if s.is_healthy()]

    if backend_weight[PRIMARY] > 0:  "SELECT event_timestamp, node_name, event, successful │   └── entrypoint.sh           # Dynamic primary discovery (not included)

        candidate_standbys.append(PRIMARY)

    route_to(random_weighted_choice(candidate_standbys))   FROM repmgr.events │

else:

    route_to(PRIMARY)  # Default fallback   ORDER BY event_timestamp DESC ├── witness/                    # Quorum node (no data)

```

   LIMIT 20;"│

---

```├── scripts/                    # Helper scripts

## 🔄 Update & Maintenance

│   ├── generate-passwords.sh  # Auto-generate .env

### Update PostgreSQL Version

---│   ├── show-credentials.sh    # Display all connection info

1. Edit `Dockerfile`, change `FROM postgres:17-alpine` → `FROM postgres:18-alpine`

2. Redeploy services via Railway dashboard (rebuild)│   └── test_full_flow.sh      # Automated failover tests

3. Follow PostgreSQL major upgrade docs if crossing major versions

## 📊 Monitoring & Maintenance│

### Scale Standbys

├── monitoring/                 # Grafana, Prometheus, Loki, Tempo

To add `pg-5`:

### Health Checks│   └── config/                 # Pre-configured dashboards

1. Add service in Railway dashboard

2. Set environment variables:│

   ```

   NODE_NAME=pg-5```sql└── docs/                       # Detailed documentation

   REPMGR_NODE_ID=5

   NODE_PRIORITY=60-- Check replication lag    ├── COMPLETE_DOCUMENTATION.md   # Full technical details

   PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal,pg-5.railway.internal

   PRIMARY_HOST=pg-1.railway.internalSELECT     ├── DEPLOYMENT.md               # Production deployment guide

   ```

3. Update `PG_BACKENDS` in `pgpool-1` and `pgpool-2`:  client_addr,    ├── PGPOOL_DEPLOYMENT.md        # PgPool tuning

   ```

   PG_BACKENDS=pg-1.railway.internal:5432,...,pg-5.railway.internal:5432  state,    └── SCALING_GUIDE.md            # Add/remove nodes

   ```

4. Restart PgPool services to pick up new backend  sync_state,```



### Backup Strategy  pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS send_lag,



**Recommended: Railway Volume Snapshots**  pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag---

```bash

# Via Railway CLI (if available)FROM pg_stat_replication;

railway volumes snapshot create --service pg-1

## ⚠️ Production Checklist

# Or use pg_dump for logical backups

railway run --service pg-1 -- pg_dump -U postgres postgres > backup.sql-- Check cluster status

```

SELECT * FROM repmgr.show_nodes();Before deploying to production:

**Continuous Archiving (Advanced):**

- Configure WAL archiving to S3/GCS

- Edit `postgresql.conf`: `archive_mode = on`, `archive_command = 'aws s3 cp ...'`

-- View recent failover events- [ ] Run `./scripts/generate-passwords.sh` with secure random passwords

---

SELECT * FROM repmgr.events WHERE event = 'standby_promote' ORDER BY event_timestamp DESC LIMIT 5;- [ ] Change Grafana admin password

## 🐛 Troubleshooting

```- [ ] Configure TLS/SSL in pgpool.conf

### Cluster won't start

- [ ] Set up automated backups (pg_basebackup + WAL archiving)

**Symptom:** All nodes show "waiting for primary..."

### Backups- [ ] Configure firewall rules (close direct node ports, expose only PgPool)

**Solution:**

```bash- [ ] Set resource limits in docker-compose.yml

# Check if pg-1 actually initialized

railway logs --service pg-1**Option 1: Railway Volume Snapshots**- [ ] Enable connection limits per user



# If pg-1 failed to initialize, manually bootstrap:- Go to service → Volume → Snapshots- [ ] Configure log rotation

railway run --service pg-1 -- /bin/bash

# Inside container:- Create manual snapshot or enable scheduled backups- [ ] Set up alerting (Prometheus Alertmanager)

rm -rf /var/lib/postgresql/data/*

/usr/local/bin/entrypoint.sh- [ ] Test full disaster recovery procedure

```

**Option 2: pg_dump (via TCP Proxy)**- [ ] Document runbooks for your team

### Standby stuck in "cloning" state

```bash

**Symptom:** `railway logs --service pg-2` shows endless pg_basebackup attempts

# Enable TCP proxy on pg-1See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for details.

**Cause:** Primary not accepting replication connections

# Get connection details

**Solution:**

```bashrailway variables --service pg-1---

# Check primary pg_hba.conf allows replication

railway run --service pg-1 -- cat /var/lib/postgresql/data/pg_hba.conf | grep replication



# Ensure repmgr user exists on primary# Backup## �� Troubleshooting

railway run --service pg-1 -- gosu postgres psql -c "SELECT rolname FROM pg_roles WHERE rolname='repmgr';"

```PGPASSWORD=<password> pg_dump \



### PgPool shows "backend down" for healthy node  -h <RAILWAY_TCP_PROXY_DOMAIN> \### Node won't rejoin cluster



**Symptom:** `pcp_node_info` shows status "down" even though PostgreSQL is running  -p <RAILWAY_TCP_PROXY_PORT> \```bash



**Cause:** Authentication failure or network issue  -U postgres \# Check repmgr logs



**Solution:**  -Fc \docker logs pg-2 | grep repmgr

```bash

# Test backend connection from pgpool container  -f backup-$(date +%Y%m%d).dump \

railway run --service pgpool-1 -- psql -h pg-1.railway.internal -U repmgr -d postgres -c "SELECT 1"

  postgres# Manual rejoin with pg_rewind

# Check pgpool logs for errors

railway logs --service pgpool-1 | grep ERROR```docker exec -it pg-2 bash



# Verify pool_passwd contains correct SCRAM hashgosu postgres repmgr node rejoin -f /etc/repmgr/repmgr.conf --force-rewind

railway run --service pgpool-1 -- cat /etc/pgpool-II/pool_passwd

```### Metrics```



### Replication lag too high



**Symptom:** Promotion guard prevents failover due to lagRailway provides built-in metrics:*(PgPool troubleshooting omitted in this branch.)*



**Solution:**- CPU usage

```bash

# Check WAL sender/receiver status- Memory usage### Replication lag too high

railway run --service pg-1 -- gosu postgres psql -c "SELECT * FROM pg_stat_replication;"

- Network I/O```bash

# Increase lag threshold (if acceptable)

railway variables set REPMGR_PROMOTE_MAX_LAG_SECS=30- Disk usage# Check lag (bytes)



# Or manually force promotion (bypass guard)docker exec pg-1 psql -U postgres -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, sync_state FROM pg_stat_replication;"

railway run --service pg-2 -- touch /tmp/force_promote_override

railway run --service pg-2 -- gosu postgres repmgr standby promote -f /etc/repmgr/repmgr.confAccess via Railway dashboard → Service → Metrics

```

# Check PgPool delay threshold (default: 10MB)

---

---docker exec pgpool-1 grep delay_threshold /etc/pgpool-II/pgpool.conf

## 📖 Additional Resources

```

- [PostgreSQL 17 Documentation](https://www.postgresql.org/docs/17/)

- [Repmgr Documentation](https://repmgr.org/docs/current/)## 🔧 Troubleshooting

- [PgPool-II Documentation](https://www.pgpool.net/docs/latest/en/html/)

- [Railway Documentation](https://docs.railway.app)See [docs/COMPLETE_DOCUMENTATION.md](docs/COMPLETE_DOCUMENTATION.md) Section 9 for more.

- [Railway Private Networking](https://docs.railway.app/guides/private-networking)

### Service Won't Start

---

---

## 🤝 Contributing

**Check logs:**

Contributions welcome! Please:

```bash## 📖 Documentation

1. Fork this repo

2. Create a feature branch (`git checkout -b feature/amazing-feature`)railway logs --service pg-1

3. Test changes on Railway staging environment

4. Submit PR with detailed description```| File | Purpose |



---|------|---------|



## 📝 License**Common issues:**| [QUICK_START.md](QUICK_START.md) | 5-minute deployment walkthrough |



MIT License - See [LICENSE](LICENSE) file- ❌ Shared variables not set → Set passwords in project variables| [COMPLETE_DOCUMENTATION.md](COMPLETE_DOCUMENTATION.md) | Full technical reference (algorithms, failover logic, recovery) |



---- ❌ Volume not attached → Add volume with mount path `/var/lib/postgresql/data`| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Production deployment (Docker Swarm, K8s, bare metal) |



## 🙏 Acknowledgments- ❌ Missing NODE_NAME/NODE_ID → Set service variables| [docs/PGPOOL_DEPLOYMENT.md](docs/PGPOOL_DEPLOYMENT.md) | PgPool-II tuning and configuration |



Built with:| [docs/SCALING_GUIDE.md](docs/SCALING_GUIDE.md) | Add/remove nodes dynamically |

- [PostgreSQL](https://www.postgresql.org/) - World's most advanced open source database

- [Repmgr](https://repmgr.org/) - Replication manager for PostgreSQL### Cannot Connect Between Nodes| [docs/SECURITY.md](docs/SECURITY.md) | Security hardening guide |

- [PgPool-II](https://www.pgpool.net/) - Connection pooling and load balancing

- [Railway](https://railway.app) - Infrastructure platform



---**Verify:**---



**Questions? Issues?** Open a GitHub issue or contact [@hiendt2907](https://github.com/hiendt2907)1. All services in same Railway project/environment


2. PEERS variable uses correct DNS: `<service>.railway.internal`## 🔗 Technology References

3. PostgreSQL listening on IPv6 (auto-configured in entrypoint)

- [PostgreSQL 17 Documentation](https://www.postgresql.org/docs/17/)

**Test connectivity:**- [Repmgr Documentation](https://repmgr.org/docs/current/)

```bash- [PgPool-II Documentation](https://www.pgpool.net/docs/latest/en/html/)

railway run --service pg-2 \

  pg_isready -h pg-1.railway.internal -p 5432---

```

## 📝 Key Algorithms

### Promotion Not Happening

### 1. Password Escaping (Special Characters Support)

**Check:**- `.pgpass`: Uses `printf` (not heredoc) to preserve `\` and escape `:`

1. Repmgrd running on standbys:- `repmgr.conf`: Simple quotes `'password'` for SCRAM-SHA-256

   ```bash

   railway run --service pg-2 ps aux | grep repmgrd### 2. Primary Discovery (PgPool)

   ```- Queries `SELECT pg_is_in_recovery()` on all nodes

2. Replication lag not too high:- Finds node returning `false` → Sets as primary

   ```sql- 60 retries × 5s = 5min max wait

   SELECT pg_last_xact_replay_timestamp();

   ```### 3. Full Cluster Recovery

3. Quorum available (witness + at least 1 standby online)- Each node checks `/var/lib/postgresql/last_known_primary`

- Last-known-primary waits 30s, then bootstraps if others not ready

**Force manual promotion:**- Other nodes wait for primary, then clone/rejoin

```bash

railway run --service pg-2 \### 4. Last-Known-Primary Tracking

  gosu postgres repmgr standby promote -f /etc/repmgr/repmgr.conf- `monitor.sh` queries primary every 30s

```- Atomic write: `printf > tmp → mv → sync`

- Read: `tail -n 1` (handles multi-line corruption)

### Split Brain Prevention

See [COMPLETE_DOCUMENTATION.md](COMPLETE_DOCUMENTATION.md) for detailed algorithms.

Cluster uses:

- Witness node for quorum---

- Last-known-primary file tracking

- Promotion guard checking lag before promote## ✅ Tested Scenarios

- Automatic pg_rewind on rejoin

- ✅ Primary failover (pg-1 down → pg-2 promoted) - **15-30s**

If split-brain suspected:- ✅ Old primary rejoin (pg-1 rejoins as standby) - **Automatic**

```bash- ✅ Full cluster outage + recovery - **60-90s**

# Check which node is primary- ✅ Manual switchover (zero downtime)

for service in pg-1 pg-2 pg-3 pg-4; do- ✅ PgPool failover (pgpool-1 down → pgpool-2 active)

  echo "=== $service ==="- ✅ Network partition recovery

  railway run --service $service \- ✅ Special character passwords (`:;#*!` etc.)

    psql -U postgres -tAc "SELECT NOT pg_is_in_recovery();"- ✅ Timeline divergence handling (pg_rewind)

done

```---



Only ONE should return `t` (true).**Status**: ✅ Production Ready

**Version**: 2.0.0

---**PostgreSQL**: 17.6

**Repmgr**: 5.x

## 💰 Cost Optimization

### Reduce Costs

1. **Use Private Networking** (free)
   - All inter-service communication via `*.railway.internal`
   - No egress charges for replication

2. **Disable TCP Proxy** when not needed
   - Only enable on primary for external access
   - Use Railway's internal DNS for app connections

3. **Right-size Volumes**
   - Data nodes: Start with 10GB, grow as needed
   - Witness: 1-2GB sufficient

4. **Scale Down Non-Prod**
   - Use separate environments for staging/dev
   - Stop services when not in use

5. **Monitor Usage**
   - Railway dashboard → Project → Usage
   - Set up budget alerts

### Estimated Monthly Cost

Based on Railway's pricing (as of 2025):

**Minimal setup (5 services):**
- Compute: ~$5-10/month (execution time)
- Volumes: ~$0.25/GB/month
  - 4 × 10GB data volumes = $10/month
  - 1 × 2GB witness volume = $0.50/month
- Network: Private = free, TCP proxy egress = variable

**Total: ~$15-25/month** for development
**Production: $50-100/month** (depending on usage)

---

## 📚 Additional Documentation

- **[Railway Deployment Guide](railway-config/RAILWAY_DEPLOYMENT.md)** - Complete step-by-step
- **[Variables Reference](railway-config/VARIABLES.md)** - All environment variables
- **[Docker Compose Guide](README.docker-compose.md)** - Local development setup

### Reference Links

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Repmgr Documentation](https://www.repmgr.org/docs/current/)
- [Railway Documentation](https://docs.railway.app/)
- [Railway Private Networking](https://docs.railway.app/guides/private-networking)

---

## 🤝 Contributing

Issues and PRs welcome! Please:
1. Test changes locally first
2. Update documentation
3. Follow existing code style

---

## 📝 License

MIT License - see [LICENSE](LICENSE) file

---

## 🆘 Support

- **Issues:** [GitHub Issues](https://github.com/hiendt2907/pg-ha-repo/issues)
- **Railway Support:** [Railway Discord](https://discord.gg/railway)
- **PostgreSQL:** [PostgreSQL Mailing Lists](https://www.postgresql.org/list/)

---

## ⚠️ Production Checklist

Before going to production:

- [ ] Set strong passwords (24+ chars, random)
- [ ] Enable Railway volume backups
- [ ] Set up monitoring/alerting
- [ ] Test failover scenarios
- [ ] Document connection strings for your team
- [ ] Configure Railway environments (staging/production)
- [ ] Set up SSL certificates (if using TCP proxy)
- [ ] Review Railway pricing and set budget alerts
- [ ] Enable Railway's IP allowlist (if needed)
- [ ] Test backup/restore procedures

---

**Built with ❤️ for Railway**

*Note: This is an unmanaged database service. You are responsible for maintenance, backups, and security. For managed PostgreSQL, consider Railway's database service or dedicated providers.*
