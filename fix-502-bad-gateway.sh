#!/bin/bash

# Fix 502 Bad Gateway errors
# Nginx can't connect to backend services

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

print_status "Fixing 502 Bad Gateway errors..."

cd "$PROJECT_ROOT"

# 1. Check container status and port bindings
print_status "1. Checking container status and port bindings..."
docker compose -f docker-compose-https.yml ps

print_status "Checking port bindings..."
netstat -tlnp | grep -E ":(3000|3001|1212|7070)" || print_warning "Some expected ports not found"

# 2. Check if services are responding locally
print_status "2. Testing services locally..."

# Test GUI
print_status "Testing GUI locally..."
if curl -s http://127.0.0.1:3000 | grep -q "html\|torrust"; then
    print_success "✅ GUI responding on port 3000"
else
    print_error "❌ GUI not responding on port 3000"
    print_status "GUI response:"
    curl -s http://127.0.0.1:3000 | head -5
fi

# Test Index API
print_status "Testing Index API locally..."
if curl -s http://127.0.0.1:3001/v1/settings/public | grep -q "tracker\|api"; then
    print_success "✅ Index API responding on port 3001"
else
    print_error "❌ Index API not responding on port 3001"
    print_status "Index API response:"
    curl -s http://127.0.0.1:3001/v1/settings/public | head -5
fi

# Test Tracker API
print_status "Testing Tracker API locally..."
if curl -s http://127.0.0.1:1212/api/health_check | grep -q "Ok"; then
    print_success "✅ Tracker API responding on port 1212"
else
    print_error "❌ Tracker API not responding on port 1212"
    print_status "Tracker API response:"
    curl -s http://127.0.0.1:1212/api/health_check | head -5
fi

# Test HTTP Tracker
print_status "Testing HTTP Tracker locally..."
if curl -s http://127.0.0.1:7070/announce | grep -q "announce\|tracker"; then
    print_success "✅ HTTP Tracker responding on port 7070"
else
    print_error "❌ HTTP Tracker not responding on port 7070"
    print_status "HTTP Tracker response:"
    curl -s http://127.0.0.1:7070/announce | head -5
fi

# 3. Check container logs for errors
print_status "3. Checking container logs for errors..."
print_status "GUI logs (last 10 lines):"
docker compose -f docker-compose-https.yml logs --tail=10 gui

print_status "Index logs (last 10 lines):"
docker compose -f docker-compose-https.yml logs --tail=10 index

print_status "Tracker logs (last 10 lines):"
docker compose -f docker-compose-https.yml logs --tail=10 tracker

# 4. Fix Nginx configuration to use correct backend addresses
print_status "4. Fixing Nginx configuration..."

# Create a simple Nginx configuration that works
cat > /etc/nginx/sites-available/macosapps << 'EOF'
server {
    listen 80;
    server_name macosapps.net www.macosapps.net;
    
    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name macosapps.net www.macosapps.net;
    
    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/macosapps.net/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/macosapps.net/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/macosapps.net/chain.pem;
    
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
    
    # Index API routes
    location /api/ {
        proxy_pass http://127.0.0.1:3001/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # CORS headers
        add_header Access-Control-Allow-Origin "https://macosapps.net" always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        add_header Access-Control-Allow-Credentials "true" always;
        
        # Handle preflight requests
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin "https://macosapps.net";
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "Authorization, Content-Type";
            add_header Access-Control-Allow-Credentials "true";
            add_header Content-Length 0;
            add_header Content-Type text/plain;
            return 204;
        }
    }
    
    # Tracker API routes
    location /tracker-api/ {
        proxy_pass http://127.0.0.1:1212/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # CORS headers
        add_header Access-Control-Allow-Origin "https://macosapps.net" always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        add_header Access-Control-Allow-Credentials "true" always;
    }
    
    # Main location - proxy to GUI
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Test Nginx configuration
print_status "Testing Nginx configuration..."
nginx -t

# Reload Nginx
print_status "Reloading Nginx..."
systemctl reload nginx

# 5. Wait for services to be ready
print_status "5. Waiting for services to be ready..."
sleep 10

# 6. Test the endpoints again
print_status "6. Testing endpoints after Nginx fix..."

# Test GUI
print_status "Testing GUI through domain..."
GUI_RESPONSE=$(curl -s https://macosapps.net/ | head -5)
if echo "$GUI_RESPONSE" | grep -q "html\|torrust"; then
    print_success "✅ GUI working through domain"
else
    print_error "❌ GUI still not working through domain"
    print_status "GUI response: $GUI_RESPONSE"
fi

# Test Index API
print_status "Testing Index API through domain..."
INDEX_RESPONSE=$(curl -s https://macosapps.net/api/v1/settings/public)
if echo "$INDEX_RESPONSE" | grep -q "tracker\|api"; then
    print_success "✅ Index API working through domain"
else
    print_error "❌ Index API still not working through domain"
    print_status "Index API response: $INDEX_RESPONSE"
fi

# Test Tracker API
print_status "Testing Tracker API through domain..."
TRACKER_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" https://macosapps.net/tracker-api/stats)
if echo "$TRACKER_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ Tracker API working through domain"
else
    print_warning "⚠️ Tracker API response: $TRACKER_RESPONSE"
fi

# Test upload endpoint
print_status "Testing upload endpoint..."
UPLOAD_RESPONSE=$(curl -s -I https://macosapps.net/api/v1/torrent/upload)
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "✅ Upload endpoint accessible"
elif echo "$UPLOAD_RESPONSE" | grep -q "502"; then
    print_error "❌ Upload endpoint still returning 502"
else
    print_status "Upload endpoint response: $UPLOAD_RESPONSE"
fi

# 7. Final status
print_status "7. Final status check..."
print_status "Container status:"
docker compose -f docker-compose-https.yml ps

print_status "Port bindings:"
netstat -tlnp | grep -E ":(3000|3001|1212|7070)" || print_warning "Some ports not found"

print_status "502 Bad Gateway fix completed!"
print_status ""
print_status "If you're still getting 502 errors, the issue is likely:"
print_status "1. Services not fully started yet (wait a few minutes)"
print_status "2. Port conflicts or firewall issues"
print_status "3. Container networking problems"
print_status ""
print_status "Check the container logs above for any error messages."
