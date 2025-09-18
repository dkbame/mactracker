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
