#!/bin/bash

# Torrust Complete Build & Deployment Script
# This script builds and deploys the entire Torrust suite

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="/Users/kieranmenadue/Downloads/MacTracker"
TRACKER_DIR="$PROJECT_ROOT/torrust-tracker"
INDEX_DIR="$PROJECT_ROOT/torrust-index"
GUI_DIR="$PROJECT_ROOT/torrust-index-gui"
STORAGE_DIR="$PROJECT_ROOT/storage"
CONFIG_DIR="$PROJECT_ROOT/config"

# Function to print colored output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate random secret
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command_exists rustc; then
        print_error "Rust is not installed. Please install Rust first."
        exit 1
    fi
    
    if ! command_exists cargo; then
        print_error "Cargo is not installed. Please install Cargo first."
        exit 1
    fi
    
    if ! command_exists node; then
        print_error "Node.js is not installed. Please install Node.js first."
        exit 1
    fi
    
    if ! command_exists npm; then
        print_error "NPM is not installed. Please install NPM first."
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

# Create directory structure
create_directories() {
    print_status "Creating directory structure..."
    
    mkdir -p "$STORAGE_DIR/tracker/lib/database"
    mkdir -p "$STORAGE_DIR/tracker/etc"
    mkdir -p "$STORAGE_DIR/tracker/lib/tls"
    mkdir -p "$STORAGE_DIR/index/lib/database"
    mkdir -p "$STORAGE_DIR/index/etc"
    mkdir -p "$STORAGE_DIR/index/lib/tls"
    mkdir -p "$CONFIG_DIR"
    
    print_success "Directory structure created"
}

# Generate secrets
generate_secrets() {
    print_status "Generating secrets..."
    
    # Generate tracker API admin token
    TRACKER_API_TOKEN=$(generate_secret)
    echo "$TRACKER_API_TOKEN" > "$STORAGE_DIR/tracker/lib/tracker_api_admin_token.secret"
    chmod 600 "$STORAGE_DIR/tracker/lib/tracker_api_admin_token.secret"
    
    # Generate index auth secret key
    INDEX_AUTH_SECRET=$(generate_secret)
    echo "$INDEX_AUTH_SECRET" > "$STORAGE_DIR/index/lib/index_auth_secret.secret"
    chmod 600 "$STORAGE_DIR/index/lib/index_auth_secret.secret"
    
    print_success "Secrets generated and stored securely"
}

# Build Torrust Tracker
build_tracker() {
    print_status "Building Torrust Tracker..."
    
    cd "$TRACKER_DIR"
    
    # Create database file
    touch "$STORAGE_DIR/tracker/lib/database/sqlite3.db"
    
    # Copy and customize tracker configuration
    cp "$TRACKER_DIR/share/default/config/tracker.development.sqlite3.toml" "$STORAGE_DIR/tracker/etc/tracker.toml"
    
    # Update configuration with generated secrets
    sed -i.bak "s/MyAccessToken/$TRACKER_API_TOKEN/g" "$STORAGE_DIR/tracker/etc/tracker.toml"
    
    # Build tracker
    cargo build --release
    
    print_success "Torrust Tracker built successfully"
}

# Build Torrust Index
build_index() {
    print_status "Building Torrust Index..."
    
    cd "$INDEX_DIR"
    
    # Create database file
    touch "$STORAGE_DIR/index/lib/database/sqlite3.db"
    
    # Copy and customize index configuration
    cp "$INDEX_DIR/share/default/config/index.development.sqlite3.toml" "$STORAGE_DIR/index/etc/index.toml"
    
    # Update configuration with generated secrets
    sed -i.bak "s/MyAccessToken/$TRACKER_API_TOKEN/g" "$STORAGE_DIR/index/etc/index.toml"
    sed -i.bak "s/MaxVerstappenWC2021/$INDEX_AUTH_SECRET/g" "$STORAGE_DIR/index/etc/index.toml"
    
    # Build index
    cargo build --release
    
    print_success "Torrust Index built successfully"
}

# Build Torrust Index GUI
build_gui() {
    print_status "Building Torrust Index GUI..."
    
    cd "$GUI_DIR"
    
    # Install dependencies
    npm install
    
    # Create environment file
    cat > "$GUI_DIR/.env" << EOF
# App build variables
API_BASE_URL=http://localhost:3001/v1

# Rust SQLx
DATABASE_URL=sqlite://$STORAGE_DIR/index/lib/database/sqlite3.db?mode=rwc

# Docker compose
TORRUST_INDEX_CONFIG_TOML=
USER_ID=1000
TORRUST_TRACKER_CONFIG_TOML=
TORRUST_TRACKER_CONFIG_OVERRIDE_HTTP_API__ACCESS_TOKENS__ADMIN=$TRACKER_API_TOKEN
EOF
    
    # Build GUI
    npm run build
    
    print_success "Torrust Index GUI built successfully"
}

# Create systemd service files
create_systemd_services() {
    print_status "Creating systemd service files..."
    
    # Tracker service
    cat > "$CONFIG_DIR/torrust-tracker.service" << EOF
[Unit]
Description=Torrust Tracker
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$TRACKER_DIR
ExecStart=$TRACKER_DIR/target/release/torrust-tracker
Environment=TORRUST_TRACKER_CONFIG_TOML_PATH=$STORAGE_DIR/tracker/etc/tracker.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Index service
    cat > "$CONFIG_DIR/torrust-index.service" << EOF
[Unit]
Description=Torrust Index
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INDEX_DIR
ExecStart=$INDEX_DIR/target/release/torrust-index
Environment=TORRUST_INDEX_CONFIG_TOML_PATH=$STORAGE_DIR/index/etc/index.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    print_success "Systemd service files created"
}

# Create Nginx configuration
create_nginx_config() {
    print_status "Creating Nginx configuration..."
    
    cat > "$CONFIG_DIR/torrust.conf" << EOF
server {
    listen 80;
    server_name localhost;
    
    # Serve the GUI
    location / {
        root $GUI_DIR/dist;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    
    # Proxy API requests to the index backend
    location /api/ {
        proxy_pass http://127.0.0.1:3001/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Proxy tracker API requests
    location /tracker-api/ {
        proxy_pass http://127.0.0.1:1212/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    print_success "Nginx configuration created"
}

# Create management scripts
create_management_scripts() {
    print_status "Creating management scripts..."
    
    # Start script
    cat > "$PROJECT_ROOT/start.sh" << 'EOF'
#!/bin/bash
set -e

PROJECT_ROOT="/Users/kieranmenadue/Downloads/MacTracker"
TRACKER_DIR="$PROJECT_ROOT/torrust-tracker"
INDEX_DIR="$PROJECT_ROOT/torrust-index"
GUI_DIR="$PROJECT_ROOT/torrust-index-gui"
STORAGE_DIR="$PROJECT_ROOT/storage"

echo "Starting Torrust services..."

# Start tracker
echo "Starting Torrust Tracker..."
cd "$TRACKER_DIR"
TORRUST_TRACKER_CONFIG_TOML_PATH="$STORAGE_DIR/tracker/etc/tracker.toml" ./target/release/torrust-tracker &
TRACKER_PID=$!

# Wait a moment for tracker to start
sleep 2

# Start index
echo "Starting Torrust Index..."
cd "$INDEX_DIR"
TORRUST_INDEX_CONFIG_TOML_PATH="$STORAGE_DIR/index/etc/index.toml" ./target/release/torrust-index &
INDEX_PID=$!

# Wait a moment for index to start
sleep 2

# Start GUI (if built)
if [ -d "$GUI_DIR/dist" ]; then
    echo "Starting Torrust Index GUI..."
    cd "$GUI_DIR"
    npm run preview &
    GUI_PID=$!
fi

echo "All services started!"
echo "Tracker PID: $TRACKER_PID"
echo "Index PID: $INDEX_PID"
if [ ! -z "$GUI_PID" ]; then
    echo "GUI PID: $GUI_PID"
fi

echo ""
echo "Services are running:"
echo "- Tracker API: http://localhost:1212"
echo "- Index API: http://localhost:3001"
echo "- GUI: http://localhost:3000"
echo ""
echo "To stop services, run: ./stop.sh"

# Save PIDs for stop script
echo "$TRACKER_PID" > "$PROJECT_ROOT/.tracker.pid"
echo "$INDEX_PID" > "$PROJECT_ROOT/.index.pid"
if [ ! -z "$GUI_PID" ]; then
    echo "$GUI_PID" > "$PROJECT_ROOT/.gui.pid"
fi
EOF

    # Stop script
    cat > "$PROJECT_ROOT/stop.sh" << 'EOF'
#!/bin/bash

PROJECT_ROOT="/Users/kieranmenadue/Downloads/MacTracker"

echo "Stopping Torrust services..."

# Stop tracker
if [ -f "$PROJECT_ROOT/.tracker.pid" ]; then
    TRACKER_PID=$(cat "$PROJECT_ROOT/.tracker.pid")
    if kill -0 "$TRACKER_PID" 2>/dev/null; then
        kill "$TRACKER_PID"
        echo "Stopped tracker (PID: $TRACKER_PID)"
    fi
    rm -f "$PROJECT_ROOT/.tracker.pid"
fi

# Stop index
if [ -f "$PROJECT_ROOT/.index.pid" ]; then
    INDEX_PID=$(cat "$PROJECT_ROOT/.index.pid")
    if kill -0 "$INDEX_PID" 2>/dev/null; then
        kill "$INDEX_PID"
        echo "Stopped index (PID: $INDEX_PID)"
    fi
    rm -f "$PROJECT_ROOT/.index.pid"
fi

# Stop GUI
if [ -f "$PROJECT_ROOT/.gui.pid" ]; then
    GUI_PID=$(cat "$PROJECT_ROOT/.gui.pid")
    if kill -0 "$GUI_PID" 2>/dev/null; then
        kill "$GUI_PID"
        echo "Stopped GUI (PID: $GUI_PID)"
    fi
    rm -f "$PROJECT_ROOT/.gui.pid"
fi

echo "All services stopped"
EOF

    # Make scripts executable
    chmod +x "$PROJECT_ROOT/start.sh"
    chmod +x "$PROJECT_ROOT/stop.sh"

    print_success "Management scripts created"
}

# Create comprehensive README
create_readme() {
    print_status "Creating comprehensive README..."
    
    cat > "$PROJECT_ROOT/README.md" << EOF
# Torrust Complete Build & Deployment

This repository contains a complete build and deployment setup for the Torrust BitTorrent suite.

## Architecture

The Torrust project consists of three main components:

1. **Torrust Tracker** (Rust) - A modern BitTorrent tracker that manages peer connections
2. **Torrust Index** (Rust) - Backend API for torrent metadata management  
3. **Torrust Index GUI** (Vue.js/Nuxt) - Frontend web interface

## Quick Start

### Prerequisites

- Rust (≥1.72)
- Cargo
- Node.js (≥20.10.0)
- NPM

### Build Everything

\`\`\`bash
./build.sh
\`\`\`

This will:
- Check prerequisites
- Create directory structure
- Generate secure secrets
- Build all three components
- Create configuration files
- Set up management scripts

### Start Services

\`\`\`bash
./start.sh
\`\`\`

### Stop Services

\`\`\`bash
./stop.sh
\`\`\`

## Services

After starting, the following services will be available:

- **Tracker API**: http://localhost:1212
- **Index API**: http://localhost:3001
- **GUI**: http://localhost:3000

## Configuration

### Tracker Configuration
- Location: \`storage/tracker/etc/tracker.toml\`
- Database: \`storage/tracker/lib/database/sqlite3.db\`
- API Token: Generated automatically and stored in \`storage/tracker/lib/tracker_api_admin_token.secret\`

### Index Configuration
- Location: \`storage/index/etc/index.toml\`
- Database: \`storage/index/lib/database/sqlite3.db\`
- Auth Secret: Generated automatically and stored in \`storage/index/lib/index_auth_secret.secret\`

### GUI Configuration
- Environment: \`.env\`
- Built files: \`dist/\`

## Management

### Manual Service Management

#### Start Tracker
\`\`\`bash
cd torrust-tracker
TORRUST_TRACKER_CONFIG_TOML_PATH="../storage/tracker/etc/tracker.toml" ./target/release/torrust-tracker
\`\`\`

#### Start Index
\`\`\`bash
cd torrust-index
TORRUST_INDEX_CONFIG_TOML_PATH="../storage/index/etc/index.toml" ./target/release/torrust-index
\`\`\`

#### Start GUI
\`\`\`bash
cd torrust-index-gui
npm run dev  # Development mode
# or
npm run preview  # Production preview
\`\`\`

### Database Management

The databases are SQLite files located in:
- Tracker: \`storage/tracker/lib/database/sqlite3.db\`
- Index: \`storage/index/lib/database/sqlite3.db\`

### Logs

Check the console output for logs. For production deployment, consider setting up proper logging.

## Production Deployment

For production deployment:

1. **Security**: Change all default secrets and tokens
2. **SSL/TLS**: Configure SSL certificates
3. **Reverse Proxy**: Use Nginx or similar
4. **Process Management**: Use systemd or similar
5. **Monitoring**: Set up health checks and monitoring
6. **Backups**: Regular database backups

## Troubleshooting

### Common Issues

1. **Port conflicts**: Ensure ports 1212, 3001, and 3000 are available
2. **Permission issues**: Check file permissions for database and config files
3. **Build failures**: Ensure all prerequisites are installed

### Health Checks

- Tracker: \`curl http://localhost:1212/api/v1/stats?token=YOUR_TOKEN\`
- Index: \`curl http://localhost:3001/v1/health\`
- GUI: \`curl http://localhost:3000\`

## Development

### Rebuilding

To rebuild after changes:

\`\`\`bash
# Rebuild tracker
cd torrust-tracker && cargo build --release

# Rebuild index
cd torrust-index && cargo build --release

# Rebuild GUI
cd torrust-index-gui && npm run build
\`\`\`

### Testing

\`\`\`bash
# Test tracker
cd torrust-tracker && cargo test

# Test index
cd torrust-index && cargo test

# Test GUI
cd torrust-index-gui && npm run test
\`\`\`

## License

This project is licensed under the AGPL-3.0 license. See the individual component repositories for details.

## Support

For issues and questions:
- [Torrust Tracker](https://github.com/torrust/torrust-tracker)
- [Torrust Index](https://github.com/torrust/torrust-index)
- [Torrust Index GUI](https://github.com/torrust/torrust-index-gui)
EOF

    print_success "README created"
}

# Main build function
main() {
    print_status "Starting Torrust complete build process..."
    
    check_prerequisites
    create_directories
    generate_secrets
    build_tracker
    build_index
    build_gui
    create_systemd_services
    create_nginx_config
    create_management_scripts
    create_readme
    
    print_success "Build completed successfully!"
    print_status ""
    print_status "Next steps:"
    print_status "1. Run './start.sh' to start all services"
    print_status "2. Access the GUI at http://localhost:3000"
    print_status "3. Check the README.md for detailed information"
    print_status ""
    print_status "Services will be available at:"
    print_status "- Tracker API: http://localhost:1212"
    print_status "- Index API: http://localhost:3001"
    print_status "- GUI: http://localhost:3000"
}

# Run main function
main "$@"
