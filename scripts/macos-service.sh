#!/bin/bash
# Run the WhatsApp bridge as a macOS launchd background service.
# It starts at login, restarts if it crashes, and logs to ~/Library/Logs/whatsapp-bridge.log.
#
# Usage: scripts/macos-service.sh install | uninstall | restart | status | logs
#
# Pair once in a terminal first (cd whatsapp-bridge && ./whatsapp-bridge, scan the QR, Ctrl+C);
# the service then reuses the saved session in whatsapp-bridge/store/.
set -euo pipefail

LABEL="com.whatsapp-mcp.bridge"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE_DIR="$REPO_DIR/whatsapp-bridge"
BINARY="$BRIDGE_DIR/whatsapp-bridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/whatsapp-bridge.log"
DOMAIN="gui/$(id -u)"

build() {
  echo "Building bridge..."
  (cd "$BRIDGE_DIR" && go build -buildvcs=false -o whatsapp-bridge .)
}

install() {
  [ -x "$BINARY" ] || build
  if [ ! -f "$BRIDGE_DIR/store/whatsapp.db" ]; then
    echo "No WhatsApp session found. Pair first: cd $BRIDGE_DIR && ./whatsapp-bridge (scan QR, then Ctrl+C)." >&2
    exit 1
  fi
  if pgrep -f "^\./whatsapp-bridge" >/dev/null || pgrep -fx "$BINARY" >/dev/null; then
    echo "A bridge is already running outside launchd; stop it (Ctrl+C in its terminal) and re-run." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
  cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BINARY</string></array>
  <key>WorkingDirectory</key><string>$BRIDGE_DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$PLIST"
  echo "Installed and started $LABEL (log: $LOG)"
}

uninstall() {
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Stopped and removed $LABEL"
}

case "${1:-}" in
  install) install ;;
  uninstall) uninstall ;;
  restart) launchctl kickstart -k "$DOMAIN/$LABEL" && echo "Restarted $LABEL" ;;
  status) launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E "state =|pid =|last exit code" || echo "$LABEL is not loaded" ;;
  logs) tail -n 50 -f "$LOG" ;;
  *) echo "Usage: $0 install | uninstall | restart | status | logs" >&2; exit 1 ;;
esac
