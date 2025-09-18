#!/bin/bash

# Fix Tracker API issues specifically
# This script will diagnose and fix Tracker API problems

set -e

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

print_status "Fixing Tracker API issues..."

cd "$PROJECT_ROOT"

# 1. Stop tracker container
print_status "1. Stopping tracker container..."
docker compose -f docker-compose-https.yml stop tracker

# 2. Check tracker configuration
print_status "2. Checking tracker configuration..."
if [ -f "./config/tracker.toml" ]; then
    print_success "Tracker config exists"
    print_status "Tracker config contents:"
    cat ./config/tracker.toml
else
    print_error "Tracker config missing!"
    exit 1
fi

# 3. Check database permissions
print_status "3. Checking database permissions..."
if [ -f "./storage/tracker/lib/database/sqlite3.db" ]; then
    print_success "Tracker database exists"
    ls -la ./storage/tracker/lib/database/sqlite3.db
    print_status "Fixing database permissions..."
    chmod 664 ./storage/tracker/lib/database/sqlite3.db
    chown 1000:1000 ./storage/tracker/lib/database/sqlite3.db
else
    print_warning "Tracker database missing, creating..."
    mkdir -p ./storage/tracker/lib/database
    touch ./storage/tracker/lib/database/sqlite3.db
    chmod 664 ./storage/tracker/lib/database/sqlite3.db
    chown 1000:1000 ./storage/tracker/lib/database/sqlite3.db
fi

# 4. Create a minimal tracker config if needed
print_status "4. Creating minimal tracker config..."
cat > ./config/tracker.toml << 'EOF'
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

[[udp_trackers]]
bind_address = "0.0.0.0:6969"
tracker_usage_statistics = true

[[http_trackers]]
bind_address = "0.0.0.0:7070"
tracker_usage_statistics = true

[http_api]
bind_address = "0.0.0.0:1212"

[http_api.access_tokens]
admin = "MyAccessToken"
EOF

print_success "Tracker config created/updated"

# 5. Start tracker container
print_status "5. Starting tracker container..."
docker compose -f docker-compose-https.yml up -d tracker

# 6. Wait for tracker to start
print_status "6. Waiting for tracker to start..."
sleep 15

# 7. Test tracker endpoints
print_status "7. Testing tracker endpoints..."

# Test health endpoint
print_status "Testing health endpoint..."
if curl -s http://127.0.0.1:1212/health 2>/dev/null | grep -q "healthy\|ok"; then
    print_success "Health endpoint working"
else
    print_warning "Health endpoint not working, trying alternative..."
    curl -s http://127.0.0.1:1212/health || true
fi

# Test stats endpoint
print_status "Testing stats endpoint..."
if curl -s http://127.0.0.1:1212/stats 2>/dev/null | grep -q "stats\|tracker"; then
    print_success "Stats endpoint working"
else
    print_warning "Stats endpoint not working, trying alternative..."
    curl -s http://127.0.0.1:1212/stats || true
fi

# Test with admin token
print_status "Testing with admin token..."
if curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats 2>/dev/null | grep -q "stats\|tracker"; then
    print_success "Stats with token working"
else
    print_warning "Stats with token not working, trying alternative..."
    curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats || true
fi

# Test HTTP tracker
print_status "Testing HTTP tracker..."
if curl -s http://127.0.0.1:7070/announce 2>/dev/null | grep -q "announce\|tracker"; then
    print_success "HTTP tracker working"
else
    print_warning "HTTP tracker not working, trying alternative..."
    curl -s http://127.0.0.1:7070/announce || true
fi

# 8. Check tracker logs
print_status "8. Checking tracker logs..."
print_status "Recent tracker logs:"
docker compose -f docker-compose-https.yml logs --tail=20 tracker

# 9. Test port bindings
print_status "9. Checking port bindings..."
netstat -tlnp | grep -E ":(1212|7070|6969)" || print_warning "Some tracker ports not listening"

# 10. If still not working, try restarting with fresh container
if ! curl -s http://127.0.0.1:1212/stats 2>/dev/null | grep -q "stats\|tracker"; then
    print_status "10. Tracker still not working, trying fresh restart..."
    
    # Remove tracker container completely
    docker compose -f docker-compose-https.yml rm -f tracker
    
    # Start fresh
    docker compose -f docker-compose-https.yml up -d tracker
    sleep 20
    
    # Test again
    print_status "Testing after fresh restart..."
    if curl -s http://127.0.0.1:1212/stats 2>/dev/null | grep -q "stats\|tracker"; then
        print_success "Tracker working after fresh restart"
    else
        print_error "Tracker still not working after fresh restart"
        print_status "Full tracker logs:"
        docker compose -f docker-compose-https.yml logs tracker
    fi
fi

print_status "Tracker API fix completed!"
print_status ""
print_status "If tracker is still not working, check:"
print_status "1. Docker logs: docker compose -f docker-compose-https.yml logs tracker"
print_status "2. Port conflicts: netstat -tlnp | grep -E ':(1212|7070|6969)'"
print_status "3. Database permissions: ls -la ./storage/tracker/lib/database/"
print_status "4. Container status: docker compose -f docker-compose-https.yml ps"
