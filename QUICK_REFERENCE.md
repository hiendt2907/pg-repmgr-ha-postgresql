# Quick Reference: New Repository Structure

## 📂 Directory Layout

```
pg-ha-repo/
├── README.md                      ← Repo overview, start here
│
└── postgresql-cluster/            ← ⭐ MAIN CLUSTER (all-in-one)
    │
    ├── README.md                  ← Complete cluster guide
    ├── docker-compose.yml         ← Local development
    ├── railway.toml               ← Railway config
    ├── .env.example               ← Environment template
    ├── .gitignore
    │
    ├── postgresql/                ← PostgreSQL + Repmgr
    │   ├── Dockerfile
    │   └── entrypoint.sh
    │
    ├── pgpool/                    ← PgPool-II
    │   ├── Dockerfile
    │   ├── entrypoint.sh
    │   ├── pgpool.conf
    │   ├── pool_hba.conf
    │   └── pcp.conf
    │
    ├── haproxy/                   ← HAProxy
    │   ├── Dockerfile
    │   ├── entrypoint.sh
    │   └── haproxy.cfg
    │
    ├── scripts/                   ← Utilities
    │   ├── promote_guard.sh
    │   └── monitor.sh
    │
    ├── railway-config/            ← Railway deployment
    │   ├── railway-services.json
    │   ├── deploy-railway.sh
    │   ├── RAILWAY_DEPLOYMENT.md
    │   └── VARIABLES.md
    │
    └── docs/                      ← Documentation
        ├── README.md
        ├── CHANGELOG.md
        ├── RAILWAY_QUICK_REFERENCE.md
        └── RAILWAY_MIGRATION_SUMMARY.md
```

## 🚀 Quick Start Commands

### Railway Deployment
```bash
cd /root/pg-ha-repo/postgresql-cluster/railway-config
./deploy-railway.sh
```

### Local Docker Compose
```bash
cd /root/pg-ha-repo/postgresql-cluster
cp .env.example .env
# Edit .env
docker-compose up -d
```

### Check Cluster Status
```bash
cd /root/pg-ha-repo/postgresql-cluster
docker exec -it pg-1 repmgr cluster show
docker exec -it pgpool-1 pcp_node_count -h localhost -p 9898 -U admin -w
```

## 📖 Documentation Locations

| Document | Location | Purpose |
|----------|----------|---------|
| Repository Overview | `/README.md` | What's in this repo |
| Cluster Guide | `postgresql-cluster/README.md` | Complete cluster documentation |
| Railway Deployment | `postgresql-cluster/railway-config/RAILWAY_DEPLOYMENT.md` | Step-by-step Railway guide |
| Quick Reference | `postgresql-cluster/docs/RAILWAY_QUICK_REFERENCE.md` | Common commands & troubleshooting |
| Restructuring Guide | `postgresql-cluster/RESTRUCTURING_GUIDE.md` | Migration from old structure |
| Changelog | `postgresql-cluster/docs/CHANGELOG.md` | Version history |

## 🔧 Common File Locations

| Component | File | Path |
|-----------|------|------|
| PostgreSQL | Dockerfile | `postgresql-cluster/postgresql/Dockerfile` |
| PostgreSQL | Entrypoint | `postgresql-cluster/postgresql/entrypoint.sh` |
| PgPool | Dockerfile | `postgresql-cluster/pgpool/Dockerfile` |
| PgPool | Config | `postgresql-cluster/pgpool/pgpool.conf` |
| HAProxy | Dockerfile | `postgresql-cluster/haproxy/Dockerfile` |
| HAProxy | Config | `postgresql-cluster/haproxy/haproxy.cfg` |
| Promote Guard | Script | `postgresql-cluster/scripts/promote_guard.sh` |
| Railway Services | Config | `postgresql-cluster/railway-config/railway-services.json` |
| Docker Compose | Config | `postgresql-cluster/docker-compose.yml` |
| Environment | Template | `postgresql-cluster/.env.example` |

## 🎯 What Changed vs Old Structure

### Moved Files
- `Dockerfile` → `postgresql-cluster/postgresql/Dockerfile`
- `entrypoint.sh` → `postgresql-cluster/postgresql/entrypoint.sh`
- `pgpool/*` → `postgresql-cluster/pgpool/*`
- `haproxy/*` → `postgresql-cluster/haproxy/*`
- `railway-config/*` → `postgresql-cluster/railway-config/*`
- `README.md` → `postgresql-cluster/docs/README.md`

### Updated Paths
- All `railway-services.json` Dockerfile paths
- All Dockerfile COPY instructions
- Documentation cross-references

### Unchanged (Still Works!)
- Service names (pg-1, pg-2, pgpool-1, haproxy)
- Environment variables
- Port mappings
- Volume mounts
- Network configs

## ✅ Verification Checklist

```bash
cd /root/pg-ha-repo/postgresql-cluster

# All directories exist?
ls -d postgresql pgpool haproxy scripts railway-config docs

# Key files present?
ls postgresql/Dockerfile pgpool/Dockerfile haproxy/Dockerfile

# Can build?
docker-compose build --no-cache

# Services defined in railway-services.json?
jq '.services | keys' railway-config/railway-services.json
```

## 📞 Getting Help

1. **Read documentation**: Start with `postgresql-cluster/README.md`
2. **Check guides**: See `docs/` and `railway-config/` directories
3. **Review restructuring**: Read `RESTRUCTURING_GUIDE.md` for migration info
4. **Verify setup**: Run verification commands above

## 💡 Pro Tips

- **Always work from `postgresql-cluster/` directory** for cluster operations
- **Use relative paths** when editing docker-compose.yml
- **Update both Dockerfile and railway-services.json** when changing paths
- **Test locally first** with `docker-compose build` before Railway deployment
- **Keep `.env` in sync** with `.env.example` when adding new variables

---

**Quick Navigation**:
- 🏠 Start: `/root/pg-ha-repo/README.md`
- 🎯 Cluster: `/root/pg-ha-repo/postgresql-cluster/README.md`
- 🚀 Deploy: `/root/pg-ha-repo/postgresql-cluster/railway-config/RAILWAY_DEPLOYMENT.md`
- 📚 Docs: `/root/pg-ha-repo/postgresql-cluster/docs/`
