# Manual Fix for Mixed Content Issues

## Quick Steps to Fix Mixed Content

### Step 1: Stop the GUI container
```bash
cd /opt/torrust
docker compose -f docker-compose-fixed.yml stop gui
```

### Step 2: Create new Docker Compose file with HTTPS API
```bash
cat > docker-compose-https.yml << 'EOF'
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
      - NUXT_PUBLIC_API_BASE=https://macosapps.net:3001/v1
    depends_on:
      - index
    restart: unless-stopped
    networks:
      - torrust

networks:
  torrust:
    driver: bridge
EOF
```

### Step 3: Start services with HTTPS configuration
```bash
docker compose -f docker-compose-https.yml up -d
```

### Step 4: Update Nginx configuration
```bash
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
    
    # API routes (proxy to index service)
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
```

### Step 5: Test and reload Nginx
```bash
nginx -t
systemctl reload nginx
```

### Step 6: Test the setup
```bash
# Test API endpoint
curl -I https://macosapps.net/api/v1/health

# Test GUI
curl -I https://macosapps.net
```

## What This Fixes

- **Mixed Content**: Frontend now uses HTTPS for all API calls
- **CORS**: Proper headers for cross-origin requests
- **Security**: All traffic encrypted end-to-end

## After the Fix

Your API endpoints will be:
- Settings: `https://macosapps.net/api/v1/settings/public`
- Tags: `https://macosapps.net/api/v1/tags`
- Categories: `https://macosapps.net/api/v1/category`
- Torrents: `https://macosapps.net/api/v1/torrents`
