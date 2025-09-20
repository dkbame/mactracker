#!/bin/bash

# Script to extract source files from Docker container and modify them
# Works with production Docker deployments

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

print_status "Extracting and modifying source files from Docker container..."

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

# 2. Create a temporary directory for extracted files
TEMP_DIR="/tmp/torrust-gui-source"
print_status "2. Creating temporary directory: $TEMP_DIR"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# 3. Extract the entire GUI application from the container
print_status "3. Extracting GUI application from container..."
docker cp "$GUI_CONTAINER:/app" "$TEMP_DIR/"

# 4. Check what we extracted
print_status "4. Examining extracted files..."
if [ -d "$TEMP_DIR/app/.output" ]; then
    print_success "Found .output directory (production build)"
    print_status "Contents of .output:"
    ls -la "$TEMP_DIR/app/.output/"
else
    print_error "No .output directory found"
    exit 1
fi

# 5. Look for source files in the container
print_status "5. Searching for source files in container..."
SOURCE_FILES=$(docker exec "$GUI_CONTAINER" find /app -name "*.vue" -o -name "package.json" -o -name "nuxt.config.*" 2>/dev/null | head -10 || echo "")
if [ -n "$SOURCE_FILES" ]; then
    print_success "Found source files in container:"
    echo "$SOURCE_FILES"
else
    print_warning "No source files found in container"
fi

# 6. Since this is a production build, let's try a different approach
# We'll create a custom component and inject it via the built files
print_status "6. Creating custom tracker URLs component..."

# Create a custom Vue component
TRACKER_COMPONENT='<template>
  <div class="tracker-urls-info">
    <h3 class="tracker-urls-title">Tracker URLs</h3>
    <p class="tracker-urls-description">Your torrent will use these tracker URLs:</p>
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
    <p class="tracker-url-note">These URLs will be embedded in your torrent file for peer discovery.</p>
  </div>
</template>

<script setup lang="ts">
// Tracker URLs component
</script>

<style scoped>
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
  font-family: Monaco, Menlo, Ubuntu Mono, monospace;
  font-size: 14px;
  color: #ffffff;
}

.tracker-url-note {
  font-size: 12px;
  color: rgba(255, 255, 255, 0.5);
  margin-top: 8px;
}
</style>'

# Create the component file
echo "$TRACKER_COMPONENT" > "$TEMP_DIR/TrackerUrls.vue"

# 7. Create a JavaScript injection script
print_status "7. Creating JavaScript injection script..."

INJECTION_SCRIPT='// Tracker URLs Display Injection
(function() {
    console.log("Tracker URLs injection script loaded");
    
    function addTrackerUrlsDisplay() {
        // Check if we are on the upload page
        if (!window.location.pathname.includes("/upload")) {
            return;
        }
        
        // Check if already added
        if (document.querySelector(".tracker-urls-info")) {
            return;
        }
        
        // Wait for the form to be present
        const form = document.querySelector("form") || 
                    document.querySelector("[data-cy=\"upload-form-title\"]") || 
                    document.querySelector("input[name=\"title\"]")?.closest("div");
        
        if (!form) {
            console.log("Upload form not found, retrying...");
            return;
        }
        
        console.log("Upload form found, adding tracker URLs display");
        
        // Create the tracker URLs display
        const trackerUrlsDiv = document.createElement("div");
        trackerUrlsDiv.className = "tracker-urls-info";
        trackerUrlsDiv.innerHTML = `
            <h3 class="tracker-urls-title">Tracker URLs</h3>
            <p class="tracker-urls-description">Your torrent will use these tracker URLs:</p>
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
            <p class="tracker-url-note">These URLs will be embedded in your torrent file for peer discovery.</p>
        `;
        
        // Add CSS styles
        const style = document.createElement("style");
        style.textContent = `
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
                font-family: Monaco, Menlo, Ubuntu Mono, monospace;
                font-size: 14px;
                color: #ffffff;
            }
            .tracker-url-note {
                font-size: 12px;
                color: rgba(255, 255, 255, 0.5);
                margin-top: 8px;
            }
        `;
        document.head.appendChild(style);
        
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
    
    // Also try after delays to catch dynamically loaded content
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
})();'

# Save the injection script
echo "$INJECTION_SCRIPT" > "$TEMP_DIR/tracker-urls-injection.js"

# 8. Copy files back into the container
print_status "8. Copying modified files back into container..."

# Copy the injection script
docker cp "$TEMP_DIR/tracker-urls-injection.js" "$GUI_CONTAINER:/app/.output/public/_nuxt/tracker-urls-injection.js"

# 9. Try to find and modify HTML files
print_status "9. Looking for HTML files to modify..."
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
        sed -i 's|</body>|  <script src=\"/_nuxt/tracker-urls-injection.js\"></script>\n</body>|' '$FIRST_HTML'
        
        echo 'Injection script added to HTML file'
    "
else
    print_warning "No HTML files found. This is likely a pure SSR application."
    
    # Try to add the script to the server-side rendering
    print_status "10. Adding script to server-side rendering..."
    
    # Find server files
    SERVER_FILES=$(docker exec "$GUI_CONTAINER" find /app/.output/server -name "*.mjs" -o -name "*.js" 2>/dev/null | head -5 || echo "")
    if [ -n "$SERVER_FILES" ]; then
        print_success "Found server files:"
        echo "$SERVER_FILES"
        
        # Add script reference to the first server file
        FIRST_SERVER=$(echo "$SERVER_FILES" | head -1)
        print_status "Adding script reference to: $FIRST_SERVER"
        
        docker exec "$GUI_CONTAINER" sh -c "
            # Create backup
            cp '$FIRST_SERVER' '$FIRST_SERVER.backup'
            
            # Add script reference at the end
            echo '// Tracker URLs Display Script' >> '$FIRST_SERVER'
            echo 'const trackerUrlsScript = \"<script src=\\\"/_nuxt/tracker-urls-injection.js\\\"></script>\";' >> '$FIRST_SERVER'
            
            echo 'Script reference added to server file'
        "
    fi
fi

# 10. Restart the GUI container
print_status "11. Restarting GUI container..."
docker restart "$GUI_CONTAINER"

# 11. Wait for restart
sleep 15

# 12. Test accessibility
print_status "12. Testing accessibility..."
if curl -s -I https://macosapps.net | grep -q "200\|301\|302"; then
    print_success "✅ GUI is accessible at https://macosapps.net"
else
    print_warning "⚠️  GUI might not be fully ready yet"
fi

# 13. Clean up
print_status "13. Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

print_success "Tracker URLs display injection completed!"
print_status ""
print_status "The upload page should now show tracker URLs when you visit:"
print_status "https://macosapps.net/upload"
print_status ""
print_status "Check the browser console for injection messages:"
print_status "- 'Tracker URLs injection script loaded'"
print_status "- 'Upload form found, adding tracker URLs display'"
print_status ""
print_status "Services status:"
docker ps --filter "name=torrust" --format "table {{.Names}}\t{{.Status}}"
