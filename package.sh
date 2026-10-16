#!/bin/bash
# 构建拖拽安装磁盘镜像，默认输出到 README 使用的 downloads 目录。
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${XT_BUILD_DIR:-$PROJECT_DIR/.build}"
DMG_PATH="${1:-$PROJECT_DIR/downloads/XuanTu-arm64.dmg}"
mkdir -p "$BUILD_DIR" "$(dirname "$DMG_PATH")"
PACKAGE_DIR="$(mktemp -d "$BUILD_DIR/package.XXXXXX")"
trap 'rm -rf "$PACKAGE_DIR"' EXIT
XT_BUILD_DIR="$BUILD_DIR" bash "$PROJECT_DIR/build.sh" "$PACKAGE_DIR/悬图.app"
cp "$PROJECT_DIR/LICENSE" "$PACKAGE_DIR/LICENSE"
ln -s /Applications "$PACKAGE_DIR/Applications"
hdiutil create -volname '悬图' -srcfolder "$PACKAGE_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"
printf '安装包已生成：%s\n' "$DMG_PATH"
