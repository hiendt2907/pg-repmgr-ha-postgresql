# Repository Restructuring Guide

## Overview

The PostgreSQL HA cluster has been reorganized into a dedicated `postgresql-cluster/` directory for better maintainability and clarity.

## What Changed

### Old Structure
```
pg-ha-repo/
├── Dockerfile                    # PostgreSQL
├── entrypoint.sh                # PostgreSQL entrypoint
├── promote_guard.sh             # Failover script
├── monitor.sh                   # Monitoring script
├── pgpool/                      # PgPool directory
├── haproxy/                     # HAProxy directory
├── railway-config/              # Railway configs
├── README.md                    # Documentation
└── [other files]
```

### New Structure
```
pg-ha-repo/
├── README.md                           # Repository overview
├── postgresql-cluster/                 # ⭐ All cluster files
│   ├── postgresql/                    # PostgreSQL + Repmgr
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   ├── pgpool/                        # PgPool-II
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   ├── pgpool.conf
│   │   ├── pool_hba.conf
│   │   └── pcp.conf
│   ├── haproxy/                       # HAProxy
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   └── haproxy.cfg
│   ├── scripts/                       # Utility scripts
│   │   ├── promote_guard.sh
│   │   └── monitor.sh
│   ├── railway-config/                # Railway deployment
│   │   ├── railway-services.json
│   │   ├── deploy-railway.sh
│   │   ├── RAILWAY_DEPLOYMENT.md
│   │   └── VARIABLES.md
│   ├── docs/                          # Documentation
│   │   ├── README.md
│   │   ├── RAILWAY_QUICK_REFERENCE.md
│   │   ├── RAILWAY_MIGRATION_SUMMARY.md
│   │   └── CHANGELOG.md
│   ├── docker-compose.yml             # Local development
│   ├── railway.toml                   # Railway config
│   ├── .env.example                   # Environment template
│   ├── .gitignore
│   └── README.md                      # Cluster documentation
└── [other projects]
```

## Benefits

1. **Clear Separation**: PostgreSQL cluster isolated from other projects
2. **Self-contained**: All cluster files in one directory
3. **Better Organization**: Logical grouping (docs/, scripts/, railway-config/)
4. **Easy Navigation**: Quick access to specific components
5. **Version Control**: Easier to track cluster-specific changes
6. **Deployment**: Single directory for production deployment

## Updated Paths

### Dockerfile Paths
All Dockerfiles now use relative paths from repository root:

**PostgreSQL Services (pg-1, pg-2, pg-3, pg-4, witness)**:
```json
{
  "source": {
    "type": "dockerfile",
    "dockerfile": "postgresql-cluster/postgresql/Dockerfile"
  }
}
```

**PgPool Services (pgpool-1, pgpool-2)**:
```json
{
  "source": {
    "type": "dockerfile",
    "dockerfile": "postgresql-cluster/pgpool/Dockerfile",
    "context": "."
  }
}
```

**HAProxy Service**:
```json
{
  "source": {
    "type": "dockerfile",
    "dockerfile": "postgresql-cluster/haproxy/Dockerfile",
    "context": "."
  }
}
```

### COPY Instructions in Dockerfiles

**PostgreSQL Dockerfile**:
```dockerfile
COPY postgresql-cluster/postgresql/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY postgresql-cluster/scripts/monitor.sh /usr/local/bin/monitor.sh
COPY postgresql-cluster/scripts/promote_guard.sh /usr/local/bin/promote_guard.sh
```

**PgPool Dockerfile**:
```dockerfile
COPY postgresql-cluster/pgpool/pgpool.conf /config/
COPY postgresql-cluster/pgpool/pool_hba.conf /config/
COPY postgresql-cluster/pgpool/pcp.conf /config/
COPY postgresql-cluster/pgpool/entrypoint.sh /usr/local/bin/
COPY postgresql-cluster/pgpool/monitor.sh /usr/local/bin/
COPY postgresql-cluster/pgpool/failover.sh /usr/local/bin/
```

**HAProxy Dockerfile**:
```dockerfile
COPY postgresql-cluster/haproxy/haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
COPY postgresql-cluster/haproxy/entrypoint.sh /usr/local/bin/entrypoint.sh
```

## Migration Checklist

If you have existing deployments or local development environments:

### For Railway Deployments

1. **Update railway-services.json**: Already updated with new paths
2. **Redeploy services**: Use updated deployment script
   ```bash
   cd postgresql-cluster/railway-config
   ./deploy-railway.sh
   ```
3. **No data migration needed**: Environment variables and volumes unchanged

### For Local Docker Compose

1. **Navigate to new directory**:
   ```bash
   cd postgresql-cluster
   ```

2. **Copy environment file**:
   ```bash
   cp .env.example .env
   # Edit .env with your passwords
   ```

3. **Rebuild images**:
   ```bash
   docker-compose down
   docker-compose build
   docker-compose up -d
   ```

### For Existing Git Clones

1. **Pull latest changes**:
   ```bash
   cd /path/to/pg-ha-repo
   git pull origin main
   ```

2. **Update local scripts** that reference old paths

3. **Rebuild Docker images** if running locally

## Documentation Updates

All documentation has been reorganized:

- **Main README**: `/postgresql-cluster/README.md` - Complete cluster guide
- **Railway Deployment**: `/postgresql-cluster/railway-config/RAILWAY_DEPLOYMENT.md`
- **Quick Reference**: `/postgresql-cluster/docs/RAILWAY_QUICK_REFERENCE.md`
- **Changelog**: `/postgresql-cluster/docs/CHANGELOG.md`
- **Migration Summary**: `/postgresql-cluster/docs/RAILWAY_MIGRATION_SUMMARY.md`

## No Breaking Changes

### Unchanged:
- ✅ Environment variables
- ✅ Service names (pg-1, pg-2, pgpool-1, haproxy, etc.)
- ✅ Port mappings
- ✅ Volume mount paths
- ✅ Network configurations
- ✅ Internal hostnames (pg-1.railway.internal, etc.)
- ✅ Configuration file contents

### Changed:
- ✅ Directory structure (files moved to postgresql-cluster/)
- ✅ Dockerfile paths in railway-services.json
- ✅ COPY instructions in Dockerfiles
- ✅ Documentation locations

## Testing

After migration, verify:

1. **Build succeeds**:
   ```bash
   cd postgresql-cluster
   docker-compose build
   ```

2. **Services start**:
   ```bash
   docker-compose up -d
   docker-compose ps
   ```

3. **Cluster health**:
   ```bash
   docker exec -it pg-1 repmgr cluster show
   docker exec -it pgpool-1 pcp_node_count -h localhost -p 9898 -U admin -w
   ```

4. **Connectivity**:
   ```bash
   psql -h localhost -p 5432 -U app_readwrite -d postgres
   ```

## Rollback

If issues occur, revert to previous structure:

```bash
git log --oneline  # Find commit before restructuring
git checkout <commit-hash>
docker-compose down
docker-compose build
docker-compose up -d
```

## Support

Questions or issues? Check:
- [Main README](/postgresql-cluster/README.md)
- [Railway Deployment Guide](/postgresql-cluster/railway-config/RAILWAY_DEPLOYMENT.md)
- [Quick Reference](/postgresql-cluster/docs/RAILWAY_QUICK_REFERENCE.md)

## Summary

The restructuring provides:
- ✅ Better organization
- ✅ Easier maintenance
- ✅ No functional changes
- ✅ Backward compatible (same service names, ports, env vars)
- ✅ Updated documentation paths only

**Next Steps**: Navigate to `postgresql-cluster/` and follow the README for deployment instructions.
