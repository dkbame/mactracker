#!/bin/bash

# Setup domain and SSL for Torrust
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

print_status "Setting up domain $DOMAIN with SSL..."

cd "$PROJECT_ROOT"

# Install Certbot
print_status "Installing Certbot..."
apt-get update
apt-get install -y certbot python3-certbot-nginx

# Stop existing containers
print_status "Stopping existing containers..."
docker compose -f docker-compose-fixed.yml down 2>/dev/null || true

# Create Nginx configuration with domain
print_status "Creating Nginx configuration for domain $DOMAIN..."

cat > config/nginx.conf << EOF
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
        
        # SSL configuration will be added by Certbot
        
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

# Create directory for Let's Encrypt challenges
print_status "Creating Let's Encrypt challenge directory..."
mkdir -p /var/www/certbot

# Create temporary Nginx configuration for SSL certificate generation
print_status "Creating temporary Nginx configuration for SSL setup..."

cat > /etc/nginx/sites-available/torrust-temp << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF

# Enable temporary site
ln -sf /etc/nginx/sites-available/torrust-temp /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload Nginx
print_status "Testing Nginx configuration..."
nginx -t
systemctl reload nginx

# Generate SSL certificate
print_status "Generating SSL certificate for $DOMAIN..."
certbot certonly --webroot -w /var/www/certbot -d $DOMAIN -d www.$DOMAIN --email $EMAIL --agree-tos --non-interactive

# Update Nginx configuration with SSL
print_status "Updating Nginx configuration with SSL certificates..."

cat > /etc/nginx/sites-available/torrust << EOF
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
ln -sf /etc/nginx/sites-available/torrust /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/torrust-temp

# Test Nginx configuration
print_status "Testing Nginx configuration..."
nginx -t

# Reload Nginx
print_status "Reloading Nginx..."
systemctl reload nginx

# Start Torrust services
print_status "Starting Torrust services..."
docker compose -f docker-compose-fixed.yml up -d

# Wait for services to start
print_status "Waiting for services to start..."
sleep 10

# Setup automatic SSL renewal
print_status "Setting up automatic SSL renewal..."
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

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
print_status "SSL certificate will auto-renew every 12 hours"
print_status ""
print_status "To check service status:"
print_status "  docker compose -f docker-compose-fixed.yml ps"
print_status ""
print_status "To view logs:"
print_status "  docker compose -f docker-compose-fixed.yml logs -f"
print_status ""
print_status "To check SSL certificate:"
print_status "  certbot certificates"
