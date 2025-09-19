#!/bin/bash

# Fix empty responses from tracker API
# This addresses the specific issue where endpoints return empty responses

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

print_status "Fixing empty responses from tracker API..."

cd "$PROJECT_ROOT"

# 1. Stop all services
print_status "1. Stopping all services..."
docker compose -f docker-compose-https.yml down
sleep 5

# 2. Clean up containers and volumes
print_status "2. Cleaning up containers and volumes..."
docker compose -f docker-compose-https.yml rm -f
docker volume prune -f

# 3. Remove and recreate database files
print_status "3. Recreating database files..."
rm -rf ./storage/tracker/lib/database/*
rm -rf ./storage/index/lib/database/*
mkdir -p ./storage/tracker/lib/database
mkdir -p ./storage/index/lib/database

# 4. Create a working tracker configuration
print_status "4. Creating working tracker configuration..."
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

# 5. Create a working index configuration
print_status "5. Creating working index configuration..."
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

# 6. Start services one by one with proper waiting
print_status "6. Starting services with proper initialization..."

# Start tracker first
print_status "Starting tracker..."
docker compose -f docker-compose-https.yml up -d tracker

# Wait for tracker to fully initialize
print_status "Waiting for tracker to initialize (30 seconds)..."
sleep 30

# Check if tracker is responding
print_status "Checking tracker initialization..."
for i in {1..10}; do
    if curl -s http://127.0.0.1:1212/api/health_check | grep -q "Ok"; then
        print_success "Tracker is responding"
        break
    elif [ $i -eq 10 ]; then
        print_error "Tracker failed to initialize"
        docker compose -f docker-compose-https.yml logs tracker
        exit 1
    else
        print_status "Waiting for tracker... ($i/10)"
        sleep 5
    fi
done

# Start index
print_status "Starting index..."
docker compose -f docker-compose-https.yml up -d index

# Wait for index to initialize
print_status "Waiting for index to initialize (20 seconds)..."
sleep 20

# Start GUI
print_status "Starting GUI..."
docker compose -f docker-compose-https.yml up -d gui

# Wait for GUI to start
sleep 10

# 7. Test all endpoints thoroughly
print_status "7. Testing all endpoints thoroughly..."

# Test tracker health
print_status "Testing tracker health endpoint..."
HEALTH_RESPONSE=$(curl -s http://127.0.0.1:1212/api/health_check)
print_status "Health response: $HEALTH_RESPONSE"
if echo "$HEALTH_RESPONSE" | grep -q "Ok"; then
    print_success "✅ Tracker health working"
else
    print_error "❌ Tracker health failed"
fi

# Test tracker stats with different methods
print_status "Testing tracker stats endpoint..."

# Method 1: Bearer token
STATS_BEARER=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats)
print_status "Stats with Bearer token: $STATS_BEARER"

# Method 2: Token header
STATS_TOKEN=$(curl -s -H "Token: MyAccessToken" http://127.0.0.1:1212/stats)
print_status "Stats with Token header: $STATS_TOKEN"

# Method 3: Query parameter
STATS_QUERY=$(curl -s "http://127.0.0.1:1212/stats?token=MyAccessToken")
print_status "Stats with query param: $STATS_QUERY"

# Method 4: /api/stats
API_STATS=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/api/stats)
print_status "API stats response: $API_STATS"

# Check which method works
if echo "$STATS_BEARER" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /stats with Bearer token working"
elif echo "$STATS_TOKEN" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /stats with Token header working"
elif echo "$STATS_QUERY" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /stats with query parameter working"
elif echo "$API_STATS" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /api/stats working"
else
    print_error "❌ All stats endpoints returning empty or invalid responses"
fi

# Test HTTP tracker
print_status "Testing HTTP tracker..."
HTTP_TRACKER_RESPONSE=$(curl -s http://127.0.0.1:7070/announce)
print_status "HTTP tracker response: $HTTP_TRACKER_RESPONSE"
if echo "$HTTP_TRACKER_RESPONSE" | grep -q "announce\|tracker"; then
    print_success "✅ HTTP tracker working"
else
    print_error "❌ HTTP tracker failed"
fi

# Test index API
print_status "Testing index API..."
INDEX_RESPONSE=$(curl -s http://127.0.0.1:3001/v1/settings/public)
print_status "Index response: $INDEX_RESPONSE"
if echo "$INDEX_RESPONSE" | grep -q "tracker\|api"; then
    print_success "✅ Index API working"
else
    print_error "❌ Index API failed"
fi

# Test upload endpoint
print_status "Testing upload endpoint..."
UPLOAD_RESPONSE=$(curl -s -I https://macosapps.net/api/v1/torrent/upload)
print_status "Upload endpoint response: $UPLOAD_RESPONSE"
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "✅ Upload endpoint accessible"
elif echo "$UPLOAD_RESPONSE" | grep -q "503"; then
    print_error "❌ Upload endpoint returning 503"
else
    print_status "Upload endpoint response: $UPLOAD_RESPONSE"
fi

# 8. Final status
print_status "8. Final service status:"
docker compose -f docker-compose-https.yml ps

print_status "Empty responses fix completed!"
print_status ""
print_status "If tracker API endpoints are still returning empty responses,"
print_status "the issue may be with the tracker version or Docker image."
print_status "The HTTP tracker should work regardless for BitTorrent protocol."
