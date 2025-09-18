#!/bin/bash

# Fix Nginx proxy to serve GUI on port 80
# Run this on your server to fix the Nginx configuration

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

print_status "Fixing Nginx proxy configuration..."

cd /opt/torrust

# Stop existing containers
print_status "Stopping existing containers..."
docker compose -f docker-compose-fixed.yml down

# Create a fixed Nginx configuration
print_status "Creating fixed Nginx configuration..."

cat > config/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    # Upstream servers
    upstream gui_backend {
        server gui:3000;
    }
    
    upstream index_backend {
        server index:3001;
    }
    
    upstream tracker_backend {
        server tracker:1212;
    }
    
    server {
        listen 80;
        server_name _;
        
        # Main location - proxy to GUI
        location / {
            proxy_pass http://gui_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
        
        # API routes
        location /api/ {
            proxy_pass http://index_backend/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # Tracker API routes
        location /tracker-api/ {
            proxy_pass http://tracker_backend/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # Health check
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# Create a fixed docker-compose file
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
      - NUXT_PUBLIC_API_BASE=http://109.104.153.250:3001/v1
    depends_on:
      - index
    restart: unless-stopped
    networks:
      - torrust

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
    networks:
      - torrust

networks:
  torrust:
    driver: bridge
EOF

# Start services with fixed configuration
print_status "Starting services with fixed Nginx configuration..."
docker compose -f docker-compose-fixed.yml up -d

# Wait for services to start
print_status "Waiting for services to start..."
sleep 10

# Test the configuration
print_status "Testing the configuration..."

# Test Nginx
if curl -s http://localhost:80 > /dev/null; then
    print_success "Nginx is responding on port 80"
else
    print_error "Nginx is not responding on port 80"
fi

# Test GUI through Nginx
if curl -s http://localhost:80 | grep -q "html"; then
    print_success "GUI is accessible through Nginx on port 80"
else
    print_error "GUI is not accessible through Nginx on port 80"
fi

print_success "Nginx proxy configuration fixed!"
print_status ""
print_status "Your Torrust BitTorrent suite is now accessible at:"
print_status "- Web Interface: http://109.104.153.250"
print_status "- Tracker API: http://109.104.153.250:1212"
print_status "- Index API: http://109.104.153.250:3001"
print_status ""
print_status "To check service status:"
print_status "  docker compose -f docker-compose-fixed.yml ps"
print_status ""
print_status "To view logs:"
print_status "  docker compose -f docker-compose-fixed.yml logs -f"
