#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh
# 目的  : Mozc iOS ビルドの前提を整える。bazelisk と xcode-select の確認、
#         および Mozc ソースの取得（shallow clone）を行う。
# 期待出力: third_party/mozc/ に Mozc ソースが存在する状態。冪等（既にあれば skip）。
# 失敗時 : 不足ツール名・原因を明示して非0で終了する。
# =============================================================================
set -euo pipefail

# --- 設定 -------------------------------------------------------------------
# Mozc の取得元と固定リビジョン。安定性のため特定コミットに固定する。
# （実際のビルド時はメインエージェントが必要に応じて更新する）
MOZC_REPO_URL="${MOZC_REPO_URL:-https://github.com/google/mozc.git}"
# 固定したいリビジョン（タグ/ブランチ/コミット）。空なら既定ブランチの最新。
MOZC_REVISION="${MOZC_REVISION:-master}"

# スクリプトの場所からプロジェクトルートを解決（呼び出し位置に依存しない）。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MOZC_DIR="${PROJECT_ROOT}/third_party/mozc"

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

# --- 4. Mozc ソースの取得（冪等 / shallow clone） ---------------------------
if [ -d "${MOZC_DIR}/.git" ]; then
  echo "==> Mozc ソースは既に存在します。clone をスキップ: ${MOZC_DIR}"
else
  echo "==> Mozc を shallow clone します: ${MOZC_REPO_URL} (rev: ${MOZC_REVISION})"
  mkdir -p "$(dirname "${MOZC_DIR}")"
  # --depth 1 で軽量に取得。特定リビジョンはブランチ/タグ指定で取得を試みる。
  if ! git clone --depth 1 --branch "${MOZC_REVISION}" "${MOZC_REPO_URL}" "${MOZC_DIR}" 2>/dev/null; then
    echo "WARN: branch/tag '${MOZC_REVISION}' での shallow clone に失敗。既定ブランチで再試行します。" >&2
    if ! git clone --depth 1 "${MOZC_REPO_URL}" "${MOZC_DIR}"; then
      echo "ERROR: Mozc の clone に失敗しました。ネットワーク / URL / リビジョンを確認してください。" >&2
      echo "  URL: ${MOZC_REPO_URL}" >&2
      echo "  REV: ${MOZC_REVISION}" >&2
      exit 1
    fi
  fi
  echo "==> Mozc の取得完了: ${MOZC_DIR}"
fi

echo "==> bootstrap 完了。次は scripts/build_mozc_ios.sh を実行してください。"
