#!/bin/bash

# Script to add tracker URLs display to the compiled Nuxt.js application
# Works with the built/compiled version in /app/.output/public/

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

print_status "Adding tracker URLs display to compiled Nuxt.js application..."

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

# 3. Find the compiled JavaScript files
print_status "2. Finding compiled JavaScript files..."
JS_FILES=$(docker exec "$GUI_CONTAINER" find /app/.output/public/_nuxt -name "*.js" | head -10)
if [ -n "$JS_FILES" ]; then
    print_success "Found compiled JavaScript files:"
    echo "$JS_FILES"
else
    print_error "No compiled JavaScript files found"
    exit 1
fi

# 4. Look for upload-related files
print_status "3. Looking for upload-related files..."
UPLOAD_FILES=$(docker exec "$GUI_CONTAINER" find /app/.output/public/_nuxt -name "*upload*" | head -10)
if [ -n "$UPLOAD_FILES" ]; then
    print_success "Found upload-related files:"
    echo "$UPLOAD_FILES"
else
    print_warning "No upload-related files found"
fi

# 5. Check for CSS files
print_status "4. Looking for CSS files..."
CSS_FILES=$(docker exec "$GUI_CONTAINER" find /app/.output/public/_nuxt -name "*.css" | head -10)
if [ -n "$CSS_FILES" ]; then
    print_success "Found CSS files:"
    echo "$CSS_FILES"
else
    print_warning "No CSS files found"
fi

# 6. Since this is a compiled application, we need to add the tracker URLs via a different approach
# We'll add it to the main HTML template or create a custom CSS/JS injection
print_status "5. Adding tracker URLs display via CSS/JS injection..."

# Create a custom CSS file for the tracker URLs display
TRACKER_CSS='
/* Tracker URLs Display Styles */
.tracker-urls-info {
    background: rgba(0, 0, 0, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 16px;
    padding: 16px;
    margin: 16px 0;
}

.tracker-urls-title {
    font-size: 18px;
    font-weight: 600;
    color: #ffffff;
    margin-bottom: 12px;
}

.tracker-urls-description {
    font-size: 14px;
    color: rgba(255, 255, 255, 0.7);
    margin-bottom: 12px;
}

.tracker-urls-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
}

.tracker-url-item {
    display: flex;
    align-items: center;
    gap: 12px;
}

.tracker-url-label {
    font-size: 12px;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    min-width: 60px;
}

.tracker-url-label.udp {
    color: #3b82f6;
}

.tracker-url-label.http {
    color: #10b981;
}

.tracker-url-code {
    flex: 1;
    padding: 8px 12px;
    background: rgba(0, 0, 0, 0.2);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 8px;
    font-family: "Monaco", "Menlo", "Ubuntu Mono", monospace;
    font-size: 14px;
    color: #ffffff;
}

.tracker-url-note {
    font-size: 12px;
    color: rgba(255, 255, 255, 0.5);
    margin-top: 8px;
}
'

# Create a custom JavaScript file to inject the tracker URLs
TRACKER_JS='
// Tracker URLs Display JavaScript
document.addEventListener("DOMContentLoaded", function() {
    // Wait for the upload form to be loaded
    const checkForUploadForm = setInterval(function() {
        const uploadForm = document.querySelector("form") || document.querySelector("[data-cy=\"upload-form-title\"]");
        if (uploadForm) {
            clearInterval(checkForUploadForm);
            
            // Create the tracker URLs display
            const trackerUrlsDiv = document.createElement("div");
            trackerUrlsDiv.className = "tracker-urls-info";
            trackerUrlsDiv.innerHTML = `
                <div class="tracker-urls-title">Tracker URLs</div>
                <div class="tracker-urls-description">Your torrent will use these tracker URLs:</div>
                <div class="tracker-urls-list">
                    <div class="tracker-url-item">
                        <span class="tracker-url-label udp">UDP:</span>
                        <code class="tracker-url-code">udp://macosapps.net:6969/announce</code>
                    </div>
                    <div class="tracker-url-item">
                        <span class="tracker-url-label http">HTTP:</span>
                        <code class="tracker-url-code">http://macosapps.net:7070/announce</code>
                    </div>
                </div>
                <div class="tracker-url-note">These URLs will be embedded in your torrent file for peer discovery.</div>
            `;
            
            // Insert the tracker URLs display before the agreement checkbox
            const agreementDiv = document.querySelector("input[name=\"agree-to-terms\"]")?.closest("div");
            if (agreementDiv) {
                agreementDiv.parentNode.insertBefore(trackerUrlsDiv, agreementDiv);
            } else {
                // Fallback: insert at the end of the form
                uploadForm.appendChild(trackerUrlsDiv);
            }
        }
    }, 1000);
    
    // Stop checking after 10 seconds
    setTimeout(function() {
        clearInterval(checkForUploadForm);
    }, 10000);
});
'

# 7. Copy the CSS and JS files into the container
print_status "6. Adding custom CSS and JavaScript to the container..."

# Create temporary files
echo "$TRACKER_CSS" > /tmp/tracker-urls.css
echo "$TRACKER_JS" > /tmp/tracker-urls.js

# Copy files into the container
docker cp /tmp/tracker-urls.css "$GUI_CONTAINER:/app/.output/public/_nuxt/tracker-urls.css"
docker cp /tmp/tracker-urls.js "$GUI_CONTAINER:/app/.output/public/_nuxt/tracker-urls.js"

# 8. Modify the main HTML file to include our custom CSS and JS
print_status "7. Modifying the main HTML file to include custom CSS and JS..."

# Find the main HTML file
MAIN_HTML=$(docker exec "$GUI_CONTAINER" find /app/.output/public -name "*.html" | head -1)
if [ -z "$MAIN_HTML" ]; then
    print_error "No main HTML file found"
    exit 1
fi

print_success "Found main HTML file: $MAIN_HTML"

# Add our custom CSS and JS to the HTML file
docker exec "$GUI_CONTAINER" sh -c "
# Create backup
cp '$MAIN_HTML' '$MAIN_HTML.backup'

# Add CSS link before closing head tag
sed -i 's|</head>|  <link rel=\"stylesheet\" href=\"/_nuxt/tracker-urls.css\">\n</head>|' '$MAIN_HTML'

# Add JS script before closing body tag
sed -i 's|</body>|  <script src=\"/_nuxt/tracker-urls.js\"></script>\n</body>|' '$MAIN_HTML'

echo 'Custom CSS and JS added to HTML file'
"

# 9. Restart the GUI container to apply changes
print_status "8. Restarting GUI container to apply changes..."
docker restart "$GUI_CONTAINER"

# 10. Wait for restart
sleep 10

# 11. Test if GUI is accessible
print_status "9. Testing GUI accessibility..."
if curl -s -I https://macosapps.net | grep -q "200\|301\|302"; then
    print_success "✅ GUI is accessible at https://macosapps.net"
else
    print_warning "⚠️  GUI might not be fully ready yet, please wait a moment"
fi

# 12. Clean up
rm -f /tmp/tracker-urls.css /tmp/tracker-urls.js

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
