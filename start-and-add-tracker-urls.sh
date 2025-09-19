#!/bin/bash

# Script to start Torrust services and add tracker URLs display to upload page

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

print_status "Starting Torrust services and adding tracker URLs display..."

cd "$PROJECT_ROOT"

# 1. Start the Torrust services
print_status "1. Starting Torrust services..."
docker compose -f docker-compose-https.yml up -d

# 2. Wait for services to be ready
print_status "2. Waiting for services to be ready..."
sleep 10

# 3. Check if GUI container is running
if ! docker compose -f docker-compose-https.yml ps | grep -q "torrust-gui.*running"; then
    print_error "GUI container failed to start"
    print_status "Checking logs..."
    docker compose -f docker-compose-https.yml logs torrust-gui
    exit 1
fi

print_success "Services are running"

# 4. Get the container ID
GUI_CONTAINER=$(docker compose -f docker-compose-https.yml ps -q torrust-gui)
print_status "GUI container ID: $GUI_CONTAINER"

# 5. Create the tracker URLs HTML snippet
TRACKER_HTML='      <!-- Tracker URLs Information -->
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

# 6. Create a temporary file with the HTML
echo "$TRACKER_HTML" > /tmp/tracker_urls.html

# 7. Copy the file into the container
print_status "3. Copying tracker URLs HTML to container..."
docker cp /tmp/tracker_urls.html "$GUI_CONTAINER:/tmp/tracker_urls.html"

# 8. Apply the changes inside the container
print_status "4. Applying changes inside the container..."
docker exec "$GUI_CONTAINER" sh -c '
# Find the upload.vue file
UPLOAD_FILE=$(find /app -name "upload.vue" -path "*/pages/*" 2>/dev/null | head -1)

if [ -z "$UPLOAD_FILE" ]; then
    echo "Upload page not found in container"
    exit 1
fi

echo "Found upload page at: $UPLOAD_FILE"

# Create backup
cp "$UPLOAD_FILE" "$UPLOAD_FILE.backup"

# Add the tracker URLs section after the UploadFile component
sed -i "/<UploadFile sub-title=\"Only .torrent files allowed\. BitTorrent v2 files are NOT supported\.\" accept=\"\.torrent\" @on-change=\"setFile\" \/>/r /tmp/tracker_urls.html" "$UPLOAD_FILE"

echo "Tracker URLs section added to upload page"
'

# 9. Restart the GUI container to apply changes
print_status "5. Restarting GUI container to apply changes..."
docker compose -f docker-compose-https.yml restart torrust-gui

# 10. Wait for restart
sleep 5

# 11. Check if GUI is accessible
print_status "6. Testing GUI accessibility..."
if curl -s -I https://macosapps.net | grep -q "200\|301\|302"; then
    print_success "GUI is accessible at https://macosapps.net"
else
    print_warning "GUI might not be fully ready yet, please wait a moment"
fi

# 12. Clean up
rm -f /tmp/tracker_urls.html

print_success "Tracker URLs display added to upload page!"
print_status ""
print_status "The upload page will now show:"
print_success "  UDP: udp://macosapps.net:6969/announce"
print_success "  HTTP: http://macosapps.net:7070/announce"
print_status ""
print_status "Visit https://macosapps.net/upload to see the changes"
print_status ""
print_status "Services status:"
docker compose -f docker-compose-https.yml ps
