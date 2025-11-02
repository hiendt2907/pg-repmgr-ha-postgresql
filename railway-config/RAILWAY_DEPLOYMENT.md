# PostgreSQL HA Cluster on Railway

## Tổng quan

Dự án này deploy một PostgreSQL High Availability cluster lên Railway với:
- **4 PostgreSQL nodes** (pg-1, pg-2, pg-3, pg-4) - tự động failover với repmgr
- **1 Witness node** - quorum cho cluster nhỏ
- **Private networking** - tất cả nodes giao tiếp qua Railway private network
- **Persistent volumes** - mỗi node có volume riêng

## Kiến trúc

```
┌─────────────────────────────────────────────────────┐
│           Railway Project (Private Network)         │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌────────┐│
│  │ pg-1 │  │ pg-2 │  │ pg-3 │  │ pg-4 │  │witness ││
│  │(Pri) │  │(Stby)│  │(Stby)│  │(Stby)│  │        ││
│  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘  └───┬────┘│
│     │         │         │         │          │     │
│     └─────────┴─────────┴─────────┴──────────┘     │
│              repmgr cluster sync                    │
│                                                      │
│  Internal DNS:                                       │
│  - pg-1.railway.internal:5432                       │
│  - pg-2.railway.internal:5432                       │
│  - pg-3.railway.internal:5432                       │
│  - pg-4.railway.internal:5432                       │
│  - witness.railway.internal:5432                    │
└──────────────────────────────────────────────────────┘
```

## Bước 1: Tạo Project trên Railway

1. Đăng nhập vào [Railway](https://railway.app)
2. Tạo project mới: `PostgreSQL HA Cluster`
3. **Quan trọng**: Tạo Shared Variables cho toàn project (chỉ cần set 1 lần)

### Shared Variables (Project-level)

```bash
# Shared secrets - set một lần cho cả project
POSTGRES_PASSWORD=<your-strong-password>
REPMGR_PASSWORD=<your-repmgr-password>
APP_READONLY_PASSWORD=<your-readonly-password>
APP_READWRITE_PASSWORD=<your-readwrite-password>

# Cluster config (optional - có defaults)
REPMGR_PROMOTE_MAX_LAG_SECS=10
RETRY_INTERVAL=5
RETRY_ROUNDS=36
```

## Bước 2: Deploy các Services

Deploy **THEO THỨ TỰ** sau (quan trọng):

### Service 1: pg-1 (Primary node)

1. **New Service** → **Empty Service** → Đặt tên: `pg-1`
2. **Settings**:
   - **Service Name**: `pg-1` (dùng cho DNS: `pg-1.railway.internal`)
   - **Source**: GitHub (connect repo này)
   - **Root Directory**: `/` (hoặc để trống)
   - **Dockerfile Path**: `Dockerfile`
3. **Variables** (service-specific):
   ```bash
   NODE_NAME=pg-1
   NODE_ID=1
   PRIMARY_HINT=pg-1.railway.internal
   IS_WITNESS=false
   PEERS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432,witness.railway.internal:5432
   ```
4. **Volume**:
   - Mount Path: `/var/lib/postgresql/data`
   - Size: 10GB (tùy nhu cầu)
5. **Settings → Networking**:
   - Enable TCP Proxy (nếu cần connect từ ngoài)
6. **Deploy** và đợi pg-1 khởi động thành công

### Service 2: pg-2 (Standby node)

1. **New Service** → **Empty Service** → Đặt tên: `pg-2`
2. **Settings**: giống pg-1
3. **Variables**:
   ```bash
   NODE_NAME=pg-2
   NODE_ID=2
   PRIMARY_HINT=pg-1.railway.internal
   IS_WITNESS=false
   PEERS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432,witness.railway.internal:5432
   ```
4. **Volume**: `/var/lib/postgresql/data` (10GB)
5. **Deploy**

### Service 3: pg-3 (Standby node)

1. **New Service** → **Empty Service** → Đặt tên: `pg-3`
2. **Variables**:
   ```bash
   NODE_NAME=pg-3
   NODE_ID=3
   PRIMARY_HINT=pg-1.railway.internal
   IS_WITNESS=false
   PEERS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432,witness.railway.internal:5432
   ```
3. **Volume**: `/var/lib/postgresql/data` (10GB)
4. **Deploy**

### Service 4: pg-4 (Standby node)

1. **New Service** → **Empty Service** → Đặt tên: `pg-4`
2. **Variables**:
   ```bash
   NODE_NAME=pg-4
   NODE_ID=4
   PRIMARY_HINT=pg-1.railway.internal
   IS_WITNESS=false
   PEERS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432,witness.railway.internal:5432
   ```
3. **Volume**: `/var/lib/postgresql/data` (10GB)
4. **Deploy**

### Service 5: witness (Witness node)

1. **New Service** → **Empty Service** → Đặt tên: `witness`
2. **Variables**:
   ```bash
   NODE_NAME=witness
   NODE_ID=99
   PRIMARY_HINT=pg-1.railway.internal
   IS_WITNESS=true
   PEERS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432,witness.railway.internal:5432
   ```
3. **Volume**: `/var/lib/postgresql/data` (1GB - witness không cần nhiều)
4. **Deploy**

## Bước 3: Kiểm tra Cluster

### 3.1. Xem logs

Vào mỗi service → **Deployments** → Xem logs để đảm bảo:
- pg-1: `[primary] Registered as primary`
- pg-2,3,4: `[standby] Cloned from primary` và `registered`
- witness: `witness registered`

### 3.2. Connect vào primary và check cluster status

```bash
# Get pg-1 TCP Proxy info từ Railway UI
# Hoặc dùng Railway CLI
railway run --service pg-1 psql -U repmgr -d repmgr -c "SELECT * FROM repmgr.show_nodes;"
```

Expected output:
```
 node_id | node_name | active | upstream_node_name 
---------+-----------+--------+--------------------
       1 | pg-1      | t      | -
       2 | pg-2      | t      | pg-1
       3 | pg-3      | t      | pg-1
       4 | pg-4      | t      | pg-1
      99 | witness   | t      | pg-1
```

## Bước 4: Test Failover

### Test 1: Stop standby
```bash
# Stop pg-4 từ Railway UI
# Cluster vẫn hoạt động bình thường
# Restart pg-4 → tự động rejoin
```

### Test 2: Stop primary (automatic promotion)
```bash
# Stop pg-1 từ Railway UI
# Chờ ~30s → pg-2 hoặc pg-3 sẽ tự động promote
# Check logs để xem node nào được promote
# Restart pg-1 → tự động pg_rewind và rejoin as standby
```

## Kết nối từ Application

### Internal (từ service khác trong Railway project)

Dùng biến reference:
```bash
# Trong app service, set:
DATABASE_URL=postgresql://app_readwrite:${{shared.APP_READWRITE_PASSWORD}}@pg-1.railway.internal:5432/postgres
```

Hoặc dùng connection pooling bằng PgBouncer/Pgpool (optional).

### External (từ internet)

1. Enable **TCP Proxy** cho pg-1 (primary)
2. Lấy `RAILWAY_TCP_PROXY_DOMAIN` và `RAILWAY_TCP_PROXY_PORT` từ variables
3. Connect: 
   ```
   postgresql://postgres:$PASSWORD@roundhouse.proxy.rlwy.net:12345/postgres
   ```

**⚠️ Lưu ý**: TCP Proxy tính phí Network Egress, chỉ dùng khi cần thiết.

## Cost Optimization

- **Shared Variables**: Giảm duplicate, chỉ maintain passwords ở 1 chỗ
- **Private Networking**: Free, không tính egress giữa các services
- **Volumes**: Chỉ pay theo GB sử dụng
- **TCP Proxy**: Chỉ enable cho primary khi cần external access

## Monitoring & Maintenance

### Check cluster health
```sql
-- Via Railway CLI
railway run --service pg-1 \
  psql -U repmgr -d repmgr -c \
  "SELECT node_name, active, node_id FROM repmgr.nodes ORDER BY node_id;"
```

### View repmgr events
```sql
railway run --service pg-1 \
  psql -U repmgr -d repmgr -c \
  "SELECT * FROM repmgr.events ORDER BY event_timestamp DESC LIMIT 20;"
```

### Backup
Dùng Railway's built-in volume backups hoặc pg_dump qua TCP proxy.

## Troubleshooting

### Service không start
- Check logs: `railway logs --service pg-1`
- Verify shared variables được set đúng
- Ensure volume đã mount tại `/var/lib/postgresql/data`

### Không kết nối được giữa nodes
- Verify tất cả services trong cùng 1 project
- Check `PEERS` variable có đúng DNS không (`.railway.internal`)
- Đảm bảo PostgreSQL listen trên IPv6 (đã config trong entrypoint)

### Promotion không tự động
- Check promote_guard logs
- Verify repmgrd đang chạy trên các standby
- Check replication lag: `SELECT pg_last_xact_replay_timestamp();`

## So sánh với Docker Compose local

| Feature | Docker Compose | Railway |
|---------|---------------|---------|
| Networking | Docker bridge | Private IPv6 network |
| DNS | Container names | `<service>.railway.internal` |
| Volumes | Named volumes | Railway volumes |
| Secrets | .env file | Shared/Service variables |
| Scaling | docker-compose scale | Add more services |
| Cost | Server costs | Pay per usage |

## Tối thiểu hóa Variables

Railway cho phép tối thiểu variables bằng cách:

1. **Shared Variables**: Passwords, common configs
2. **Railway-provided vars**: `RAILWAY_PRIVATE_DOMAIN`, `PORT` (auto-injected)
3. **Reference Variables**: `${{pg-1.POSTGRES_PASSWORD}}` thay vì duplicate
4. **Defaults trong code**: Entrypoint có sẵn defaults cho hầu hết configs

### Variables tối thiểu cần thiết (per service):

**Shared (1 lần):**
- POSTGRES_PASSWORD
- REPMGR_PASSWORD  
- APP_READONLY_PASSWORD
- APP_READWRITE_PASSWORD

**Per service (chỉ 3-4 variables):**
- NODE_NAME
- NODE_ID
- IS_WITNESS
- PEERS

Tất cả các variables khác đều có defaults hoặc được tính toán tự động.
