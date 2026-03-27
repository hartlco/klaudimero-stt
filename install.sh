#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.klaudimero-stt"
PLIST_NAME="com.klaudimero.stt"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
PORT="${STT_PORT:-8586}"

echo "=== klaudimero-stt installer ==="

# Check prerequisites
if ! command -v swift &>/dev/null; then
    echo "Error: Swift toolchain not found. Install Xcode or Swift."
    exit 1
fi

if ! command -v ffmpeg &>/dev/null; then
    echo "Warning: ffmpeg not found. Voice format conversion will fail."
    echo "Install with: brew install ffmpeg"
fi

# Build
echo "Building release binary..."
cd "$SCRIPT_DIR"
swift build -c release

# Install binary
mkdir -p "$INSTALL_DIR"
BINARY_PATH="$(swift build -c release --show-bin-path)/KlaudimeroSTT"
cp "$BINARY_PATH" "$INSTALL_DIR/klaudimero-stt"
echo "Installed binary to $INSTALL_DIR/klaudimero-stt"

# Create launchd plist
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/klaudimero-stt</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>STT_PORT</key>
        <string>${PORT}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${INSTALL_DIR}/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${INSTALL_DIR}/stderr.log</string>
</dict>
</plist>
EOF

echo "Created launchd plist at $PLIST_PATH"

# Load service
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo ""
echo "=== Done ==="
echo "Service running on port $PORT"
echo "  Health check: curl http://localhost:$PORT/health"
echo "  Logs: tail -f $INSTALL_DIR/stderr.log"
echo "  Stop: launchctl unload $PLIST_PATH"
echo "  Start: launchctl load $PLIST_PATH"
