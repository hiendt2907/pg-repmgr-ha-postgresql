# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2025-01-09 - Railway Migration + PgPool Integration

### 🚀 Major Changes

**Railway Platform Migration**
- Completely refactored for Railway.app deployment
- Removed Docker Compose in favor of Railway's native service model
- Implemented Railway private networking (`*.railway.internal`)
- Added Railway volume configuration for persistent storage
- Reduced environment variables from ~50 to **5 shared secrets**

**PgPool-II Integration**
- Added 2 PgPool-II nodes for connection pooling and load balancing
- Implemented smart query routing (writes→primary, reads→standbys)
- Added SCRAM-SHA-256 password hashing for `pool_passwd`
- Configured health checks and streaming replication monitoring
- Added PCP protocol support for runtime management
- Watchdog HA support (optional, disabled by default for Railway)

### ✨ Added

**New Components**
- `pgpool-1` and `pgpool-2` services (Debian-based, pgpool2 package)
- `/pgpool/` directory with Dockerfile, entrypoint, configs
- `railway-config/railway-services.json` - Complete Railway service definitions
- `RAILWAY_DEPLOYMENT.md` - Step-by-step deployment guide

**New Features**
- Connection pooling reduces overhead (100 max children, 20 pool/backend)
- Load-balanced reads across all standbys
- Session-level load balancing (transaction-safe)
- `disable_load_balance_on_write = 'always'` prevents read-after-write issues
- PgPool automatic primary detection and failover integration
- Backend 0 (primary) weight = 0 to prevent read traffic

**New Scripts & Tools**
- `pgpool/monitor.sh` - PgPool health monitoring
- `pgpool/failover.sh` - Failover integration hook (disabled by default)
- `promote_guard.sh` enhancements for PgPool coordination

**Documentation**
- Comprehensive README with PgPool architecture diagrams
- Railway-specific connection string examples
- PCP command reference
- Security hardening recommendations
- Troubleshooting guide for PgPool-specific issues

### 🔧 Changed

**PostgreSQL Nodes**
- Updated entrypoint to support Railway DNS (`*.railway.internal`)
- Ensured IPv6 compatibility (Railway private networking)
- Kept `listen_addresses = '*'` for both IPv4/IPv6
- Updated `PEERS` variable format for Railway domains

**Environment Variables**
- Simplified to 5 shared secrets:
  - `POSTGRES_PASSWORD`
  - `REPMGR_PASSWORD`
  - `APP_READONLY_PASSWORD`
  - `APP_READWRITE_PASSWORD`
  - `PCP_PASSWORD` (new)
- Added PgPool-specific vars:
  - `PGPOOL_NODE_ID`, `PGPOOL_HOSTNAME`
  - `PG_BACKENDS` (comma-separated Railway domains)
  - `EXPORT_PLAINTEXT_POOLPWD` (default: `false`)
- Removed Docker Compose-specific vars (network names, hostnames)

**Configuration Files**
- Updated `pgpool.conf`:
  - `backend_auth_method = 'scram-sha-256'`
  - `allow_clear_text_frontend_auth = off`
  - `pool_passwd` points to SCRAM hash file
  - Dynamic backend generation via `PG_BACKENDS` env var
- Updated `pool_hba.conf`:
  - Enforced SCRAM for host connections
  - (Note: currently allows 0.0.0.0/0 - see security recommendations)

**Deployment Model**
- Changed from single `docker-compose.yml` to 7 Railway services
- Each PostgreSQL node has dedicated Railway volume
- PgPool nodes are stateless (no volumes)
- Services auto-discover via Railway private DNS

### 🛡️ Security Improvements

- **SCRAM-SHA-256 Enforced**: PgPool `pool_passwd` uses hashed credentials (no plaintext)
- **Minimal Secrets**: Reduced attack surface with fewer environment variables
- **Railway Encryption**: All secrets encrypted at rest by Railway
- **No Hardcoded Passwords**: All passwords via environment variables or secrets
- **Peer Auth**: Local PostgreSQL connections use `peer` (no password for postgres user inside container)

### 🐛 Fixed

- Fixed IPv6 compatibility issues for Railway private networking
- Fixed PgPool entrypoint to wait for writable primary (not just reachable)
- Fixed `pool_passwd` generation to use proper SCRAM-SHA-256 format
- Fixed backend connection pooling race condition (added `PGPOOL_BACKEND_WAIT`)

### ⚠️ Breaking Changes

- **Docker Compose Removed**: `docker-compose.yml` no longer used for Railway deployments
- **Environment Variable Changes**: Old env vars (e.g., `CLUSTER_NAME`, `PGPOOL_ENABLE`) removed
- **Networking**: Changed from Docker bridge networks to Railway private networking
- **Volumes**: Changed from Docker named volumes to Railway volume service

### 📚 Documentation Updates

- **README.md**: Completely rewritten for Railway deployment
  - New architecture diagram with PgPool
  - Railway-specific quick start
  - Connection string examples for PgPool
  - PCP command reference
  - Troubleshooting for PgPool issues
- **RAILWAY_DEPLOYMENT.md**: New step-by-step guide
  - 7-service deployment walkthrough
  - Variable configuration examples
  - Verification steps
  - Cost optimization tips
- **.env.example**: Updated with Railway-focused variables

### 🔮 Future Enhancements (Roadmap)

- SSL/TLS support for client connections
- Automated backups to S3/GCS via WAL archiving
- Prometheus/Grafana integration for monitoring
- PgPool watchdog active-active HA (currently disabled)
- Restrict `pool_hba.conf` to Railway internal CIDR only
- Dedicated `pgpool_check` user for health checks (minimal privileges)

---

## [1.x] - Previous Versions

See git history for pre-Railway versions (Docker Compose-based cluster).

Key features in 1.x:
- 4 PostgreSQL nodes + witness
- Repmgr automatic failover
- Promotion guard (lag threshold)
- Auto-rejoin via `pg_rewind`
- SCRAM-SHA-256 authentication
- Data checksums enabled

---

**Migration from 1.x to 2.0:**
1. Backup all data (`pg_dump` from each node)
2. Deploy new Railway services (follow `RAILWAY_DEPLOYMENT.md`)
3. Restore data to new primary (`psql < backup.sql`)
4. Update application connection strings to PgPool public domains
5. Decommission old Docker Compose stack
