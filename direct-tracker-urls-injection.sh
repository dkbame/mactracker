#!/bin/bash

# Direct approach to inject tracker URLs into the upload page
# Works by modifying the server-side rendering or adding client-side injection

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

print_status "Direct tracker URLs injection approach..."

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

# 2. Create a simple JavaScript injection that works on any page
print_status "2. Creating universal JavaScript injection..."

# Create a simple, robust JavaScript file
UNIVERSAL_JS='
// Universal Tracker URLs Display
(function() {
    console.log("Tracker URLs script loaded");
    
    // Function to add tracker URLs display
    function addTrackerUrlsDisplay() {
        // Check if we're on the upload page
        if (!window.location.pathname.includes("/upload")) {
            return;
        }
        
        // Check if tracker URLs already added
        if (document.querySelector(".tracker-urls-info")) {
            return;
        }
        
        // Wait for the form to be present
        const form = document.querySelector("form") || document.querySelector("[data-cy=\"upload-form-title\"]") || document.querySelector("input[name=\"title\"]")?.closest("div");
        
        if (!form) {
            console.log("Upload form not found, retrying...");
            return;
        }
        
        console.log("Upload form found, adding tracker URLs display");
        
        // Create the tracker URLs display
        const trackerUrlsDiv = document.createElement("div");
        trackerUrlsDiv.className = "tracker-urls-info";
        trackerUrlsDiv.style.cssText = `
            background: rgba(0, 0, 0, 0.1);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 16px;
            padding: 16px;
            margin: 16px 0;
            color: white;
        `;
        
        trackerUrlsDiv.innerHTML = `
            <div style="font-size: 18px; font-weight: 600; color: #ffffff; margin-bottom: 12px;">Tracker URLs</div>
            <div style="font-size: 14px; color: rgba(255, 255, 255, 0.7); margin-bottom: 12px;">Your torrent will use these tracker URLs:</div>
            <div style="display: flex; flex-direction: column; gap: 8px;">
                <div style="display: flex; align-items: center; gap: 12px;">
                    <span style="font-size: 12px; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; min-width: 60px; color: #3b82f6;">UDP:</span>
                    <code style="flex: 1; padding: 8px 12px; background: rgba(0, 0, 0, 0.2); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 8px; font-family: Monaco, Menlo, Ubuntu Mono, monospace; font-size: 14px; color: #ffffff;">udp://macosapps.net:6969/announce</code>
                </div>
                <div style="display: flex; align-items: center; gap: 12px;">
                    <span style="font-size: 12px; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; min-width: 60px; color: #10b981;">HTTP:</span>
                    <code style="flex: 1; padding: 8px 12px; background: rgba(0, 0, 0, 0.2); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 8px; font-family: Monaco, Menlo, Ubuntu Mono, monospace; font-size: 14px; color: #ffffff;">http://macosapps.net:7070/announce</code>
                </div>
            </div>
            <div style="font-size: 12px; color: rgba(255, 255, 255, 0.5); margin-top: 8px;">These URLs will be embedded in your torrent file for peer discovery.</div>
        `;
        
        // Try to insert before the agreement checkbox
        const agreementInput = document.querySelector("input[name=\"agree-to-terms\"]");
        if (agreementInput) {
            const agreementDiv = agreementInput.closest("div");
            if (agreementDiv) {
                agreementDiv.parentNode.insertBefore(trackerUrlsDiv, agreementDiv);
                console.log("Tracker URLs added before agreement checkbox");
                return;
            }
        }
        
        // Fallback: insert at the end of the form
        form.appendChild(trackerUrlsDiv);
        console.log("Tracker URLs added to end of form");
    }
    
    // Try to add immediately
    addTrackerUrlsDisplay();
    
    // Also try on DOM ready
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", addTrackerUrlsDisplay);
    }
    
    // Also try after a delay to catch dynamically loaded content
    setTimeout(addTrackerUrlsDisplay, 1000);
    setTimeout(addTrackerUrlsDisplay, 3000);
    setTimeout(addTrackerUrlsDisplay, 5000);
    
    // Watch for route changes (for SPA)
    let currentPath = window.location.pathname;
    setInterval(function() {
        if (window.location.pathname !== currentPath) {
            currentPath = window.location.pathname;
            setTimeout(addTrackerUrlsDisplay, 1000);
        }
    }, 500);
})();
'

# 3. Create a simple HTML file that can be served directly
print_status "3. Creating standalone HTML file for testing..."
STANDALONE_HTML='<!DOCTYPE html>
<html>
<head>
    <title>Tracker URLs Test</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #1a1a1a; color: white; }
        .tracker-urls-info { background: rgba(0, 0, 0, 0.1); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 16px; padding: 16px; margin: 16px 0; }
        .tracker-urls-title { font-size: 18px; font-weight: 600; color: #ffffff; margin-bottom: 12px; }
        .tracker-urls-description { font-size: 14px; color: rgba(255, 255, 255, 0.7); margin-bottom: 12px; }
        .tracker-urls-list { display: flex; flex-direction: column; gap: 8px; }
        .tracker-url-item { display: flex; align-items: center; gap: 12px; }
        .tracker-url-label { font-size: 12px; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; min-width: 60px; }
        .tracker-url-label.udp { color: #3b82f6; }
        .tracker-url-label.http { color: #10b981; }
        .tracker-url-code { flex: 1; padding: 8px 12px; background: rgba(0, 0, 0, 0.2); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 8px; font-family: Monaco, Menlo, Ubuntu Mono, monospace; font-size: 14px; color: #ffffff; }
        .tracker-url-note { font-size: 12px; color: rgba(255, 255, 255, 0.5); margin-top: 8px; }
    </style>
</head>
<body>
    <h1>Tracker URLs Display Test</h1>
    <div class="tracker-urls-info">
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
    </div>
    <p>This is how the tracker URLs will appear on the upload page.</p>
</body>
</html>'

# 4. Copy files into the container
print_status "4. Adding files to container..."
echo "$UNIVERSAL_JS" > /tmp/tracker-urls-universal.js
echo "$STANDALONE_HTML" > /tmp/tracker-urls-test.html

# Copy files into the container
docker cp /tmp/tracker-urls-universal.js "$GUI_CONTAINER:/app/.output/public/_nuxt/tracker-urls-universal.js"
docker cp /tmp/tracker-urls-test.html "$GUI_CONTAINER:/app/.output/public/tracker-urls-test.html"

# 5. Try to find and modify any HTML file
print_status "5. Searching for HTML files to modify..."
HTML_FILES=$(docker exec "$GUI_CONTAINER" find /app/.output -name "*.html" 2>/dev/null || echo "")
if [ -n "$HTML_FILES" ]; then
    print_success "Found HTML files:"
    echo "$HTML_FILES"
    
    # Modify the first HTML file found
    FIRST_HTML=$(echo "$HTML_FILES" | head -1)
    print_status "Modifying: $FIRST_HTML"
    
    docker exec "$GUI_CONTAINER" sh -c "
        # Create backup
        cp '$FIRST_HTML' '$FIRST_HTML.backup'
        
        # Add our script before closing body tag
        sed -i 's|</body>|  <script src=\"/_nuxt/tracker-urls-universal.js\"></script>\n</body>|' '$FIRST_HTML'
        
        echo 'Script added to HTML file'
    "
else
    print_warning "No HTML files found. This is likely a pure SSR application."
    
    # Try to modify the server-side rendering files
    print_status "6. Looking for server-side rendering files..."
    SSR_FILES=$(docker exec "$GUI_CONTAINER" find /app/.output/server -name "*.mjs" -o -name "*.js" 2>/dev/null | head -5 || echo "")
    if [ -n "$SSR_FILES" ]; then
        print_success "Found SSR files:"
        echo "$SSR_FILES"
        
        # Add our script to the first SSR file
        FIRST_SSR=$(echo "$SSR_FILES" | head -1)
        print_status "Adding script to SSR file: $FIRST_SSR"
        
        # Create a simple script injection
        docker exec "$GUI_CONTAINER" sh -c "
            # Create backup
            cp '$FIRST_SSR' '$FIRST_SSR.backup'
            
            # Add our script at the end of the file
            echo '// Tracker URLs Display Script' >> '$FIRST_SSR'
            echo 'const trackerUrlsScript = \"<script src=\\\"/_nuxt/tracker-urls-universal.js\\\"></script>\";' >> '$FIRST_SSR'
            
            echo 'Script reference added to SSR file'
        "
    fi
fi

# 6. Restart the GUI container
print_status "7. Restarting GUI container..."
docker restart "$GUI_CONTAINER"

# 7. Wait for restart
sleep 15

# 8. Test accessibility
print_status "8. Testing accessibility..."
if curl -s -I https://macosapps.net | grep -q "200\|301\|302"; then
    print_success "✅ GUI is accessible at https://macosapps.net"
else
    print_warning "⚠️  GUI might not be fully ready yet"
fi

# 9. Test the standalone HTML file
print_status "9. Testing standalone HTML file..."
if curl -s -I https://macosapps.net/tracker-urls-test.html | grep -q "200"; then
    print_success "✅ Standalone HTML file accessible at https://macosapps.net/tracker-urls-test.html"
    print_status "Visit this URL to see how the tracker URLs should look"
else
    print_warning "⚠️  Standalone HTML file not accessible"
fi

# 10. Clean up
rm -f /tmp/tracker-urls-universal.js /tmp/tracker-urls-test.html

print_success "Direct tracker URLs injection completed!"
print_status ""
print_status "The upload page should now show tracker URLs when you visit:"
print_status "https://macosapps.net/upload"
print_status ""
print_status "You can also test the display at:"
print_status "https://macosapps.net/tracker-urls-test.html"
print_status ""
print_status "Services status:"
docker ps --filter "name=torrust" --format "table {{.Names}}\t{{.Status}}"
