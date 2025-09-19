#!/bin/bash

# Debug tracker API issues - empty responses and container restarts
# This script will identify the root cause and fix it

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

print_status "Debugging tracker API issues..."

cd "$PROJECT_ROOT"

# 1. Check container status
print_status "1. Checking container status..."
docker compose -f docker-compose-https.yml ps

# 2. Check tracker logs for errors
print_status "2. Checking tracker logs for errors..."
print_status "Recent tracker logs:"
docker compose -f docker-compose-https.yml logs --tail=20 tracker

# 3. Check index logs for errors
print_status "3. Checking index logs for errors..."
print_status "Recent index logs:"
docker compose -f docker-compose-https.yml logs --tail=20 index

# 4. Test tracker endpoints with verbose output
print_status "4. Testing tracker endpoints with verbose output..."

# Test /api/health_check
print_status "Testing /api/health_check with verbose output..."
curl -v http://127.0.0.1:1212/api/health_check 2>&1 | head -20

# Test /stats with verbose output
print_status "Testing /stats with verbose output..."
curl -v -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats 2>&1 | head -20

# Test /api/stats with verbose output
print_status "Testing /api/stats with verbose output..."
curl -v -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/api/stats 2>&1 | head -20

# 5. Check if tracker is actually listening on the right ports
print_status "5. Checking port bindings..."
netstat -tlnp | grep -E ":(1212|7070)" || print_warning "Ports not found"

# 6. Check tracker configuration
print_status "6. Checking tracker configuration..."
if [ -f "./config/tracker.toml" ]; then
    print_status "Tracker config contents:"
    cat ./config/tracker.toml
else
    print_error "Tracker config missing!"
fi

# 7. Check if there are any permission issues
print_status "7. Checking database permissions..."
ls -la ./storage/tracker/lib/database/ 2>/dev/null || print_warning "Database directory not accessible"

# 8. Try to restart tracker with fresh configuration
print_status "8. Restarting tracker with fresh configuration..."

# Stop tracker
docker compose -f docker-compose-https.yml stop tracker

# Remove tracker container
docker compose -f docker-compose-https.yml rm -f tracker

# Create a minimal working tracker config
print_status "Creating minimal tracker configuration..."
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

# Start tracker
print_status "Starting tracker with fresh config..."
docker compose -f docker-compose-https.yml up -d tracker

# Wait for tracker to start
sleep 20

# 9. Test again
print_status "9. Testing tracker endpoints after restart..."

# Test /api/health_check
print_status "Testing /api/health_check..."
HEALTH_RESPONSE=$(curl -s http://127.0.0.1:1212/api/health_check)
print_status "Response: $HEALTH_RESPONSE"

# Test /stats
print_status "Testing /stats..."
STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats)
print_status "Response: $STATS_RESPONSE"

# Test /api/stats
print_status "Testing /api/stats..."
API_STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/api/stats)
print_status "Response: $API_STATS_RESPONSE"

# 10. Check if any endpoint is working
print_status "10. Final status check..."
if echo "$HEALTH_RESPONSE" | grep -q "Ok"; then
    print_success "✅ /api/health_check working"
else
    print_error "❌ /api/health_check failed"
fi

if echo "$STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /stats working"
elif [ -n "$STATS_RESPONSE" ]; then
    print_warning "⚠️ /stats returned: $STATS_RESPONSE"
else
    print_error "❌ /stats returned empty response"
fi

if echo "$API_STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /api/stats working"
elif [ -n "$API_STATS_RESPONSE" ]; then
    print_warning "⚠️ /api/stats returned: $API_STATS_RESPONSE"
else
    print_error "❌ /api/stats returned empty response"
fi

# 11. Show final container status
print_status "11. Final container status:"
docker compose -f docker-compose-https.yml ps

print_status "Debug completed!"
print_status "Check the logs above for any error messages that might indicate the root cause."
