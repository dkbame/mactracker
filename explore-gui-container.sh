#!/bin/bash

# Script to explore the GUI container and find the upload page

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

print_status "Exploring GUI container to find upload page..."

cd "$PROJECT_ROOT"

# 1. Auto-detect the GUI container name
print_status "1. Auto-detecting GUI container name..."
GUI_CONTAINER_NAME=""
GUI_CONTAINER=""

# Try different possible container names
for name in torrust-gui torrust_index_gui torrust-index-gui gui; do
    if docker ps --filter "name=$name" --format "{{.Names}}" | grep -q "$name"; then
        GUI_CONTAINER_NAME="$name"
        GUI_CONTAINER=$(docker ps --filter "name=$name" --format "{{.ID}}")
        print_success "Found GUI container: $GUI_CONTAINER_NAME (ID: $GUI_CONTAINER)"
        break
    fi
done

if [ -z "$GUI_CONTAINER_NAME" ]; then
    print_error "Could not find GUI container. Available containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

# 2. Explore the container structure
print_status "2. Exploring container structure..."
print_status "Container working directory:"
docker exec "$GUI_CONTAINER" pwd

print_status "Container root directory contents:"
docker exec "$GUI_CONTAINER" ls -la /

print_status "Looking for common web app directories..."
for dir in /app /usr/share/nginx/html /var/www /opt /home; do
    if docker exec "$GUI_CONTAINER" test -d "$dir" 2>/dev/null; then
        print_status "Directory $dir exists:"
        docker exec "$GUI_CONTAINER" ls -la "$dir" | head -10
        echo ""
    fi
done

# 3. Search for Vue files
print_status "3. Searching for Vue files..."
VUE_FILES=$(docker exec "$GUI_CONTAINER" find / -name "*.vue" 2>/dev/null | head -20 || echo "")
if [ -n "$VUE_FILES" ]; then
    print_success "Found Vue files:"
    echo "$VUE_FILES"
else
    print_warning "No Vue files found"
fi

# 4. Search for upload-related files
print_status "4. Searching for upload-related files..."
UPLOAD_FILES=$(docker exec "$GUI_CONTAINER" find / -name "*upload*" 2>/dev/null | head -20 || echo "")
if [ -n "$UPLOAD_FILES" ]; then
    print_success "Found upload-related files:"
    echo "$UPLOAD_FILES"
else
    print_warning "No upload-related files found"
fi

# 5. Search for pages directory
print_status "5. Searching for pages directory..."
PAGES_DIRS=$(docker exec "$GUI_CONTAINER" find / -type d -name "pages" 2>/dev/null || echo "")
if [ -n "$PAGES_DIRS" ]; then
    print_success "Found pages directories:"
    echo "$PAGES_DIRS"
    for dir in $PAGES_DIRS; do
        print_status "Contents of $dir:"
        docker exec "$GUI_CONTAINER" ls -la "$dir" 2>/dev/null || echo "Cannot access $dir"
    done
else
    print_warning "No pages directories found"
fi

# 6. Search for HTML files
print_status "6. Searching for HTML files..."
HTML_FILES=$(docker exec "$GUI_CONTAINER" find / -name "*.html" 2>/dev/null | head -10 || echo "")
if [ -n "$HTML_FILES" ]; then
    print_success "Found HTML files:"
    echo "$HTML_FILES"
else
    print_warning "No HTML files found"
fi

# 7. Check for Nuxt.js specific files
print_status "7. Checking for Nuxt.js specific files..."
NUXT_FILES=$(docker exec "$GUI_CONTAINER" find / -name "nuxt.config.*" -o -name ".nuxt" -o -name ".output" 2>/dev/null || echo "")
if [ -n "$NUXT_FILES" ]; then
    print_success "Found Nuxt.js files:"
    echo "$NUXT_FILES"
    
    # Check .output directory if it exists
    if docker exec "$GUI_CONTAINER" test -d "/app/.output" 2>/dev/null; then
        print_status "Contents of /app/.output:"
        docker exec "$GUI_CONTAINER" find /app/.output -type f | head -20
    fi
else
    print_warning "No Nuxt.js files found"
fi

# 8. Check for package.json
print_status "8. Checking for package.json..."
PACKAGE_FILES=$(docker exec "$GUI_CONTAINER" find / -name "package.json" 2>/dev/null || echo "")
if [ -n "$PACKAGE_FILES" ]; then
    print_success "Found package.json files:"
    echo "$PACKAGE_FILES"
    for file in $PACKAGE_FILES; do
        print_status "Contents of $file:"
        docker exec "$GUI_CONTAINER" cat "$file" | head -20
    done
else
    print_warning "No package.json files found"
fi

# 9. Check for nginx configuration
print_status "9. Checking for nginx configuration..."
NGINX_CONF=$(docker exec "$GUI_CONTAINER" find / -name "nginx.conf" -o -name "*.conf" 2>/dev/null | head -10 || echo "")
if [ -n "$NGINX_CONF" ]; then
    print_success "Found nginx configuration files:"
    echo "$NGINX_CONF"
else
    print_warning "No nginx configuration files found"
fi

# 10. Check for static files
print_status "10. Checking for static files..."
STATIC_DIRS=$(docker exec "$GUI_CONTAINER" find / -type d -name "static" -o -name "public" -o -name "dist" -o -name "build" 2>/dev/null || echo "")
if [ -n "$STATIC_DIRS" ]; then
    print_success "Found static file directories:"
    echo "$STATIC_DIRS"
    for dir in $STATIC_DIRS; do
        print_status "Contents of $dir:"
        docker exec "$GUI_CONTAINER" ls -la "$dir" | head -10
    done
else
    print_warning "No static file directories found"
fi

print_status "Container exploration completed!"
print_status "Use this information to determine where the upload page is located."
