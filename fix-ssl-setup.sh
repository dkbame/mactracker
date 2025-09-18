#!/bin/bash

# Fix SSL setup for macosapps.net
# This script will help diagnose and fix the SSL certificate issue

set -e

# Configuration
DOMAIN="macosapps.net"
EMAIL="admin@macosapps.net"
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

print_status "Fixing SSL setup for $DOMAIN..."

cd "$PROJECT_ROOT"

# Check domain resolution
print_status "Checking domain resolution..."
echo "Checking $DOMAIN:"
nslookup $DOMAIN
echo ""
echo "Checking www.$DOMAIN:"
nslookup www.$DOMAIN

# Check if domain points to this server
print_status "Checking if domain points to this server..."
SERVER_IP=$(curl -s ifconfig.me)
print_status "Server IP: $SERVER_IP"

# Check if port 80 is accessible
print_status "Checking if port 80 is accessible..."
if netstat -tlnp | grep -q ":80 "; then
    print_success "Port 80 is listening"
else
    print_error "Port 80 is not listening"
    print_status "Starting Nginx to listen on port 80..."
    systemctl start nginx
fi

# Create a simple test page for domain verification
print_status "Creating test page for domain verification..."
mkdir -p /var/www/html
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>macosapps.net - Coming Soon</title>
</head>
<body>
    <h1>macosapps.net</h1>
    <p>Torrust BitTorrent Suite</p>
    <p>Setting up SSL certificate...</p>
</body>
</html>
EOF

# Create a simple Nginx configuration for domain verification
print_status "Creating simple Nginx configuration for domain verification..."

cat > /etc/nginx/sites-available/macosapps << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    root /var/www/html;
    index index.html;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/macosapps /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
print_status "Testing Nginx configuration..."
nginx -t

# Reload Nginx
print_status "Reloading Nginx..."
systemctl reload nginx

# Create certbot directory
print_status "Creating certbot directory..."
mkdir -p /var/www/certbot

# Test domain accessibility
print_status "Testing domain accessibility..."
if curl -s http://$DOMAIN | grep -q "macosapps.net"; then
    print_success "Domain is accessible"
else
    print_warning "Domain may not be accessible yet (DNS propagation)"
fi

# Try to generate SSL certificate
print_status "Attempting to generate SSL certificate..."
certbot certonly --webroot -w /var/www/certbot -d $DOMAIN -d www.$DOMAIN --email $EMAIL --agree-tos --non-interactive --force-renewal

if [ $? -eq 0 ]; then
    print_success "SSL certificate generated successfully!"
    
    # Now create the full Nginx configuration with SSL
    print_status "Creating full Nginx configuration with SSL..."
    
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
    
    # Test and reload Nginx
    print_status "Testing Nginx configuration..."
    nginx -t
    
    print_status "Reloading Nginx..."
    systemctl reload nginx
    
    # Start Torrust services
    print_status "Starting Torrust services..."
    docker compose -f docker-compose-fixed.yml up -d
    
    # Setup automatic SSL renewal
    print_status "Setting up automatic SSL renewal..."
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet && systemctl reload nginx") | crontab -
    
    print_success "SSL setup completed successfully!"
    print_status "Your site is now available at: https://$DOMAIN"
    
else
    print_error "SSL certificate generation failed"
    print_status "This usually means:"
    print_status "1. Domain is not pointing to this server yet (DNS propagation)"
    print_status "2. Firewall is blocking port 80"
    print_status "3. Domain registrar hasn't updated DNS records"
    print_status ""
    print_status "Please check:"
    print_status "- DNS records for $DOMAIN and www.$DOMAIN"
    print_status "- Firewall settings (port 80 should be open)"
    print_status "- Wait for DNS propagation (can take up to 24 hours)"
    print_status ""
    print_status "You can test the domain with: curl http://$DOMAIN"
fi
