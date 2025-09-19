#!/bin/bash

# Immediate fix for tracker URL to use domain instead of localhost
# Based on the torrent details page showing udp://localhost:6969

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

print_status "Fixing tracker URL to use domain instead of localhost..."

cd "$PROJECT_ROOT"

# 1. Check current configuration
print_status "1. Checking current configuration..."
if [ -f "./config/index.toml" ]; then
    print_status "Current index configuration:"
    grep -A 5 "\[tracker\]" ./config/index.toml
fi

# 2. Update index configuration with proper tracker URL
print_status "2. Updating index configuration with proper tracker URL..."

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
token = "$(cat ./secrets/tracker_admin_token.secret 2>/dev/null || echo 'MyAccessToken')"
url = "udp://$DOMAIN:6969/announce"

[database]
connect_url = "sqlite:///var/lib/torrust/index/database/sqlite3.db"

[auth]
secret_key = "$(cat ./secrets/auth_secret_key.secret 2>/dev/null || echo 'MaxVerstappenWC2021')"
user_claim_token_pepper = "$(cat ./secrets/user_claim_token_pepper.secret 2>/dev/null || echo 'AnotherSecretPepper123')"

[tracker_statistics_importer]
port = 3002
torrent_info_update_interval = 3600

[unstable]
EOF

print_success "Index configuration updated with tracker URL: udp://$DOMAIN:6969"

# 3. Restart index service
print_status "3. Restarting index service..."
docker compose -f docker-compose-https.yml restart index
sleep 15

# 4. Test the configuration
print_status "4. Testing the configuration..."

# Check if index is running
if docker compose -f docker-compose-https.yml ps index | grep -q "running"; then
    print_success "✅ Index is running"
else
    print_error "❌ Index is not running"
    docker compose -f docker-compose-https.yml logs index
    exit 1
fi

# Test index API
if curl -s http://127.0.0.1:3001/v1/settings/public | grep -q "tracker\|api"; then
    print_success "✅ Index API responding"
else
    print_error "❌ Index API not responding"
fi

# 5. Show the fix
print_status "5. Configuration updated:"
print_status "Tracker URL in index config: udp://$DOMAIN:6969/announce"
print_status ""
print_status "New torrent uploads will now use:"
print_success "  udp://$DOMAIN:6969/announce"
print_success "  http://$DOMAIN:7070/announce"
print_status ""
print_warning "Note: Existing torrents will still show localhost URLs."
print_status "Only new uploads will use the correct domain URLs."

# 6. Test upload endpoint
print_status "6. Testing upload endpoint..."
UPLOAD_RESPONSE=$(curl -s -I https://$DOMAIN/api/v1/torrent/upload)
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "✅ Upload endpoint accessible"
    print_status "You can now upload a new torrent to test the fix"
else
    print_error "❌ Upload endpoint not accessible"
fi

print_status "Tracker URL fix completed!"
print_status ""
print_status "To test the fix:"
print_status "1. Upload a new torrent"
print_status "2. Check the torrent details page"
print_status "3. Verify the tracker URL shows: udp://$DOMAIN:6969/announce"
