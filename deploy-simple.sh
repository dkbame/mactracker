#!/bin/bash

# Simple Torrust Server Deployment Script
# This script uses Docker for easier deployment

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

# Install Docker
install_docker() {
    print_status "Installing Docker..."
    
    if ! command -v docker &> /dev/null; then
        # Update package list
        apt-get update
        
        # Install required packages
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Add Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        # Start Docker
        systemctl start docker
        systemctl enable docker
    else
        print_status "Docker already installed"
    fi
    
    print_success "Docker installed"
}

# Deploy with Docker
deploy_docker() {
    print_status "Deploying with Docker..."
    
    # Create project directory
    mkdir -p "$PROJECT_ROOT"
    cd "$PROJECT_ROOT"
    
    # Clone repository
    if [ ! -d ".git" ]; then
        git clone "$REPO_URL" .
    else
        git pull origin main
    fi
    
    # Create necessary directories
    mkdir -p storage/tracker/lib/database
    mkdir -p storage/index/lib/database
    mkdir -p config
    
    # Create basic configuration files
    cat > config/tracker.toml << 'EOF'
[metadata]
app = "torrust-tracker"
purpose = "configuration"
schema_version = "2.0.0"

[logging]
threshold = "info"

[core]
inactive_peer_cleanup_interval = 120
listed = false
private = false

[core.database]
driver = "sqlite3"
path = "/var/lib/torrust/tracker/database/sqlite3.db"

[core.tracker_policy]
max_peer_timeout = 60
persistent_torrent_completed_stat = true
remove_peerless_torrents = true

[[udp_trackers]]
bind_address = "0.0.0.0:6969"
tracker_usage_statistics = true

[[http_trackers]]
bind_address = "0.0.0.0:7070"
tracker_usage_statistics = true

[http_api]
bind_address = "0.0.0.0:1212"

[http_api.access_tokens]
admin = "MyAccessToken"

[health_check_api]
bind_address = "127.0.0.1:1313"
EOF

    cat > config/index.toml << 'EOF'
[metadata]
app = "torrust-index"
purpose = "configuration"
schema_version = "2.0.0"

[logging]
threshold = "info"

[tracker]
token = "MyAccessToken"

[database]
connect_url = "sqlite:///var/lib/torrust/index/database/sqlite3.db"

[auth]
user_claim_token_pepper = "MaxVerstappenWC2021"

[registration]
[registration.email]
EOF

    # Start services with Docker Compose
    print_status "Starting services with Docker Compose..."
    docker compose up -d
    
    print_success "Services started with Docker"
}

# Configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    # Install UFW if not present
    apt-get install -y ufw
    
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

# Main deployment function
main() {
    print_status "Starting simple Torrust server deployment..."
    
    check_root
    install_docker
    deploy_docker
    configure_firewall
    
    print_success "Deployment completed successfully!"
    print_status ""
    print_status "Services are running:"
    print_status "- Web Interface: http://your-server-ip"
    print_status "- Tracker API: http://your-server-ip:1212"
    print_status "- Index API: http://your-server-ip:3001"
    print_status ""
    print_status "To check service status:"
    print_status "  docker compose ps"
    print_status ""
    print_status "To view logs:"
    print_status "  docker compose logs -f"
    print_status ""
    print_status "To stop services:"
    print_status "  docker compose down"
}

# Run main function
main "$@"
