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
OBJECT_DIR="$(mktemp -d "$BUILD_DIR/objects.XXXXXX")"
OBJECT_DIR="$(cd "$OBJECT_DIR" && pwd)"
trap 'rm -rf "$OBJECT_DIR"' EXIT
# 部分 Command Line Tools 升级后同时残留两份 SwiftBridging 模块定义。
# 仅在本次编译的虚拟文件系统中屏蔽旧定义，不修改系统工具链文件。
SWIFT_BUILD_FLAGS=()
SWIFT_INCLUDE_DIR="$(cd "$(dirname "$(xcrun --find swiftc)")/../include/swift" && pwd)"
if [[ -f "$SWIFT_INCLUDE_DIR/module.modulemap" && -f "$SWIFT_INCLUDE_DIR/bridging.modulemap" ]] \
  && /usr/bin/grep -q '^module SwiftBridging {' "$SWIFT_INCLUDE_DIR/module.modulemap" \
  && /usr/bin/grep -q '^module SwiftBridging {' "$SWIFT_INCLUDE_DIR/bridging.modulemap"; then
  printf '// 本次构建屏蔽旧版重复模块定义。\n' > "$OBJECT_DIR/empty.modulemap"
  JSON_SWIFT_INCLUDE_DIR="$(printf '%s' "$SWIFT_INCLUDE_DIR" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  JSON_OBJECT_DIR="$(printf '%s' "$OBJECT_DIR" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"version":0,"case-sensitive":false,"use-external-names":false,"roots":[{"type":"file","name":"%s/module.modulemap","external-contents":"%s/empty.modulemap"}]}\n' \
    "$JSON_SWIFT_INCLUDE_DIR" "$JSON_OBJECT_DIR" > "$OBJECT_DIR/swift-vfs-overlay.json"
  SWIFT_BUILD_FLAGS=(-vfsoverlay "$OBJECT_DIR/swift-vfs-overlay.json")
fi
# VisionKit 的文字选择接口由 Swift 桥接，生成供 Objective-C 导入的头文件。
xcrun swiftc -sdk "$SDK_PATH" -target arm64-apple-macosx14.0 -O \
  "${SWIFT_BUILD_FLAGS[@]}" \
  -parse-as-library -module-name XuanTuText -emit-object \
  -emit-objc-header -emit-objc-header-path "$OBJECT_DIR/XuanTuText-Swift.h" \
  "$PROJECT_DIR/Sources/XTTextSelection.swift" -o "$OBJECT_DIR/XTTextSelection.o"
for SOURCE in "$PROJECT_DIR"/Sources/*.m; do
  OBJECT_NAME="$(basename "$SOURCE" .m)"
  xcrun clang -isysroot "$SDK_PATH" -arch arm64 -mmacosx-version-min=14.0 \
    -fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-unused-parameter \
    -I "$OBJECT_DIR" -c "$SOURCE" -o "$OBJECT_DIR/$OBJECT_NAME.o"
done
# 交由 Swift 驱动链接，以包含桥接代码需要的系统 Swift 运行时。
xcrun swiftc -sdk "$SDK_PATH" -target arm64-apple-macosx14.0 \
  -framework Cocoa -framework Carbon -framework ScreenCaptureKit \
  -framework UniformTypeIdentifiers -framework QuartzCore -framework VisionKit \
  -Xlinker -rpath -Xlinker /usr/lib/swift \
  "$OBJECT_DIR"/*.o -o "$APP_PATH/Contents/MacOS/XuanTu"
xcrun clang -isysroot "$SDK_PATH" -arch arm64 -mmacosx-version-min=14.0 \
  -fobjc-arc -O2 -framework Cocoa "$PROJECT_DIR/Resources/GenerateIcon.m" -o "$BUILD_DIR/GenerateIcon"
"$BUILD_DIR/GenerateIcon" "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
codesign --force --sign - "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"
printf '应用已生成：%s\n' "$APP_PATH"
