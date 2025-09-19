#!/bin/bash

# Test Tracker API authorization
# This script will test all the tracker endpoints with proper authentication

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

print_status "Testing Tracker API authorization..."

cd "$PROJECT_ROOT"

# Test endpoints with and without authentication
print_status "Testing tracker endpoints..."

# 1. Test /api/health_check (no auth required)
print_status "1. Testing /api/health_check (no auth required)..."
HEALTH_CHECK_RESPONSE=$(curl -s http://127.0.0.1:1212/api/health_check)
print_status "Response: $HEALTH_CHECK_RESPONSE"
if echo "$HEALTH_CHECK_RESPONSE" | grep -q "Ok"; then
    print_success "✅ /api/health_check working"
else
    print_error "❌ /api/health_check failed"
fi

# 2. Test /stats without auth
print_status "2. Testing /stats without authentication..."
STATS_NO_AUTH=$(curl -s http://127.0.0.1:1212/stats)
print_status "Response: $STATS_NO_AUTH"
if echo "$STATS_NO_AUTH" | grep -q "unauthorized"; then
    print_success "✅ /stats correctly requires authentication"
else
    print_warning "⚠️ /stats response without auth: $STATS_NO_AUTH"
fi

# 3. Test /stats with auth
print_status "3. Testing /stats with authentication..."
STATS_WITH_AUTH=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats)
print_status "Response: $STATS_WITH_AUTH"
if echo "$STATS_WITH_AUTH" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /stats with auth working"
elif echo "$STATS_WITH_AUTH" | grep -q "unauthorized"; then
    print_error "❌ /stats still unauthorized with token"
else
    print_warning "⚠️ /stats with auth response: $STATS_WITH_AUTH"
fi

# 4. Test /api/stats with auth
print_status "4. Testing /api/stats with authentication..."
API_STATS_AUTH=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/api/stats)
print_status "Response: $API_STATS_AUTH"
if echo "$API_STATS_AUTH" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /api/stats with auth working"
elif echo "$API_STATS_AUTH" | grep -q "unauthorized"; then
    print_error "❌ /api/stats still unauthorized with token"
else
    print_warning "⚠️ /api/stats with auth response: $API_STATS_AUTH"
fi

# 5. Test /api/v1/stats with auth
print_status "5. Testing /api/v1/stats with authentication..."
API_V1_STATS_AUTH=$(curl -s -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/api/v1/stats)
print_status "Response: $API_V1_STATS_AUTH"
if echo "$API_V1_STATS_AUTH" | grep -q "stats\|tracker\|torrents"; then
    print_success "✅ /api/v1/stats with auth working"
elif echo "$API_V1_STATS_AUTH" | grep -q "unauthorized"; then
    print_error "❌ /api/v1/stats still unauthorized with token"
else
    print_warning "⚠️ /api/v1/stats with auth response: $API_V1_STATS_AUTH"
fi

# 6. Test HTTP tracker (should work without auth)
print_status "6. Testing HTTP tracker (no auth required)..."
HTTP_TRACKER_RESPONSE=$(curl -s http://127.0.0.1:7070/announce)
print_status "Response: $HTTP_TRACKER_RESPONSE"
if echo "$HTTP_TRACKER_RESPONSE" | grep -q "announce\|tracker"; then
    print_success "✅ HTTP tracker working"
else
    print_error "❌ HTTP tracker failed"
fi

# 7. Test different token formats
print_status "7. Testing different token formats..."

# Test with different header format
print_status "Testing with 'Token' header..."
STATS_TOKEN_HEADER=$(curl -s -H "Token: MyAccessToken" http://127.0.0.1:1212/stats)
print_status "Response with Token header: $STATS_TOKEN_HEADER"

# Test with query parameter
print_status "Testing with query parameter..."
STATS_QUERY=$(curl -s "http://127.0.0.1:1212/stats?token=MyAccessToken")
print_status "Response with query param: $STATS_QUERY"

# 8. Summary
print_status "8. Authorization test summary:"
echo ""
print_status "Working endpoints:"
if echo "$HEALTH_CHECK_RESPONSE" | grep -q "Ok"; then
    print_success "  ✅ /api/health_check"
fi
if echo "$HTTP_TRACKER_RESPONSE" | grep -q "announce\|tracker"; then
    print_success "  ✅ HTTP Tracker (port 7070)"
fi
if echo "$STATS_WITH_AUTH" | grep -q "stats\|tracker\|torrents"; then
    print_success "  ✅ /stats (with auth)"
fi

echo ""
print_status "Endpoints with issues:"
if echo "$STATS_WITH_AUTH" | grep -q "unauthorized"; then
    print_error "  ❌ /stats (authorization failing)"
fi
if echo "$API_STATS_AUTH" | grep -q "unauthorized"; then
    print_error "  ❌ /api/stats (authorization failing)"
fi
if echo "$API_V1_STATS_AUTH" | grep -q "unauthorized"; then
    print_error "  ❌ /api/v1/stats (authorization failing)"
fi

echo ""
print_status "For torrent uploads, use:"
print_status "http://109.104.153.250:7070/announce"
