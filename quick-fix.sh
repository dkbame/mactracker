#!/bin/bash

# Quick fix for port 80 conflict
# Run this on your server

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_status "Quick fix for port 80 conflict..."

# Stop existing services that might be using port 80
print_status "Stopping services that might be using port 80..."

# Stop nginx if running
if systemctl is-active --quiet nginx; then
    print_status "Stopping nginx..."
    systemctl stop nginx
    systemctl disable nginx
    print_success "Nginx stopped"
fi

# Stop apache if running
if systemctl is-active --quiet apache2; then
    print_status "Stopping apache2..."
    systemctl stop apache2
    systemctl disable apache2
    print_success "Apache2 stopped"
fi

# Kill any process using port 80
print_status "Killing any process using port 80..."
if lsof -ti:80 > /dev/null 2>&1; then
    lsof -ti:80 | xargs kill -9 2>/dev/null || true
    print_success "Processes using port 80 killed"
fi

# Wait a moment
sleep 2

# Check if port 80 is free now
if lsof -i :80 > /dev/null 2>&1; then
    print_error "Port 80 is still in use. Please check manually:"
    lsof -i :80
    exit 1
fi

print_success "Port 80 is now free!"

# Now try to start the services again
print_status "Starting Torrust services..."

# Go to the project directory
cd /opt/torrust

# Stop any existing containers
docker compose down 2>/dev/null || true

# Start services
docker compose up -d

print_success "Services started successfully!"
print_status ""
print_status "Services are running:"
print_status "- Web Interface: http://your-server-ip"
print_status "- Tracker API: http://your-server-ip:1212"
print_status "- Index API: http://your-server-ip:3001"
print_status ""
print_status "To check service status:"
print_status "  docker compose ps"
print_status ""
print_status "To view logs:"
print_status "  docker compose logs -f"
