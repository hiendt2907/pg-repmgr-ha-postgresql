# TODO: Railway Deployment - FQDN Fix
**Ngày tạo:** 2 Nov 2025  
**Trạng thái:** Đã commit code, chưa deploy

---

## ✅ Đã hoàn thành

1. **Root Cause Analysis:**
   - Lỗi: "password authentication failed" ở tất cả nodes
   - Nguyên nhân thực: `NODE_NAME=pg-1` nhưng Railway hostname là `pg-1.railway.internal`
   - repmgr kết nối đến `pg-1` (không resolve) → connection failed → lỗi auth

2. **Code Fixes (Đã commit):**
   - Commit `3ed7a85`: Railway reference variables trong `create-services.sh` & `VARIABLES.md`
   - Commit `2a189a5`: Fix `PRIMARY_HINT` logic để work với FQDN
   - Đã verify: Tất cả code paths (last_known_primary, comparisons) đều compatible với FQDN

3. **Testing:**
   - ✅ Local auth: `psql -h localhost -U repmgr` → SUCCESS
   - ✅ Remote auth: `psql -h pg-1.railway.internal -U repmgr` → SUCCESS
   - ✅ Password OK: 32 chars, SCRAM-SHA-256, không có vấn đề escaping

---

## 📋 CẦN LÀM NGÀY MAI

### Bước 1: Update Railway Dashboard Variables

**Services cần update:** pg-1, pg-2, pg-3, pg-4, witness, pgpool-1, pgpool-2, haproxy

#### PostgreSQL Nodes (pg-1, pg-2, pg-3, pg-4):
```bash
NODE_NAME=${{RAILWAY_PRIVATE_DOMAIN}}
PEERS=${{pg-1.RAILWAY_PRIVATE_DOMAIN}},${{pg-2.RAILWAY_PRIVATE_DOMAIN}},${{pg-3.RAILWAY_PRIVATE_DOMAIN}},${{pg-4.RAILWAY_PRIVATE_DOMAIN}}
PRIMARY_HOST=${{pg-1.RAILWAY_PRIVATE_DOMAIN}}
```

#### Witness Node:
```bash
NODE_NAME=${{RAILWAY_PRIVATE_DOMAIN}}
PEERS=${{pg-1.RAILWAY_PRIVATE_DOMAIN}},${{pg-2.RAILWAY_PRIVATE_DOMAIN}},${{pg-3.RAILWAY_PRIVATE_DOMAIN}},${{pg-4.RAILWAY_PRIVATE_DOMAIN}}
PRIMARY_HOST=${{pg-1.RAILWAY_PRIVATE_DOMAIN}}
IS_WITNESS=true
```

#### PgPool-1:
```bash
PGPOOL_HOSTNAME=${{RAILWAY_PRIVATE_DOMAIN}}
PG_BACKENDS=${{pg-1.RAILWAY_PRIVATE_DOMAIN}}:5432,${{pg-2.RAILWAY_PRIVATE_DOMAIN}}:5432,${{pg-3.RAILWAY_PRIVATE_DOMAIN}}:5432,${{pg-4.RAILWAY_PRIVATE_DOMAIN}}:5432
OTHER_PGPOOL_HOSTNAME=${{pgpool-2.RAILWAY_PRIVATE_DOMAIN}}
```

#### PgPool-2:
```bash
PGPOOL_HOSTNAME=${{RAILWAY_PRIVATE_DOMAIN}}
PG_BACKENDS=${{pg-1.RAILWAY_PRIVATE_DOMAIN}}:5432,${{pg-2.RAILWAY_PRIVATE_DOMAIN}}:5432,${{pg-3.RAILWAY_PRIVATE_DOMAIN}}:5432,${{pg-4.RAILWAY_PRIVATE_DOMAIN}}:5432
OTHER_PGPOOL_HOSTNAME=${{pgpool-1.RAILWAY_PRIVATE_DOMAIN}}
```

#### HAProxy:
```bash
PGPOOL_BACKENDS=${{pgpool-1.RAILWAY_PRIVATE_DOMAIN}}:5432,${{pgpool-2.RAILWAY_PRIVATE_DOMAIN}}:5432
```

---

### Bước 2: Clean Deployment

1. **Delete volumes:** Xóa tất cả volumes của pg-1, pg-2, pg-3, pg-4, witness
   - Railway Dashboard → Service → Settings → Volumes → Delete

2. **Redeploy theo thứ tự:**
   ```
   1. pg-1 (chờ đến khi thấy "repmgr user authentication test PASSED")
   2. pg-2, pg-3, pg-4 (deploy song song)
   3. witness
   4. pgpool-1, pgpool-2
   5. haproxy
   ```

3. **Verify cluster:**
   ```bash
   # Check logs
   railway logs -s pg-1 | grep -E "NOTICE|cluster"
   railway logs -s pg-2 | grep "standby.*connected"
   
   # Check repmgr cluster
   railway run -s pg-1 -- bash -c "su - postgres -c 'repmgr cluster show'"
   ```

---

### Bước 3: Success Criteria

**Logs nên thấy:**
- ✅ `new standby 'pg-2.railway.internal' (ID: 2) has connected`
- ✅ `repmgr user authentication test PASSED`
- ✅ Không có "password authentication failed"

**repmgr cluster show nên hiển thị:**
```
 ID | Name                    | Role    | Status    | Upstream              | Location
----+-------------------------+---------+-----------+-----------------------+----------
 1  | pg-1.railway.internal   | primary | * running |                       | default
 2  | pg-2.railway.internal   | standby |   running | pg-1.railway.internal | default
 3  | pg-3.railway.internal   | standby |   running | pg-1.railway.internal | default
 4  | pg-4.railway.internal   | standby |   running | pg-1.railway.internal | default
 5  | witness.railway.internal| witness | * running | pg-1.railway.internal | default
```

---

## 🔧 Tham khảo nhanh

### Railway Reference Variables
- `${{RAILWAY_PRIVATE_DOMAIN}}` = hostname của service hiện tại (e.g., pg-1.railway.internal)
- `${{service-name.VARIABLE_NAME}}` = truy cập variable của service khác
- Railway tự động inject, không cần hardcode .railway.internal

### Các lệnh hữu ích
```bash
# Check hostname trong container
railway run -s pg-1 -- hostname

# Test auth local
railway run -s pg-1 -- bash -c 'PGPASSWORD="$REPMGR_PASSWORD" psql -h localhost -U repmgr -d repmgr -c "SELECT 1"'

# Test auth remote
railway run -s pg-2 -- bash -c 'PGPASSWORD="$REPMGR_PASSWORD" psql -h pg-1.railway.internal -U repmgr -d repmgr -c "SELECT 1"'

# Check repmgr config
railway run -s pg-1 -- cat /etc/repmgr.conf

# Tail logs
railway logs -s pg-1 --limit 100
```

---

## 📝 Notes

- Password authentication OK (đã test local + remote)
- Vấn đề chỉ là hostname mismatch: pg-1 vs pg-1.railway.internal
- Tất cả code đã fix để support FQDN
- Đã commit và push lên GitHub (main branch)
- Chỉ cần update variables trên Railway Dashboard và redeploy

**Ưu tiên:** HIGH - Ready to deploy khi có thời gian

---

## 📞 Liên hệ khi gặp vấn đề

Nếu sau khi deploy vẫn có lỗi:
1. Check logs: `railway logs -s <service> | grep -i error`
2. Verify variables đã đúng format: Railway Dashboard → Service → Variables
3. Check hostname resolve: `railway run -s pg-1 -- ping pg-2.railway.internal`
4. Test manual connection giữa các nodes

---

**Git commits để reference:**
- `3ed7a85`: Railway reference variables in create-services.sh
- `2a189a5`: PRIMARY_HINT FQDN compatibility fixes

**Repo:** https://github.com/hiendt2907/pg-ha-repo  
**Branch:** main
