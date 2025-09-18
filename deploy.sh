#!/bin/bash

# Torrust Server Deployment Script
# This script deploys the Torrust suite on a production server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="/opt/torrust"
REPO_URL="https://github.com/dkbame/mactracker.git"
SERVICE_USER="torrust"
NGINX_CONFIG="/etc/nginx/sites-available/torrust"
NGINX_ENABLED="/etc/nginx/sites-enabled/torrust"

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Install system dependencies
install_dependencies() {
    print_status "Installing system dependencies..."
    
    # Update package list
    apt-get update
    
    # Install required packages
    apt-get install -y \
        git \
        curl \
        build-essential \
        pkg-config \
        libssl-dev \
        libsqlite3-dev \
        nginx \
        supervisor \
        ufw \
        fail2ban
    
    print_success "System dependencies installed"
}

# Install Rust
install_rust() {
    print_status "Installing Rust..."
    
    if ! command -v rustc &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source /root/.cargo/env
        echo 'source $HOME/.cargo/env' >> /root/.bashrc
    else
        print_status "Rust already installed"
    fi
    
    print_success "Rust installed"
}

# Install Node.js
install_nodejs() {
    print_status "Installing Node.js..."
    
    if ! command -v node &> /dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    else
        print_status "Node.js already installed"
    fi
    
    print_success "Node.js installed"
}

# Create service user
create_user() {
    print_status "Creating service user..."
    
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$PROJECT_ROOT" "$SERVICE_USER"
        print_success "Service user created"
    else
        print_status "Service user already exists"
    fi
}

# Clone and build project
deploy_project() {
    print_status "Deploying project..."
    
    # Create project directory
    mkdir -p "$PROJECT_ROOT"
    cd "$PROJECT_ROOT"
    
    # Clone repository
    if [ ! -d ".git" ]; then
        git clone "$REPO_URL" .
    else
        git pull origin main
    fi
    
    # Build tracker
    print_status "Building Torrust Tracker..."
    cd torrust-tracker
    cargo build --release
    cd ..
    
    # Build index
    print_status "Building Torrust Index..."
    cd torrust-index
    cargo build --release
    cd ..
    
    # Build GUI
    print_status "Building Torrust Index GUI..."
    cd torrust-index-gui
    npm install
    npm run build
    cd ..
    
    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$PROJECT_ROOT"
    
    print_success "Project deployed and built"
}

# Configure systemd services
configure_services() {
    print_status "Configuring systemd services..."
    
    # Tracker service
    cat > /etc/systemd/system/torrust-tracker.service << EOF
[Unit]
Description=Torrust Tracker
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$PROJECT_ROOT/torrust-tracker
ExecStart=$PROJECT_ROOT/torrust-tracker/target/release/torrust-tracker
Environment=TORRUST_TRACKER_CONFIG_TOML_PATH=$PROJECT_ROOT/storage/tracker/etc/tracker.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Index service
    cat > /etc/systemd/system/torrust-index.service << EOF
[Unit]
Description=Torrust Index
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$PROJECT_ROOT/torrust-index
ExecStart=$PROJECT_ROOT/torrust-index/target/release/torrust-index
Environment=TORRUST_INDEX_CONFIG_TOML_PATH=$PROJECT_ROOT/storage/index/etc/index.toml
Environment=TORRUST_INDEX_API_CORS_PERMISSIVE=1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # GUI service
    cat > /etc/systemd/system/torrust-gui.service << EOF
[Unit]
Description=Torrust Index GUI
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$PROJECT_ROOT/torrust-index-gui
ExecStart=/usr/bin/node $PROJECT_ROOT/torrust-index-gui/.output/server/index.mjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload
    
    print_success "Systemd services configured"
}

# Configure Nginx
configure_nginx() {
    print_status "Configuring Nginx..."
    
    # Create Nginx configuration
    cat > "$NGINX_CONFIG" << EOF
server {
    listen 80;
    server_name _;
    
    # Serve the GUI
    location / {
        root $PROJECT_ROOT/torrust-index-gui/dist;
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

    # Enable site
    ln -sf "$NGINX_CONFIG" "$NGINX_ENABLED"
    
    # Test configuration
    nginx -t
    
    print_success "Nginx configured"
}

# Configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    # Enable UFW
    ufw --force enable
    
    # Allow SSH
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow tracker ports
    ufw allow 6969/udp
    ufw allow 7070/tcp
    
    print_success "Firewall configured"
}

# Start services
start_services() {
    print_status "Starting services..."
    
    # Enable services
    systemctl enable torrust-tracker
    systemctl enable torrust-index
    systemctl enable torrust-gui
    
    # Start services
    systemctl start torrust-tracker
    systemctl start torrust-index
    systemctl start torrust-gui
    
    # Restart Nginx
    systemctl restart nginx
    
    print_success "Services started"
}

# Main deployment function
main() {
    print_status "Starting Torrust server deployment..."
    
    check_root
    install_dependencies
    install_rust
    install_nodejs
    create_user
    deploy_project
    configure_services
    configure_nginx
    configure_firewall
    start_services
    
    print_success "Deployment completed successfully!"
    print_status ""
    print_status "Services are running:"
    print_status "- Tracker API: http://your-server:1212"
    print_status "- Index API: http://your-server:3001"
    print_status "- GUI: http://your-server"
    print_status ""
    print_status "To check service status:"
    print_status "  systemctl status torrust-tracker"
    print_status "  systemctl status torrust-index"
    print_status "  systemctl status torrust-gui"
    print_status ""
    print_status "To view logs:"
    print_status "  journalctl -u torrust-tracker -f"
    print_status "  journalctl -u torrust-index -f"
    print_status "  journalctl -u torrust-gui -f"
}

# Run main function
main "$@"
