#!/bin/bash

# Script to start Torrust services

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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status "Starting Torrust services..."

cd "$PROJECT_ROOT"

# 1. Stop any existing services
print_status "1. Stopping any existing services..."
docker compose -f docker-compose-https.yml down

# 2. Start the services
print_status "2. Starting Torrust services..."
docker compose -f docker-compose-https.yml up -d

# 3. Wait for services to be ready
print_status "3. Waiting for services to be ready..."
sleep 15

# 4. Check service status
print_status "4. Checking service status..."
docker compose -f docker-compose-https.yml ps

# 5. Test services
print_status "5. Testing services..."

# Test GUI
if curl -s -I https://macosapps.net | grep -q "200\|301\|302"; then
    print_success "✅ GUI is accessible at https://macosapps.net"
else
    print_warning "⚠️  GUI might not be ready yet, please wait a moment"
fi

# Test Index API
if curl -s http://127.0.0.1:3001/v1/settings/public | grep -q "tracker\|api"; then
    print_success "✅ Index API is responding"
else
    print_warning "⚠️  Index API not responding yet"
fi

# Test Tracker
if curl -s http://127.0.0.1:7070/health_check | grep -q "200"; then
    print_success "✅ Tracker HTTP is responding"
else
    print_warning "⚠️  Tracker HTTP not responding yet"
fi

print_status "Services started! You can now:"
print_status "1. Visit https://macosapps.net to access the web interface"
print_status "2. Run the tracker URL display script if needed"
print_status "3. Upload torrents and test the system"
