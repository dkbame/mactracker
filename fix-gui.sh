#!/bin/bash

# Fix GUI access issues
# Run this on your server to fix GUI problems

set -e

print_status() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_status "Fixing GUI access issues..."

cd /opt/torrust

# Stop existing containers
print_status "Stopping existing containers..."
docker compose -f docker-compose-fixed.yml down

# Create a simpler configuration that exposes GUI directly
print_status "Creating simplified configuration..."

cat > docker-compose-simple.yml << 'EOF'
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
    depends_on:
      - tracker
    restart: unless-stopped

  gui:
    image: torrust/index-gui:develop
    container_name: torrust-gui
    ports:
      - "80:3000"  # Map port 80 directly to GUI port 3000
    environment:
      - NUXT_PUBLIC_API_BASE=http://109.104.153.250:3001/v1
    depends_on:
      - index
    restart: unless-stopped
EOF

# Create necessary directories
print_status "Creating necessary directories..."
mkdir -p storage/tracker/lib/database
mkdir -p storage/index/lib/database
mkdir -p config

# Create configuration files
print_status "Creating configuration files..."

cat > config/tracker.toml << 'EOF'
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
admin = "MyAccessToken"

[health_check_api]
bind_address = "127.0.0.1:1313"
EOF

cat > config/index.toml << 'EOF'
[metadata]
app = "torrust-index"
purpose = "configuration"
schema_version = "2.0.0"

[logging]
threshold = "info"

[tracker]
token = "MyAccessToken"

[database]
connect_url = "sqlite:///var/lib/torrust/index/database/sqlite3.db"

[auth]
user_claim_token_pepper = "MaxVerstappenWC2021"

[registration]
[registration.email]
EOF

# Start services with simplified configuration
print_status "Starting services with simplified configuration..."
docker compose -f docker-compose-simple.yml up -d

# Wait for services to start
print_status "Waiting for services to start..."
sleep 10

# Test services
print_status "Testing services..."

# Test tracker
if curl -s http://localhost:1212/api/v1/stats?token=MyAccessToken > /dev/null; then
    print_success "Tracker API is responding"
else
    print_error "Tracker API is not responding"
fi

# Test index
if curl -s http://localhost:3001/v1/torrents > /dev/null; then
    print_success "Index API is responding"
else
    print_error "Index API is not responding"
fi

# Test GUI
if curl -s http://localhost:80 > /dev/null; then
    print_success "GUI is responding on port 80"
else
    print_error "GUI is not responding on port 80"
fi

print_success "Services started with simplified configuration!"
print_status ""
print_status "Services are now running:"
print_status "- Web Interface: http://109.104.153.250"
print_status "- Tracker API: http://109.104.153.250:1212"
print_status "- Index API: http://109.104.153.250:3001"
print_status ""
print_status "To check service status:"
print_status "  docker compose -f docker-compose-simple.yml ps"
print_status ""
print_status "To view logs:"
print_status "  docker compose -f docker-compose-simple.yml logs -f"
