# PostgreSQL High Availability Cluster

Production-ready PostgreSQL HA cluster with automatic failover, connection pooling, and load balancing.

## Architecture

```
Client Application
       ↓
   HAProxy (Single Endpoint)
       ↓
   ┌───────────────┐
   ↓               ↓
PgPool-1      PgPool-2
(LB/Splitting) (LB/Splitting)
   ↓               ↓
   └───────┬───────┘
           ↓
   ┌───────┴───────┬───────┬───────┐
   ↓       ↓       ↓       ↓       ↓
  PG-1    PG-2    PG-3    PG-4  Witness
(Primary)(Standby)(Standby)(Standby)(Quorum)
```

## Components

### 1. HAProxy Layer
- **Purpose**: Single client endpoint, load balancing to PgPool instances
- **Features**:
  - TCP mode for PostgreSQL protocol passthrough
  - Leastconn balancing algorithm
  - Health checks with PostgreSQL SSL handshake probe
  - Stats page on port 8404
- **Resources**: 8 vCPU / 4 GB RAM

### 2. PgPool-II Layer (2 instances)
- **Purpose**: Connection pooling, read/write splitting, query caching
- **Features**:
  - 500 child processes per instance (1000 total)
  - 10 backend connections per child = 5,000 backend connections per PgPool
  - 4GB memory cache per instance (8GB total)
  - Automatic failover detection via repmgr integration
- **Resources**: 16 vCPU / 32 GB RAM each

### 3. PostgreSQL Layer (4 data nodes + 1 witness)
- **Purpose**: Data storage with streaming replication
- **Features**:
  - Repmgr automatic failover (<10s SLA)
  - Synchronous replication with remote_write
  - 8GB shared_buffers, 32 parallel workers
  - Aggressive autovacuum (8 workers, 10s interval)
  - Promote guard with fencing and race condition prevention
- **Resources**: 32 vCPU / 32 GB RAM / 100 GB disk each

## Directory Structure

```
postgresql-cluster/
├── postgresql/          # PostgreSQL + Repmgr
│   ├── Dockerfile
│   └── entrypoint.sh
├── pgpool/             # PgPool-II connection pooling
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── pgpool.conf
│   ├── pool_hba.conf
│   └── pcp.conf
├── haproxy/            # HAProxy load balancer
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── haproxy.cfg
├── scripts/            # Utility scripts
│   ├── promote_guard.sh
│   └── monitor.sh
├── railway-config/     # Railway deployment
│   ├── railway-services.json
│   ├── deploy-railway.sh
│   ├── RAILWAY_DEPLOYMENT.md
│   └── VARIABLES.md
├── docs/               # Documentation
│   ├── README.md (this file at root also)
│   ├── RAILWAY_QUICK_REFERENCE.md
│   ├── RAILWAY_MIGRATION_SUMMARY.md
│   └── CHANGELOG.md
├── docker-compose.yml  # Local development
├── railway.toml        # Railway configuration
├── .env.example        # Environment variables template
└── .gitignore
```

## Quick Start

### Railway Deployment

1. **Set up Railway project**:
```bash
cd postgresql-cluster/railway-config
chmod +x deploy-railway.sh
./deploy-railway.sh
```

2. **Configure secrets** in Railway dashboard:
- `POSTGRES_PASSWORD`: PostgreSQL superuser password
- `REPMGR_PASSWORD`: Repmgr user password
- `APP_READONLY_PASSWORD`: Application read-only user password
- `APP_READWRITE_PASSWORD`: Application read-write user password
- `PCP_PASSWORD`: PgPool PCP admin password
- `HAPROXY_STATS_PASSWORD`: HAProxy stats page password

3. **Deploy services in order**:
   1. pg-1 (primary) → wait until healthy
   2. pg-2, pg-3, pg-4 (standbys) → wait until all healthy
   3. witness
   4. pgpool-1, pgpool-2 → wait until healthy
   5. haproxy → generates public domain

4. **Connect to cluster**:
```bash
# Application connection (via HAProxy)
postgresql://app_readwrite:PASSWORD@haproxy-production.railway.app:5432/postgres

# Read-only connection
postgresql://app_readonly:PASSWORD@haproxy-production.railway.app:5432/postgres

# HAProxy stats
http://haproxy-production.railway.app:8404
# Login: admin / HAPROXY_STATS_PASSWORD
```

### Local Development (Docker Compose)

1. **Set up environment**:
```bash
cp .env.example .env
# Edit .env with your passwords
```

2. **Start cluster**:
```bash
docker-compose up -d
```

3. **Verify cluster status**:
```bash
# Check repmgr cluster
docker exec -it pg-1 repmgr cluster show

# Check PgPool status
docker exec -it pgpool-1 pcp_node_count -h localhost -p 9898 -U admin -w

# Check HAProxy stats
curl http://localhost:8404
```

## Performance Specifications

### Capacity
- **Total concurrent connections**: ~40,000 (via HAProxy)
- **Backend connections**: 20,000 per PgPool instance
- **Query cache**: 8GB total (4GB per PgPool)
- **PostgreSQL max connections**: 1,000 per node

### Failover SLA
- **Detection time**: 6s (2s interval × 3 retries)
- **Promotion time**: <2s (promote_guard with fencing)
- **Client reconnect**: <2s
- **Total failover time**: <10s

### Resource Allocation (Railway)
- **HAProxy**: 8 vCPU / 4 GB RAM
- **PgPool (×2)**: 16 vCPU / 32 GB RAM each
- **PostgreSQL (×4)**: 32 vCPU / 32 GB RAM / 100 GB disk each
- **Witness**: 2 vCPU / 2 GB RAM / 10 GB disk
- **Total**: 210 vCPU / 196 GB RAM / 410 GB disk

## Key Features

### Data Integrity
- ✅ Synchronous replication with `remote_write`
- ✅ Witness node for quorum-based failover
- ✅ Promote guard with distributed lock (prevents split-brain)
- ✅ Replication lag check (max 5s lag before promotion)
- ✅ WAL compression and 10GB WAL retention

### High Availability
- ✅ Automatic failover <10s
- ✅ Race condition prevention via fencing
- ✅ Split-brain detection
- ✅ PgPool health checks with backend status monitoring
- ✅ HAProxy health checks with PostgreSQL handshake probe

### Performance
- ✅ Connection pooling (500 children per PgPool)
- ✅ Query result caching (4GB per PgPool)
- ✅ Read/write splitting
- ✅ Parallel query execution (32 workers)
- ✅ Optimized shared_buffers (8GB = 25% RAM)

### Security
- ✅ SSL/TLS support
- ✅ Role-based access (readonly/readwrite users)
- ✅ PCP authentication for PgPool control
- ✅ HAProxy stats authentication
- ✅ Network isolation via Railway private networking

## Monitoring & Operations

### Health Checks
```bash
# Cluster topology
repmgr cluster show

# PgPool backend status
pcp_node_info -h localhost -p 9898 -U admin -w

# HAProxy backend status
curl http://localhost:8404/stats

# PostgreSQL replication lag
psql -U postgres -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"
```

### Manual Failover
```bash
# Promote specific standby
docker exec -it pg-2 repmgr standby promote

# Rejoin old primary as standby
docker exec -it pg-1 repmgr node rejoin -d 'host=pg-2 user=repmgr dbname=repmgr'
```

### Scaling Operations
- **Add read replica**: Deploy new PostgreSQL node with `repmgr standby clone`
- **Scale PgPool**: Add more PgPool instances, update HAProxy backends
- **Increase resources**: Adjust vCPU/RAM in `railway-services.json`

## Troubleshooting

See [RAILWAY_QUICK_REFERENCE.md](docs/RAILWAY_QUICK_REFERENCE.md) for common issues and solutions.

## Documentation

- [Railway Deployment Guide](railway-config/RAILWAY_DEPLOYMENT.md)
- [Railway Quick Reference](docs/RAILWAY_QUICK_REFERENCE.md)
- [Migration Summary](docs/RAILWAY_MIGRATION_SUMMARY.md)
- [Changelog](docs/CHANGELOG.md)
- [Environment Variables](railway-config/VARIABLES.md)

## License

MIT License - See repository root for details.

## Support

For issues and questions:
- GitHub Issues: [pg-ha-repo](https://github.com/hiendt2907/pg-ha-repo)
- Documentation: See `docs/` directory
