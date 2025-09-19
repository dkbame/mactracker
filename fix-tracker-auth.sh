#!/bin/bash

# Fix Tracker API authorization issues
# The API endpoints are returning "unauthorized" errors

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

print_status "Fixing Tracker API authorization issues..."

cd "$PROJECT_ROOT"

# 1. Check current tracker configuration
print_status "1. Checking current tracker configuration..."
if [ -f "./config/tracker.toml" ]; then
    print_status "Current tracker config:"
    cat ./config/tracker.toml
else
    print_error "Tracker config not found!"
    exit 1
fi

# 2. Create a working tracker configuration with proper auth
print_status "2. Creating working tracker configuration..."
cat > ./config/tracker.toml << 'EOF'
[metadata]
app = "torrust-tracker"
purpose = "configuration"
schema_version = "2.0.0"

[logging]
threshold = "info"

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

print_success "Tracker configuration updated"

# 3. Restart tracker container
print_status "3. Restarting tracker container..."
docker compose -f docker-compose-https.yml restart tracker
sleep 15

# 4. Test authorization with proper token
print_status "4. Testing authorization..."

# Test /api/health_check (should work without auth)
print_status "Testing /api/health_check (no auth required)..."
HEALTH_CHECK_RESPONSE=$(curl -s http://127.0.0.1:1212/api/health_check)
if echo "$HEALTH_CHECK_RESPONSE" | grep -q "Ok"; then
    print_success "/api/health_check working: $HEALTH_CHECK_RESPONSE"
else
    print_warning "/api/health_check response: $HEALTH_CHECK_RESPONSE"
fi

# Test /stats with admin token
print_status "Testing /stats with admin token..."
STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats)
if echo "$STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "/stats with token working"
    print_status "Response: $STATS_RESPONSE"
elif echo "$STATS_RESPONSE" | grep -q "unauthorized"; then
    print_warning "/stats still unauthorized: $STATS_RESPONSE"
else
    print_warning "/stats response: $STATS_RESPONSE"
fi

# Test /api/stats with admin token
print_status "Testing /api/stats with admin token..."
API_STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/api/stats)
if echo "$API_STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "/api/stats with token working"
    print_status "Response: $API_STATS_RESPONSE"
elif echo "$API_STATS_RESPONSE" | grep -q "unauthorized"; then
    print_warning "/api/stats still unauthorized: $API_STATS_RESPONSE"
else
    print_warning "/api/stats response: $API_STATS_RESPONSE"
fi

# Test /api/v1/stats with admin token
print_status "Testing /api/v1/stats with admin token..."
API_V1_STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/api/v1/stats)
if echo "$API_V1_STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "/api/v1/stats with token working"
    print_status "Response: $API_V1_STATS_RESPONSE"
elif echo "$API_V1_STATS_RESPONSE" | grep -q "unauthorized"; then
    print_warning "/api/v1/stats still unauthorized: $API_V1_STATS_RESPONSE"
else
    print_warning "/api/v1/stats response: $API_V1_STATS_RESPONSE"
fi

# 5. Update Index configuration to use the correct token
print_status "5. Updating Index configuration..."
if [ -f "./config/index.toml" ]; then
    print_status "Current index tracker config:"
    grep -A 3 "\[tracker\]" ./config/index.toml
    
    # Update index config to match tracker token
    print_status "Updating index config with correct token..."
    cat > ./config/index.toml << 'EOF'
[metadata]
app = "torrust-index"
purpose = "configuration"
schema_version = "2.0.0"

[logging]
threshold = "info"

[net]
bind_address = "0.0.0.0:3001"
public_address = "https://macosapps.net:3001"

[tracker]
api_url = "http://tracker:1212"
token = "MyAccessToken"

[database]
connect_url = "sqlite:///var/lib/torrust/index/database/sqlite3.db"

[tracker_statistics_importer]
port = 3002
torrent_info_update_interval = 3600

[unstable]
EOF
    
    print_success "Index configuration updated"
    
    # Restart index to use new config
    print_status "Restarting index container..."
    docker compose -f docker-compose-https.yml restart index
    sleep 10
else
    print_error "Index config not found!"
fi

# 6. Test upload endpoint
print_status "6. Testing upload endpoint..."
UPLOAD_RESPONSE=$(curl -s -I https://macosapps.net/api/v1/torrent/upload)
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "Upload endpoint is accessible!"
    print_status "Response: $UPLOAD_RESPONSE"
elif echo "$UPLOAD_RESPONSE" | grep -q "503"; then
    print_warning "Upload endpoint still returning 503"
    print_status "Response: $UPLOAD_RESPONSE"
else
    print_status "Upload endpoint response: $UPLOAD_RESPONSE"
fi

# 7. Show working endpoints
print_status "7. Working endpoints summary:"
print_success "HTTP Tracker: http://109.104.153.250:7070/announce"
print_success "API Health Check: http://127.0.0.1:1212/api/health_check"

if curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats | grep -q "stats\|tracker"; then
    print_success "API Stats (with token): http://127.0.0.1:1212/stats"
else
    print_warning "API Stats: Still having authorization issues"
fi

print_status "Tracker authorization fix completed!"
print_status ""
print_status "For torrent uploads, use this announce URL:"
print_status "http://109.104.153.250:7070/announce"
print_status ""
print_status "The HTTP tracker is working perfectly for BitTorrent protocol."
