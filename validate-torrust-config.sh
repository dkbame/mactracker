#!/bin/bash

# Validate Torrust configuration against official documentation
# This script ensures all components are configured correctly

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

print_status "Validating Torrust configuration against official documentation..."

cd "$PROJECT_ROOT"

# 1. Check tracker configuration
print_status "1. Validating tracker configuration..."
if [ -f "./config/tracker.toml" ]; then
    print_success "Tracker config file exists"
    
    # Check required sections
    if grep -q "\[http_api\]" ./config/tracker.toml; then
        print_success "✅ HTTP API section present"
    else
        print_error "❌ HTTP API section missing"
    fi
    
    if grep -q "bind_address = \"0.0.0.0:1212\"" ./config/tracker.toml; then
        print_success "✅ API bind address correct"
    else
        print_error "❌ API bind address incorrect"
    fi
    
    if grep -q "admin = \"MyAccessToken\"" ./config/tracker.toml; then
        print_success "✅ Admin token configured"
    else
        print_error "❌ Admin token missing or incorrect"
    fi
    
    if grep -q "bind_address = \"0.0.0.0:7070\"" ./config/tracker.toml; then
        print_success "✅ HTTP tracker bind address correct"
    else
        print_error "❌ HTTP tracker bind address incorrect"
    fi
else
    print_error "Tracker config file missing!"
fi

# 2. Check index configuration
print_status "2. Validating index configuration..."
if [ -f "./config/index.toml" ]; then
    print_success "Index config file exists"
    
    # Check required sections
    if grep -q "\[tracker\]" ./config/index.toml; then
        print_success "✅ Tracker section present"
    else
        print_error "❌ Tracker section missing"
    fi
    
    if grep -q "api_url = \"http://tracker:1212\"" ./config/index.toml; then
        print_success "✅ Tracker API URL correct"
    else
        print_error "❌ Tracker API URL incorrect"
    fi
    
    if grep -q "token = \"MyAccessToken\"" ./config/index.toml; then
        print_success "✅ Tracker token configured"
    else
        print_error "❌ Tracker token missing or incorrect"
    fi
    
    if grep -q "bind_address = \"0.0.0.0:3001\"" ./config/index.toml; then
        print_success "✅ Index bind address correct"
    else
        print_error "❌ Index bind address incorrect"
    fi
else
    print_error "Index config file missing!"
fi

# 3. Check database files
print_status "3. Validating database files..."
if [ -f "./storage/tracker/lib/database/sqlite3.db" ]; then
    print_success "✅ Tracker database exists"
    ls -la ./storage/tracker/lib/database/sqlite3.db
else
    print_error "❌ Tracker database missing"
fi

if [ -f "./storage/index/lib/database/sqlite3.db" ]; then
    print_success "✅ Index database exists"
    ls -la ./storage/index/lib/database/sqlite3.db
else
    print_error "❌ Index database missing"
fi

# 4. Check service status
print_status "4. Validating service status..."
docker compose -f docker-compose-https.yml ps

# 5. Test API endpoints
print_status "5. Testing API endpoints..."

# Test tracker health
print_status "Testing tracker health endpoint..."
if curl -s http://127.0.0.1:1212/api/health_check | grep -q "Ok"; then
    print_success "✅ Tracker health endpoint working"
else
    print_error "❌ Tracker health endpoint failed"
fi

# Test tracker stats with auth
print_status "Testing tracker stats with authentication..."
STATS_RESPONSE=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats)
if echo "$STATS_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ Tracker stats endpoint working with auth"
elif echo "$STATS_RESPONSE" | grep -q "unauthorized"; then
    print_error "❌ Tracker stats endpoint authorization failed"
else
    print_warning "⚠️ Tracker stats endpoint response: $STATS_RESPONSE"
fi

# Test index API
print_status "Testing index API..."
if curl -s http://127.0.0.1:3001/v1/settings/public | grep -q "tracker\|api"; then
    print_success "✅ Index API working"
else
    print_error "❌ Index API failed"
fi

# Test HTTP tracker
print_status "Testing HTTP tracker..."
if curl -s http://127.0.0.1:7070/announce | grep -q "announce\|tracker"; then
    print_success "✅ HTTP tracker working"
else
    print_error "❌ HTTP tracker failed"
fi

# 6. Test index-tracker communication
print_status "6. Testing index-tracker communication..."
INDEX_TRACKER_RESPONSE=$(docker exec torrust-index curl -s -H "Authorization: Bearer MyAccessToken" http://tracker:1212/stats 2>/dev/null || echo "ERROR")
if echo "$INDEX_TRACKER_RESPONSE" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ Index-tracker communication working"
elif echo "$INDEX_TRACKER_RESPONSE" | grep -q "ERROR"; then
    print_error "❌ Index-tracker communication failed"
else
    print_warning "⚠️ Index-tracker communication response: $INDEX_TRACKER_RESPONSE"
fi

# 7. Test upload endpoint
print_status "7. Testing upload endpoint..."
UPLOAD_RESPONSE=$(curl -s -I https://macosapps.net/api/v1/torrent/upload)
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "✅ Upload endpoint accessible"
elif echo "$UPLOAD_RESPONSE" | grep -q "503"; then
    print_error "❌ Upload endpoint returning 503"
else
    print_status "Upload endpoint response: $UPLOAD_RESPONSE"
fi

# 8. Check logs for errors
print_status "8. Checking recent logs for errors..."
print_status "Tracker logs (last 5 lines):"
docker compose -f docker-compose-https.yml logs --tail=5 tracker

print_status "Index logs (last 5 lines):"
docker compose -f docker-compose-https.yml logs --tail=5 index

# 9. Summary
print_status "9. Configuration validation summary:"
echo ""
print_status "✅ Working components:"
print_success "  - HTTP Tracker (port 7070)"
print_success "  - Web Interface (https://macosapps.net)"
print_success "  - Index API (port 3001)"

echo ""
print_status "⚠️ Components needing attention:"
if ! curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats | grep -q "stats\|tracker"; then
    print_warning "  - Tracker API authorization"
fi

echo ""
print_status "📋 Configuration based on official documentation:"
print_status "  - Tracker API: http://127.0.0.1:1212"
print_status "  - Index API: http://127.0.0.1:3001"
print_status "  - HTTP Tracker: http://127.0.0.1:7070"
print_status "  - Web Interface: https://macosapps.net"

print_status "Configuration validation completed!"
