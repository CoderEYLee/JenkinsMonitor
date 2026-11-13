#!/bin/bash
set -euo pipefail

# 将 Jenkins Monitor 归档并在桌面生成 JenkinsMonitor.dmg。
# 用法：在仓库根目录执行  ./export_dmg.sh

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/JenkinsMonitor/JenkinsMonitor.xcodeproj"
SCHEME="Jenkins Monitor"
APP_NAME="Jenkins Monitor.app"
VOLNAME="Jenkins Monitor"
DMG_PATH="${HOME}/Desktop/JenkinsMonitor.dmg"

if [[ ! -f "$PROJECT/project.pbxproj" ]]; then
  echo "找不到 Xcode 工程：$PROJECT" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/jenkins-monitor-dmg.XXXXXX")"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

ARCHIVE_PATH="$WORKDIR/JenkinsMonitor.xcarchive"
STAGE="$WORKDIR/stage"
mkdir -p "$STAGE"

echo "正在归档 $SCHEME …"
xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  archive

APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
if [[ ! -d "$APP" ]]; then
  echo "归档完成，但未找到 $APP_NAME" >&2
  exit 1
fi

cp -R "$APP" "$STAGE/"

echo "正在生成 $DMG_PATH …"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH"

# 路径用绿色输出，并加上 file:// 链接，方便在终端里点击打开。
FILE_URL="file://${DMG_PATH}"
printf '已生成：\033]8;;%s\033\\\033[32m%s\033[0m\033]8;;\033\\\n' "$FILE_URL" "$DMG_PATH"
