#!/bin/bash

# Fix Nginx conflicts and port binding issues
# This script will clean up Nginx configuration and resolve port conflicts

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_status "Fixing Nginx conflicts and port binding issues..."

cd "$PROJECT_ROOT"

# Stop all services first
print_status "Stopping all services..."
systemctl stop nginx 2>/dev/null || true
docker compose -f docker-compose-fixed.yml down 2>/dev/null || true

# Kill any processes using port 80
print_status "Killing processes using port 80..."
lsof -ti:80 | xargs kill -9 2>/dev/null || true
sleep 2

# Clean up Nginx configuration
print_status "Cleaning up Nginx configuration..."

# Remove all existing site configurations
rm -f /etc/nginx/sites-enabled/*
rm -f /etc/nginx/sites-available/macosapps
rm -f /etc/nginx/sites-available/torrust*

# Create a clean, single Nginx configuration
print_status "Creating clean Nginx configuration..."

cat > /etc/nginx/sites-available/macosapps << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/chain.pem;
    
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Main location - proxy to GUI
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # API routes
    location /api/ {
        proxy_pass http://127.0.0.1:3001/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Tracker API routes
    location /tracker-api/ {
        proxy_pass http://127.0.0.1:1212/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/macosapps /etc/nginx/sites-enabled/

# Test Nginx configuration
print_status "Testing Nginx configuration..."
nginx -t

# Start Nginx
print_status "Starting Nginx..."
systemctl start nginx
systemctl enable nginx

# Wait a moment for Nginx to start
sleep 3

# Check if port 80 is free
if netstat -tlnp | grep -q ":80 "; then
    print_success "Port 80 is now listening on Nginx"
else
    print_error "Port 80 is still not listening"
    exit 1
fi

# Create certbot directory
print_status "Creating certbot directory..."
mkdir -p /var/www/certbot

# Start Torrust services (without the nginx container since we're using system Nginx)
print_status "Starting Torrust services..."
docker compose -f docker-compose-fixed.yml up -d tracker index gui

# Wait for services to start
print_status "Waiting for services to start..."
sleep 10

# Test the setup
print_status "Testing the setup..."

# Test HTTP redirect
if curl -s -I http://$DOMAIN | grep -q "301\|302"; then
    print_success "HTTP to HTTPS redirect is working"
else
    print_warning "HTTP to HTTPS redirect may not be working"
fi

# Test HTTPS
if curl -s -I https://$DOMAIN | grep -q "200 OK"; then
    print_success "HTTPS is working"
else
    print_warning "HTTPS may not be working yet"
fi

# Setup automatic SSL renewal
print_status "Setting up automatic SSL renewal..."
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet && systemctl reload nginx") | crontab -

print_success "Nginx conflicts fixed and services started!"
print_status ""
print_status "Your Torrust BitTorrent suite is now accessible at:"
print_status "- Web Interface: https://$DOMAIN"
print_status "- Web Interface (www): https://www.$DOMAIN"
print_status "- Tracker API: https://$DOMAIN:1212"
print_status "- Index API: https://$DOMAIN:3001"
print_status ""
print_status "Services running:"
print_status "- System Nginx (port 80/443)"
print_status "- Docker containers: tracker, index, gui"
print_status ""
print_status "To check service status:"
print_status "  systemctl status nginx"
print_status "  docker compose -f docker-compose-fixed.yml ps"
print_status ""
print_status "To view logs:"
print_status "  journalctl -u nginx -f"
print_status "  docker compose -f docker-compose-fixed.yml logs -f"
