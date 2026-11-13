#!/bin/bash
set -euo pipefail

# 将 Jenkins Monitor 归档，并在桌面生成可拖拽安装的 JenkinsMonitor.dmg。
# 用法：在仓库根目录执行  ./export_dmg.sh

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/JenkinsMonitor/JenkinsMonitor.xcodeproj"
SCHEME="Jenkins Monitor"
APP_NAME="Jenkins Monitor.app"
VOLNAME="Jenkins Monitor"
DMG_PATH="${HOME}/Desktop/JenkinsMonitor.dmg"

# 窗口内容区尺寸；图标坐标以左上为原点，对准背景图上的箭头。
WIN_WIDTH=660
WIN_HEIGHT=500
TITLE_BAR=28
ICON_SIZE=128
ICON_X_APP=180
ICON_X_APPS=480
ICON_Y=290

if [[ ! -f "$PROJECT/project.pbxproj" ]]; then
  echo "找不到 Xcode 工程：$PROJECT" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/jenkins-monitor-dmg.XXXXXX")"
RW_DMG="$WORKDIR/rw.dmg"
DEVICE=""
VOLUME="/Volumes/$VOLNAME"

unmount_volume() {
  local target="${1:-}"
  [[ -z "$target" ]] && return 0
  local _i
  for _i in 1 2 3 4 5 6 7 8; do
    if hdiutil detach "$target" -quiet 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  hdiutil detach "$target" -force -quiet 2>/dev/null || true
}

cleanup() {
  if [[ -n "${DEVICE:-}" ]]; then
    unmount_volume "$DEVICE"
  fi
  if [[ -d "$VOLUME" ]]; then
    unmount_volume "$VOLUME"
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [[ -d "$VOLUME" ]]; then
  echo "已有同名磁盘镜像挂载，正在弹出…"
  unmount_volume "$VOLUME"
  local_i=0
  while [[ -d "$VOLUME" && $local_i -lt 15 ]]; do
    sleep 1
    local_i=$((local_i + 1))
  done
  if [[ -d "$VOLUME" ]]; then
    echo "无法弹出已挂载的「$VOLNAME」，请先在 Finder 中推出后再试。" >&2
    exit 1
  fi
fi

make_background() {
  local out="$1"
  local swift="$WORKDIR/make_dmg_background.swift"
  cat > "$swift" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count >= 8,
      let width = Double(CommandLine.arguments[2]),
      let height = Double(CommandLine.arguments[3]),
      let iconXApp = Double(CommandLine.arguments[4]),
      let iconXApps = Double(CommandLine.arguments[5]),
      let iconY = Double(CommandLine.arguments[6]),
      let _iconSize = Double(CommandLine.arguments[7])
else {
  fputs("usage: make_dmg_background.swift <out.png> <w> <h> <iconXApp> <iconXApps> <iconY> <iconSize>\n", stderr)
  exit(1)
}
let outPath = CommandLine.arguments[1]
let scale: CGFloat = 2
let pxW = Int((width * Double(scale)).rounded())
let pxH = Int((height * Double(scale)).rounded())

guard let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: pxW,
  pixelsHigh: pxH,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fputs("无法创建背景图位图\n", stderr)
  exit(1)
}
rep.size = NSSize(width: width, height: height)

guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
  fputs("无法创建绘图上下文\n", stderr)
  exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let gc = ctx.cgContext

// 翻转到左上原点，方便和 Finder 图标坐标对齐。
gc.translateBy(x: 0, y: height)
gc.scaleBy(x: 1, y: -1)

let colorSpace = CGColorSpaceCreateDeviceRGB()
let start = NSColor(calibratedRed: 0.957, green: 0.957, blue: 0.957, alpha: 1).cgColor
let end = NSColor(calibratedRed: 0.976, green: 0.976, blue: 0.976, alpha: 1).cgColor
if let gradient = CGGradient(colorsSpace: colorSpace, colors: [start, end] as CFArray, locations: [0, 1]) {
  gc.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: height), options: [])
}

func drawText(_ string: String, font: NSFont, color: NSColor, centerX: CGFloat, centerY: CGFloat) {
  let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: color
  ]
  let size = (string as NSString).size(withAttributes: attrs)
  let x = centerX - size.width / 2
  let y = centerY - size.height / 2
  gc.saveGState()
  gc.translateBy(x: x, y: y + size.height)
  gc.scaleBy(x: 1, y: -1)
  (string as NSString).draw(at: .zero, withAttributes: attrs)
  gc.restoreGState()
}

let titleFont = NSFont.systemFont(ofSize: 40, weight: .regular)
drawText(
  "Jenkins Monitor",
  font: titleFont,
  color: NSColor(calibratedWhite: 0.08, alpha: 1),
  centerX: width / 2,
  centerY: 92
)

let midX = (iconXApp + iconXApps) / 2
let arrowY = iconY
let arrowColor = NSColor(calibratedWhite: 0.22, alpha: 1)
gc.saveGState()
gc.setStrokeColor(arrowColor.cgColor)
gc.setLineWidth(2.4)
gc.setLineCap(.round)
gc.setLineJoin(.round)
let shaftLeft = midX - 28
let shaftRight = midX + 22
let head: CGFloat = 10
let path = CGMutablePath()
path.move(to: CGPoint(x: shaftLeft, y: arrowY))
path.addLine(to: CGPoint(x: shaftRight, y: arrowY))
path.move(to: CGPoint(x: shaftRight - head, y: arrowY - head))
path.addLine(to: CGPoint(x: shaftRight, y: arrowY))
path.addLine(to: CGPoint(x: shaftRight - head, y: arrowY + head))
gc.addPath(path)
gc.strokePath()
gc.restoreGState()

let captionFont = NSFont.systemFont(ofSize: 13, weight: .regular)
drawText(
  "拖动到文件夹以安装",
  font: captionFont,
  color: NSColor(calibratedWhite: 0.42, alpha: 1),
  centerX: midX,
  centerY: iconY + 34
)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
  fputs("无法编码背景图\n", stderr)
  exit(1)
}
do {
  try data.write(to: URL(fileURLWithPath: outPath))
} catch {
  fputs("无法写入 \(outPath): \(error)\n", stderr)
  exit(1)
}
SWIFT

  swift "$swift" "$out" "$WIN_WIDTH" "$WIN_HEIGHT" "$ICON_X_APP" "$ICON_X_APPS" "$ICON_Y" "$ICON_SIZE"
}

ARCHIVE_PATH="$WORKDIR/JenkinsMonitor.xcarchive"
STAGE="$WORKDIR/stage"
mkdir -p "$STAGE/.background"

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

echo "正在制作安装窗口背景…"
BG_PNG="$WORKDIR/background.png"
make_background "$BG_PNG"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$BG_PNG" "$STAGE/.background/background.png"

ICNS=""
if [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  ICNS="$APP/Contents/Resources/AppIcon.icns"
else
  ICNS="$(find "$APP/Contents/Resources" -name '*.icns' | head -1 || true)"
fi
if [[ -n "$ICNS" && -f "$ICNS" ]]; then
  cp "$ICNS" "$STAGE/.VolumeIcon.icns"
fi

echo "正在生成可写磁盘镜像…"
hdiutil create \
  -srcfolder "$STAGE" \
  -volname "$VOLNAME" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  "$RW_DMG" >/dev/null

# 预留空间，方便 Finder 写入窗口布局（.DS_Store）。
# 新版 hdiutil 的 -size 不再接受扇区单位 s，改用 -sectors。
MIN_SECTORS="$(hdiutil resize -limits "$RW_DMG" | awk 'END { print $1 }')"
hdiutil resize -sectors "$((MIN_SECTORS + 40000))" "$RW_DMG" >/dev/null

echo "正在设置图标布局…"
MOUNT_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
DEVICE="$(echo "$MOUNT_OUTPUT" | grep -F "$VOLUME" | awk '{print $1}')"
if [[ -z "$DEVICE" ]]; then
  echo "未能挂载临时磁盘镜像。" >&2
  echo "$MOUNT_OUTPUT" >&2
  exit 1
fi

for _i in $(seq 1 20); do
  if [[ -d "$VOLUME" ]]; then
    break
  fi
  sleep 0.5
done
if [[ ! -d "$VOLUME" ]]; then
  echo "挂载后未找到 $VOLUME" >&2
  exit 1
fi

if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "$VOLUME/.background" || true
  if [[ -f "$VOLUME/.VolumeIcon.icns" ]]; then
    SetFile -c icnC "$VOLUME/.VolumeIcon.icns" || true
    SetFile -a C "$VOLUME" || true
  fi
else
  chflags hidden "$VOLUME/.background" || true
fi

WIN_RIGHT=$((300 + WIN_WIDTH))
WIN_BOTTOM=$((160 + WIN_HEIGHT + TITLE_BAR))

if ! osascript - "$VOLNAME" "$APP_NAME" "$WIN_RIGHT" "$WIN_BOTTOM" "$ICON_SIZE" "$ICON_X_APP" "$ICON_Y" "$ICON_X_APPS" <<'APPLESCRIPT'
on run argv
  set volName to item 1 of argv
  set appName to item 2 of argv
  set winRight to item 3 of argv as integer
  set winBottom to item 4 of argv as integer
  set iconSize to item 5 of argv as integer
  set iconXApp to item 6 of argv as integer
  set iconY to item 7 of argv as integer
  set iconXApps to item 8 of argv as integer

  tell application "Finder"
    repeat 20 times
      if exists disk volName then exit repeat
      delay 0.5
    end repeat
    if not (exists disk volName) then error "找不到磁盘 «" & volName & "»"

    tell disk volName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set sidebar width of container window to 0
      set the bounds of container window to {300, 160, winRight, winBottom}
      set theViewOptions to the icon view options of container window
      set arrangement of theViewOptions to not arranged
      set icon size of theViewOptions to iconSize
      set text size of theViewOptions to 13
      set background picture of theViewOptions to file ".background:background.png"
      set position of item appName to {iconXApp, iconY}
      set position of item "Applications" to {iconXApps, iconY}
      try
        set extension hidden of item appName to true
      end try
      update without registering applications
      delay 1
      close
      open
      update without registering applications
      delay 2
      close
    end tell
  end tell
end run
APPLESCRIPT
then
  echo "设置窗口布局失败。若是第一次运行，请在系统弹出授权时允许终端控制「Finder」，然后重新执行本脚本。" >&2
  exit 1
fi

bless --folder "$VOLUME" --openfolder "$VOLUME" >/dev/null 2>&1 || true
sync
sleep 1
unmount_volume "$DEVICE"
DEVICE=""

for _i in $(seq 1 15); do
  if [[ ! -d "$VOLUME" ]]; then
    break
  fi
  sleep 1
  unmount_volume "$VOLUME"
done
if [[ -d "$VOLUME" ]]; then
  echo "无法推出临时磁盘镜像，请先在 Finder 中推出「$VOLNAME」后再试。" >&2
  exit 1
fi

if [[ -f "$DMG_PATH" ]]; then
  rm -f "$DMG_PATH"
fi

echo "正在生成 $DMG_PATH …"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

FILE_URL="file://${DMG_PATH}"
printf '已生成：\033]8;;%s\033\\\033[32m%s\033[0m\033]8;;\033\\\n' "$FILE_URL" "$DMG_PATH"
