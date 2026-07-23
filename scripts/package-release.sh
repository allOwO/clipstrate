#!/usr/bin/env bash

set -euo pipefail

TAG="${1:-}"
OUTPUT_DIR="${2:-}"
BUILD_NUMBER="${3:-1}"

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "用法：$0 v主版本.次版本.修订号 [输出目录] [构建号]" >&2
  echo "示例：$0 v0.1.0 dist 1" >&2
  exit 2
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "构建号必须是正整数：$BUILD_NUMBER" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${TAG#v}"
OUTPUT_DIR="${OUTPUT_DIR:-"$ROOT_DIR/dist"}"

for tool in xcodegen xcodebuild codesign ditto hdiutil plutil shasum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "缺少构建工具：$tool" >&2
    exit 3
  fi
done

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/clipstrate-release.XXXXXX")"
cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

DERIVED_DATA="$WORK_ROOT/DerivedData"
DMG_ROOT="$WORK_ROOT/dmg-root"
APP_NAME="Clipstrate.app"
ARCHIVE_BASENAME="Clipstrate-${VERSION}-macOS-arm64"
ZIP_PATH="$OUTPUT_DIR/${ARCHIVE_BASENAME}.zip"
DMG_PATH="$OUTPUT_DIR/${ARCHIVE_BASENAME}.dmg"
CHECKSUM_PATH="$OUTPUT_DIR/${ARCHIVE_BASENAME}.sha256"

mkdir -p "$OUTPUT_DIR" "$DMG_ROOT"
rm -f "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"

cd "$ROOT_DIR"
xcodegen generate
xcodebuild \
  -project Clipstrate.xcodeproj \
  -scheme Clipstrate \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "构建完成但未找到 App：$APP_PATH" >&2
  exit 4
fi

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")"
ACTUAL_BUILD="$(plutil -extract CFBundleVersion raw "$APP_PATH/Contents/Info.plist")"
if [[ "$ACTUAL_VERSION" != "$VERSION" || "$ACTUAL_BUILD" != "$BUILD_NUMBER" ]]; then
  echo "版本写入失败：期望 $VERSION ($BUILD_NUMBER)，实际 $ACTUAL_VERSION ($ACTUAL_BUILD)" >&2
  exit 5
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
ditto "$APP_PATH" "$DMG_ROOT/$APP_NAME"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "Clipstrate" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")" \
    > "$(basename "$CHECKSUM_PATH")"
)

echo "发布产物已生成："
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
