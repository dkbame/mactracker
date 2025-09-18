#!/bin/bash

# Diagnose domain and SSL setup issues
# Run this to check what's preventing SSL certificate generation

set -e

DOMAIN="macosapps.net"
SERVER_IP="109.104.153.250"

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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status "Diagnosing domain and SSL setup for $DOMAIN..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_warning "Not running as root - some checks may fail"
fi

# 1. Check domain resolution
print_status "1. Checking domain resolution..."
echo "Checking $DOMAIN:"
DOMAIN_IP=$(nslookup $DOMAIN | grep -A1 "Name:" | tail -1 | awk '{print $2}')
echo "Domain resolves to: $DOMAIN_IP"
echo "Expected server IP: $SERVER_IP"

if [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
    print_success "Domain points to correct server"
else
    print_error "Domain does not point to this server!"
    print_status "Please update your DNS records:"
    print_status "A record: $DOMAIN -> $SERVER_IP"
    print_status "A record: www.$DOMAIN -> $SERVER_IP"
fi

echo ""
echo "Checking www.$DOMAIN:"
WWW_IP=$(nslookup www.$DOMAIN | grep -A1 "Name:" | tail -1 | awk '{print $2}')
echo "www.$DOMAIN resolves to: $WWW_IP"

if [ "$WWW_IP" = "$SERVER_IP" ]; then
    print_success "www subdomain points to correct server"
else
    print_error "www subdomain does not point to this server!"
fi

# 2. Check if domain is accessible
print_status "2. Checking domain accessibility..."
if curl -s --connect-timeout 10 http://$DOMAIN > /dev/null; then
    print_success "Domain is accessible via HTTP"
else
    print_error "Domain is not accessible via HTTP"
    print_status "This could be due to:"
    print_status "- DNS propagation delay (wait up to 24 hours)"
    print_status "- Firewall blocking port 80"
    print_status "- Nginx not running"
fi

# 3. Check port 80
print_status "3. Checking port 80..."
if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
    print_success "Port 80 is listening"
    netstat -tlnp | grep ":80 "
else
    print_error "Port 80 is not listening"
    print_status "Starting Nginx..."
    systemctl start nginx 2>/dev/null || print_error "Failed to start Nginx"
fi

# 4. Check firewall
print_status "4. Checking firewall..."
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status | grep "80/tcp" || echo "Port 80 not found in UFW rules")
    print_status "UFW status for port 80: $UFW_STATUS"
fi

if command -v iptables &> /dev/null; then
    IPTABLES_RULES=$(iptables -L INPUT | grep -i "80\|http" || echo "No HTTP rules found")
    print_status "iptables rules: $IPTABLES_RULES"
fi

# 5. Check Nginx configuration
print_status "5. Checking Nginx configuration..."
if nginx -t 2>/dev/null; then
    print_success "Nginx configuration is valid"
else
    print_error "Nginx configuration has errors"
    nginx -t
fi

# 6. Check if Let's Encrypt can reach the domain
print_status "6. Testing Let's Encrypt challenge path..."
mkdir -p /var/www/certbot
echo "test" > /var/www/certbot/test.txt

if curl -s http://$DOMAIN/.well-known/acme-challenge/test.txt | grep -q "test"; then
    print_success "Let's Encrypt challenge path is accessible"
else
    print_error "Let's Encrypt challenge path is not accessible"
    print_status "This is why SSL certificate generation is failing"
fi

# 7. Check if domain is accessible from external sources
print_status "7. Checking external accessibility..."
if curl -s --connect-timeout 10 http://$DOMAIN | grep -q "macosapps.net\|nginx\|apache"; then
    print_success "Domain is accessible from external sources"
else
    print_warning "Domain may not be accessible from external sources"
    print_status "This could be due to DNS propagation delay"
fi

# 8. Provide recommendations
print_status "8. Recommendations:"
echo ""
if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
    print_error "CRITICAL: Update your DNS records first!"
    print_status "Set these DNS records:"
    print_status "A record: $DOMAIN -> $SERVER_IP"
    print_status "A record: www.$DOMAIN -> $SERVER_IP"
    print_status "Then wait for DNS propagation (up to 24 hours)"
    echo ""
fi

if ! netstat -tlnp | grep -q ":80 "; then
    print_error "CRITICAL: Port 80 is not listening!"
    print_status "Start Nginx: systemctl start nginx"
    echo ""
fi

print_status "After fixing the above issues, run:"
print_status "sudo ./fix-ssl-setup.sh"
