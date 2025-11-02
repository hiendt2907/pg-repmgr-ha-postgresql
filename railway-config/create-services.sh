#!/usr/bin/env bash
# create-services.sh - Create all Railway services for PostgreSQL HA cluster
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "  Creating Railway Services & Setting Variables"
echo "=================================================="
echo ""

# Check Railway CLI
if ! command -v railway &> /dev/null; then
    echo "❌ Railway CLI not found"
    echo "Install: npm i -g @railway/cli"
    exit 1
fi

# Check authentication
if ! railway whoami &> /dev/null; then
    echo "❌ Not logged in to Railway"
    echo "Run: railway login"
    exit 1
fi

echo "✅ Railway CLI authenticated"
echo ""

# Check if project is linked
if ! railway status &> /dev/null; then
    echo "❌ No Railway project linked"
    echo "Run: railway link"
    echo "Or create new: railway init"
    exit 1
fi

echo "Current project:"
railway status
echo ""

# Read credentials file
CREDENTIALS_FILE=$(ls -t "$SCRIPT_DIR"/../railway-credentials-*.txt 2>/dev/null | head -1)
if [ -z "$CREDENTIALS_FILE" ]; then
    echo "❌ No credentials file found"
    echo "Run: ./setup-variables.sh first"
    exit 1
fi

echo "Using credentials from: $(basename "$CREDENTIALS_FILE")"
echo ""

# Parse passwords from credentials file
POSTGRES_PASSWORD=$(grep "^POSTGRES_PASSWORD=" "$CREDENTIALS_FILE" | cut -d'=' -f2)
REPMGR_PASSWORD=$(grep "^REPMGR_PASSWORD=" "$CREDENTIALS_FILE" | cut -d'=' -f2)
APP_READONLY_PASSWORD=$(grep "^APP_READONLY_PASSWORD=" "$CREDENTIALS_FILE" | cut -d'=' -f2)
APP_READWRITE_PASSWORD=$(grep "^APP_READWRITE_PASSWORD=" "$CREDENTIALS_FILE" | cut -d'=' -f2)
PCP_PASSWORD=$(grep "^PCP_PASSWORD=" "$CREDENTIALS_FILE" | cut -d'=' -f2)
HAPROXY_STATS_PASSWORD=$(grep "^HAPROXY_STATS_PASSWORD=" "$CREDENTIALS_FILE" | cut -d'=' -f2)

# Function to create service and set variables
create_service_with_vars() {
    local service_name=$1
    shift
    local vars=("$@")
    
    echo "📦 Creating service: $service_name"
    
    # Create empty service (without repo)
    if railway add --service "$service_name" 2>&1 | grep -q "already exists\|created"; then
        echo "  ✅ Service created (or already exists)"
    else
        echo "  ⚠️  Check service creation manually"
    fi
    
    # Link to this service
    echo "  🔗 Linking to service..."
    railway service "$service_name"
    
    # Set variables for this service
    echo "  📝 Setting variables..."
    local var_args=()
    for var in "${vars[@]}"; do
        var_args+=(--set "$var")
    done
    
    railway variables "${var_args[@]}" --skip-deploys
    
    echo "  ✅ Variables set for $service_name"
    echo ""
}

# Function to add volume to service
add_volume_to_service() {
    local service_name=$1
    local mount_path=$2
    
    echo "  💾 Adding volume to $service_name..."
    
    # Link to service first
    railway service "$service_name"
    
    # Add volume
    if railway volume add --mount-path "$mount_path" 2>&1; then
        echo "  ✅ Volume added (mount: $mount_path)"
    else
        echo "  ⚠️  Could not add volume via CLI - add manually in Dashboard"
    fi
}

# GitHub repo
GITHUB_REPO="hiendt2907/pg-ha-repo"

echo "=================================================="
echo "Step 1: Setting Shared Variables"
echo "=================================================="
echo ""

# Set shared variables (project-level, no service needed)
echo "Setting project-level shared variables..."
if railway variables \
    --set "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
    --set "REPMGR_PASSWORD=$REPMGR_PASSWORD" \
    --set "APP_READONLY_PASSWORD=$APP_READONLY_PASSWORD" \
    --set "APP_READWRITE_PASSWORD=$APP_READWRITE_PASSWORD" \
    --set "PCP_PASSWORD=$PCP_PASSWORD" \
    --set "HAPROXY_STATS_PASSWORD=$HAPROXY_STATS_PASSWORD" \
    --set "REPMGR_PROMOTE_MAX_LAG_SECS=5" \
    --skip-deploys 2>&1; then
    echo "✅ Shared variables set"
else
    echo "⚠️  Could not set shared variables via CLI"
    echo "   Please set them manually in Railway Dashboard → Shared Variables"
fi
echo ""

echo "=================================================="
echo "Step 2: Creating PostgreSQL Services"
echo "=================================================="
echo ""

# Create pg-1 with variables
create_service_with_vars "pg-1" \
    "NODE_NAME=\${{RAILWAY_PRIVATE_DOMAIN}}" \
    "NODE_ID=1" \
    "NODE_PRIORITY=100" \
    "PEERS=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}},\${{pg-2.RAILWAY_PRIVATE_DOMAIN}},\${{pg-3.RAILWAY_PRIVATE_DOMAIN}},\${{pg-4.RAILWAY_PRIVATE_DOMAIN}}" \
    "PRIMARY_HOST=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}}"

# Create pg-2 with variables
create_service_with_vars "pg-2" \
    "NODE_NAME=\${{RAILWAY_PRIVATE_DOMAIN}}" \
    "NODE_ID=2" \
    "NODE_PRIORITY=90" \
    "PEERS=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}},\${{pg-2.RAILWAY_PRIVATE_DOMAIN}},\${{pg-3.RAILWAY_PRIVATE_DOMAIN}},\${{pg-4.RAILWAY_PRIVATE_DOMAIN}}" \
    "PRIMARY_HOST=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}}"

# Create pg-3 with variables
create_service_with_vars "pg-3" \
    "NODE_NAME=\${{RAILWAY_PRIVATE_DOMAIN}}" \
    "NODE_ID=3" \
    "NODE_PRIORITY=80" \
    "PEERS=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}},\${{pg-2.RAILWAY_PRIVATE_DOMAIN}},\${{pg-3.RAILWAY_PRIVATE_DOMAIN}},\${{pg-4.RAILWAY_PRIVATE_DOMAIN}}" \
    "PRIMARY_HOST=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}}"

# Create pg-4 with variables
create_service_with_vars "pg-4" \
    "NODE_NAME=\${{RAILWAY_PRIVATE_DOMAIN}}" \
    "NODE_ID=4" \
    "NODE_PRIORITY=70" \
    "PEERS=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}},\${{pg-2.RAILWAY_PRIVATE_DOMAIN}},\${{pg-3.RAILWAY_PRIVATE_DOMAIN}},\${{pg-4.RAILWAY_PRIVATE_DOMAIN}}" \
    "PRIMARY_HOST=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}}"

# Create witness with variables
create_service_with_vars "witness" \
    "NODE_NAME=\${{RAILWAY_PRIVATE_DOMAIN}}" \
    "NODE_ID=100" \
    "NODE_PRIORITY=0" \
    "IS_WITNESS=true" \
    "PEERS=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}},\${{pg-2.RAILWAY_PRIVATE_DOMAIN}},\${{pg-3.RAILWAY_PRIVATE_DOMAIN}},\${{pg-4.RAILWAY_PRIVATE_DOMAIN}}" \
    "PRIMARY_HOST=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}}"

echo "=================================================="
echo "Step 3: Creating PgPool Services"
echo "=================================================="
echo ""

# Create pgpool-1 with variables
create_service_with_vars "pgpool-1" \
    "PGPOOL_NODE_ID=0" \
    "PGPOOL_HOSTNAME=\${{RAILWAY_PRIVATE_DOMAIN}}" \
    "PG_BACKENDS=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}}:5432,\${{pg-2.RAILWAY_PRIVATE_DOMAIN}}:5432,\${{pg-3.RAILWAY_PRIVATE_DOMAIN}}:5432,\${{pg-4.RAILWAY_PRIVATE_DOMAIN}}:5432" \
    "EXPORT_PLAINTEXT_POOLPWD=false" \
    "OTHER_PGPOOL_HOSTNAME=\${{pgpool-2.RAILWAY_PRIVATE_DOMAIN}}" \
    "OTHER_PGPOOL_PORT=5432" \
    "PGPOOL_WAIT_RETRIES=600" \
    "PGPOOL_WAIT_INTERVAL=2"

# Create pgpool-2 with variables
create_service_with_vars "pgpool-2" \
    "PGPOOL_NODE_ID=1" \
    "PGPOOL_HOSTNAME=\${{RAILWAY_PRIVATE_DOMAIN}}" \
    "PG_BACKENDS=\${{pg-1.RAILWAY_PRIVATE_DOMAIN}}:5432,\${{pg-2.RAILWAY_PRIVATE_DOMAIN}}:5432,\${{pg-3.RAILWAY_PRIVATE_DOMAIN}}:5432,\${{pg-4.RAILWAY_PRIVATE_DOMAIN}}:5432" \
    "EXPORT_PLAINTEXT_POOLPWD=false" \
    "OTHER_PGPOOL_HOSTNAME=\${{pgpool-1.RAILWAY_PRIVATE_DOMAIN}}" \
    "OTHER_PGPOOL_PORT=5432" \
    "PGPOOL_WAIT_RETRIES=600" \
    "PGPOOL_WAIT_INTERVAL=2"

echo "=================================================="
echo "Step 4: Creating HAProxy Service"
echo "=================================================="
echo ""

# Create haproxy with variables
create_service_with_vars "haproxy" \
    "PGPOOL_BACKENDS=\${{pgpool-1.RAILWAY_PRIVATE_DOMAIN}}:5432,\${{pgpool-2.RAILWAY_PRIVATE_DOMAIN}}:5432" \
    "HAPROXY_STATS_PORT=8404" \
    "HAPROXY_STATS_USER=admin"

echo "=================================================="
echo "Step 5: Adding Volumes to PostgreSQL Services"
echo "=================================================="
echo ""

# Add volumes to PostgreSQL data nodes
for service in pg-1 pg-2 pg-3 pg-4; do
    echo "Adding volume to $service..."
    add_volume_to_service "$service" "/var/lib/postgresql/data"
    echo ""
done

# Add volume to witness
echo "Adding volume to witness..."
add_volume_to_service "witness" "/var/lib/postgresql/data"
echo ""

echo "=================================================="
echo "✅ All Services Created with Variables & Volumes!"
echo "=================================================="
echo ""
echo "📋 NEXT STEPS - Go to Railway Dashboard:"
echo ""
echo "1. Open Railway Dashboard:"
echo "   https://railway.app/dashboard"
echo ""
echo "2. Set Shared Variables:"
echo "   ───────────────────────"
echo "   Go to: Project Settings → Shared Variables"
echo "   Copy from: $CREDENTIALS_FILE"
echo "   "
echo "   Required:"
echo "   • POSTGRES_PASSWORD"
echo "   • REPMGR_PASSWORD"
echo "   • APP_READONLY_PASSWORD"
echo "   • APP_READWRITE_PASSWORD"
echo "   • PCP_PASSWORD"
echo "   • HAPROXY_STATS_PASSWORD"
echo "   • REPMGR_PROMOTE_MAX_LAG_SECS=5"
echo ""
echo "3. For EACH service, connect GitHub repo:"
echo ""
echo "   PostgreSQL Services (pg-1, pg-2, pg-3, pg-4, witness):"
echo "   ───────────────────────────────────────────────────"
echo "   • Settings → Source → Connect Repo"
echo "   • Select: hiendt2907/pg-ha-repo"
echo "   • Root Directory: /"
echo "   • Dockerfile Path: postgresql-cluster/postgresql/Dockerfile"
echo "   • Branch: main"
echo ""
echo "   PgPool Services (pgpool-1, pgpool-2):"
echo "   ──────────────────────────────────────"
echo "   • Settings → Source → Connect Repo"
echo "   • Select: hiendt2907/pg-ha-repo"
echo "   • Root Directory: /"
echo "   • Dockerfile Path: postgresql-cluster/pgpool/Dockerfile"
echo "   • Branch: main"
echo ""
echo "   HAProxy Service (haproxy):"
echo "   ──────────────────────────"
echo "   • Settings → Source → Connect Repo"
echo "   • Select: hiendt2907/pg-ha-repo"
echo "   • Root Directory: /"
echo "   • Dockerfile Path: postgresql-cluster/haproxy/Dockerfile"
echo "   • Branch: main"
echo "   • Settings → Networking → Generate Domain ✅"
echo ""
echo "4. Verify Volumes (should be auto-created):"
echo "   ─────────────────────────────────────────"
echo "   • pg-1, pg-2, pg-3, pg-4, witness: /var/lib/postgresql/data"
echo "   • If not created, add manually in Settings → Volume"
echo ""
echo "5. Set Resources (optional, for production):"
echo "   • pg-1 to pg-4: 32 vCPU / 32 GB RAM"
echo "   • witness: 2 vCPU / 2 GB RAM"
echo "   • pgpool-1, pgpool-2: 16 vCPU / 32 GB RAM"
echo "   • haproxy: 8 vCPU / 4 GB RAM"
echo ""
echo "6. Deploy in order:"
echo "   a. Deploy pg-1 → wait until Active"
echo "   b. Deploy pg-2, pg-3, pg-4 → wait until Active"
echo "   c. Deploy witness → wait until Active"
echo "   d. Deploy pgpool-1, pgpool-2 → wait until Active"
echo "   e. Deploy haproxy → wait until Active (get public domain)"
echo ""
echo "7. Verify cluster:"
echo "   railway logs --service pg-1"
echo "   railway run --service pg-1 -- su - postgres -c 'repmgr cluster show'"
echo ""
echo "=================================================="
echo "📄 Credentials: $CREDENTIALS_FILE"
echo "=================================================="

