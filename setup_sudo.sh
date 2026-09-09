#!/bin/bash
set -e

USER_NAME="$(whoami)"
SUDOERS_FILE="/etc/sudoers.d/smartsleep"
RULE="$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep *"

echo "🔐 Opsætter tilladelse for 'pmset -a disablesleep'..."

# Use osascript to run with admin privileges
osascript -e "do shell script \"mkdir -p /etc/sudoers.d && echo '$RULE' > $SUDOERS_FILE && chmod 0440 $SUDOERS_FILE\" with administrator privileges"

echo "✅ Tilladelse opsat! SmartSleep kan nu køre 'sudo pmset -a disablesleep' uden kodeord."
