#!/usr/bin/env bash
# Double-click this in Finder to build (if needed) and open the app.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$SCRIPT_DIR/Meeting Transcriber.app"

if [ ! -d "$APP" ]; then
    echo "App not built yet — building now…"
    bash "$SCRIPT_DIR/build_app.sh" || {
        echo ""
        echo "Build failed. See errors above."
        read -rp "Press Enter to close…"
        exit 1
    }
fi

open "$APP"
