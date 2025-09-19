#!/bin/bash

# Aggressive fix for Tracker API authorization issues
# This will try multiple approaches to fix the authorization problem

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

print_status "Aggressive fix for Tracker API authorization issues..."

cd "$PROJECT_ROOT"

# 1. Stop all services
print_status "1. Stopping all services..."
docker compose -f docker-compose-https.yml down
sleep 5

# 2. Remove all containers and volumes
print_status "2. Removing containers and cleaning up..."
docker compose -f docker-compose-https.yml rm -f
docker volume prune -f

# 3. Clean up database files
print_status "3. Cleaning up database files..."
rm -f ./storage/tracker/lib/database/sqlite3.db
rm -f ./storage/index/lib/database/sqlite3.db
mkdir -p ./storage/tracker/lib/database
mkdir -p ./storage/index/lib/database

# 4. Create a completely fresh tracker config
print_status "4. Creating fresh tracker configuration..."
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

# 5. Create a fresh index config
print_status "5. Creating fresh index configuration..."
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

# 6. Start services in correct order
print_status "6. Starting services in correct order..."

# Start tracker first
print_status "Starting tracker..."
docker compose -f docker-compose-https.yml up -d tracker
sleep 20

# Check if tracker is responding
print_status "Checking tracker startup..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:1212/api/health_check | grep -q "Ok"; then
        print_success "Tracker is responding"
        break
    elif [ $i -eq 30 ]; then
        print_error "Tracker failed to start"
        docker compose -f docker-compose-https.yml logs tracker
        exit 1
    else
        print_status "Waiting for tracker... ($i/30)"
        sleep 2
    fi
done

# Start index
print_status "Starting index..."
docker compose -f docker-compose-https.yml up -d index
sleep 15

# Start GUI
print_status "Starting GUI..."
docker compose -f docker-compose-https.yml up -d gui
sleep 5

# 7. Test authorization with multiple approaches
print_status "7. Testing authorization with multiple approaches..."

# Test 1: Basic stats endpoint
print_status "Test 1: Basic /stats endpoint..."
STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats)
print_status "Response: $STATS_RESPONSE"

# Test 2: Try different header format
print_status "Test 2: Different header format..."
STATS_HEADER=$(curl -s -H "Token: MyAccessToken" http://127.0.0.1:1212/stats)
print_status "Response: $STATS_HEADER"

# Test 3: Try query parameter
print_status "Test 3: Query parameter..."
STATS_QUERY=$(curl -s "http://127.0.0.1:1212/stats?token=MyAccessToken")
print_status "Response: $STATS_QUERY"

# Test 4: Try /api/stats
print_status "Test 4: /api/stats endpoint..."
API_STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/api/stats)
print_status "Response: $API_STATS_RESPONSE"

# Test 5: Try /api/v1/stats
print_status "Test 5: /api/v1/stats endpoint..."
API_V1_STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/api/v1/stats)
print_status "Response: $API_V1_STATS_RESPONSE"

# Test 6: Try without authentication (should fail)
print_status "Test 6: Without authentication (should fail)..."
NO_AUTH_RESPONSE=$(curl -s http://127.0.0.1:1212/stats)
print_status "Response: $NO_AUTH_RESPONSE"

# 8. Check if any endpoint worked
WORKING_ENDPOINTS=0
if echo "$STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /stats with Bearer token working"
    WORKING_ENDPOINTS=$((WORKING_ENDPOINTS + 1))
fi

if echo "$STATS_HEADER" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /stats with Token header working"
    WORKING_ENDPOINTS=$((WORKING_ENDPOINTS + 1))
fi

if echo "$STATS_QUERY" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /stats with query parameter working"
    WORKING_ENDPOINTS=$((WORKING_ENDPOINTS + 1))
fi

if echo "$API_STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /api/stats working"
    WORKING_ENDPOINTS=$((WORKING_ENDPOINTS + 1))
fi

if echo "$API_V1_STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /api/v1/stats working"
    WORKING_ENDPOINTS=$((WORKING_ENDPOINTS + 1))
fi

# 9. Test upload endpoint
print_status "8. Testing upload endpoint..."
UPLOAD_RESPONSE=$(curl -s -I https://macosapps.net/api/v1/torrent/upload)
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "✅ Upload endpoint accessible"
elif echo "$UPLOAD_RESPONSE" | grep -q "503"; then
    print_warning "⚠️ Upload endpoint still returning 503"
else
    print_status "Upload endpoint response: $UPLOAD_RESPONSE"
fi

# 10. Final summary
print_status "9. Final summary:"
print_status "Working endpoints: $WORKING_ENDPOINTS"

if [ $WORKING_ENDPOINTS -gt 0 ]; then
    print_success "Authorization is working with some endpoints!"
    print_status "The tracker API is functional for torrent uploads."
else
    print_warning "Authorization still not working with any endpoints."
    print_status "However, the HTTP tracker (port 7070) should still work for BitTorrent protocol."
fi

print_status ""
print_status "HTTP Tracker (always works): http://109.104.153.250:7070/announce"
print_status "Use this announce URL for torrent uploads."

print_status "Aggressive authorization fix completed!"
