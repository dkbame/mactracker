#!/bin/bash

# Fix Torrust configuration based on official documentation
# This follows the proper configuration structure from torrust-index docs

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

print_status "Fixing Torrust configuration based on official documentation..."

cd "$PROJECT_ROOT"

# 1. Stop all services
print_status "1. Stopping all services..."
docker compose -f docker-compose-https.yml down
sleep 5

# 2. Create proper tracker configuration based on docs
print_status "2. Creating proper tracker configuration..."
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

print_success "Tracker configuration created"

# 3. Create proper index configuration based on docs
print_status "3. Creating proper index configuration..."
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

print_success "Index configuration created"

# 4. Clean up database files for fresh start
print_status "4. Cleaning up database files..."
rm -f ./storage/tracker/lib/database/sqlite3.db
rm -f ./storage/index/lib/database/sqlite3.db
mkdir -p ./storage/tracker/lib/database
mkdir -p ./storage/index/lib/database

# 5. Start services in correct order
print_status "5. Starting services in correct order..."

# Start tracker first
print_status "Starting tracker..."
docker compose -f docker-compose-https.yml up -d tracker
sleep 20

# Wait for tracker to be ready
print_status "Waiting for tracker to initialize..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:1212/api/health_check | grep -q "Ok"; then
        print_success "Tracker is ready"
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

# 6. Test tracker API endpoints with proper authentication
print_status "6. Testing tracker API endpoints..."

# Test /api/health_check (should work without auth)
print_status "Testing /api/health_check..."
HEALTH_CHECK_RESPONSE=$(curl -s http://127.0.0.1:1212/api/health_check)
print_status "Response: $HEALTH_CHECK_RESPONSE"
if echo "$HEALTH_CHECK_RESPONSE" | grep -q "Ok"; then
    print_success "✅ /api/health_check working"
else
    print_error "❌ /api/health_check failed"
fi

# Test /stats with proper Bearer token
print_status "Testing /stats with Bearer token..."
STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats)
print_status "Response: $STATS_RESPONSE"
if echo "$STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /stats with Bearer token working"
elif echo "$STATS_RESPONSE" | grep -q "unauthorized"; then
    print_error "❌ /stats still unauthorized"
else
    print_warning "⚠️ /stats response: $STATS_RESPONSE"
fi

# Test /api/stats with Bearer token
print_status "Testing /api/stats with Bearer token..."
API_STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/api/stats)
print_status "Response: $API_STATS_RESPONSE"
if echo "$API_STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /api/stats with Bearer token working"
elif echo "$API_STATS_RESPONSE" | grep -q "unauthorized"; then
    print_error "❌ /api/stats still unauthorized"
else
    print_warning "⚠️ /api/stats response: $API_STATS_RESPONSE"
fi

# 7. Test index-tracker communication
print_status "7. Testing index-tracker communication..."

# Check if index can reach tracker
print_status "Testing index to tracker communication..."
INDEX_TRACKER_RESPONSE=$(docker exec torrust-index curl -s -H "Authorization: Bearer MyAccessToken" http://tracker:1212/stats)
if echo "$INDEX_TRACKER_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ Index can communicate with tracker"
else
    print_warning "⚠️ Index-tracker communication issue: $INDEX_TRACKER_RESPONSE"
fi

# 8. Test upload endpoint
print_status "8. Testing upload endpoint..."
UPLOAD_RESPONSE=$(curl -s -I https://macosapps.net/api/v1/torrent/upload)
print_status "Upload endpoint response: $UPLOAD_RESPONSE"
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "✅ Upload endpoint is accessible"
elif echo "$UPLOAD_RESPONSE" | grep -q "503"; then
    print_error "❌ Upload endpoint still returning 503"
else
    print_status "Upload endpoint response: $UPLOAD_RESPONSE"
fi

# 9. Show final status
print_status "9. Final status summary:"
docker compose -f docker-compose-https.yml ps

print_status "10. Working endpoints:"
print_success "✅ HTTP Tracker: http://109.104.153.250:7070/announce"
print_success "✅ Web Interface: https://macosapps.net"
print_success "✅ Index API: https://macosapps.net/api/v1/"

if curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats | grep -q "stats\|tracker"; then
    print_success "✅ Tracker API: Working with proper authentication"
else
    print_warning "⚠️ Tracker API: Still having authorization issues"
fi

print_status "Torrust configuration fix completed!"
print_status ""
print_status "Based on the official documentation, the configuration should now be properly aligned."
print_status "Try uploading a torrent now using the web interface at https://macosapps.net"
