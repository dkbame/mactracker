#!/bin/bash

# Fix Tracker API 500 Internal Server Error
# The /health_check works but /health and /stats return 500 errors

set -e

PROJECT_ROOT="/opt/torrust"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status "Fixing Tracker API 500 Internal Server Error..."

cd "$PROJECT_ROOT"

# 1. Stop tracker container
print_status "1. Stopping tracker container..."
docker compose -f docker-compose-https.yml stop tracker

# 2. Remove tracker container completely
print_status "2. Removing tracker container..."
docker compose -f docker-compose-https.yml rm -f tracker

# 3. Backup and recreate database
print_status "3. Recreating tracker database..."
if [ -f "./storage/tracker/lib/database/sqlite3.db" ]; then
    print_status "Backing up existing database..."
    cp ./storage/tracker/lib/database/sqlite3.db ./storage/tracker/lib/database/sqlite3.db.backup
    rm ./storage/tracker/lib/database/sqlite3.db
fi

# Create fresh database directory
mkdir -p ./storage/tracker/lib/database
touch ./storage/tracker/lib/database/sqlite3.db
chmod 664 ./storage/tracker/lib/database/sqlite3.db
chown 1000:1000 ./storage/tracker/lib/database/sqlite3.db

# 4. Create minimal working tracker config
print_status "4. Creating minimal tracker configuration..."
cat > ./config/tracker.toml << 'EOF'
[metadata]
app = "torrust-tracker"
purpose = "configuration"
schema_version = "2.0.0"

[logging]
threshold = "debug"

[core]
inactive_peer_cleanup_interval = 120
listed = false
private = false

[core.database]
driver = "sqlite3"
path = "/var/lib/torrust/tracker/database/sqlite3.db"

[core.tracker_policy]
max_peer_timeout = 60
persistent_torrent_completed_stat = true
remove_peerless_torrents = true

[[http_trackers]]
bind_address = "0.0.0.0:7070"
tracker_usage_statistics = true

[http_api]
bind_address = "0.0.0.0:1212"

[http_api.access_tokens]
admin = "MyAccessToken"
EOF

print_success "Minimal tracker config created"

# 5. Start tracker container
print_status "5. Starting tracker container with fresh setup..."
docker compose -f docker-compose-https.yml up -d tracker

# 6. Wait for tracker to initialize
print_status "6. Waiting for tracker to initialize (this may take a minute)..."
sleep 30

# 7. Test endpoints in order
print_status "7. Testing tracker endpoints..."

# Test health_check first (this should work)
print_status "Testing /health_check endpoint..."
if curl -s http://127.0.0.1:1212/health_check | grep -q "healthy\|ok"; then
    print_success "/health_check endpoint working"
else
    print_warning "/health_check endpoint response:"
    curl -s http://127.0.0.1:1212/health_check || true
fi

# Test /api/health_check
print_status "Testing /api/health_check endpoint..."
if curl -s http://127.0.0.1:1212/api/health_check | grep -q "healthy\|ok"; then
    print_success "/api/health_check endpoint working"
else
    print_warning "/api/health_check endpoint response:"
    curl -s http://127.0.0.1:1212/api/health_check || true
fi

# Test /health endpoint
print_status "Testing /health endpoint..."
HEALTH_RESPONSE=$(curl -s http://127.0.0.1:1212/health 2>/dev/null || echo "ERROR")
if echo "$HEALTH_RESPONSE" | grep -q "healthy\|ok"; then
    print_success "/health endpoint working"
elif echo "$HEALTH_RESPONSE" | grep -q "ERROR"; then
    print_error "/health endpoint failed"
else
    print_warning "/health endpoint response: $HEALTH_RESPONSE"
fi

# Test /stats endpoint
print_status "Testing /stats endpoint..."
STATS_RESPONSE=$(curl -s http://127.0.0.1:1212/stats 2>/dev/null || echo "ERROR")
if echo "$STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "/stats endpoint working"
elif echo "$STATS_RESPONSE" | grep -q "ERROR"; then
    print_error "/stats endpoint failed"
else
    print_warning "/stats endpoint response: $STATS_RESPONSE"
fi

# Test with admin token
print_status "Testing /stats with admin token..."
STATS_TOKEN_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats 2>/dev/null || echo "ERROR")
if echo "$STATS_TOKEN_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "/stats with token working"
elif echo "$STATS_TOKEN_RESPONSE" | grep -q "ERROR"; then
    print_error "/stats with token failed"
else
    print_warning "/stats with token response: $STATS_TOKEN_RESPONSE"
fi

# Test HTTP tracker
print_status "Testing HTTP tracker..."
HTTP_TRACKER_RESPONSE=$(curl -s http://127.0.0.1:7070/announce 2>/dev/null || echo "ERROR")
if echo "$HTTP_TRACKER_RESPONSE" | grep -q "announce\|tracker"; then
    print_success "HTTP tracker working"
elif echo "$HTTP_TRACKER_RESPONSE" | grep -q "ERROR"; then
    print_error "HTTP tracker failed"
else
    print_warning "HTTP tracker response: $HTTP_TRACKER_RESPONSE"
fi

# 8. Check recent logs for any remaining errors
print_status "8. Checking recent tracker logs..."
docker compose -f docker-compose-https.yml logs --tail=10 tracker

# 9. If still having issues, try alternative endpoints
if ! curl -s http://127.0.0.1:1212/stats 2>/dev/null | grep -q "stats\|tracker"; then
    print_status "9. Trying alternative API endpoints..."
    
    # Try /api/stats
    print_status "Testing /api/stats endpoint..."
    API_STATS_RESPONSE=$(curl -s http://127.0.0.1:1212/api/stats 2>/dev/null || echo "ERROR")
    if echo "$API_STATS_RESPONSE" | grep -q "stats\|tracker"; then
        print_success "/api/stats endpoint working"
    else
        print_warning "/api/stats endpoint response: $API_STATS_RESPONSE"
    fi
    
    # Try /api/v1/stats
    print_status "Testing /api/v1/stats endpoint..."
    API_V1_STATS_RESPONSE=$(curl -s http://127.0.0.1:1212/api/v1/stats 2>/dev/null || echo "ERROR")
    if echo "$API_V1_STATS_RESPONSE" | grep -q "stats\|tracker"; then
        print_success "/api/v1/stats endpoint working"
    else
        print_warning "/api/v1/stats endpoint response: $API_V1_STATS_RESPONSE"
    fi
fi

# 10. Final status check
print_status "10. Final status check..."
docker compose -f docker-compose-https.yml ps tracker

print_status "Tracker 500 error fix completed!"
print_status ""
print_status "If /stats endpoint is still returning 500 errors, the issue may be:"
print_status "1. Database initialization problems"
print_status "2. Tracker version compatibility issues"
print_status "3. Missing API routes in the tracker version"
print_status ""
print_status "The HTTP tracker on port 7070 should work for announce requests even if the API has issues."
print_status ""
print_status "To monitor logs: docker compose -f docker-compose-https.yml logs -f tracker"
