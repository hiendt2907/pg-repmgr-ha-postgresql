#!/usr/bin/env bash
# setup-variables.sh - Set up environment variables for Railway deployment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=================================================="
echo "  PostgreSQL HA Cluster - Variable Setup"
echo "=================================================="
echo ""

# Check if Railway CLI is installed
if ! command -v railway &> /dev/null; then
    echo "❌ Railway CLI not found"
    echo "Install: npm i -g @railway/cli"
    exit 1
fi

# Check if logged in
if ! railway whoami &> /dev/null; then
    echo "❌ Not logged in to Railway"
    echo "Run: railway login"
    exit 1
fi

echo "✅ Railway CLI authenticated"
echo ""

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

echo "Generating secure passwords..."
POSTGRES_PASSWORD=$(generate_password)
REPMGR_PASSWORD=$(generate_password)
APP_READONLY_PASSWORD=$(generate_password)
APP_READWRITE_PASSWORD=$(generate_password)
PCP_PASSWORD=$(generate_password)
HAPROXY_STATS_PASSWORD=$(generate_password)

echo "✅ Passwords generated"
echo ""

# Save credentials
CREDENTIALS_FILE="$PROJECT_ROOT/railway-credentials-$(date +%s).txt"
cat > "$CREDENTIALS_FILE" <<EOF
================================================
PostgreSQL HA Cluster - Railway Credentials
Generated: $(date)
================================================

⚠️  SAVE THESE CREDENTIALS SECURELY!

Shared Variables (set these in Railway Dashboard → Shared Variables):
--------------------------------------------------------------------
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REPMGR_PASSWORD=$REPMGR_PASSWORD
APP_READONLY_PASSWORD=$APP_READONLY_PASSWORD
APP_READWRITE_PASSWORD=$APP_READWRITE_PASSWORD
PCP_PASSWORD=$PCP_PASSWORD
HAPROXY_STATS_PASSWORD=$HAPROXY_STATS_PASSWORD

Service-Specific Variables:
--------------------------------------------------------------------

pg-1:
  NODE_NAME=pg-1
  REPMGR_NODE_ID=1
  NODE_PRIORITY=100
  PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
  PRIMARY_HOST=pg-1.railway.internal

pg-2:
  NODE_NAME=pg-2
  REPMGR_NODE_ID=2
  NODE_PRIORITY=90
  PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
  PRIMARY_HOST=pg-1.railway.internal

pg-3:
  NODE_NAME=pg-3
  REPMGR_NODE_ID=3
  NODE_PRIORITY=80
  PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
  PRIMARY_HOST=pg-1.railway.internal

pg-4:
  NODE_NAME=pg-4
  REPMGR_NODE_ID=4
  NODE_PRIORITY=70
  PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
  PRIMARY_HOST=pg-1.railway.internal

witness:
  NODE_NAME=witness
  REPMGR_NODE_ID=100
  NODE_PRIORITY=0
  PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal
  PRIMARY_HOST=pg-1.railway.internal

pgpool-1:
  PGPOOL_NODE_ID=0
  PGPOOL_HOSTNAME=pgpool-1.railway.internal
  PG_BACKENDS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432
  EXPORT_PLAINTEXT_POOLPWD=false
  OTHER_PGPOOL_HOSTNAME=pgpool-2.railway.internal
  OTHER_PGPOOL_PORT=5432
  PGPOOL_WAIT_RETRIES=600
  PGPOOL_WAIT_INTERVAL=2

pgpool-2:
  PGPOOL_NODE_ID=1
  PGPOOL_HOSTNAME=pgpool-2.railway.internal
  PG_BACKENDS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432
  EXPORT_PLAINTEXT_POOLPWD=false
  OTHER_PGPOOL_HOSTNAME=pgpool-1.railway.internal
  OTHER_PGPOOL_PORT=5432
  PGPOOL_WAIT_RETRIES=600
  PGPOOL_WAIT_INTERVAL=2

haproxy:
  PGPOOL_BACKENDS=pgpool-1.railway.internal:5432,pgpool-2.railway.internal:5432
  HAPROXY_STATS_PORT=8404
  HAPROXY_STATS_USER=admin

================================================
EOF

chmod 600 "$CREDENTIALS_FILE"
echo "✅ Credentials saved to: $CREDENTIALS_FILE"
echo ""

# Try to set shared variables via CLI
echo "Attempting to set shared variables via CLI..."
echo ""

if railway variables \
    --set "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
    --set "REPMGR_PASSWORD=$REPMGR_PASSWORD" \
    --set "APP_READONLY_PASSWORD=$APP_READONLY_PASSWORD" \
    --set "APP_READWRITE_PASSWORD=$APP_READWRITE_PASSWORD" \
    --set "PCP_PASSWORD=$PCP_PASSWORD" \
    --set "HAPROXY_STATS_PASSWORD=$HAPROXY_STATS_PASSWORD" \
    --set "REPMGR_PROMOTE_MAX_LAG_SECS=5" \
    --skip-deploys 2>/dev/null; then
    echo "✅ Shared variables set via CLI"
else
    echo "⚠️  Could not set variables via CLI"
    echo "Please set them manually in Railway Dashboard:"
    echo "  1. Go to your project settings"
    echo "  2. Navigate to 'Shared Variables'"
    echo "  3. Copy variables from: $CREDENTIALS_FILE"
fi

echo ""
echo "=================================================="
echo "  DEPLOYMENT STEPS"
echo "=================================================="
echo ""
echo "1. Set up shared variables in Railway Dashboard"
echo "   (if not set automatically above)"
echo ""
echo "2. Create services using railway-services.json:"
echo "   - Use 'railway up' or Railway Dashboard"
echo "   - Or create services manually and set variables"
echo ""
echo "3. Configure volumes for each PostgreSQL service:"
echo "   - pg-1, pg-2, pg-3, pg-4: Mount at /var/lib/postgresql/data (100GB)"
echo "   - witness: Mount at /var/lib/postgresql/data (10GB)"
echo ""
echo "4. Deploy in order:"
echo "   a. pg-1 (wait until healthy)"
echo "   b. pg-2, pg-3, pg-4 (deploy together)"
echo "   c. witness"
echo "   d. pgpool-1, pgpool-2 (deploy together)"
echo "   e. haproxy (last)"
echo ""
echo "5. Enable public domain for haproxy service only"
echo ""
echo "6. Verify cluster:"
echo "   railway run --service pg-1 -- repmgr cluster show"
echo ""
echo "=================================================="
echo "✅ Setup complete!"
echo "=================================================="
echo ""
echo "📄 All credentials and variables: $CREDENTIALS_FILE"
echo ""
