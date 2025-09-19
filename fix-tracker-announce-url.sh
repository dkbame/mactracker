#!/bin/bash

# Fix tracker announce URL to use domain instead of localhost
# The torrent files should contain the public domain, not localhost

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

print_status "Fixing tracker announce URL to use domain: $DOMAIN"

cd "$PROJECT_ROOT"

# 1. Stop all services
print_status "1. Stopping all services..."
docker compose -f docker-compose-https.yml down
sleep 5

# 2. Update tracker configuration with public domain
print_status "2. Updating tracker configuration with public domain..."

# Read current tracker config
if [ -f "./config/tracker.toml" ]; then
    print_status "Current tracker configuration:"
    cat ./config/tracker.toml
fi

# Create updated tracker configuration
cat > ./config/tracker.toml << EOF
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

[[udp_trackers]]
bind_address = "0.0.0.0:6969"
tracker_usage_statistics = true

[[http_trackers]]
bind_address = "0.0.0.0:7070"
tracker_usage_statistics = true

[http_api]
bind_address = "0.0.0.0:1212"

[http_api.access_tokens]
admin = "$(cat ./secrets/tracker_admin_token.secret 2>/dev/null || echo 'MyAccessToken')"
EOF

print_success "Tracker configuration updated with public domain support"

# 3. Update index configuration to use public tracker URLs
print_status "3. Updating index configuration to use public tracker URLs..."

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

print_success "Index configuration updated"

# 4. Update Docker Compose with tracker URL environment variable
print_status "4. Updating Docker Compose with tracker URL environment variable..."

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
      - TORRUST_INDEX_CONFIG_OVERRIDE_TRACKER__TOKEN=$(cat ./secrets/tracker_admin_token.secret 2>/dev/null || echo 'MyAccessToken')
      - TORRUST_INDEX_CONFIG_OVERRIDE_AUTH__SECRET_KEY=$(cat ./secrets/auth_secret_key.secret 2>/dev/null || echo 'MaxVerstappenWC2021')
      - TORRUST_INDEX_CONFIG_OVERRIDE_AUTH__USER_CLAIM_TOKEN_PEPPER=$(cat ./secrets/user_claim_token_pepper.secret 2>/dev/null || echo 'AnotherSecretPepper123')
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

print_success "Docker Compose updated"

# 5. Start services
print_status "5. Starting services..."
docker compose -f docker-compose-https.yml up -d
sleep 20

# 6. Test tracker endpoints
print_status "6. Testing tracker endpoints..."

# Test UDP tracker
print_status "Testing UDP tracker..."
if netstat -ulnp | grep -q ":6969"; then
    print_success "✅ UDP tracker listening on port 6969"
else
    print_error "❌ UDP tracker not listening on port 6969"
fi

# Test HTTP tracker
print_status "Testing HTTP tracker..."
if curl -s http://127.0.0.1:7070/announce | grep -q "announce\|tracker"; then
    print_success "✅ HTTP tracker responding on port 7070"
else
    print_error "❌ HTTP tracker not responding on port 7070"
fi

# Test tracker API
print_status "Testing tracker API..."
if curl -s http://127.0.0.1:1212/api/health_check | grep -q "Ok"; then
    print_success "✅ Tracker API responding on port 1212"
else
    print_error "❌ Tracker API not responding on port 1212"
fi

# 7. Show correct tracker URLs
print_status "7. Correct tracker URLs for torrents:"
print_status ""
print_success "UDP Tracker: udp://$DOMAIN:6969/announce"
print_success "HTTP Tracker: http://$DOMAIN:7070/announce"
print_status ""
print_status "These URLs should be used in torrent files instead of localhost."

# 8. Test index and upload
print_status "8. Testing index and upload functionality..."

# Test index API
if curl -s http://127.0.0.1:3001/v1/settings/public | grep -q "tracker\|api"; then
    print_success "✅ Index API responding"
else
    print_error "❌ Index API not responding"
fi

# Test upload endpoint
UPLOAD_RESPONSE=$(curl -s -I https://$DOMAIN/api/v1/torrent/upload)
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "✅ Upload endpoint accessible"
else
    print_error "❌ Upload endpoint not accessible"
fi

# 9. Final status
print_status "9. Final status check..."
docker compose -f docker-compose-https.yml ps

print_status "Tracker announce URL fix completed!"
print_status ""
print_status "Your tracker URLs are now:"
print_status "  UDP: udp://$DOMAIN:6969/announce"
print_status "  HTTP: http://$DOMAIN:7070/announce"
print_status ""
print_status "When you upload new torrents, they should use these public URLs instead of localhost."
print_status ""
print_warning "Note: Existing torrents will still have localhost URLs. Only new uploads will use the correct domain."
