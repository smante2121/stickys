#!/bin/zsh
# Build Stickys from the command line.
#
#   scripts/build.sh            build (Debug)
#   scripts/build.sh run        build (Debug) and relaunch the app
#   scripts/build.sh install    build (Release) and copy to ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-build}"
config="Debug"
[[ "$mode" == "install" ]] && config="Release"

xcodebuild \
  -project Stickys.xcodeproj \
  -scheme Stickys \
  -configuration "$config" \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath build/DerivedData \
  -quiet \
  build

app="build/DerivedData/Build/Products/$config/Stickys.app"
echo "Built $app"

case "$mode" in
  run)
    pkill -x Stickys 2>/dev/null && sleep 0.5 || true
    open "$app"
    ;;
  install)
    pkill -x Stickys 2>/dev/null && sleep 0.5 || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Stickys.app
    cp -R "$app" ~/Applications/
    open ~/Applications/Stickys.app
    echo "Installed to ~/Applications/Stickys.app"
    ;;
esac
