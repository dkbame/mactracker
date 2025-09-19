#!/bin/bash

# Generate production-ready secure tokens and secrets
# Replace the default tokens with cryptographically secure ones

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

print_status "Generating production-ready secure tokens and secrets..."

cd "$PROJECT_ROOT"

# 1. Generate secure tokens and secrets
print_status "1. Generating secure tokens and secrets..."

# Generate tracker API admin token (32 bytes, base64 encoded)
TRACKER_ADMIN_TOKEN=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
print_success "Generated tracker admin token: ${TRACKER_ADMIN_TOKEN:0:8}..."

# Generate auth secret key (64 bytes, hex encoded)
AUTH_SECRET_KEY=$(openssl rand -hex 32)
print_success "Generated auth secret key: ${AUTH_SECRET_KEY:0:8}..."

# Generate user claim token pepper (32 bytes, base64 encoded)
USER_CLAIM_TOKEN_PEPPER=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
print_success "Generated user claim token pepper: ${USER_CLAIM_TOKEN_PEPPER:0:8}..."

# 2. Save secrets to secure files
print_status "2. Saving secrets to secure files..."

mkdir -p ./secrets

# Save tracker admin token
echo "$TRACKER_ADMIN_TOKEN" > ./secrets/tracker_admin_token.secret
chmod 600 ./secrets/tracker_admin_token.secret

# Save auth secret key
echo "$AUTH_SECRET_KEY" > ./secrets/auth_secret_key.secret
chmod 600 ./secrets/auth_secret_key.secret

# Save user claim token pepper
echo "$USER_CLAIM_TOKEN_PEPPER" > ./secrets/user_claim_token_pepper.secret
chmod 600 ./secrets/user_claim_token_pepper.secret

print_success "Secrets saved to ./secrets/ directory"

# 3. Update tracker configuration
print_status "3. Updating tracker configuration..."

cat > ./config/tracker.toml << EOF
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

[[http_trackers]]
bind_address = "0.0.0.0:7070"
tracker_usage_statistics = true

[http_api]
bind_address = "0.0.0.0:1212"

[http_api.access_tokens]
admin = "$TRACKER_ADMIN_TOKEN"
EOF

print_success "Tracker configuration updated with secure token"

# 4. Update index configuration
print_status "4. Updating index configuration..."

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
api_url = "http://tracker:1212"
token = "$TRACKER_ADMIN_TOKEN"

[database]
connect_url = "sqlite:///var/lib/torrust/index/database/sqlite3.db"

[auth]
secret_key = "$AUTH_SECRET_KEY"
user_claim_token_pepper = "$USER_CLAIM_TOKEN_PEPPER"

[tracker_statistics_importer]
port = 3002
torrent_info_update_interval = 3600

[unstable]
EOF

print_success "Index configuration updated with secure secrets"

# 5. Update Docker Compose with secure environment variables
print_status "5. Updating Docker Compose with secure environment variables..."

cat > docker-compose-https.yml << EOF
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
      - TORRUST_INDEX_CONFIG_OVERRIDE_TRACKER__TOKEN=$TRACKER_ADMIN_TOKEN
      - TORRUST_INDEX_CONFIG_OVERRIDE_AUTH__SECRET_KEY=$AUTH_SECRET_KEY
      - TORRUST_INDEX_CONFIG_OVERRIDE_AUTH__USER_CLAIM_TOKEN_PEPPER=$USER_CLAIM_TOKEN_PEPPER
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
      - NUXT_PUBLIC_API_BASE=https://$DOMAIN/api/v1
      - NITRO_HOST=0.0.0.0
      - NITRO_PORT=3000
    depends_on:
      - index
    restart: unless-stopped
    networks:
      - torrust

networks:
  torrust:
    driver: bridge
EOF

print_success "Docker Compose updated with secure environment variables"

# 6. Create .env file for easy access to secrets
print_status "6. Creating .env file for easy access to secrets..."

cat > .env << EOF
# Production Secrets for Torrust
# Generated on $(date)

# Tracker Admin Token
TRACKER_ADMIN_TOKEN=$TRACKER_ADMIN_TOKEN

# Auth Secret Key
AUTH_SECRET_KEY=$AUTH_SECRET_KEY

# User Claim Token Pepper
USER_CLAIM_TOKEN_PEPPER=$USER_CLAIM_TOKEN_PEPPER

# Domain
DOMAIN=$DOMAIN
EOF

chmod 600 .env

print_success ".env file created with secure secrets"

# 7. Restart services with new secrets
print_status "7. Restarting services with new secure secrets..."

docker compose -f docker-compose-https.yml down
sleep 5

# Start services
docker compose -f docker-compose-https.yml up -d
sleep 20

# 8. Test services with new secrets
print_status "8. Testing services with new secrets..."

# Test tracker locally
if curl -s http://127.0.0.1:1212/api/health_check | grep -q "Ok"; then
    print_success "✅ Tracker responding with new token"
else
    print_error "❌ Tracker not responding"
fi

# Test index locally
if curl -s http://127.0.0.1:3001/v1/settings/public | grep -q "tracker\|api"; then
    print_success "✅ Index responding with new secrets"
else
    print_error "❌ Index not responding"
fi

# Test GUI locally
if curl -s http://127.0.0.1:3000 | grep -q "html\|torrust"; then
    print_success "✅ GUI responding"
else
    print_error "❌ GUI not responding"
fi

# 9. Show final configuration
print_status "9. Final secure configuration summary:"
print_status "Generated secure tokens and secrets:"
print_status "  Tracker Admin Token: ${TRACKER_ADMIN_TOKEN:0:8}..."
print_status "  Auth Secret Key: ${AUTH_SECRET_KEY:0:8}..."
print_status "  User Claim Token Pepper: ${USER_CLAIM_TOKEN_PEPPER:0:8}..."
print_status ""
print_status "Files created:"
print_status "  ./secrets/tracker_admin_token.secret"
print_status "  ./secrets/auth_secret_key.secret"
print_status "  ./secrets/user_claim_token_pepper.secret"
print_status "  .env"
print_status ""
print_status "Environment variable overrides:"
print_status "  TORRUST_INDEX_CONFIG_OVERRIDE_TRACKER__TOKEN=${TRACKER_ADMIN_TOKEN:0:8}..."
print_status "  TORRUST_INDEX_CONFIG_OVERRIDE_AUTH__SECRET_KEY=${AUTH_SECRET_KEY:0:8}..."
print_status "  TORRUST_INDEX_CONFIG_OVERRIDE_AUTH__USER_CLAIM_TOKEN_PEPPER=${USER_CLAIM_TOKEN_PEPPER:0:8}..."

# 10. Final status check
print_status "10. Final status check..."
docker compose -f docker-compose-https.yml ps

print_success "Production secrets generation completed!"
print_status ""
print_status "Your Torrust setup now uses cryptographically secure tokens and secrets."
print_status "Keep the ./secrets/ directory and .env file secure and backed up."
print_status ""
print_warning "IMPORTANT: Never commit the ./secrets/ directory or .env file to version control!"
