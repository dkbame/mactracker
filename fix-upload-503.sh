#!/bin/bash

# Fix torrent upload 503 error
# This script will restart services and fix common issues

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

print_status "Fixing torrent upload 503 error..."

cd "$PROJECT_ROOT"

# 1. Stop all services
print_status "1. Stopping all services..."
docker compose -f docker-compose-https.yml down
systemctl stop nginx

# 2. Clean up any stuck processes
print_status "2. Cleaning up stuck processes..."
pkill -f "torrust" 2>/dev/null || true
sleep 2

# 3. Ensure database directories exist
print_status "3. Creating database directories..."
mkdir -p ./storage/index/lib/database
mkdir -p ./storage/tracker/lib/database

# 4. Start services in correct order
print_status "4. Starting services in correct order..."

# Start tracker first
print_status "Starting tracker..."
docker compose -f docker-compose-https.yml up -d tracker
sleep 5

# Start index
print_status "Starting index..."
docker compose -f docker-compose-https.yml up -d index
sleep 5

# Start GUI
print_status "Starting GUI..."
docker compose -f docker-compose-https.yml up -d gui
sleep 5

# Start Nginx
print_status "Starting Nginx..."
systemctl start nginx

# 5. Wait for services to be ready
print_status "5. Waiting for services to be ready..."
sleep 10

# 6. Test all endpoints
print_status "6. Testing all endpoints..."

# Test tracker
if curl -s -I http://127.0.0.1:1212/health | grep -q "200 OK"; then
    print_success "Tracker API is responding"
else
    print_error "Tracker API is not responding"
fi

# Test index
if curl -s -I http://127.0.0.1:3001/v1/health | grep -q "200 OK"; then
    print_success "Index API is responding"
else
    print_error "Index API is not responding"
fi

# Test GUI
if curl -s -I http://127.0.0.1:3000 | grep -q "200 OK"; then
    print_success "GUI is responding"
else
    print_error "GUI is not responding"
fi

# Test Nginx proxy
if curl -s -I https://$DOMAIN/api/v1/health | grep -q "200 OK"; then
    print_success "API proxy is working"
else
    print_error "API proxy is not working"
fi

# 7. Check if upload endpoint is working
print_status "7. Testing upload endpoint..."
if curl -s -I https://$DOMAIN/api/v1/torrent/upload | grep -q "401\|405"; then
    print_success "Upload endpoint is accessible (401/405 is expected without auth)"
else
    print_warning "Upload endpoint may have issues"
fi

# 8. Check tracker communication
print_status "8. Testing tracker communication..."
TRACKER_TOKEN=$(grep "admin" ./config/tracker.toml | cut -d'"' -f2 2>/dev/null || echo "")
if [ -n "$TRACKER_TOKEN" ]; then
    print_status "Testing tracker API with token..."
    if curl -s -H "Authorization: Bearer $TRACKER_TOKEN" http://127.0.0.1:1212/stats | grep -q "stats"; then
        print_success "Tracker communication is working"
    else
        print_warning "Tracker communication may have issues"
    fi
else
    print_warning "No tracker token found in config"
fi

# 9. Show final status
print_status "9. Final service status:"
docker compose -f docker-compose-https.yml ps

print_status "10. Port bindings:"
netstat -tlnp | grep -E ":(3000|3001|1212|7070|6969)" || print_warning "Some ports may not be listening"

print_success "Upload 503 error fix completed!"
print_status ""
print_status "Try uploading a torrent now. If you still get 503 errors:"
print_status "1. Check the browser console for more specific error messages"
print_status "2. Ensure your torrent file is valid"
print_status "3. Check that the tracker announce URL is correct:"
print_status "   http://109.104.153.250:7070/announce"
print_status ""
print_status "To view real-time logs:"
print_status "  docker compose -f docker-compose-https.yml logs -f"
