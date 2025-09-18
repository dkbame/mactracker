#!/bin/bash

# Fix Docker Compose configuration
# Run this on your server to fix the build issues

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

print_status "Fixing Docker Compose configuration..."

cd /opt/torrust

# Stop existing containers
print_status "Stopping existing containers..."
docker compose down 2>/dev/null || true

# Create fixed docker-compose file
print_status "Creating fixed Docker Compose configuration..."

cat > docker-compose-fixed.yml << 'EOF'
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
      - "3000:3000"
    environment:
      - NUXT_PUBLIC_API_BASE=http://localhost:3001/v1
    depends_on:
      - index
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: torrust-nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - gui
      - index
      - tracker
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

# Create Nginx configuration
cat > config/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    upstream index_backend {
        server index:3001;
    }
    
    upstream tracker_backend {
        server tracker:1212;
    }
    
    upstream gui_backend {
        server gui:3000;
    }
    
    server {
        listen 80;
        server_name _;
        
        location / {
            proxy_pass http://gui_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        location /api/ {
            proxy_pass http://index_backend/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        location /tracker-api/ {
            proxy_pass http://tracker_backend/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF

# Start services with fixed configuration
print_status "Starting services with fixed configuration..."
docker compose -f docker-compose-fixed.yml up -d

print_success "Services started successfully!"
print_status ""
print_status "Services are running:"
print_status "- Web Interface: http://your-server-ip"
print_status "- Tracker API: http://your-server-ip:1212"
print_status "- Index API: http://your-server-ip:3001"
print_status "- GUI Direct: http://your-server-ip:3000"
print_status ""
print_status "To check service status:"
print_status "  docker compose -f docker-compose-fixed.yml ps"
print_status ""
print_status "To view logs:"
print_status "  docker compose -f docker-compose-fixed.yml logs -f"
