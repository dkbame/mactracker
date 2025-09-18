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

```bash
./build.sh
```

This will:
- Check prerequisites
- Create directory structure
- Generate secure secrets
- Build all three components
- Create configuration files
- Set up management scripts

### Start Services

```bash
./start.sh
```

### Stop Services

```bash
./stop.sh
```

## Services

After starting, the following services will be available:

- **Tracker API**: http://localhost:1212
- **Index API**: http://localhost:3001
- **GUI**: http://localhost:3000

## Configuration

### Tracker Configuration
- Location: `storage/tracker/etc/tracker.toml`
- Database: `storage/tracker/lib/database/sqlite3.db`
- API Token: Generated automatically and stored in `storage/tracker/lib/tracker_api_admin_token.secret`

### Index Configuration
- Location: `storage/index/etc/index.toml`
- Database: `storage/index/lib/database/sqlite3.db`
- Auth Secret: Generated automatically and stored in `storage/index/lib/index_auth_secret.secret`

### GUI Configuration
- Environment: `.env`
- Built files: `dist/`

## Management

### Manual Service Management

#### Start Tracker
```bash
cd torrust-tracker
TORRUST_TRACKER_CONFIG_TOML_PATH="../storage/tracker/etc/tracker.toml" ./target/release/torrust-tracker
```

#### Start Index
```bash
cd torrust-index
TORRUST_INDEX_CONFIG_TOML_PATH="../storage/index/etc/index.toml" ./target/release/torrust-index
```

#### Start GUI
```bash
cd torrust-index-gui
npm run dev  # Development mode
# or
npm run preview  # Production preview
```

### Database Management

The databases are SQLite files located in:
- Tracker: `storage/tracker/lib/database/sqlite3.db`
- Index: `storage/index/lib/database/sqlite3.db`

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

- Tracker: `curl http://localhost:1212/api/v1/stats?token=YOUR_TOKEN`
- Index: `curl http://localhost:3001/v1/health`
- GUI: `curl http://localhost:3000`

## Development

### Rebuilding

To rebuild after changes:

```bash
# Rebuild tracker
cd torrust-tracker && cargo build --release

# Rebuild index
cd torrust-index && cargo build --release

# Rebuild GUI
cd torrust-index-gui && npm run build
```

### Testing

```bash
# Test tracker
cd torrust-tracker && cargo test

# Test index
cd torrust-index && cargo test

# Test GUI
cd torrust-index-gui && npm run test
```

## License

This project is licensed under the AGPL-3.0 license. See the individual component repositories for details.

## Support

For issues and questions:
- [Torrust Tracker](https://github.com/torrust/torrust-tracker)
- [Torrust Index](https://github.com/torrust/torrust-index)
- [Torrust Index GUI](https://github.com/torrust/torrust-index-gui)
