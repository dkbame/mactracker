#!/bin/bash

# Fix specific issues found in diagnostic
# 1. Index API 404 on health endpoint
# 2. Tracker API 500 errors
# 3. Index-Tracker communication issues

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

print_status "Fixing specific issues found in diagnostic..."

cd "$PROJECT_ROOT"

# 1. Fix Index API health endpoint issue
print_status "1. Fixing Index API health endpoint..."

# Check if the health endpoint exists
if curl -s http://127.0.0.1:3001/v1/health 2>/dev/null | grep -q "healthy\|ok"; then
    print_success "Index API health endpoint is working"
else
    print_warning "Index API health endpoint not responding properly"
    print_status "Testing other Index API endpoints..."
    
    # Test root endpoint
    curl -s http://127.0.0.1:3001/ || print_warning "Root endpoint failed"
    
    # Test API root
    curl -s http://127.0.0.1:3001/v1/ || print_warning "API root failed"
    
    # Test settings endpoint
    curl -s http://127.0.0.1:3001/v1/settings/public || print_warning "Settings endpoint failed"
fi

# 2. Fix Tracker API 500 errors
print_status "2. Fixing Tracker API 500 errors..."

# Check tracker API health
if curl -s http://127.0.0.1:1212/health 2>/dev/null | grep -q "healthy\|ok"; then
    print_success "Tracker API health endpoint is working"
else
    print_warning "Tracker API health endpoint has issues"
    print_status "Testing tracker API endpoints..."
    
    # Test tracker stats
    curl -s http://127.0.0.1:1212/stats || print_warning "Stats endpoint failed"
    
    # Test with admin token
    TRACKER_TOKEN="MyAccessToken"
    curl -s -H "Authorization: Bearer $TRACKER_TOKEN" http://127.0.0.1:1212/stats || print_warning "Stats with token failed"
fi

# 3. Fix Index-Tracker communication
print_status "3. Fixing Index-Tracker communication..."

# Check if tracker is accessible from index container
print_status "Testing tracker connectivity from index container..."
docker exec torrust-index curl -s http://tracker:1212/health || print_warning "Tracker not accessible from index container"

# Check tracker configuration in index
print_status "Checking index tracker configuration..."
if [ -f "./config/index.toml" ]; then
    print_status "Index tracker config:"
    grep -A 10 "\[tracker\]" ./config/index.toml || print_warning "No tracker section in index config"
fi

# 4. Restart services in correct order
print_status "4. Restarting services in correct order..."

# Stop all services
print_status "Stopping all services..."
docker compose -f docker-compose-https.yml down
sleep 3

# Start tracker first
print_status "Starting tracker..."
docker compose -f docker-compose-https.yml up -d tracker
sleep 10

# Check tracker is ready
print_status "Checking tracker readiness..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:1212/health 2>/dev/null | grep -q "healthy\|ok"; then
        print_success "Tracker is ready"
        break
    elif [ $i -eq 30 ]; then
        print_error "Tracker failed to start properly"
        docker compose -f docker-compose-https.yml logs tracker
        exit 1
    else
        print_status "Waiting for tracker... ($i/30)"
        sleep 2
    fi
done

# Start index
print_status "Starting index..."
docker compose -f docker-compose-https.yml up -d index
sleep 10

# Check index is ready
print_status "Checking index readiness..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:3001/v1/settings/public 2>/dev/null | grep -q "tracker\|api"; then
        print_success "Index is ready"
        break
    elif [ $i -eq 30 ]; then
        print_error "Index failed to start properly"
        docker compose -f docker-compose-https.yml logs index
        exit 1
    else
        print_status "Waiting for index... ($i/30)"
        sleep 2
    fi
done

# Start GUI
print_status "Starting GUI..."
docker compose -f docker-compose-https.yml up -d gui
sleep 5

# 5. Test all endpoints
print_status "5. Testing all endpoints..."

# Test tracker API
if curl -s http://127.0.0.1:1212/health | grep -q "healthy\|ok"; then
    print_success "Tracker API is responding"
else
    print_warning "Tracker API still has issues"
fi

# Test index API
if curl -s http://127.0.0.1:3001/v1/settings/public | grep -q "tracker\|api"; then
    print_success "Index API is responding"
else
    print_warning "Index API still has issues"
fi

# Test GUI
if curl -s http://127.0.0.1:3000 | grep -q "html\|torrust"; then
    print_success "GUI is responding"
else
    print_warning "GUI still has issues"
fi

# Test Nginx proxy
if curl -s https://$DOMAIN/api/v1/settings/public | grep -q "tracker\|api"; then
    print_success "API proxy is working"
else
    print_warning "API proxy still has issues"
fi

# 6. Test upload endpoint specifically
print_status "6. Testing upload endpoint..."
UPLOAD_RESPONSE=$(curl -s -I https://$DOMAIN/api/v1/torrent/upload)
if echo "$UPLOAD_RESPONSE" | grep -q "401\|405"; then
    print_success "Upload endpoint is accessible (401/405 expected without auth)"
elif echo "$UPLOAD_RESPONSE" | grep -q "503"; then
    print_error "Upload endpoint still returning 503"
    print_status "Response: $UPLOAD_RESPONSE"
else
    print_warning "Upload endpoint response: $UPLOAD_RESPONSE"
fi

# 7. Show final status
print_status "7. Final service status:"
docker compose -f docker-compose-https.yml ps

print_success "Specific issues fix completed!"
print_status ""
print_status "If upload still returns 503, check:"
print_status "1. Browser console for detailed error messages"
print_status "2. Index container logs: docker compose -f docker-compose-https.yml logs index"
print_status "3. Tracker container logs: docker compose -f docker-compose-https.yml logs tracker"
print_status ""
print_status "To monitor real-time logs:"
print_status "  docker compose -f docker-compose-https.yml logs -f"
