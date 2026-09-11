#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Run build first
bash "$SCRIPT_DIR/build.sh"

TARGET_DIR="$HOME/Applications"
if [ ! -d "$TARGET_DIR" ]; then
    TARGET_DIR="/Applications"
fi

APP_DEST="$TARGET_DIR/SmartSleep.app"

echo "🔐 Konfigurerer NOPASSWD for 'sudo pmset -a disablesleep'..."
USER_NAME="$(whoami)"
SUDOERS_FILE="/etc/sudoers.d/smartsleep"
RULE="$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep *"

# Configure sudoers if not already present
if [ ! -f "$SUDOERS_FILE" ]; then
    osascript -e "do shell script \"mkdir -p /etc/sudoers.d && echo '$RULE' > $SUDOERS_FILE && chmod 0440 $SUDOERS_FILE\" with administrator privileges" || true
fi

echo "🚀 Installerer SmartSleep.app i $TARGET_DIR..."

# Stop kørende instans og vent til den er helt ude. Den rydder op (pmset) før den
# afslutter, og åbnes den nye imens, fejler 'open' med -600.
pkill -f "SmartSleep.app/Contents/MacOS/SmartSleep" || true
for _ in $(seq 1 50); do
    pgrep -f "SmartSleep.app/Contents/MacOS/SmartSleep" >/dev/null || break
    sleep 0.1
done

# Restore normal sleep before restarting
sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null || true

# Copy app to Applications
rm -rf "$APP_DEST"
cp -R "$SCRIPT_DIR/build/SmartSleep.app" "$APP_DEST"

echo "✨ Åbner SmartSleep.app..."
open "$APP_DEST"

echo "🎉 SmartSleep er nu opdateret og kører med 'sudo pmset -a disablesleep 1'!"
