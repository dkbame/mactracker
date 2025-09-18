#!/bin/bash

# Quick fix for deployment issues
# Run this on the server to fix the build problems

set -e

PROJECT_ROOT="/opt/torrust"

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

print_status "Fixing deployment issues..."

cd "$PROJECT_ROOT"

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    print_status "Installing Docker..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    systemctl start docker
    systemctl enable docker
    print_success "Docker installed"
fi

# Create necessary directories
mkdir -p storage/tracker/lib/database
mkdir -p storage/index/lib/database
mkdir -p config

# Create basic configuration files
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

# Create Docker Compose file for production
cat > docker-compose.production.yml << 'EOF'
version: '3.8'

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

# Start services
print_status "Starting services with Docker..."
docker compose -f docker-compose.production.yml up -d

print_success "Deployment fixed and services started!"
print_status ""
print_status "Services are running:"
print_status "- Web Interface: http://your-server-ip"
print_status "- Tracker API: http://your-server-ip:1212"
print_status "- Index API: http://your-server-ip:3001"
print_status ""
print_status "To check service status:"
print_status "  docker compose -f docker-compose.production.yml ps"
print_status ""
print_status "To view logs:"
print_status "  docker compose -f docker-compose.production.yml logs -f"
