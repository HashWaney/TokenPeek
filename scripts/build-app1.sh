
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/TokenPeek.app"

ICON_SOURCE="$ROOT_DIR/Resources/TokenPeek.icns"
PLIST_SOURCE="$ROOT_DIR/Resources/Info.plist"
PLIST_DEST="$APP_DIR/Contents/Info.plist"

# 1. 检查必要资源
if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Error: missing application icon: $ICON_SOURCE" >&2
    exit 1
fi

if [[ ! -f "$PLIST_SOURCE" ]]; then
    echo "Error: missing Info.plist: $PLIST_SOURCE" >&2
    exit 1
fi

# 2. 构建 Swift Release
cd "$ROOT_DIR"

mkdir -p \
    "$ROOT_DIR/.build/swiftpm-cache" \
    "$ROOT_DIR/.build/clang-cache"

CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/clang-cache" \
swift build -c release \
    --disable-sandbox \
    --cache-path "$ROOT_DIR/.build/swiftpm-cache"

# 3. 创建 macOS App Bundle
mkdir -p \
    "$APP_DIR/Contents/MacOS" \
    "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/TokenPeek" \
   "$APP_DIR/Contents/MacOS/TokenPeek"

cp "$PLIST_SOURCE" "$PLIST_DEST"

# 4. 复制应用图标
cp "$ICON_SOURCE" \
   "$APP_DIR/Contents/Resources/TokenPeek.icns"

# 5. 配置 Info.plist 图标属性
if /usr/libexec/PlistBuddy \
    -c "Print :CFBundleIconFile" \
    "$PLIST_DEST" >/dev/null 2>&1; then

    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleIconFile TokenPeek.icns" \
        "$PLIST_DEST"
else
    /usr/libexec/PlistBuddy \
        -c "Add :CFBundleIconFile string TokenPeek.icns" \
        "$PLIST_DEST"
fi

# 6. 代码签名
codesign --force --deep --sign - "$APP_DIR"

echo "Built app: $APP_DIR"
echo "App icon: $APP_DIR/Contents/Resources/TokenPeek.icns"
