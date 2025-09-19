#!/bin/bash

# Script to apply the tracker URLs patch to the upload page
# This will add a clean display of tracker URLs on the upload page

set -e

PROJECT_ROOT="/opt/torrust"
GUI_PATH="$PROJECT_ROOT/torrust-index-gui"

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

print_status "Adding tracker URLs display to upload page..."

cd "$PROJECT_ROOT"

# 1. Download the patch file
print_status "1. Downloading patch file..."
wget -q https://raw.githubusercontent.com/dkbame/mactracker/main/add-tracker-urls-to-upload-page.patch
print_success "Patch file downloaded"

# 2. Check if GUI directory exists
if [ ! -d "$GUI_PATH" ]; then
    print_error "GUI directory not found at $GUI_PATH"
    print_status "This might be a Docker-only deployment. Skipping GUI patch."
    exit 0
fi

# 3. Apply the patch
print_status "2. Applying patch to upload page..."
cd "$GUI_PATH"

if patch -p1 < "$PROJECT_ROOT/add-tracker-urls-to-upload-page.patch"; then
    print_success "Patch applied successfully"
else
    print_warning "Patch failed to apply cleanly. Applying manually..."
    
    # Manual application if patch fails
    UPLOAD_FILE="pages/upload.vue"
    
    if [ -f "$UPLOAD_FILE" ]; then
        # Create backup
        cp "$UPLOAD_FILE" "$UPLOAD_FILE.backup"
        
        # Add the tracker URLs section
        sed -i '/<UploadFile sub-title="Only .torrent files allowed\. BitTorrent v2 files are NOT supported\." accept="\.torrent" @on-change="setFile" \/>/a\
\
      <!-- Tracker URLs Information -->\
      <div class="p-4 bg-base-200/50 rounded-2xl border border-base-content/10">\
        <h3 class="text-lg font-semibold text-neutral-content mb-3">Tracker URLs</h3>\
        <p class="text-sm text-neutral-content/70 mb-3">Your torrent will use these tracker URLs:</p>\
        <div class="space-y-2">\
          <div class="flex items-center gap-3">\
            <span class="text-xs font-medium text-primary uppercase tracking-wide">UDP:</span>\
            <code class="flex-1 p-2 bg-base-100 rounded-lg text-sm font-mono text-neutral-content border border-base-content/20">udp://macosapps.net:6969/announce</code>\
          </div>\
          <div class="flex items-center gap-3">\
            <span class="text-xs font-medium text-secondary uppercase tracking-wide">HTTP:</span>\
            <code class="flex-1 p-2 bg-base-100 rounded-lg text-sm font-mono text-neutral-content border border-base-content/20">http://macosapps.net:7070/announce</code>\
          </div>\
        </div>\
        <p class="text-xs text-neutral-content/50 mt-2">These URLs will be embedded in your torrent file for peer discovery.</p>\
      </div>' "$UPLOAD_FILE"
        
        print_success "Tracker URLs section added manually"
    else
        print_error "Upload page not found at $UPLOAD_FILE"
        exit 1
    fi
fi

# 4. Rebuild the GUI if we're in a development setup
print_status "3. Checking if GUI rebuild is needed..."
if [ -f "package.json" ]; then
    print_status "Found package.json, rebuilding GUI..."
    npm run build
    print_success "GUI rebuilt successfully"
else
    print_status "No package.json found, assuming Docker deployment"
fi

# 5. Restart services if needed
print_status "4. Restarting services..."
cd "$PROJECT_ROOT"

if docker compose -f docker-compose-https.yml ps | grep -q "torrust-gui"; then
    print_status "Restarting GUI container..."
    docker compose -f docker-compose-https.yml restart torrust-gui
    print_success "GUI container restarted"
else
    print_status "No GUI container found, changes will apply on next deployment"
fi

# 6. Clean up
rm -f "$PROJECT_ROOT/add-tracker-urls-to-upload-page.patch"

print_status "Tracker URLs display added to upload page!"
print_status ""
print_status "The upload page will now show:"
print_success "  UDP: udp://macosapps.net:6969/announce"
print_success "  HTTP: http://macosapps.net:7070/announce"
print_status ""
print_status "Visit https://macosapps.net/upload to see the changes"
