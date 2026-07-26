#!/usr/bin/env bash
# =============================================================================
# build_app.sh
# 目的  : xcodebuild で MozcFlickKeyboard アプリをビルドするラッパ。
# 期待出力: シミュレータ向けビルド成功（既定）。build/ に成果物。
# 失敗時 : プロジェクト不在 / スキーム不在 / xcodebuild エラーを明示する。
# 使い方  : ./build_app.sh [scheme] [destination]
#           例: ./build_app.sh MozcFlickKeyboard "platform=iOS Simulator,name=iPhone 16"
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SCHEME="${1:-MozcFlickKeyboard}"
DESTINATION="${2:-platform=iOS Simulator,name=iPhone 16}"
XCODEPROJ="${PROJECT_ROOT}/MozcFlickKeyboard.xcodeproj"
DERIVED_DATA="${PROJECT_ROOT}/build"

echo "==> build_app 開始 (scheme: ${SCHEME})"

# --- 前提チェック -----------------------------------------------------------
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: xcodebuild が見つかりません。Xcode を導入してください。" >&2
  exit 1
fi

if [ ! -d "${XCODEPROJ}" ]; then
  echo "ERROR: Xcode プロジェクトが見つかりません: ${XCODEPROJ}" >&2
  echo "  先に scripts/generate_xcode_project.sh を実行してください。" >&2
  exit 1
fi

# --- ビルド -----------------------------------------------------------------
echo "==> xcodebuild 実行 (destination: ${DESTINATION})"
set +e
xcodebuild \
  -project "${XCODEPROJ}" \
  -scheme "${SCHEME}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  build
BUILD_RC=$?
set -e

if [ ${BUILD_RC} -ne 0 ]; then
  echo "ERROR: xcodebuild に失敗しました (rc=${BUILD_RC})。" >&2
  echo "  スキーム名 / destination / 署名設定 を確認してください。" >&2
  echo "  利用可能なスキームは以下で確認できます:" >&2
  echo "    xcodebuild -project ${XCODEPROJ} -list" >&2
  exit ${BUILD_RC}
fi

echo "==> build_app 完了。成果物: ${DERIVED_DATA}"
