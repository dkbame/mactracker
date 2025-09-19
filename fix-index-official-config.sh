#!/bin/bash

# Fix Index configuration based on official documentation
# This follows the exact setup from the official Torrust Index docs

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

print_status "Fixing Index configuration based on official documentation..."

cd "$PROJECT_ROOT"

# 1. Stop all services
print_status "1. Stopping all services..."
docker compose -f docker-compose-https.yml down
sleep 5

# 2. Create proper directory structure as per official docs
print_status "2. Creating proper directory structure..."
mkdir -p ./storage/index/lib/database/
mkdir -p ./storage/index/etc/
mkdir -p ./storage/tracker/lib/database/
mkdir -p ./storage/tracker/etc/

# 3. Create empty database files as per official docs
print_status "3. Creating empty database files..."
touch ./storage/index/lib/database/sqlite3.db
touch ./storage/tracker/lib/database/sqlite3.db

print_success "Database files created"

# 4. Create proper tracker configuration
print_status "4. Creating proper tracker configuration..."
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

# 5. Create proper index configuration based on official docs
print_status "5. Creating proper index configuration..."
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

# 6. Create proper Docker Compose with environment variables as per official docs
print_status "6. Creating proper Docker Compose configuration..."
cat > docker-compose-https.yml << EOF
services:
  tracker:
    image: torrust/tracker:develop
    container_name: torrust-tracker
    ports:
      - "1212:1212"
      - "6969:6969/udp"
      - "7070:7070"
    volumes:
      - ./storage/tracker:/var/lib/torrust/tracker
      - ./config/tracker.toml:/etc/torrust/tracker.toml:ro
    environment:
      - TORRUST_TRACKER_CONFIG_TOML_PATH=/etc/torrust/tracker.toml
    restart: unless-stopped
    networks:
      - torrust

  index:
    image: torrust/index:develop
    container_name: torrust-index
    ports:
      - "3001:3001"
      - "3002:3002"
    volumes:
      - ./storage/index:/var/lib/torrust/index
      - ./config/index.toml:/etc/torrust/index.toml:ro
    environment:
      - TORRUST_INDEX_CONFIG_TOML_PATH=/etc/torrust/index.toml
      - TORRUST_INDEX_API_CORS_PERMISSIVE=1
      - TORRUST_INDEX_CONFIG_OVERRIDE_TRACKER__TOKEN=MyAccessToken
      - TORRUST_INDEX_CONFIG_OVERRIDE_AUTH__SECRET_KEY=MaxVerstappenWC2021
    depends_on:
      - tracker
    restart: unless-stopped
    networks:
      - torrust

  gui:
    image: torrust/index-gui:develop
    container_name: torrust-gui
    ports:
      - "3000:3000"
    environment:
      - NUXT_PUBLIC_API_BASE=https://$DOMAIN/api/v1
      - NITRO_HOST=0.0.0.0
      - NITRO_PORT=3000
    depends_on:
      - index
    restart: unless-stopped
    networks:
      - torrust

networks:
  torrust:
    driver: bridge
EOF

print_success "Docker Compose configuration created"

# 7. Start services in correct order as per official docs
print_status "7. Starting services in correct order..."

# Start tracker first
print_status "Starting tracker..."
docker compose -f docker-compose-https.yml up -d tracker
sleep 20

# Check tracker is ready
print_status "Checking tracker readiness..."
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
sleep 25

# Check index is ready and not crashing
print_status "Checking index readiness..."
for i in {1..40}; do
    INDEX_STATUS=$(docker compose -f docker-compose-https.yml ps index --format "{{.State}}")
    if echo "$INDEX_STATUS" | grep -q "running"; then
        # Test if index API is responding
        if curl -s http://127.0.0.1:3001/v1/settings/public | grep -q "tracker\|api"; then
            print_success "Index is ready and responding"
            break
        else
            print_status "Index is running but API not ready yet... ($i/40)"
            sleep 2
        fi
    elif echo "$INDEX_STATUS" | grep -q "exited"; then
        print_error "Index crashed again"
        print_status "Index logs:"
        docker compose -f docker-compose-https.yml logs --tail=30 index
        exit 1
    elif [ $i -eq 40 ]; then
        print_error "Index failed to start properly"
        docker compose -f docker-compose-https.yml logs --tail=30 index
        exit 1
    else
        print_status "Waiting for index... ($i/40) - Status: $INDEX_STATUS"
        sleep 2
    fi
done

# Start GUI
print_status "Starting GUI..."
docker compose -f docker-compose-https.yml up -d gui
sleep 15

# 8. Test all endpoints
print_status "8. Testing all endpoints..."

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

# 9. Show final configuration
print_status "9. Final configuration summary:"
print_status "Index environment variables:"
print_status "  TORRUST_INDEX_CONFIG_TOML_PATH=/etc/torrust/index.toml"
print_status "  TORRUST_INDEX_API_CORS_PERMISSIVE=1"
print_status "  TORRUST_INDEX_CONFIG_OVERRIDE_TRACKER__TOKEN=MyAccessToken"
print_status "  TORRUST_INDEX_CONFIG_OVERRIDE_AUTH__SECRET_KEY=MaxVerstappenWC2021"
print_status ""
print_status "GUI environment variables:"
print_status "  NUXT_PUBLIC_API_BASE=https://$DOMAIN/api/v1"
print_status "  NITRO_HOST=0.0.0.0"
print_status "  NITRO_PORT=3000"

# 10. Final status check
print_status "10. Final status check..."
docker compose -f docker-compose-https.yml ps

print_status "Index official configuration fix completed!"
print_status ""
print_status "Configuration follows the official Torrust Index documentation:"
print_status "- Proper database file setup"
print_status "- Correct environment variable overrides"
print_status "- Proper service dependencies"
print_status "- Official configuration structure"
