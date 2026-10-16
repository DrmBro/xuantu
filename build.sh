#!/bin/bash
# 构建独立的 Apple Silicon 应用。无需联网或第三方依赖。
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${XT_BUILD_DIR:-$PROJECT_DIR/.build}"
APP_PATH="${1:-$BUILD_DIR/悬图.app}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
# 正在运行的应用不能原地重写，否则可能破坏进程的代码签名身份。
if [[ -f "$APP_PATH/Contents/MacOS/XuanTu" ]] && /usr/sbin/lsof -t "$APP_PATH/Contents/MacOS/XuanTu" >/dev/null 2>&1; then
  printf '目标应用正在运行，请先退出悬图，或选择另一个打包路径。\n' >&2
  exit 1
fi
mkdir -p "$BUILD_DIR" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
# 使用一套完整的 SDK 与 clang，不修改系统开发工具配置。
xcrun clang -isysroot "$SDK_PATH" -arch arm64 -mmacosx-version-min=14.0 \
  -fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-unused-parameter \
  -framework Cocoa -framework Carbon -framework ScreenCaptureKit \
  -framework UniformTypeIdentifiers -framework QuartzCore \
  "$PROJECT_DIR"/Sources/*.m -o "$APP_PATH/Contents/MacOS/XuanTu"
xcrun clang -isysroot "$SDK_PATH" -arch arm64 -mmacosx-version-min=14.0 \
  -fobjc-arc -O2 -framework Cocoa "$PROJECT_DIR/Resources/GenerateIcon.m" -o "$BUILD_DIR/GenerateIcon"
"$BUILD_DIR/GenerateIcon" "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
codesign --force --sign - "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"
printf '应用已生成：%s\n' "$APP_PATH"
