#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh
# 目的  : Mozc iOS ビルドの前提を整える。bazelisk と xcode-select の確認、
#         および固定 Mozc ソースと管理 patch の準備を行う。
# 期待出力: third_party/mozc/ に Mozc ソースが存在する状態。既存 checkout の SHA と patch も検証する。
# 失敗時 : 不足ツール名・原因を明示して非0で終了する。
# =============================================================================
set -euo pipefail

# --- 設定 -------------------------------------------------------------------
# Mozc の取得元と固定リビジョン。安定性のため特定コミットに固定する。
MOZC_REPO_URL="${MOZC_REPO_URL:-https://github.com/google/mozc.git}"
# リビジョンは scripts/mozc-revision.txt の SHA のみ。


# スクリプトの場所からプロジェクトルートを解決（呼び出し位置に依存しない）。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MOZC_DIR="${PROJECT_ROOT}/third_party/mozc"
export USE_BAZEL_VERSION="$(tr -d '[:space:]' < "${PROJECT_ROOT}/.bazelversion")"

echo "==> bootstrap 開始 (project root: ${PROJECT_ROOT})"

# --- 1. bazelisk の確認 -----------------------------------------------------
if ! command -v bazelisk >/dev/null 2>&1; then
  echo "ERROR: bazelisk が見つかりません。" >&2
  echo "  Mozc のビルドには bazelisk（bazel ラッパ）が必要です。" >&2
  echo "  導入例: brew install bazelisk" >&2
  exit 1
fi
echo "==> bazelisk: $(command -v bazelisk) ($(bazelisk version 2>/dev/null | head -n1 || echo 'version 取得失敗'))"

# --- 2. Xcode コマンドラインツールの確認 ------------------------------------
if ! command -v xcode-select >/dev/null 2>&1; then
  echo "ERROR: xcode-select が見つかりません。Xcode / Command Line Tools を導入してください。" >&2
  exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo "ERROR: Xcode のパスが設定されていません。" >&2
  echo "  例: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi
echo "==> Xcode developer dir: $(xcode-select -p)"

# --- 3. git の確認 ----------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git が見つかりません。" >&2
  exit 1
fi

# --- Pinned source: never substitute a different branch or overwrite local work. ---
MOZC_REVISION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/mozc-revision.txt")"
PATCH="${SCRIPT_DIR}/patches/mozc-ios-archive.patch"
if [ ! -d "${MOZC_DIR}/.git" ]; then
  if [ -e "${MOZC_DIR}" ]; then
    echo "ERROR: existing non-git Mozc directory; preserve it and choose a clean checkout" >&2; exit 1
  fi
  git clone --no-checkout "${MOZC_REPO_URL}" "${MOZC_DIR}"
  git -C "${MOZC_DIR}" checkout --detach "${MOZC_REVISION}"
fi
if [ "$(git -C "${MOZC_DIR}" rev-parse HEAD)" != "${MOZC_REVISION}" ]; then
  echo "ERROR: Mozc revision differs from scripts/mozc-revision.txt; local checkout left unchanged" >&2; exit 1
fi
if git -C "${MOZC_DIR}" apply --reverse --check "${PATCH}" 2>/dev/null; then
  echo "==> Versioned iOS archive patch already applied"
elif git -C "${MOZC_DIR}" apply --check "${PATCH}"; then
  git -C "${MOZC_DIR}" apply "${PATCH}"
else
  echo "ERROR: local Mozc changes conflict with the versioned patch; no files overwritten" >&2; exit 1
fi
echo "==> bootstrap 完了: ${MOZC_REVISION}"
