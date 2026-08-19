#!/bin/sh

set -u

APP_NAME="Dead Air"
BUNDLE_ID="nu.soep.deadair"
HELPER_LABEL="$BUNDLE_ID.SMC.Helper"
SUPPORT_DIR="DeadAir"

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    HOME=$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory | awk '{print $2}')
fi

run_as_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        sudo -u "$SUDO_USER" "$@"
    else
        "$@"
    fi
}

echo "Uninstalling $APP_NAME..."

run_as_user osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true

echo "Removing the SMC helper (administrator privileges are required)..."
sudo launchctl bootout "system/$HELPER_LABEL" 2>/dev/null || true
sudo launchctl unload "/Library/LaunchDaemons/$HELPER_LABEL.plist" 2>/dev/null || true
sudo rm -f "/Library/LaunchDaemons/$HELPER_LABEL.plist"
sudo rm -f "/Library/PrivilegedHelperTools/$HELPER_LABEL"

for app in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"; do
    if [ -d "$app" ]; then
        echo "Removing $app..."
        sudo rm -rf "$app"
    fi
done

echo "Removing application data and preferences..."
rm -rf "$HOME/Library/Application Support/$SUPPORT_DIR"
rm -rf "$HOME/Library/Containers/$BUNDLE_ID.Widgets"
rm -rf "$HOME/Library/Group Containers/"*."$BUNDLE_ID".widgets
run_as_user defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
run_as_user defaults delete "$BUNDLE_ID.Widgets" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.Widgets.plist"

# The app is signed ad-hoc, so macOS can hold an approval that no longer matches any
# installed build. Dropping it leaves no orphan entry behind in Privacy & Security.
run_as_user tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "$APP_NAME has been uninstalled."
echo "If fan speeds were controlled manually, they will return to automatic control after a reboot."
