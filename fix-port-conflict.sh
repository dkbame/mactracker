#!/bin/bash

# Fix port conflict issue
# Run this on your server to resolve the port 80 conflict

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

print_status "Fixing port conflict issue..."

# Check what's using port 80
print_status "Checking what's using port 80..."
if lsof -i :80 > /dev/null 2>&1; then
    print_status "Port 80 is in use. Checking services..."
    
    # Check if nginx is running
    if systemctl is-active --quiet nginx; then
        print_status "Nginx is running. Stopping it..."
        systemctl stop nginx
        systemctl disable nginx
        print_success "Nginx stopped"
    fi
    
    # Check if apache is running
    if systemctl is-active --quiet apache2; then
        print_status "Apache is running. Stopping it..."
        systemctl stop apache2
        systemctl disable apache2
        print_success "Apache stopped"
    fi
    
    # Check for other services
    if lsof -i :80 > /dev/null 2>&1; then
        print_status "Other service is using port 80. Checking..."
        lsof -i :80
        print_status "Please stop the service using port 80 manually"
        exit 1
    fi
else
    print_status "Port 80 is free"
fi

# Alternative: Create a modified docker-compose file that uses port 8080
print_status "Creating alternative docker-compose configuration..."

cat > docker-compose.alt.yml << 'EOF'
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
      - "8080:80"  # Using port 8080 instead of 80
      - "8443:443" # Using port 8443 instead of 443
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - gui
      - index
      - tracker
    restart: unless-stopped
EOF

# Stop any existing containers
print_status "Stopping existing containers..."
docker compose down 2>/dev/null || true

# Start with alternative configuration
print_status "Starting services with alternative port configuration..."
docker compose -f docker-compose.alt.yml up -d

print_success "Services started with alternative ports!"
print_status ""
print_status "Services are now running on:"
print_status "- Web Interface: http://your-server-ip:8080"
print_status "- Tracker API: http://your-server-ip:1212"
print_status "- Index API: http://your-server-ip:3001"
print_status "- GUI Direct: http://your-server-ip:3000"
print_status ""
print_status "To check service status:"
print_status "  docker compose -f docker-compose.alt.yml ps"
print_status ""
print_status "To view logs:"
print_status "  docker compose -f docker-compose.alt.yml logs -f"
