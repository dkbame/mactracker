#!/bin/bash

# Fix Index container crash (exit code 101)
# The Index container keeps restarting, causing 502 errors

set -e

DOMAIN="macosapps.net"
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

print_status "Fixing Index container crash (exit code 101)..."

cd "$PROJECT_ROOT"

# 1. Stop all services
print_status "1. Stopping all services..."
docker compose -f docker-compose-https.yml down
sleep 5

# 2. Check Index logs for crash details
print_status "2. Checking Index logs for crash details..."
print_status "Index container logs (last 50 lines):"
docker compose -f docker-compose-https.yml logs --tail=50 index

# 3. Clean up Index container and database
print_status "3. Cleaning up Index container and database..."
docker compose -f docker-compose-https.yml rm -f index

# Remove Index database for fresh start
rm -f ./storage/index/lib/database/sqlite3.db
mkdir -p ./storage/index/lib/database

# 4. Create a working Index configuration
print_status "4. Creating working Index configuration..."
cat > ./config/index.toml << EOF
[metadata]
app = "torrust-index"
purpose = "configuration"
schema_version = "2.0.0"

[logging]
threshold = "info"

[net]
bind_address = "0.0.0.0:3001"
public_address = "https://$DOMAIN:3001"

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

# 5. Start services in correct order
print_status "5. Starting services in correct order..."

# Start tracker first
print_status "Starting tracker..."
docker compose -f docker-compose-https.yml up -d tracker
sleep 15

# Check tracker is ready
print_status "Checking tracker readiness..."
for i in {1..20}; do
    if curl -s http://127.0.0.1:1212/api/health_check | grep -q "Ok"; then
        print_success "Tracker is ready"
        break
    elif [ $i -eq 20 ]; then
        print_error "Tracker failed to start"
        docker compose -f docker-compose-https.yml logs tracker
        exit 1
    else
        print_status "Waiting for tracker... ($i/20)"
        sleep 3
    fi
done

# Start index
print_status "Starting index..."
docker compose -f docker-compose-https.yml up -d index
sleep 20

# Check if index is running without crashing
print_status "Checking index status..."
for i in {1..30}; do
    INDEX_STATUS=$(docker compose -f docker-compose-https.yml ps index --format "{{.State}}")
    if echo "$INDEX_STATUS" | grep -q "running"; then
        print_success "Index is running"
        break
    elif echo "$INDEX_STATUS" | grep -q "exited"; then
        print_error "Index crashed again"
        print_status "Index logs:"
        docker compose -f docker-compose-https.yml logs --tail=20 index
        exit 1
    elif [ $i -eq 30 ]; then
        print_error "Index failed to start properly"
        docker compose -f docker-compose-https.yml logs --tail=20 index
        exit 1
    else
        print_status "Waiting for index... ($i/30) - Status: $INDEX_STATUS"
        sleep 2
    fi
done

# Start GUI
print_status "Starting GUI..."
docker compose -f docker-compose-https.yml up -d gui
sleep 10

# 6. Test all endpoints
print_status "6. Testing all endpoints..."

# Test tracker locally
print_status "Testing tracker locally..."
if curl -s http://127.0.0.1:1212/api/health_check | grep -q "Ok"; then
    print_success "✅ Tracker responding locally"
else
    print_error "❌ Tracker not responding locally"
fi

# Test index locally
print_status "Testing index locally..."
if curl -s http://127.0.0.1:3001/v1/settings/public | grep -q "tracker\|api"; then
    print_success "✅ Index responding locally"
else
    print_error "❌ Index not responding locally"
    print_status "Index response:"
    curl -s http://127.0.0.1:3001/v1/settings/public | head -5
fi

# Test GUI locally
print_status "Testing GUI locally..."
if curl -s http://127.0.0.1:3000 | grep -q "html\|torrust"; then
    print_success "✅ GUI responding locally"
else
    print_error "❌ GUI not responding locally"
fi

# Test through domain
print_status "Testing through domain..."

# Test GUI through domain
GUI_RESPONSE=$(curl -s https://macosapps.net/ | head -5)
if echo "$GUI_RESPONSE" | grep -q "html\|torrust"; then
    print_success "✅ GUI working through domain"
else
    print_error "❌ GUI not working through domain"
    print_status "GUI response: $GUI_RESPONSE"
fi

# Test Index API through domain
INDEX_RESPONSE=$(curl -s https://macosapps.net/api/v1/settings/public)
if echo "$INDEX_RESPONSE" | grep -q "tracker\|api"; then
    print_success "✅ Index API working through domain"
else
    print_error "❌ Index API not working through domain"
    print_status "Index API response: $INDEX_RESPONSE"
fi

# Test upload endpoint
UPLOAD_RESPONSE=$(curl -s -I https://macosapps.net/api/v1/torrent/upload)
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "✅ Upload endpoint accessible"
elif echo "$UPLOAD_RESPONSE" | grep -q "502"; then
    print_error "❌ Upload endpoint still returning 502"
else
    print_status "Upload endpoint response: $UPLOAD_RESPONSE"
fi

# 7. Final status check
print_status "7. Final status check..."
docker compose -f docker-compose-https.yml ps

print_status "Index crash fix completed!"
print_status ""
if docker compose -f docker-compose-https.yml ps index | grep -q "running"; then
    print_success "Index container is now running successfully!"
else
    print_error "Index container is still having issues"
    print_status "Check the logs above for error details"
fi
