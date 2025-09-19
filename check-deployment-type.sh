#!/bin/bash

# Script to check what type of Torrust deployment is being used

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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_status "Checking Torrust deployment type..."

cd "$PROJECT_ROOT"

echo "=========================================="
echo "🔍 TORRUST DEPLOYMENT DETECTION"
echo "=========================================="

# 1. Check for Docker Compose files
print_status "1. Checking for Docker Compose files..."
if [ -f "docker-compose.yml" ]; then
    print_success "✅ Found docker-compose.yml"
else
    print_warning "⚠️  No docker-compose.yml found"
fi

if [ -f "docker-compose-https.yml" ]; then
    print_success "✅ Found docker-compose-https.yml"
else
    print_warning "⚠️  No docker-compose-https.yml found"
fi

# 2. Check for Docker containers
print_status "2. Checking for running Docker containers..."
if command -v docker >/dev/null 2>&1; then
    print_success "✅ Docker is installed"
    
    # Check for Torrust containers
    TORRUST_CONTAINERS=$(docker ps --filter "name=torrust" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "")
    if [ -n "$TORRUST_CONTAINERS" ]; then
        print_success "✅ Found Torrust Docker containers:"
        echo "$TORRUST_CONTAINERS"
    else
        print_warning "⚠️  No Torrust Docker containers found"
    fi
else
    print_warning "⚠️  Docker not installed"
fi

# 3. Check for systemd services
print_status "3. Checking for systemd services..."
if systemctl list-units --type=service | grep -i torrust >/dev/null 2>&1; then
    print_success "✅ Found Torrust systemd services:"
    systemctl list-units --type=service | grep -i torrust
else
    print_warning "⚠️  No Torrust systemd services found"
fi

# 4. Check for running processes
print_status "4. Checking for Torrust processes..."
TORRUST_PROCESSES=$(ps aux | grep -E "(torrust|tracker|index)" | grep -v grep || echo "")
if [ -n "$TORRUST_PROCESSES" ]; then
    print_success "✅ Found Torrust processes:"
    echo "$TORRUST_PROCESSES"
else
    print_warning "⚠️  No Torrust processes found"
fi

# 5. Check for source code directories
print_status "5. Checking for source code directories..."
if [ -d "torrust-tracker" ]; then
    print_success "✅ Found torrust-tracker source directory"
else
    print_warning "⚠️  No torrust-tracker source directory found"
fi

if [ -d "torrust-index" ]; then
    print_success "✅ Found torrust-index source directory"
else
    print_warning "⚠️  No torrust-index source directory found"
fi

if [ -d "torrust-index-gui" ]; then
    print_success "✅ Found torrust-index-gui source directory"
else
    print_warning "⚠️  No torrust-index-gui source directory found"
fi

# 6. Check for binary files
print_status "6. Checking for Torrust binaries..."
if [ -f "torrust-tracker/target/release/torrust-tracker" ]; then
    print_success "✅ Found compiled torrust-tracker binary"
else
    print_warning "⚠️  No compiled torrust-tracker binary found"
fi

if [ -f "torrust-index/target/release/torrust-index" ]; then
    print_success "✅ Found compiled torrust-index binary"
else
    print_warning "⚠️  No compiled torrust-index binary found"
fi

# 7. Check for Node.js processes
print_status "7. Checking for Node.js processes..."
NODE_PROCESSES=$(ps aux | grep node | grep -v grep || echo "")
if [ -n "$NODE_PROCESSES" ]; then
    print_success "✅ Found Node.js processes:"
    echo "$NODE_PROCESSES"
else
    print_warning "⚠️  No Node.js processes found"
fi

# 8. Check for npm/yarn processes
print_status "8. Checking for npm/yarn processes..."
NPM_PROCESSES=$(ps aux | grep -E "(npm|yarn)" | grep -v grep || echo "")
if [ -n "$NPM_PROCESSES" ]; then
    print_success "✅ Found npm/yarn processes:"
    echo "$NPM_PROCESSES"
else
    print_warning "⚠️  No npm/yarn processes found"
fi

# 9. Check port usage
print_status "9. Checking port usage..."
print_status "Port 3000 (GUI):"
if netstat -tlnp 2>/dev/null | grep ":3000 " >/dev/null; then
    netstat -tlnp 2>/dev/null | grep ":3000 " || echo "Port 3000 in use"
else
    print_warning "⚠️  Port 3000 not in use"
fi

print_status "Port 3001 (Index):"
if netstat -tlnp 2>/dev/null | grep ":3001 " >/dev/null; then
    netstat -tlnp 2>/dev/null | grep ":3001 " || echo "Port 3001 in use"
else
    print_warning "⚠️  Port 3001 not in use"
fi

print_status "Port 6969 (Tracker UDP):"
if netstat -ulnp 2>/dev/null | grep ":6969 " >/dev/null; then
    netstat -ulnp 2>/dev/null | grep ":6969 " || echo "Port 6969 in use"
else
    print_warning "⚠️  Port 6969 not in use"
fi

# 10. Check for configuration files
print_status "10. Checking for configuration files..."
if [ -f "config/tracker.toml" ]; then
    print_success "✅ Found tracker.toml"
else
    print_warning "⚠️  No tracker.toml found"
fi

if [ -f "config/index.toml" ]; then
    print_success "✅ Found index.toml"
else
    print_warning "⚠️  No index.toml found"
fi

# 11. Check for database files
print_status "11. Checking for database files..."
if [ -f "storage/tracker/lib/database/sqlite3.db" ]; then
    print_success "✅ Found tracker database"
else
    print_warning "⚠️  No tracker database found"
fi

if [ -f "storage/index/lib/database/sqlite3.db" ]; then
    print_success "✅ Found index database"
else
    print_warning "⚠️  No index database found"
fi

echo "=========================================="
echo "📊 DEPLOYMENT TYPE ANALYSIS"
echo "=========================================="

# Analyze the results
DOCKER_CONTAINERS=$(docker ps --filter "name=torrust" --format "{{.Names}}" 2>/dev/null | wc -l)
SYSTEMD_SERVICES=$(systemctl list-units --type=service | grep -i torrust | wc -l)
SOURCE_DIRS=0
[ -d "torrust-tracker" ] && SOURCE_DIRS=$((SOURCE_DIRS + 1))
[ -d "torrust-index" ] && SOURCE_DIRS=$((SOURCE_DIRS + 1))
[ -d "torrust-index-gui" ] && SOURCE_DIRS=$((SOURCE_DIRS + 1))

if [ "$DOCKER_CONTAINERS" -gt 0 ]; then
    print_success "🐳 DEPLOYMENT TYPE: Docker"
    print_status "You are using Docker containers for deployment"
elif [ "$SYSTEMD_SERVICES" -gt 0 ]; then
    print_success "⚙️  DEPLOYMENT TYPE: Systemd Services"
    print_status "You are using systemd services for deployment"
elif [ "$SOURCE_DIRS" -eq 3 ]; then
    print_success "🔧 DEPLOYMENT TYPE: Source Code"
    print_status "You have source code but need to check if it's running"
else
    print_warning "❓ DEPLOYMENT TYPE: Unknown"
    print_status "Could not determine deployment type"
fi

echo "=========================================="
print_status "Deployment check completed!"
