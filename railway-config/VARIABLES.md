# Environment Variables Configuration for Railway

## Minimal Required Variables

Railway deployment chỉ cần **TỐI THIỂU** các variables sau:

### 1. Shared Variables (Project-level) - Set 1 lần cho cả project

```bash
# Authentication
POSTGRES_PASSWORD=<your-strong-password>
REPMGR_PASSWORD=<your-repmgr-password>
APP_READONLY_PASSWORD=<your-readonly-password>
APP_READWRITE_PASSWORD=<your-readwrite-password>

# Cluster tuning (optional - có defaults)
REPMGR_PROMOTE_MAX_LAG_SECS=10
RETRY_INTERVAL=5
RETRY_ROUNDS=36
```

### 2. Service Variables - Per service (chỉ 5-6 variables)

#### pg-1 service:
```bash
NODE_NAME=pg-1
NODE_ID=1
NODE_PRIORITY=100
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
PRIMARY_HOST=pg-1.railway.internal
```

#### pg-2 service:
```bash
NODE_NAME=pg-2
NODE_ID=2
NODE_PRIORITY=90
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
PRIMARY_HOST=pg-1.railway.internal
```

#### pg-3 service:
```bash
NODE_NAME=pg-3
NODE_ID=3
NODE_PRIORITY=80
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
PRIMARY_HOST=pg-1.railway.internal
```

#### pg-4 service:
```bash
NODE_NAME=pg-4
NODE_ID=4
NODE_PRIORITY=70
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
PRIMARY_HOST=pg-1.railway.internal
```

#### witness service:
```bash
NODE_NAME=witness
NODE_ID=100
NODE_PRIORITY=0
IS_WITNESS=true
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
PRIMARY_HOST=pg-1.railway.internal
```

**⚠️ CRITICAL:** Witness **MUST** have `IS_WITNESS=true` or it will run as a data node!

## Railway Auto-Injected Variables

Railway tự động inject các variables sau (KHÔNG cần set):

```bash
RAILWAY_ENVIRONMENT_NAME     # e.g., production
RAILWAY_SERVICE_NAME         # e.g., pg-1
RAILWAY_PRIVATE_DOMAIN       # e.g., pg-1.railway.internal
RAILWAY_PROJECT_ID
RAILWAY_DEPLOYMENT_ID
RAILWAY_VOLUME_MOUNT_PATH    # /var/lib/postgresql/data
RAILWAY_VOLUME_NAME
```

## Default Values (trong entrypoint.sh)

Các variables sau có defaults, KHÔNG cần set nếu dùng giá trị mặc định:

```bash
PGDATA=/var/lib/postgresql/data
REPMGR_DB=repmgr
REPMGR_USER=repmgr
POSTGRES_USER=postgres
PG_PORT=5432
REPMGR_CONF=/etc/repmgr/repmgr.conf
RETRY_INTERVAL=5
RETRY_ROUNDS=36
```

## Tổng kết: Số lượng Variables cần set

### Shared (set 1 lần):
- 4 passwords (required)
- 3 tuning params (optional)
= **4-7 variables**

### Per Service:
- NODE_NAME
- NODE_ID
- PRIMARY_HINT
- IS_WITNESS
- PEERS
= **5 variables × 5 services = 25 variables**

### TOTAL: ~30 variables cho toàn bộ cluster (thay vì 100+ như Docker Compose)

## Reference Variables Pattern

Nếu muốn tối ưu hơn, dùng Railway reference variables:

```bash
# Trong app service
DATABASE_URL=postgresql://app_readwrite:${{shared.APP_READWRITE_PASSWORD}}@pg-1.railway.internal:5432/postgres

# Hoặc reference từ service khác
REPMGR_PASS=${{shared.REPMGR_PASSWORD}}
```

## Security Best Practices

1. **NEVER commit passwords** to git
2. Set passwords qua Railway UI hoặc CLI
3. Use Railway's "Sealed Variables" cho sensitive data
4. Rotate passwords regularly
5. Use Railway's built-in secrets management

## Quick Setup với Railway CLI

```bash
# Set shared variables
railway variables set \
  POSTGRES_PASSWORD="..." \
  REPMGR_PASSWORD="..." \
  APP_READONLY_PASSWORD="..." \
  APP_READWRITE_PASSWORD="..."

# Set service variables (example for pg-1)
railway variables set -s pg-1 \
  NODE_NAME="pg-1" \
  NODE_ID="1" \
  PRIMARY_HINT="pg-1.railway.internal" \
  IS_WITNESS="false" \
  PEERS="pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432,witness.railway.internal:5432"
```

## Verification

Check variables đã set:

```bash
# Shared variables
railway variables

# Service-specific
railway variables --service pg-1
```
