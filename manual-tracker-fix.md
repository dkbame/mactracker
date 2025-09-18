# Manual Tracker API Fix

## Step-by-Step Fix for Tracker API Issues

### Step 1: Stop and Remove Tracker Container
```bash
cd /opt/torrust
docker compose -f docker-compose-https.yml stop tracker
docker compose -f docker-compose-https.yml rm -f tracker
```

### Step 2: Fix Database Permissions
```bash
# Fix database permissions
chmod 664 ./storage/tracker/lib/database/sqlite3.db
chown 1000:1000 ./storage/tracker/lib/database/sqlite3.db

# Or recreate if missing
mkdir -p ./storage/tracker/lib/database
touch ./storage/tracker/lib/database/sqlite3.db
chmod 664 ./storage/tracker/lib/database/sqlite3.db
chown 1000:1000 ./storage/tracker/lib/database/sqlite3.db
```

### Step 3: Create Clean Tracker Config
```bash
cat > ./config/tracker.toml << 'EOF'
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
EOF
```

### Step 4: Start Tracker Container
```bash
docker compose -f docker-compose-https.yml up -d tracker
```

### Step 5: Wait and Test
```bash
# Wait for tracker to start
sleep 20

# Test tracker API
curl http://127.0.0.1:1212/stats

# Test with token
curl -H "Authorization: Bearer MyAccessToken" http://127.0.0.1:1212/stats

# Test HTTP tracker
curl http://127.0.0.1:7070/announce
```

### Step 6: Check Logs if Still Failing
```bash
# Check tracker logs
docker compose -f docker-compose-https.yml logs tracker

# Check port bindings
netstat -tlnp | grep -E ":(1212|7070|6969)"
```

### Step 7: If Still Not Working, Try Fresh Start
```bash
# Stop everything
docker compose -f docker-compose-https.yml down

# Remove all containers
docker compose -f docker-compose-https.yml rm -f

# Start fresh
docker compose -f docker-compose-https.yml up -d tracker
sleep 20
docker compose -f docker-compose-https.yml up -d index
sleep 10
docker compose -f docker-compose-https.yml up -d gui
```

## Expected Results

After the fix, you should see:
- `curl http://127.0.0.1:1212/stats` returns tracker statistics
- `curl http://127.0.0.1:7070/announce` returns tracker response
- No 500 errors in tracker logs

## Common Issues

1. **Database permissions**: Make sure the database file is writable by the container
2. **Port conflicts**: Check if ports 1212, 7070, 6969 are free
3. **Container startup time**: Tracker may need 15-30 seconds to fully start
4. **Configuration errors**: Make sure the tracker.toml file is valid
