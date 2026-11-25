#!/usr/bin/env bash
# Memo4Me를 소스에서 빌드해 /Applications에 설치합니다.
# 사용법: ./scripts/install.sh [설치 폴더]   (기본: /Applications)
set -euo pipefail

APP_NAME="Memo4Me"
DEST_DIR="${1:-/Applications}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/install"

die() { echo "오류: $*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || die "macOS에서만 실행할 수 있습니다."
command -v xcodebuild >/dev/null || die "Xcode가 필요합니다. App Store에서 설치한 뒤 한 번 실행해 라이선스에 동의하세요."
command -v xcodegen >/dev/null || die "XcodeGen이 필요합니다: brew install xcodegen"

cd "$ROOT"

echo "==> Xcode 프로젝트 생성"
xcodegen generate

echo "==> Release 빌드"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  build

APP_SRC="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP_SRC" ]] || die "빌드 결과를 찾을 수 없습니다: $APP_SRC"

if pgrep -x "$APP_NAME" >/dev/null; then
  echo "==> 실행 중인 $APP_NAME 종료"
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  sleep 1
  pkill -x "$APP_NAME" 2>/dev/null || true
fi

echo "==> $DEST_DIR 에 설치"
mkdir -p "$DEST_DIR"
if ! { rm -rf "$DEST_DIR/$APP_NAME.app" && cp -R "$APP_SRC" "$DEST_DIR/"; } 2>/dev/null; then
  echo "    권한이 필요해 sudo로 다시 시도합니다."
  sudo rm -rf "$DEST_DIR/$APP_NAME.app"
  sudo cp -R "$APP_SRC" "$DEST_DIR/"
fi

echo "==> 완료: $DEST_DIR/$APP_NAME.app"
echo "    메뉴바 앱이라 독에는 나타나지 않습니다. Launchpad/Spotlight에서 실행하세요."
open "$DEST_DIR/$APP_NAME.app"
