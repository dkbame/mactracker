#!/bin/bash

# Quick fix for 503 upload error
# Based on diagnostic findings

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

print_status "Quick fix for 503 upload error..."

cd /opt/torrust

# 1. Stop all services
print_status "Stopping all services..."
docker compose -f docker-compose-https.yml down
systemctl stop nginx

# 2. Start tracker first and wait
print_status "Starting tracker..."
docker compose -f docker-compose-https.yml up -d tracker
sleep 15

# 3. Start index and wait
print_status "Starting index..."
docker compose -f docker-compose-https.yml up -d index
sleep 15

# 4. Start GUI
print_status "Starting GUI..."
docker compose -f docker-compose-https.yml up -d gui
sleep 5

# 5. Start Nginx
print_status "Starting Nginx..."
systemctl start nginx

# 6. Test endpoints
print_status "Testing endpoints..."

# Test tracker
if curl -s http://127.0.0.1:1212/stats | grep -q "stats"; then
    print_success "Tracker API working"
else
    print_error "Tracker API not working"
fi

# Test index
if curl -s http://127.0.0.1:3001/v1/settings/public | grep -q "tracker"; then
    print_success "Index API working"
else
    print_error "Index API not working"
fi

# Test upload endpoint
UPLOAD_TEST=$(curl -s -I https://macosapps.net/api/v1/torrent/upload)
if echo "$UPLOAD_TEST" | grep -q "401\|405"; then
    print_success "Upload endpoint accessible"
else
    print_error "Upload endpoint still has issues: $UPLOAD_TEST"
fi

print_status "Quick fix completed. Try uploading a torrent now."
