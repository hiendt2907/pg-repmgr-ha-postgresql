# Railway Migration Summary

## Tổng quan chuyển đổi

Dự án PostgreSQL HA Cluster đã được **hoàn toàn refactor** để deploy lên **Railway.app** với **PgPool-II** tích hợp sẵn.

---

## 🎯 Thay đổi chính

### 1. Kiến trúc mới (7 Railway Services)

| Service | Vai trò | Public? | Volume | RAM khuyến nghị |
|---------|---------|---------|--------|-----------------|
| `pg-1` | PostgreSQL Primary | ❌ | ✅ pg-1-data | 512 MB - 2 GB |
| `pg-2` | PostgreSQL Standby | ❌ | ✅ pg-2-data | 512 MB - 2 GB |
| `pg-3` | PostgreSQL Standby | ❌ | ✅ pg-3-data | 512 MB - 2 GB |
| `pg-4` | PostgreSQL Standby | ❌ | ✅ pg-4-data | 512 MB - 2 GB |
| `witness` | Repmgr Witness | ❌ | ✅ witness-data | 256 MB |
| `pgpool-1` | Load Balancer #1 | ✅ | ❌ | 256 MB - 1 GB |
| `pgpool-2` | Load Balancer #2 | ✅ | ❌ | 256 MB - 1 GB |

**Tổng chi phí ước tính (Railway):** ~$20-40/tháng (tùy RAM và traffic)

---

### 2. Environment Variables (Giảm từ ~50 xuống 5!)

**Trước (Docker Compose):**
- Mỗi service có ~10-15 biến riêng
- Nhiều biến trùng lặp (POSTGRES_PASSWORD trong 5 services)
- Khó quản lý và dễ lỗi

**Sau (Railway):**
- **5 shared secrets** dùng chung cho tất cả services:
  ```
  POSTGRES_PASSWORD
  REPMGR_PASSWORD
  APP_READONLY_PASSWORD
  APP_READWRITE_PASSWORD
  PCP_PASSWORD
  ```
- Các biến khác auto-generated hoặc hardcoded trong service config

---

### 3. PgPool-II Features

**Tại sao cần PgPool?**
- ✅ **Connection Pooling**: Giảm overhead khi mở/đóng kết nối
- ✅ **Load Balancing**: Tự động phân tán read queries lên các standby
- ✅ **Query Routing**: Writes → Primary, Reads → Standbys
- ✅ **High Availability**: 2 PgPool nodes, nếu 1 chết thì còn 1
- ✅ **Transparent Failover**: Client không cần biết primary mới là ai

**Cách hoạt động:**
```
Client → pgpool-1.railway.app:5432
           ↓
    [PgPool Decision]
           ↓
    ┌──────┴──────┐
    ↓             ↓
  SELECT?      INSERT/UPDATE?
    ↓             ↓
Standbys      Primary
(pg-2,3,4)     (pg-1)
```

---

### 4. Files thay đổi

#### Files mới tạo:
- ✅ `README.md` - Hoàn toàn mới, focus Railway
- ✅ `RAILWAY_DEPLOYMENT.md` - Hướng dẫn deploy từng bước
- ✅ `CHANGELOG.md` - Lịch sử thay đổi chi tiết
- ✅ `railway-config/railway-services.json` - Template config 7 services
- ✅ `.env.example` - Template biến môi trường Railway
- ✅ `.railwayignore` - Ignore files khi build trên Railway

#### Files đã backup:
- 📦 `README.md.backup` - README cũ (Docker Compose)
- 📦 `CHANGELOG.md.backup` - CHANGELOG cũ
- 📦 `.env.example.backup` - .env cũ

#### Files giữ nguyên (không đổi):
- `entrypoint.sh` - Đã hỗ trợ sẵn Railway DNS
- `Dockerfile` - Vẫn dùng được
- `pgpool/` - Đã có sẵn, chỉ cần deploy

---

## 📋 Checklist Deploy lên Railway

### Bước 1: Chuẩn bị
- [ ] Có Railway account
- [ ] Cài Railway CLI: `npm i -g @railway/cli`
- [ ] Login: `railway login`

### Bước 2: Tạo project
- [ ] Push code lên GitHub (repo riêng của bạn)
- [ ] Railway dashboard → New Project → From GitHub
- [ ] Chọn repo `pg-ha-repo`

### Bước 3: Set shared variables
- [ ] Railway → Project → Variables → Shared
- [ ] Add 5 secrets (xem `.env.example`)

### Bước 4: Deploy từng service
- [ ] Deploy `pg-1` (Primary) - Đợi healthy
- [ ] Deploy `pg-2, pg-3, pg-4` (Standbys) - Có thể parallel
- [ ] Deploy `witness`
- [ ] Deploy `pgpool-1, pgpool-2` - **Chờ tất cả PG nodes healthy**

### Bước 5: Expose public domains
- [ ] `pgpool-1` → Settings → Generate Domain
- [ ] `pgpool-2` → Settings → Generate Domain

### Bước 6: Test
- [ ] Connect qua PgPool: `psql -h pgpool-1-xxx.railway.app -U app_readwrite`
- [ ] Check cluster: `railway run --service pg-1 -- repmgr cluster show`
- [ ] Test failover (optional)

---

## 🔗 Connection Strings

### Cho ứng dụng (Production)

**Primary connection (read+write via PgPool):**
```
postgresql://app_readwrite:YOUR_PASSWORD@pgpool-1-production-xxx.railway.app:5432/postgres
```

**Fallback connection (nếu pgpool-1 chết):**
```
postgresql://app_readwrite:YOUR_PASSWORD@pgpool-2-production-yyy.railway.app:5432/postgres
```

**Read-only (tùy chọn):**
```
postgresql://app_readonly:YOUR_PASSWORD@pgpool-1-production-xxx.railway.app:5432/postgres
```

### Cho admin/debug (Direct node access)

**Primary trực tiếp (không qua PgPool):**
```
railway run --service pg-1 -- psql -U postgres
```

**Standby trực tiếp:**
```
railway run --service pg-2 -- psql -U postgres
```

---

## 🛠️ Monitoring & Operations

### Check cluster status
```bash
railway run --service pg-1 -- gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show
```

### Check PgPool backends
```bash
railway run --service pgpool-1 -- pcp_node_info -h localhost -p 9898 -U admin -w
```

### Check replication lag
```bash
railway run --service pg-1 -- gosu postgres psql -c "SELECT application_name, state, replay_lag FROM pg_stat_replication;"
```

### Manual failover (nếu cần)
```bash
# Promote pg-2 lên primary
railway run --service pg-2 -- gosu postgres repmgr standby promote -f /etc/repmgr/repmgr.conf

# Force pg-3, pg-4 follow pg-2
railway run --service pg-3 -- gosu postgres repmgr standby follow -f /etc/repmgr/repmgr.conf --upstream-node-id=2
```

---

## 💰 Cost Estimation (Railway)

### Free Tier
- $5 credit/month
- 512 MB RAM per service
- Có thể chạy được **1-2 services** (test/dev only)

### Production (Paid)
Giả sử mỗi PG node = 1 GB RAM, PgPool = 512 MB:

| Service | RAM | Cost/month (ước tính) |
|---------|-----|----------------------|
| pg-1 | 1 GB | ~$5 |
| pg-2 | 1 GB | ~$5 |
| pg-3 | 1 GB | ~$5 |
| pg-4 | 1 GB | ~$5 |
| witness | 256 MB | ~$2 |
| pgpool-1 | 512 MB | ~$3 |
| pgpool-2 | 512 MB | ~$3 |
| **Total** | | **~$28/month** |

**Volume costs** (persistent storage):
- $0.25/GB/month
- Ví dụ: 4 nodes × 10 GB = 40 GB → ~$10/month

**Grand total:** ~$38-50/month (tùy data size & traffic)

---

## 🔒 Security Checklist

- [x] SCRAM-SHA-256 enabled (done)
- [x] No plaintext passwords in code (done)
- [x] Railway secrets encrypted at rest (done)
- [ ] Restrict `pool_hba.conf` to Railway CIDR only (TODO)
- [ ] Enable SSL/TLS for client connections (TODO)
- [ ] Create dedicated `pgpool_check` user (TODO)
- [ ] Rotate secrets monthly (manual task)

---

## 📚 Tài liệu tham khảo

- **README.md** - Overview và quick start
- **RAILWAY_DEPLOYMENT.md** - Chi tiết từng bước deploy
- **CHANGELOG.md** - Lịch sử thay đổi đầy đủ
- **railway-config/railway-services.json** - Template config 7 services
- **PgPool docs:** https://www.pgpool.net/docs/latest/en/html/
- **Railway docs:** https://docs.railway.app

---

## ⚠️ Lưu ý quan trọng

### 1. Không push lên git (theo yêu cầu)
Các file mới này **chưa được commit/push**. Bạn có thể:
- Review toàn bộ changes
- Test local trước
- Khi sẵn sàng: `git add -A && git commit -m "feat: Railway migration with PgPool" && git push`

### 2. Backup files
Tất cả files cũ đã được backup:
- `README.md.backup`
- `CHANGELOG.md.backup`
- `.env.example.backup`

Nếu cần rollback: `mv README.md.backup README.md`

### 3. Docker Compose vẫn hoạt động
File `docker-compose.yml` **không bị xóa**. Nếu bạn muốn test local:
```bash
docker compose up -d
```

Nhưng để deploy Railway, **không dùng docker-compose**.

### 4. PgPool watchdog tắt mặc định
Trong config hiện tại: `use_watchdog = off`

Nếu muốn bật (high availability cho PgPool):
- Edit `pgpool/pgpool.conf`: `use_watchdog = on`
- Configure VIP (virtual IP) - Railway không hỗ trợ tự động
- Khuyến nghị: Dùng Railway's built-in load balancer thay vì watchdog

---

## 🚀 Next Steps

1. **Review changes** - Đọc kỹ README.md và RAILWAY_DEPLOYMENT.md
2. **Test local** (optional) - `docker compose up` để verify builds work
3. **Deploy to Railway** - Follow RAILWAY_DEPLOYMENT.md
4. **Update app connection strings** - Point to `pgpool-1.railway.app`
5. **Monitor & optimize** - Check logs, adjust RAM if needed
6. **Setup backups** - Configure pg_dump cron hoặc Railway volume snapshots

---

**Có thắc mắc?** Đọc RAILWAY_DEPLOYMENT.md hoặc README.md troubleshooting section.
