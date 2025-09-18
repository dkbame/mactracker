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
TORRUST_INDEX_CONFIG_TOML_PATH="$STORAGE_DIR/index/etc/index.toml" TORRUST_INDEX_API_CORS_PERMISSIVE=1 ./target/release/torrust-index &
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
