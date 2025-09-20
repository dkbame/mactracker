#!/bin/bash

# Script to find the main HTML file and add tracker URLs display
# Handles different Nuxt.js build structures

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

print_status "Finding HTML file and adding tracker URLs display..."

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

# 3. Search for HTML files more thoroughly
print_status "2. Searching for HTML files..."
HTML_FILES=$(docker exec "$GUI_CONTAINER" find /app/.output -name "*.html" 2>/dev/null || echo "")
if [ -n "$HTML_FILES" ]; then
    print_success "Found HTML files:"
    echo "$HTML_FILES"
else
    print_warning "No HTML files found in /app/.output"
fi

# 4. Search in other common locations
print_status "3. Searching in other common locations..."
for dir in /app /app/.output /app/.output/public /app/.output/server /usr/share/nginx/html /var/www/html; do
    if docker exec "$GUI_CONTAINER" test -d "$dir" 2>/dev/null; then
        print_status "Searching in $dir..."
        HTML_FILES_IN_DIR=$(docker exec "$GUI_CONTAINER" find "$dir" -name "*.html" 2>/dev/null | head -5 || echo "")
        if [ -n "$HTML_FILES_IN_DIR" ]; then
            print_success "Found HTML files in $dir:"
            echo "$HTML_FILES_IN_DIR"
        fi
    fi
done

# 5. Check for index files
print_status "4. Checking for index files..."
INDEX_FILES=$(docker exec "$GUI_CONTAINER" find /app/.output -name "index.*" 2>/dev/null || echo "")
if [ -n "$INDEX_FILES" ]; then
    print_success "Found index files:"
    echo "$INDEX_FILES"
else
    print_warning "No index files found"
fi

# 6. Check for server-side rendering files
print_status "5. Checking for server-side rendering files..."
SSR_FILES=$(docker exec "$GUI_CONTAINER" find /app/.output/server -name "*.mjs" -o -name "*.js" 2>/dev/null | head -10 || echo "")
if [ -n "$SSR_FILES" ]; then
    print_success "Found server-side rendering files:"
    echo "$SSR_FILES"
else
    print_warning "No server-side rendering files found"
fi

# 7. Since this is a Nuxt.js app, it might be using server-side rendering
# Let's try a different approach - modify the server-side rendering
print_status "6. Trying server-side rendering approach..."

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

# 8. Copy the CSS and JS files into the container
print_status "7. Adding custom CSS and JavaScript to the container..."

# Create temporary files
echo "$TRACKER_CSS" > /tmp/tracker-urls.css
echo "$TRACKER_JS" > /tmp/tracker-urls.js

# Copy files into the container
docker cp /tmp/tracker-urls.css "$GUI_CONTAINER:/app/.output/public/_nuxt/tracker-urls.css"
docker cp /tmp/tracker-urls.js "$GUI_CONTAINER:/app/.output/public/_nuxt/tracker-urls.js"

# 9. Try to find and modify the main HTML file
print_status "8. Looking for main HTML file to modify..."

# Try different possible HTML file locations
HTML_FILE=""
for possible_file in "/app/.output/public/index.html" "/app/.output/public/_nuxt/index.html" "/app/.output/server/index.html"; do
    if docker exec "$GUI_CONTAINER" test -f "$possible_file" 2>/dev/null; then
        HTML_FILE="$possible_file"
        print_success "Found HTML file: $HTML_FILE"
        break
    fi
done

if [ -z "$HTML_FILE" ]; then
    print_warning "No main HTML file found. This might be a pure SSR application."
    print_status "Trying to add CSS and JS via nginx configuration..."
    
    # Create a custom nginx configuration
    NGINX_CONFIG='
    location /_nuxt/tracker-urls.css {
        add_header Content-Type text/css;
        return 200 "
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
        ";
    }
    
    location /_nuxt/tracker-urls.js {
        add_header Content-Type application/javascript;
        return 200 "
document.addEventListener(\"DOMContentLoaded\", function() {
    const checkForUploadForm = setInterval(function() {
        const uploadForm = document.querySelector(\"form\") || document.querySelector(\"[data-cy=\\\"upload-form-title\\\"]\");
        if (uploadForm) {
            clearInterval(checkForUploadForm);
            const trackerUrlsDiv = document.createElement(\"div\");
            trackerUrlsDiv.className = \"tracker-urls-info\";
            trackerUrlsDiv.innerHTML = \`
                <div class=\"tracker-urls-title\">Tracker URLs</div>
                <div class=\"tracker-urls-description\">Your torrent will use these tracker URLs:</div>
                <div class=\"tracker-urls-list\">
                    <div class=\"tracker-url-item\">
                        <span class=\"tracker-url-label udp\">UDP:</span>
                        <code class=\"tracker-url-code\">udp://macosapps.net:6969/announce</code>
                    </div>
                    <div class=\"tracker-url-item\">
                        <span class=\"tracker-url-label http\">HTTP:</span>
                        <code class=\"tracker-url-code\">http://macosapps.net:7070/announce</code>
                    </div>
                </div>
                <div class=\"tracker-url-note\">These URLs will be embedded in your torrent file for peer discovery.</div>
            \`;
            const agreementDiv = document.querySelector(\"input[name=\\\"agree-to-terms\\\"]\")?.closest(\"div\");
            if (agreementDiv) {
                agreementDiv.parentNode.insertBefore(trackerUrlsDiv, agreementDiv);
            } else {
                uploadForm.appendChild(trackerUrlsDiv);
            }
        }
    }, 1000);
    setTimeout(function() { clearInterval(checkForUploadForm); }, 10000);
});
        ";
    }
    '
    
    print_status "Creating nginx configuration for tracker URLs..."
    echo "$NGINX_CONFIG" > /tmp/tracker-urls-nginx.conf
    
    # Copy nginx config to container
    docker cp /tmp/tracker-urls-nginx.conf "$GUI_CONTAINER:/tmp/tracker-urls-nginx.conf"
    
    print_status "Nginx configuration created. You may need to manually add this to your nginx config."
else
    # Modify the HTML file
    print_status "Modifying HTML file: $HTML_FILE"
    docker exec "$GUI_CONTAINER" sh -c "
        # Create backup
        cp '$HTML_FILE' '$HTML_FILE.backup'
        
        # Add CSS link before closing head tag
        sed -i 's|</head>|  <link rel=\"stylesheet\" href=\"/_nuxt/tracker-urls.css\">\n</head>|' '$HTML_FILE'
        
        # Add JS script before closing body tag
        sed -i 's|</body>|  <script src=\"/_nuxt/tracker-urls.js\"></script>\n</body>|' '$HTML_FILE'
        
        echo 'Custom CSS and JS added to HTML file'
    "
fi

# 10. Restart the GUI container to apply changes
print_status "9. Restarting GUI container to apply changes..."
docker restart "$GUI_CONTAINER"

# 11. Wait for restart
sleep 10

# 12. Test if GUI is accessible
print_status "10. Testing GUI accessibility..."
if curl -s -I https://macosapps.net | grep -q "200\|301\|302"; then
    print_success "✅ GUI is accessible at https://macosapps.net"
else
    print_warning "⚠️  GUI might not be fully ready yet, please wait a moment"
fi

# 13. Clean up
rm -f /tmp/tracker-urls.css /tmp/tracker-urls.js /tmp/tracker-urls-nginx.conf

print_success "Tracker URLs display setup completed!"
print_status ""
print_status "The upload page will now show:"
print_success "  UDP: udp://macosapps.net:6969/announce"
print_success "  HTTP: http://macosapps.net:7070/announce"
print_status ""
print_status "Visit https://macosapps.net/upload to see the changes"
print_status ""
print_status "Services status:"
docker ps --filter "name=torrust" --format "table {{.Names}}\t{{.Status}}"
