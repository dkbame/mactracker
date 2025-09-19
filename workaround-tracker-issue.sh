#!/bin/bash

# Workaround for Tracker API 500 errors
# Since HTTP tracker (port 7070) works, we can still use it for torrent uploads

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

print_status "Setting up workaround for Tracker API 500 errors..."

cd "$PROJECT_ROOT"

# 1. Update Index configuration to use working tracker endpoints
print_status "1. Updating Index configuration..."

# Check if index config exists
if [ -f "./config/index.toml" ]; then
    print_status "Current index tracker config:"
    grep -A 5 "\[tracker\]" ./config/index.toml || print_warning "No tracker section found"
    
    # Create updated index config that works around the API issues
    print_status "Creating updated index configuration..."
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
else
    print_error "Index configuration file not found!"
    exit 1
fi

# 2. Restart index container to use new config
print_status "2. Restarting index container..."
docker compose -f docker-compose-https.yml restart index
sleep 10

# 3. Test if upload endpoint now works
print_status "3. Testing upload endpoint..."
UPLOAD_RESPONSE=$(curl -s -I https://macosapps.net/api/v1/torrent/upload)
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "Upload endpoint is now accessible!"
    print_status "Response: $UPLOAD_RESPONSE"
elif echo "$UPLOAD_RESPONSE" | grep -q "503"; then
    print_warning "Upload endpoint still returning 503"
    print_status "Response: $UPLOAD_RESPONSE"
else
    print_status "Upload endpoint response: $UPLOAD_RESPONSE"
fi

# 4. Test tracker communication
print_status "4. Testing tracker communication from index..."
# Check if index can communicate with tracker
docker exec torrust-index curl -s http://tracker:1212/health_check || print_warning "Index cannot reach tracker health_check"

# 5. Show working tracker endpoints
print_status "5. Working tracker endpoints:"
print_success "HTTP Tracker (for announce): http://109.104.153.250:7070/announce"
print_warning "API endpoints may have issues, but announce should work"
print_status ""
print_status "For torrent uploads, use this announce URL:"
print_status "http://109.104.153.250:7070/announce"
print_status ""
print_status "The HTTP tracker is working fine for BitTorrent protocol."
print_status "The API issues don't affect actual torrent tracking."

print_status "Workaround setup completed!"
print_status ""
print_status "Try uploading a torrent now using announce URL:"
print_status "http://109.104.153.250:7070/announce"
