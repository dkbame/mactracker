# Torrust Server Setup Guide

This guide will help you deploy the Torrust BitTorrent suite on a production server.

## Prerequisites

- Ubuntu 20.04+ or Debian 11+
- Root access or sudo privileges
- At least 2GB RAM
- At least 10GB disk space

## Quick Deployment

### Option 1: Automated Script (Recommended)

```bash
# Clone the repository
git clone https://github.com/dkbame/mactracker.git
cd mactracker

# Make the deployment script executable
chmod +x deploy.sh

# Run the deployment script
sudo ./deploy.sh
```

### Option 2: Docker Compose

```bash
# Clone the repository
git clone https://github.com/dkbame/mactracker.git
cd mactracker

# Start all services
docker-compose up -d
```

### Option 3: Manual Setup

Follow the manual setup steps below.

## Manual Setup

### 1. Install Dependencies

```bash
# Update package list
sudo apt update

# Install required packages
sudo apt install -y git curl build-essential pkg-config libssl-dev libsqlite3-dev nginx supervisor ufw fail2ban

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
```

### 2. Deploy the Application

```bash
# Create project directory
sudo mkdir -p /opt/torrust
cd /opt/torrust

# Clone repository
sudo git clone https://github.com/dkbame/mactracker.git .

# Create service user
sudo useradd -r -s /bin/false -d /opt/torrust torrust

# Build the application
cd torrust-tracker && cargo build --release && cd ..
cd torrust-index && cargo build --release && cd ..
cd torrust-index-gui && npm install && npm run build && cd ..

# Set ownership
sudo chown -R torrust:torrust /opt/torrust
```

### 3. Configure Services

#### Tracker Service

Create `/etc/systemd/system/torrust-tracker.service`:

```ini
[Unit]
Description=Torrust Tracker
After=network.target

[Service]
Type=simple
User=torrust
Group=torrust
WorkingDirectory=/opt/torrust/torrust-tracker
ExecStart=/opt/torrust/torrust-tracker/target/release/torrust-tracker
Environment=TORRUST_TRACKER_CONFIG_TOML_PATH=/opt/torrust/storage/tracker/etc/tracker.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

#### Index Service

Create `/etc/systemd/system/torrust-index.service`:

```ini
[Unit]
Description=Torrust Index
After=network.target

[Service]
Type=simple
User=torrust
Group=torrust
WorkingDirectory=/opt/torrust/torrust-index
ExecStart=/opt/torrust/torrust-index/target/release/torrust-index
Environment=TORRUST_INDEX_CONFIG_TOML_PATH=/opt/torrust/storage/index/etc/index.toml
Environment=TORRUST_INDEX_API_CORS_PERMISSIVE=1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

#### GUI Service

Create `/etc/systemd/system/torrust-gui.service`:

```ini
[Unit]
Description=Torrust Index GUI
After=network.target

[Service]
Type=simple
User=torrust
Group=torrust
WorkingDirectory=/opt/torrust/torrust-index-gui
ExecStart=/usr/bin/node /opt/torrust/torrust-index-gui/.output/server/index.mjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 4. Configure Nginx

Create `/etc/nginx/sites-available/torrust`:

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    # Serve the GUI
    location / {
        root /opt/torrust/torrust-index-gui/dist;
        index index.html;
        try_files $uri $uri/ /index.html;
    }
    
    # Proxy API requests
    location /api/ {
        proxy_pass http://127.0.0.1:3001/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Proxy tracker API requests
    location /tracker-api/ {
        proxy_pass http://127.0.0.1:1212/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable the site:

```bash
sudo ln -s /etc/nginx/sites-available/torrust /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 5. Configure Firewall

```bash
# Enable UFW
sudo ufw enable

# Allow SSH
sudo ufw allow ssh

# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow tracker ports
sudo ufw allow 6969/udp
sudo ufw allow 7070/tcp
```

### 6. Start Services

```bash
# Enable services
sudo systemctl enable torrust-tracker
sudo systemctl enable torrust-index
sudo systemctl enable torrust-gui

# Start services
sudo systemctl start torrust-tracker
sudo systemctl start torrust-index
sudo systemctl start torrust-gui
```

## SSL/HTTPS Setup

### Using Let's Encrypt (Recommended)

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Get SSL certificate
sudo certbot --nginx -d your-domain.com

# Test automatic renewal
sudo certbot renew --dry-run
```

## Monitoring

### Check Service Status

```bash
# Check all services
sudo systemctl status torrust-tracker torrust-index torrust-gui

# Check logs
sudo journalctl -u torrust-tracker -f
sudo journalctl -u torrust-index -f
sudo journalctl -u torrust-gui -f
```

### Health Checks

```bash
# Check tracker API
curl http://localhost:1212/api/v1/stats?token=YOUR_TOKEN

# Check index API
curl http://localhost:3001/v1/torrents

# Check GUI
curl http://localhost:3000
```

## Security Considerations

1. **Change Default Secrets**: Update all default tokens and secrets in configuration files
2. **Firewall**: Only open necessary ports
3. **SSL**: Use HTTPS in production
4. **Updates**: Regularly update the system and application
5. **Backups**: Regular database backups
6. **Monitoring**: Set up monitoring and alerting

## Troubleshooting

### Common Issues

1. **Port Conflicts**: Check if ports are already in use
2. **Permission Issues**: Ensure proper file ownership
3. **CORS Errors**: Verify CORS environment variable is set
4. **Database Issues**: Check database file permissions

### Logs

- Tracker logs: `journalctl -u torrust-tracker -f`
- Index logs: `journalctl -u torrust-index -f`
- GUI logs: `journalctl -u torrust-gui -f`
- Nginx logs: `/var/log/nginx/error.log`

## Maintenance

### Updates

```bash
# Pull latest changes
cd /opt/torrust
sudo git pull origin main

# Rebuild and restart services
sudo systemctl restart torrust-tracker torrust-index torrust-gui
```

### Backups

```bash
# Backup databases
sudo cp /opt/torrust/storage/tracker/lib/database/sqlite3.db /backup/tracker-$(date +%Y%m%d).db
sudo cp /opt/torrust/storage/index/lib/database/sqlite3.db /backup/index-$(date +%Y%m%d).db
```

## Support

For issues and questions:
- [Torrust Tracker](https://github.com/torrust/torrust-tracker)
- [Torrust Index](https://github.com/torrust/torrust-index)
- [Torrust Index GUI](https://github.com/torrust/torrust-index-gui)
