#!/bin/bash
# Builds Vinyl.app into ./build. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Vinyl.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Vinyl "$APP/Contents/MacOS/Vinyl"
cp Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature: fine for running locally. macOS may ask for Automation access
# again after each rebuild because the signature changes.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Vinyl || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Vinyl.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/Vinyl.app"
    echo "Installed to ~/Applications/Vinyl.app"
fi
