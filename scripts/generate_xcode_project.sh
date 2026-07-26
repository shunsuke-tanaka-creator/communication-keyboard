#!/usr/bin/env bash
# =============================================================================
# generate_xcode_project.sh
# 目的  : XcodeGen を用いて project.yml から Xcode プロジェクトを生成する。
# 期待出力: プロジェクトルートに MozcFlickKeyboard.xcodeproj。
# 失敗時 : XcodeGen 未導入なら導入方法を案内、project.yml 不在なら明示する。
# 備考  : project.yml はメインエージェントが用意する。本スクリプトは
#         xcodegen 呼び出しの薄いラッパ。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_YML="${PROJECT_ROOT}/project.yml"

echo "==> generate_xcode_project 開始 (root: ${PROJECT_ROOT})"

# --- XcodeGen の確認 --------------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen が見つかりません。" >&2
  echo "  導入方法:" >&2
  echo "    brew install xcodegen" >&2
  echo "  もしくは https://github.com/yonaskolb/XcodeGen を参照してください。" >&2
  exit 1
fi
echo "==> xcodegen: $(command -v xcodegen) ($(xcodegen --version 2>/dev/null || echo 'version 取得失敗'))"

# --- project.yml の確認 -----------------------------------------------------
if [ ! -f "${PROJECT_YML}" ]; then
  echo "ERROR: project.yml が見つかりません: ${PROJECT_YML}" >&2
  echo "  メインエージェントが用意する project.yml を配置してから再実行してください。" >&2
  exit 1
fi

# --- 生成 -------------------------------------------------------------------
echo "==> project.yml から Xcode プロジェクトを生成します。"
( cd "${PROJECT_ROOT}" && xcodegen generate --spec "${PROJECT_YML}" )

echo "==> 生成完了。次は scripts/build_app.sh でビルドできます。"
