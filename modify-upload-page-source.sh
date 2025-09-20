#!/bin/bash

# Script to modify the actual upload.vue source file
# This is the proper way to make UX changes

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

print_status "Modifying upload.vue source file to add tracker URL display..."

cd "$PROJECT_ROOT"

# 1. Check if we have the source code
if [ ! -d "torrust-index-gui" ]; then
    print_error "Source code directory not found. This script requires the source code."
    print_status "Please ensure you have cloned the repositories or are running in development mode."
    exit 1
fi

# 2. Check if the upload.vue file exists
UPLOAD_FILE="torrust-index-gui/pages/upload.vue"
if [ ! -f "$UPLOAD_FILE" ]; then
    print_error "Upload page not found at $UPLOAD_FILE"
    exit 1
fi

print_success "Found upload page: $UPLOAD_FILE"

# 3. Create backup
print_status "Creating backup of original file..."
cp "$UPLOAD_FILE" "$UPLOAD_FILE.backup.$(date +%Y%m%d_%H%M%S)"
print_success "Backup created"

# 4. Check if tracker URLs are already added
if grep -q "Tracker URLs" "$UPLOAD_FILE"; then
    print_warning "Tracker URLs display already exists in the file"
    print_status "Skipping modification to avoid duplicates"
    exit 0
fi

# 5. Add the tracker URLs display
print_status "Adding tracker URLs display to upload page..."

# Create the tracker URLs HTML
TRACKER_URLS_HTML='      <!-- Tracker URLs Information -->
      <div class="p-4 bg-base-200/50 rounded-2xl border border-base-content/10">
        <h3 class="text-lg font-semibold text-neutral-content mb-3">Tracker URLs</h3>
        <p class="text-sm text-neutral-content/70 mb-3">Your torrent will use these tracker URLs:</p>
        <div class="space-y-2">
          <div class="flex items-center gap-3">
            <span class="text-xs font-medium text-primary uppercase tracking-wide">UDP:</span>
            <code class="flex-1 p-2 bg-base-100 rounded-lg text-sm font-mono text-neutral-content border border-base-content/20">udp://macosapps.net:6969/announce</code>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-xs font-medium text-secondary uppercase tracking-wide">HTTP:</span>
            <code class="flex-1 p-2 bg-base-100 rounded-lg text-sm font-mono text-neutral-content border border-base-content/20">http://macosapps.net:7070/announce</code>
          </div>
        </div>
        <p class="text-xs text-neutral-content/50 mt-2">These URLs will be embedded in your torrent file for peer discovery.</p>
      </div>'

# 6. Insert the tracker URLs after the UploadFile component
# Find the UploadFile component and add our content after it
sed -i '/<UploadFile sub-title="Only .torrent files allowed\. BitTorrent v2 files are NOT supported\." accept="\.torrent" @on-change="setFile" \/>/a\
\
'"$TRACKER_URLS_HTML" "$UPLOAD_FILE"

print_success "Tracker URLs display added to upload page"

# 7. Verify the changes
print_status "Verifying changes..."
if grep -q "Tracker URLs" "$UPLOAD_FILE"; then
    print_success "✅ Tracker URLs display successfully added"
else
    print_error "❌ Failed to add tracker URLs display"
    exit 1
fi

# 8. Show the modified section
print_status "Modified section:"
echo "----------------------------------------"
grep -A 20 "Tracker URLs Information" "$UPLOAD_FILE" | head -15
echo "----------------------------------------"

# 9. Check if we're in development or production mode
if [ -f "torrust-index-gui/package.json" ]; then
    print_status "9. Build and deployment options:"
    print_status ""
    print_status "Development mode:"
    print_status "  cd torrust-index-gui"
    print_status "  npm run dev"
    print_status ""
    print_status "Production build:"
    print_status "  cd torrust-index-gui"
    print_status "  npm run build"
    print_status ""
    print_status "Docker rebuild (if using containers):"
    print_status "  docker compose -f docker-compose-https.yml build torrust-gui"
    print_status "  docker compose -f docker-compose-https.yml up -d"
else
    print_warning "No package.json found. This might not be a development environment."
fi

print_success "Upload page modification completed!"
print_status ""
print_status "The upload page now includes:"
print_success "  UDP: udp://macosapps.net:6969/announce"
print_success "  HTTP: http://macosapps.net:7070/announce"
print_status ""
print_status "Next steps:"
print_status "1. If in development: Run 'npm run dev' in torrust-index-gui/"
print_status "2. If in production: Rebuild the container"
print_status "3. Visit the upload page to see the changes"
