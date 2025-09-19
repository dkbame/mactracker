#!/bin/bash

# Auto-detecting script to add tracker URLs display to the upload page
# Automatically finds the correct container names

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

print_status "Adding tracker URLs display to upload page (Auto-detecting method)..."

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

# 2. Check if container is running
if ! docker ps --filter "name=$GUI_CONTAINER_NAME" --format "{{.Status}}" | grep -q "Up"; then
    print_error "GUI container is not running. Starting services..."
    docker compose -f docker-compose-https.yml up -d
    print_status "Waiting for services to start..."
    sleep 15
fi

# 3. Find the upload.vue file inside the container
print_status "2. Finding upload page in container..."
UPLOAD_FILE=$(docker exec "$GUI_CONTAINER" find /app -name "upload.vue" -path "*/pages/*" 2>/dev/null | head -1)

if [ -z "$UPLOAD_FILE" ]; then
    print_error "Upload page not found in container"
    print_status "Searching for Vue files..."
    docker exec "$GUI_CONTAINER" find /app -name "*.vue" | head -10
    exit 1
fi

print_success "Found upload page at: $UPLOAD_FILE"

# 4. Create backup and apply changes
print_status "3. Applying changes to upload page..."
docker exec "$GUI_CONTAINER" sh -c "
# Create backup
cp '$UPLOAD_FILE' '$UPLOAD_FILE.backup'

# Add the tracker URLs section after the UploadFile component
sed -i '/<UploadFile sub-title=\"Only .torrent files allowed\. BitTorrent v2 files are NOT supported\.\" accept=\"\.torrent\" @on-change=\"setFile\" \/>/a\
\
      <!-- Tracker URLs Information -->\
      <div class=\"p-4 bg-base-200/50 rounded-2xl border border-base-content/10\">\
        <h3 class=\"text-lg font-semibold text-neutral-content mb-3\">Tracker URLs</h3>\
        <p class=\"text-sm text-neutral-content/70 mb-3\">Your torrent will use these tracker URLs:</p>\
        <div class=\"space-y-2\">\
          <div class=\"flex items-center gap-3\">\
            <span class=\"text-xs font-medium text-primary uppercase tracking-wide\">UDP:</span>\
            <code class=\"flex-1 p-2 bg-base-100 rounded-lg text-sm font-mono text-neutral-content border border-base-content/20\">udp://macosapps.net:6969/announce</code>\
          </div>\
          <div class=\"flex items-center gap-3\">\
            <span class=\"text-xs font-medium text-secondary uppercase tracking-wide\">HTTP:</span>\
            <code class=\"flex-1 p-2 bg-base-100 rounded-lg text-sm font-mono text-neutral-content border border-base-content/20\">http://macosapps.net:7070/announce</code>\
          </div>\
        </div>\
        <p class=\"text-xs text-neutral-content/50 mt-2\">These URLs will be embedded in your torrent file for peer discovery.</p>\
      </div>' '$UPLOAD_FILE'

echo 'Tracker URLs section added successfully'
"

# 5. Restart the GUI container to apply changes
print_status "4. Restarting GUI container to apply changes..."
docker restart "$GUI_CONTAINER"

# 6. Wait for restart
sleep 10

# 7. Test if GUI is accessible
print_status "5. Testing GUI accessibility..."
if curl -s -I https://macosapps.net | grep -q "200\|301\|302"; then
    print_success "✅ GUI is accessible at https://macosapps.net"
else
    print_warning "⚠️  GUI might not be fully ready yet, please wait a moment"
fi

print_success "Tracker URLs display added to upload page!"
print_status ""
print_status "The upload page will now show:"
print_success "  UDP: udp://macosapps.net:6969/announce"
print_success "  HTTP: http://macosapps.net:7070/announce"
print_status ""
print_status "Visit https://macosapps.net/upload to see the changes"
print_status ""
print_status "Services status:"
docker ps --filter "name=torrust" --format "table {{.Names}}\t{{.Status}}"
