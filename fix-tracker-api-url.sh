#!/bin/bash

# Fix tracker API URL to use domain instead of internal Docker network
# The tracker API should be accessible via the domain and port

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

print_status "Fixing tracker API URL to use domain: $DOMAIN"

cd "$PROJECT_ROOT"

# 1. Stop all services
print_status "1. Stopping all services..."
docker compose -f docker-compose-https.yml down
sleep 5

# 2. Update index configuration to use domain for tracker API
print_status "2. Updating index configuration to use domain for tracker API..."

cat > ./config/index.toml << EOF
[metadata]
app = "torrust-index"
purpose = "configuration"
schema_version = "2.0.0"

[logging]
threshold = "info"

[net]
bind_address = "0.0.0.0:3001"
public_address = "https://$DOMAIN:3001"

[tracker]
api_url = "http://$DOMAIN:1212"
token = "MyAccessToken"

[database]
connect_url = "sqlite:///var/lib/torrust/index/database/sqlite3.db"

[tracker_statistics_importer]
port = 3002
torrent_info_update_interval = 3600

[unstable]
EOF

print_success "Index configuration updated with domain-based tracker API URL"

# 3. Update Nginx configuration to proxy tracker API
print_status "3. Updating Nginx configuration to proxy tracker API..."

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
    
    # Index API routes (proxy to index service)
    location /api/ {
        proxy_pass http://127.0.0.1:3001/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # CORS headers
        add_header Access-Control-Allow-Origin "https://$DOMAIN" always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        add_header Access-Control-Allow-Credentials "true" always;
        
        # Handle preflight requests
        if (\$request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin "https://$DOMAIN";
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "Authorization, Content-Type";
            add_header Access-Control-Allow-Credentials "true";
            add_header Content-Length 0;
            add_header Content-Type text/plain;
            return 204;
        }
    }
    
    # Tracker API routes (proxy to tracker service)
    location /tracker-api/ {
        proxy_pass http://127.0.0.1:1212/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # CORS headers
        add_header Access-Control-Allow-Origin "https://$DOMAIN" always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        add_header Access-Control-Allow-Credentials "true" always;
    }
    
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

# 4. Update index configuration to use HTTPS tracker API
print_status "4. Updating index configuration to use HTTPS tracker API..."

cat > ./config/index.toml << EOF
[metadata]
app = "torrust-index"
purpose = "configuration"
schema_version = "2.0.0"

[logging]
threshold = "info"

[net]
bind_address = "0.0.0.0:3001"
public_address = "https://$DOMAIN:3001"

[tracker]
api_url = "https://$DOMAIN/tracker-api"
token = "MyAccessToken"

[database]
connect_url = "sqlite:///var/lib/torrust/index/database/sqlite3.db"

[tracker_statistics_importer]
port = 3002
torrent_info_update_interval = 3600

[unstable]
EOF

print_success "Index configuration updated with HTTPS tracker API URL"

# 5. Start services
print_status "5. Starting services..."
docker compose -f docker-compose-https.yml up -d
sleep 15

# 6. Test the configuration
print_status "6. Testing the configuration..."

# Test tracker API through domain
print_status "Testing tracker API through domain..."
TRACKER_API_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" "https://$DOMAIN/tracker-api/stats")
print_status "Tracker API response: $TRACKER_API_RESPONSE"

if echo "$TRACKER_API_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ Tracker API accessible through domain"
else
    print_warning "⚠️ Tracker API response: $TRACKER_API_RESPONSE"
fi

# Test index API
print_status "Testing index API..."
INDEX_API_RESPONSE=$(curl -s "https://$DOMAIN/api/v1/settings/public")
print_status "Index API response: $INDEX_API_RESPONSE"

if echo "$INDEX_API_RESPONSE" | grep -q "tracker\|api"; then
    print_success "✅ Index API working"
else
    print_warning "⚠️ Index API response: $INDEX_API_RESPONSE"
fi

# Test upload endpoint
print_status "Testing upload endpoint..."
UPLOAD_RESPONSE=$(curl -s -I "https://$DOMAIN/api/v1/torrent/upload")
print_status "Upload endpoint response: $UPLOAD_RESPONSE"

if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "✅ Upload endpoint accessible"
elif echo "$UPLOAD_RESPONSE" | grep -q "503"; then
    print_error "❌ Upload endpoint returning 503"
else
    print_status "Upload endpoint response: $UPLOAD_RESPONSE"
fi

# 7. Show final configuration
print_status "7. Final configuration summary:"
print_status "Tracker API URL: https://$DOMAIN/tracker-api"
print_status "Index API URL: https://$DOMAIN/api/v1/"
print_status "Web Interface: https://$DOMAIN/"
print_status "HTTP Tracker: http://$DOMAIN:7070/announce"

print_status "Tracker API URL fix completed!"
print_status ""
print_status "The tracker API is now accessible through your domain:"
print_status "https://$DOMAIN/tracker-api/stats"
print_status ""
print_status "This should resolve the communication issues between Index and Tracker."
