#!/usr/bin/env bash
# deploy-railway.sh - Helper script to deploy PostgreSQL HA cluster to Railway
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=================================================="
echo "  PostgreSQL HA Cluster - Railway Deployment"
echo "=================================================="
echo ""

# Check if Railway CLI is installed
if ! command -v railway &> /dev/null; then
    echo "❌ Railway CLI not found. Installing..."
    echo ""
    echo "Please install Railway CLI first:"
    echo "  npm i -g @railway/cli"
    echo "  or: brew install railway"
    echo ""
    echo "Then run: railway login"
    echo ""
    exit 1
fi

# Check if logged in
if ! railway whoami &> /dev/null; then
    echo "❌ Not logged in to Railway"
    echo "Please run: railway login"
    exit 1
fi

echo "✅ Railway CLI found and authenticated"
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

echo "✅ Passwords generated"
echo ""

# Check if project exists
echo "Checking Railway project..."
if ! railway status &> /dev/null; then
    echo "Creating new Railway project..."
    railway init -n "pg-ha-cluster"
    echo "✅ Project created"
else
    echo "✅ Using existing project"
fi
echo ""

# Set shared variables
echo "Setting shared variables (project-level)..."
railway variables \
    --set "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
    --set "REPMGR_PASSWORD=$REPMGR_PASSWORD" \
    --set "APP_READONLY_PASSWORD=$APP_READONLY_PASSWORD" \
    --set "APP_READWRITE_PASSWORD=$APP_READWRITE_PASSWORD" \
    --set "REPMGR_PROMOTE_MAX_LAG_SECS=10" \
    --set "RETRY_INTERVAL=5" \
    --set "RETRY_ROUNDS=36" \
    --skip-deploys

echo "✅ Shared variables set"
echo ""

# Save passwords to a secure file
CREDENTIALS_FILE="$PROJECT_ROOT/railway-credentials-$(date +%s).txt"
cat > "$CREDENTIALS_FILE" <<EOF
================================================
PostgreSQL HA Cluster - Railway Credentials
Generated: $(date)
================================================

⚠️  IMPORTANT: Save these credentials securely!
⚠️  This file will not be regenerated.

POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REPMGR_PASSWORD=$REPMGR_PASSWORD
APP_READONLY_PASSWORD=$APP_READONLY_PASSWORD
APP_READWRITE_PASSWORD=$APP_READWRITE_PASSWORD

================================================
Connection Info (after deployment):
================================================

To get connection details:
  railway variables --service pg-1

Example connection string:
  postgresql://postgres:$POSTGRES_PASSWORD@pg-1.railway.internal:5432/postgres

For external access:
  1. Enable TCP Proxy on pg-1 service
  2. Get proxy details: railway variables --service pg-1 | grep TCP
  3. Connect to: RAILWAY_TCP_PROXY_DOMAIN:RAILWAY_TCP_PROXY_PORT

================================================
EOF

chmod 600 "$CREDENTIALS_FILE"
echo "✅ Credentials saved to: $CREDENTIALS_FILE"
echo ""

# Deploy services
echo "=================================================="
echo "Deploying services..."
echo "=================================================="
echo ""

services=("pg-1" "pg-2" "pg-3" "pg-4" "witness")

for service in "${services[@]}"; do
    echo "📦 Creating service: $service"
    
    # Determine service-specific variables
    if [ "$service" = "witness" ]; then
        NODE_ID=99
        IS_WITNESS=true
    else
        NODE_ID="${service#pg-}"
        IS_WITNESS=false
    fi
    
    # Check if service exists, create if not
    echo "  Checking if service exists..."
    if ! railway service "$service" 2>/dev/null; then
        echo "  Creating service..."
        railway service create "$service" || echo "  Note: Service may already exist"
    fi
    
    # Set service variables
    echo "  Setting variables for $service..."
    railway variables \
        --service "$service" \
        --set "NODE_NAME=$service" \
        --set "NODE_ID=$NODE_ID" \
        --set "PRIMARY_HINT=pg-1.railway.internal" \
        --set "IS_WITNESS=$IS_WITNESS" \
        --set "PEERS=pg-1.railway.internal:5432,pg-2.railway.internal:5432,pg-3.railway.internal:5432,pg-4.railway.internal:5432,witness.railway.internal:5432" \
        --skip-deploys || echo "  ⚠️  Could not set variables automatically"
    
    echo "  ✅ Service $service configured"
done

echo ""
echo "=================================================="
echo "⚠️  MANUAL STEPS REQUIRED:"
echo "=================================================="
echo ""
echo "1. For each service (pg-1, pg-2, pg-3, pg-4, witness):"
echo "   a. Go to Railway dashboard"
echo "   b. Select the service"
echo "   c. Go to Settings → Volume"
echo "   d. Create volume with mount path: /var/lib/postgresql/data"
echo "   e. For data nodes (pg-1 to pg-4): 10GB+"
echo "   f. For witness: 1-2GB is enough"
echo ""
echo "2. Deploy order (IMPORTANT):"
echo "   a. Deploy pg-1 first (wait until healthy)"
echo "   b. Deploy pg-2, pg-3, pg-4 (can deploy together)"
echo "   c. Deploy witness last"
echo ""
echo "3. Monitor deployment:"
echo "   railway logs --service pg-1"
echo ""
echo "4. Verify cluster health:"
echo "   railway run --service pg-1 psql -U repmgr -d repmgr -c 'SELECT * FROM repmgr.show_nodes();'"
echo ""
echo "=================================================="
echo "✅ Deployment preparation complete!"
echo "=================================================="
echo ""
echo "📄 Credentials saved to: $CREDENTIALS_FILE"
echo ""
