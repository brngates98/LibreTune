#!/bin/bash
#
# Build LibreTune for the current platform and output to releases/ directory
#
# Usage:
#   ./scripts/build-release.sh [--clean]
#
# Options:
#   --clean    Clean build artifacts before building
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_ROOT/crates/libretune-app"
RELEASES_DIR="$PROJECT_ROOT/releases"

cd "$PROJECT_ROOT"

# Parse arguments
CLEAN=false
for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--clean]"
            echo ""
            echo "Build LibreTune for the current platform and output to releases/ directory"
            echo ""
            echo "Options:"
            echo "  --clean    Clean build artifacts before building"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Detect platform
OS="$(uname -s)"
case "$OS" in
    Linux*)
        PLATFORM="linux"
        ;;
    Darwin*)
        PLATFORM="macos"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        PLATFORM="windows"
        ;;
    *)
        echo "Unknown operating system: $OS"
        exit 1
        ;;
esac

echo "========================================="
echo "LibreTune Release Build"
echo "========================================="
echo "Platform: $PLATFORM"
echo "Project Root: $PROJECT_ROOT"
echo "Releases Dir: $RELEASES_DIR"
echo ""

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo "Cleaning build artifacts..."
    cd "$APP_DIR"
    npm run tauri clean || true
    cd "$PROJECT_ROOT"
    cargo clean || true
    echo "Clean complete."
    echo ""
fi

# Ensure frontend dependencies are installed
echo "Installing frontend dependencies..."
cd "$APP_DIR"
if [ ! -d "node_modules" ] || [ "package.json" -nt "node_modules" ]; then
    npm ci
else
    echo "Frontend dependencies already up to date."
fi

# Build frontend
echo ""
echo "Building frontend..."
npm run build

# Build Tauri app
echo ""
echo "Building Tauri app for $PLATFORM..."
npm run tauri build

# Create releases directory structure
echo ""
echo "Collecting release artifacts..."
mkdir -p "$RELEASES_DIR/$PLATFORM"

# Change back to project root for copying artifacts
cd "$PROJECT_ROOT"

# Copy platform-specific artifacts (paths are relative to project root)
case "$PLATFORM" in
    linux)
        echo "Copying Linux artifacts..."
        if [ -d "target/release/bundle/deb" ]; then
            find target/release/bundle/deb -name "*.deb" -type f -exec cp -v {} "$RELEASES_DIR/$PLATFORM/" \;
        fi
        if [ -d "target/release/bundle/appimage" ]; then
            find target/release/bundle/appimage -name "*.AppImage" -type f -exec cp -v {} "$RELEASES_DIR/$PLATFORM/" \;
        fi
        if [ -f "target/release/libretune-app" ]; then
            cp -v target/release/libretune-app "$RELEASES_DIR/$PLATFORM/"
        fi
        ;;
    macos)
        echo "Copying macOS artifacts..."
        # Copy DMG files
        if [ -d "target/release/bundle/dmg" ]; then
            find target/release/bundle/dmg -name "*.dmg" -type f -exec cp -v {} "$RELEASES_DIR/$PLATFORM/" \;
        fi
        # Copy .app bundle
        if [ -d "target/release/bundle/macos" ]; then
            find target/release/bundle/macos -name "*.app" -type d -exec cp -R {} "$RELEASES_DIR/$PLATFORM/" \;
        fi
        ;;
    windows)
        echo "Copying Windows artifacts..."
        if [ -d "target/release/bundle/msi" ]; then
            find target/release/bundle/msi -name "*.msi" -type f -exec cp -v {} "$RELEASES_DIR/$PLATFORM/" \;
        fi
        if [ -d "target/release/bundle/nsis" ]; then
            find target/release/bundle/nsis -name "*.exe" -type f -exec cp -v {} "$RELEASES_DIR/$PLATFORM/" \;
        fi
        if [ -f "target/release/libretune-app.exe" ]; then
            cp -v target/release/libretune-app.exe "$RELEASES_DIR/$PLATFORM/"
        fi
        ;;
esac

# Create a summary file
VERSION=$(node -p "require('./package.json').version" 2>/dev/null || echo "unknown")
SUMMARY_FILE="$RELEASES_DIR/$PLATFORM/BUILD_INFO.txt"
cat > "$SUMMARY_FILE" <<EOF
LibreTune Release Build
=======================

Platform: $PLATFORM
Version: $VERSION
Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Build OS: $OS
Build Host: $(hostname)

Artifacts:
EOF

# List all artifacts with sizes
find "$RELEASES_DIR/$PLATFORM" -type f \( -name "*.deb" -o -name "*.AppImage" -o -name "*.dmg" -o -name "*.msi" -o -name "*.exe" -o -name "libretune-app" \) | while read file; do
    if [ -f "$file" ]; then
        SIZE=$(du -h "$file" | cut -f1)
        echo "  - $(basename "$file") ($SIZE)" >> "$SUMMARY_FILE"
    fi
done
# List .app bundles (directories)
find "$RELEASES_DIR/$PLATFORM" -type d -name "*.app" | while read file; do
    if [ -d "$file" ]; then
        SIZE=$(du -sh "$file" | cut -f1)
        echo "  - $(basename "$file") ($SIZE)" >> "$SUMMARY_FILE"
    fi
done

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo "Release artifacts are in: $RELEASES_DIR/$PLATFORM"
echo ""
echo "Built files:"
find "$RELEASES_DIR/$PLATFORM" -type f \( -name "*.deb" -o -name "*.AppImage" -o -name "*.dmg" -o -name "*.msi" -o -name "*.exe" -o -name "libretune-app" \) -exec ls -lh {} \; | awk '{print "  - " $9 " (" $5 ")"}'
find "$RELEASES_DIR/$PLATFORM" -type d -name "*.app" -exec du -sh {} \; | awk '{print "  - " $2 " (" $1 ")"}'
echo ""
echo "Build info saved to: $SUMMARY_FILE"

