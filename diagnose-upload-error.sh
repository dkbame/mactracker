#!/bin/bash

# Diagnose torrent upload 503 error
# This script will check all services and identify the issue

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

print_status "Diagnosing torrent upload 503 error..."

cd "$PROJECT_ROOT"

# 1. Check if all containers are running
print_status "1. Checking Docker containers..."
docker compose -f docker-compose-https.yml ps

# 2. Check if services are responding
print_status "2. Checking service endpoints..."

# Check GUI
print_status "Checking GUI (port 3000)..."
if curl -s -I http://127.0.0.1:3000 | grep -q "200 OK"; then
    print_success "GUI is responding"
else
    print_error "GUI is not responding"
fi

# Check Index API
print_status "Checking Index API (port 3001)..."
if curl -s -I http://127.0.0.1:3001/v1/health | grep -q "200 OK"; then
    print_success "Index API is responding"
else
    print_error "Index API is not responding"
fi

# Check Tracker API
print_status "Checking Tracker API (port 1212)..."
if curl -s -I http://127.0.0.1:1212/health | grep -q "200 OK"; then
    print_success "Tracker API is responding"
else
    print_error "Tracker API is not responding"
fi

# Check Tracker HTTP endpoints
print_status "Checking Tracker HTTP (port 7070)..."
if curl -s -I http://127.0.0.1:7070/announce | grep -q "200\|400"; then
    print_success "Tracker HTTP is responding"
else
    print_error "Tracker HTTP is not responding"
fi

# 3. Check Nginx proxy
print_status "3. Checking Nginx proxy..."
if curl -s -I https://$DOMAIN/api/v1/health | grep -q "200 OK"; then
    print_success "API proxy is working"
else
    print_error "API proxy is not working"
    print_status "Testing direct API access..."
    curl -s -I https://$DOMAIN/api/v1/health || true
fi

# 4. Check logs for errors
print_status "4. Checking recent logs for errors..."

print_status "Index container logs (last 20 lines):"
docker compose -f docker-compose-https.yml logs --tail=20 index

print_status "Tracker container logs (last 20 lines):"
docker compose -f docker-compose-https.yml logs --tail=20 tracker

print_status "Nginx logs (last 10 lines):"
journalctl -u nginx --no-pager -n 10

# 5. Check database connectivity
print_status "5. Checking database files..."
if [ -f "./storage/index/lib/database/sqlite3.db" ]; then
    print_success "Index database exists"
    ls -la ./storage/index/lib/database/sqlite3.db
else
    print_error "Index database is missing"
fi

if [ -f "./storage/tracker/lib/database/sqlite3.db" ]; then
    print_success "Tracker database exists"
    ls -la ./storage/tracker/lib/database/sqlite3.db
else
    print_error "Tracker database is missing"
fi

# 6. Check tracker configuration
print_status "6. Checking tracker configuration..."
if [ -f "./config/tracker.toml" ]; then
    print_success "Tracker config exists"
    print_status "Tracker admin token:"
    grep "admin" ./config/tracker.toml
else
    print_error "Tracker config is missing"
fi

if [ -f "./config/index.toml" ]; then
    print_success "Index config exists"
    print_status "Index tracker API URL:"
    grep -A 5 "\[tracker\]" ./config/index.toml || print_warning "No tracker section in index config"
else
    print_error "Index config is missing"
fi

# 7. Test tracker communication
print_status "7. Testing tracker communication..."
TRACKER_TOKEN=$(grep "admin" ./config/tracker.toml | cut -d'"' -f2)
if [ -n "$TRACKER_TOKEN" ]; then
    print_status "Testing tracker API with token: $TRACKER_TOKEN"
    curl -s -H "Authorization: Bearer $TRACKER_TOKEN" http://127.0.0.1:1212/stats || print_warning "Tracker API test failed"
else
    print_warning "No tracker token found"
fi

# 8. Check port bindings
print_status "8. Checking port bindings..."
netstat -tlnp | grep -E ":(3000|3001|1212|7070|6969)" || print_warning "Some expected ports are not listening"

# 9. Provide recommendations
print_status "9. Recommendations:"
echo ""
print_status "If Index API is not responding:"
print_status "  docker compose -f docker-compose-https.yml restart index"
echo ""
print_status "If Tracker API is not responding:"
print_status "  docker compose -f docker-compose-https.yml restart tracker"
echo ""
print_status "If databases are missing:"
print_status "  docker compose -f docker-compose-https.yml down"
print_status "  docker compose -f docker-compose-https.yml up -d"
echo ""
print_status "If Nginx proxy is not working:"
print_status "  systemctl restart nginx"
echo ""
print_status "To restart all services:"
print_status "  docker compose -f docker-compose-https.yml restart"
print_status "  systemctl reload nginx"
