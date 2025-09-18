#!/bin/bash

# Setup domain and SSL for Torrust (Docker version)
# Run this on your server to configure macosapps.net with Let's Encrypt SSL

set -e

# Configuration
DOMAIN="macosapps.net"
EMAIL="admin@macosapps.net"  # Change this to your email
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

print_status "Setting up domain $DOMAIN with SSL using Docker..."

cd "$PROJECT_ROOT"

# Install Docker Compose if not present
if ! command -v docker compose &> /dev/null; then
    print_status "Installing Docker Compose..."
    apt-get update
    apt-get install -y docker-compose-plugin
fi

# Stop existing containers
print_status "Stopping existing containers..."
docker compose -f docker-compose-fixed.yml down 2>/dev/null || true

# Create Docker Compose with SSL support
print_status "Creating Docker Compose configuration with SSL support..."

cat > docker-compose-ssl.yml << EOF
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
      - NUXT_PUBLIC_API_BASE=https://$DOMAIN:3001/v1
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
      - ./config/nginx-ssl.conf:/etc/nginx/nginx.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
    depends_on:
      - gui
      - index
      - tracker
    restart: unless-stopped
    networks:
      - torrust

  certbot:
    image: certbot/certbot
    container_name: torrust-certbot
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt
      - /var/www/certbot:/var/www/certbot
    command: certonly --webroot -w /var/www/certbot -d $DOMAIN -d www.$DOMAIN --email $EMAIL --agree-tos --non-interactive
    networks:
      - torrust

networks:
  torrust:
    driver: bridge
EOF

# Create Nginx configuration with SSL
print_status "Creating Nginx configuration with SSL support..."

cat > config/nginx-ssl.conf << EOF
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
    
    # HTTP server (redirects to HTTPS)
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
    
    # HTTPS server
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
            proxy_pass http://gui_backend;
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
            proxy_pass http://index_backend/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
        
        # Tracker API routes
        location /tracker-api/ {
            proxy_pass http://tracker_backend/;
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
}
EOF

# Create necessary directories
print_status "Creating necessary directories..."
mkdir -p /var/www/certbot
mkdir -p /etc/letsencrypt

# Start services without SSL first
print_status "Starting services without SSL..."
docker compose -f docker-compose-ssl.yml up -d tracker index gui nginx

# Wait for services to start
print_status "Waiting for services to start..."
sleep 10

# Generate SSL certificate
print_status "Generating SSL certificate for $DOMAIN..."
docker compose -f docker-compose-ssl.yml run --rm certbot

# Restart Nginx with SSL
print_status "Restarting Nginx with SSL configuration..."
docker compose -f docker-compose-ssl.yml restart nginx

# Setup automatic SSL renewal
print_status "Setting up automatic SSL renewal..."
cat > /etc/cron.d/certbot-renew << EOF
0 12 * * * root docker compose -f $PROJECT_ROOT/docker-compose-ssl.yml run --rm certbot renew --quiet && docker compose -f $PROJECT_ROOT/docker-compose-ssl.yml restart nginx
EOF

# Test the setup
print_status "Testing the setup..."

# Wait a moment for services to be ready
sleep 5

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
    print_warning "HTTPS may not be working yet (DNS propagation may take time)"
fi

print_success "Domain and SSL setup completed!"
print_status ""
print_status "Your Torrust BitTorrent suite is now accessible at:"
print_status "- Web Interface: https://$DOMAIN"
print_status "- Web Interface (www): https://www.$DOMAIN"
print_status "- Tracker API: https://$DOMAIN:1212"
print_status "- Index API: https://$DOMAIN:3001"
print_status ""
print_status "SSL certificate will auto-renew daily"
print_status ""
print_status "To check service status:"
print_status "  docker compose -f docker-compose-ssl.yml ps"
print_status ""
print_status "To view logs:"
print_status "  docker compose -f docker-compose-ssl.yml logs -f"
print_status ""
print_status "To check SSL certificate:"
print_status "  docker compose -f docker-compose-ssl.yml run --rm certbot certificates"
