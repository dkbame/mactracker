#!/bin/bash

# Diagnostic script for Torrust deployment
# Run this on your server to check what's wrong

set -e

print_status() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[0;33m[WARNING]\033[0m $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_status "Diagnosing Torrust deployment..."

cd /opt/torrust

# Check Docker containers
print_status "Checking Docker containers..."
docker compose -f docker-compose-fixed.yml ps

echo ""
print_status "Checking container logs..."

# Check tracker logs
print_status "=== TRACKER LOGS ==="
docker compose -f docker-compose-fixed.yml logs tracker | tail -10

echo ""
print_status "=== INDEX LOGS ==="
docker compose -f docker-compose-fixed.yml logs index | tail -10

echo ""
print_status "=== GUI LOGS ==="
docker compose -f docker-compose-fixed.yml logs gui | tail -10

echo ""
print_status "=== NGINX LOGS ==="
docker compose -f docker-compose-fixed.yml logs nginx | tail -10

echo ""
print_status "Testing endpoints..."

# Test tracker
print_status "Testing tracker API..."
if curl -s http://localhost:1212/api/v1/stats?token=MyAccessToken > /dev/null; then
    print_success "Tracker API is responding"
else
    print_error "Tracker API is not responding"
fi

# Test index
print_status "Testing index API..."
if curl -s http://localhost:3001/v1/torrents > /dev/null; then
    print_success "Index API is responding"
else
    print_error "Index API is not responding"
fi

# Test GUI
print_status "Testing GUI..."
if curl -s http://localhost:3000 > /dev/null; then
    print_success "GUI is responding"
else
    print_error "GUI is not responding"
fi

# Test nginx
print_status "Testing Nginx..."
if curl -s http://localhost:80 > /dev/null; then
    print_success "Nginx is responding"
else
    print_error "Nginx is not responding"
fi

echo ""
print_status "Checking port bindings..."
netstat -tlnp | grep -E "(80|3000|3001|1212)"

echo ""
print_status "Checking firewall..."
ufw status

echo ""
print_status "Testing external access..."
print_status "Testing from server itself..."
curl -I http://109.104.153.250/ 2>/dev/null || print_error "Cannot access from server"

echo ""
print_status "=== DIAGNOSIS COMPLETE ==="
print_status "If all services are running but the web interface is not accessible:"
print_status "1. Check if port 80 is open in your server's firewall"
print_status "2. Check if your hosting provider blocks port 80"
print_status "3. Try accessing the GUI directly: http://109.104.153.250:3000"
print_status "4. Check if there are any reverse proxy or load balancer issues"
