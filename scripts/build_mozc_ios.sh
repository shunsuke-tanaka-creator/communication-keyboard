#!/usr/bin/env bash
# =============================================================================
# build_mozc_ios.sh
# 目的  : Mozc を iOS (arm64) 向けに Bazel(bazelisk) でクロスビルドし、
#         静的ライブラリ / XCFramework を out/ に生成する。
# 期待出力: out/mozc/ 以下にビルド成果物（.a もしくは .xcframework）。
# 失敗時 : どの前提が欠けているか・どのビルドステップで失敗したかを明示する。
# 注意  : Mozc の iOS ビルドは非常に重く、環境依存で失敗しやすい。
#         本スクリプトは「正しいコマンド列」と「前提チェック」を重視する
#         ベストエフォート実装。長時間ビルドはメイン側で別途実行する想定。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MOZC_DIR="${PROJECT_ROOT}/third_party/mozc"
# Mozc のリポジトリはビルド定義が src/ 配下にあることが多い。
MOZC_SRC_DIR="${MOZC_DIR}/src"
OUT_DIR="${PROJECT_ROOT}/out/mozc"

# iOS ビルド設定
IOS_ARCH="${IOS_ARCH:-arm64}"
IOS_MIN_VERSION="${IOS_MIN_VERSION:-15.0}"

echo "==> build_mozc_ios 開始 (arch: ${IOS_ARCH}, min iOS: ${IOS_MIN_VERSION})"

# --- 前提チェック -----------------------------------------------------------
if ! command -v bazelisk >/dev/null 2>&1; then
  echo "ERROR: bazelisk が見つかりません。先に scripts/bootstrap.sh を実行してください。" >&2
  exit 1
fi

if [ ! -d "${MOZC_DIR}/.git" ]; then
  echo "ERROR: Mozc ソースがありません: ${MOZC_DIR}" >&2
  echo "  先に scripts/bootstrap.sh を実行して Mozc を取得してください。" >&2
  exit 1
fi

# Mozc のビルドは src/ に WORKSPACE / MODULE.bazel を持つことが多い。無ければルートを使う。
BUILD_ROOT="${MOZC_SRC_DIR}"
if [ ! -d "${MOZC_SRC_DIR}" ]; then
  BUILD_ROOT="${MOZC_DIR}"
fi
if [ ! -e "${BUILD_ROOT}/WORKSPACE" ] && [ ! -e "${BUILD_ROOT}/WORKSPACE.bazel" ] && [ ! -e "${BUILD_ROOT}/MODULE.bazel" ]; then
  echo "ERROR: Bazel の WORKSPACE/MODULE.bazel が ${BUILD_ROOT} に見つかりません。" >&2
  echo "  Mozc のディレクトリ構成が想定と異なります。third_party/mozc を確認してください。" >&2
  exit 1
fi
echo "==> Bazel build root: ${BUILD_ROOT}"

mkdir -p "${OUT_DIR}"

# --- Bazel ビルド -----------------------------------------------------------
# iOS 向けクロスコンパイル用の Mozc 集約ターゲット。
# //ios:mozc_ios_combined は ios_engine とその推移的依存(engine/session/protobuf/absl 等)を
# 1 本の静的ライブラリ(*_lipo.a)にまとめる apple_static_library（third_party/mozc/src/ios/BUILD.bazel に追加済み）。
MOZC_BAZEL_TARGET="${MOZC_BAZEL_TARGET:-//ios:mozc_ios_combined}"

# iOS 向けビルドフラグ（検証済み 2026-07-14, tag 2.32.5994.102 / Bazel 8.4.1）。
# 注意: --config=oss_macos は TARGET=oss_macos を強制し mac 専用コード(Cocoa)を引くため使えない。
#       macos_env(コンパイラ設定のみ) + TARGET=ios が正解。apple_static_library はアーキを --ios_multi_cpus で受ける。
BAZEL_FLAGS=(
  "--config=macos_env"
  "--define" "TARGET=ios"
  "--ios_multi_cpus=${IOS_ARCH}"
  "--ios_minimum_os=${IOS_MIN_VERSION}"
)

echo "==> Bazel ターゲット: ${MOZC_BAZEL_TARGET}"
echo "==> Bazel フラグ: ${BAZEL_FLAGS[*]}"
echo "==> 注意: 初回ビルドは依存取得を含み数十分〜数時間かかる場合があります。"

# 実際のビルド実行。失敗しても原因が分かるよう終了コードを捕捉する。
set +e
( cd "${BUILD_ROOT}" && bazelisk build "${BAZEL_FLAGS[@]}" "${MOZC_BAZEL_TARGET}" )
BUILD_RC=$?
set -e

if [ ${BUILD_RC} -ne 0 ]; then
  echo "ERROR: Mozc の Bazel ビルドに失敗しました (rc=${BUILD_RC})。" >&2
  echo "  よくある原因:" >&2
  echo "   - ターゲット名が Mozc のバージョンと不一致 → 環境変数 MOZC_BAZEL_TARGET で指定" >&2
  echo "   - iOS toolchain / Xcode の設定不足 → xcode-select -p を確認" >&2
  echo "   - Bazel の config 名変更（--config=oss_macos 等） → Mozc の docs/build を参照" >&2
  echo "  現在の BUILD_ROOT: ${BUILD_ROOT}" >&2
  exit ${BUILD_RC}
fi

# 追加: OSS 辞書データ(mozc.data)をホスト側でビルドする。
# 辞書はデータコンパイラ(ホスト実行)の成果物なので iOS 向けフラグ不要。--config=oss_macos で生成する。
# IosEngine(data_file_path) にこのファイルパスを渡して初期化する。
echo "==> OSS 辞書データ //data_manager/oss:mozc.data をビルドします。"
set +e
( cd "${BUILD_ROOT}" && bazelisk build --config=oss_macos //data_manager/oss:mozc.data )
DATA_RC=$?
set -e
if [ ${DATA_RC} -ne 0 ]; then
  echo "WARN: 辞書データのビルドに失敗しました (rc=${DATA_RC})。" >&2
fi

# --- 成果物の収集 -----------------------------------------------------------
# apple_static_library は <name>_lipo.a を出力する。これを 1 本の Mozc iOS ライブラリとして収集する。
BAZEL_BIN="${BUILD_ROOT}/bazel-bin"
COMBINED_LIB="${BAZEL_BIN}/ios/mozc_ios_combined_lipo.a"
if [ -e "${COMBINED_LIB}" ]; then
  echo "==> 集約静的ライブラリを ${OUT_DIR}/libmozc_ios.a に収集します。"
  cp -Lf "${COMBINED_LIB}" "${OUT_DIR}/libmozc_ios.a"
  # ブリッジから使うヘッダを収集する。
  # MozcEngineBridge.mm は ios/ios_engine.h -> protocol/*.pb.h -> google/protobuf/*, absl/* と
  # 推移的に include するため、それらを 1 本のヘッダ検索パス out/mozc/include にまとめて収集する。
  INC_DIR="${OUT_DIR}/include"
  mkdir -p "${INC_DIR}/ios" "${INC_DIR}/protocol"
  cp -f "${MOZC_SRC_DIR}/ios/ios_engine.h" "${INC_DIR}/ios/" 2>/dev/null || true
  # 生成 protobuf ヘッダ(*.pb.h)は bazel-bin/protocol にある。
  cp -f "${BAZEL_BIN}/protocol/"*.pb.h "${INC_DIR}/protocol/" 2>/dev/null || true
  # absl / protobuf のヘッダ(.h/.inc)を外部リポジトリからツリーごと収集（ヘッダのみ）。
  ABSL_SRC="${BUILD_ROOT}/bazel-src/external/abseil-cpp+"
  PROTO_SRC="${BUILD_ROOT}/bazel-src/external/protobuf+/src"
  if [ -d "${ABSL_SRC}/absl" ]; then
    ( cd "${ABSL_SRC}" && rsync -aR --include='*/' --include='*.h' --include='*.inc' --exclude='*' absl "${INC_DIR}/" )
  fi
  if [ -d "${PROTO_SRC}/google" ]; then
    ( cd "${PROTO_SRC}" && rsync -aR --include='*/' --include='*.h' --include='*.inc' --exclude='*' google "${INC_DIR}/" )
  fi
  echo "==> 収集完了: ${OUT_DIR}/libmozc_ios.a ($(ls -lh "${OUT_DIR}/libmozc_ios.a" | awk '{print $5}')) / headers $(du -sh "${INC_DIR}" | awk '{print $1}')"
else
  echo "WARN: 集約ライブラリが見つかりません: ${COMBINED_LIB}" >&2
fi

# 追加: 辞書データ(mozc.data)を収集。アプリ(Extension)バンドルに同梱して IosEngine に渡す。
MOZC_DATA="${BAZEL_BIN}/data_manager/oss/mozc.data"
if [ -e "${MOZC_DATA}" ]; then
  cp -Lf "${MOZC_DATA}" "${OUT_DIR}/mozc.data"
  echo "==> 辞書データ収集完了: ${OUT_DIR}/mozc.data ($(ls -lh "${OUT_DIR}/mozc.data" | awk '{print $5}'))"
else
  echo "WARN: 辞書データが見つかりません: ${MOZC_DATA}" >&2
fi

echo "==> build_mozc_ios 完了。成果物: ${OUT_DIR}"
echo "    ここで生成した .a / .xcframework を Xcode プロジェクトにリンクし、"
echo "    MOZC_AVAILABLE を定義すると MozcEngineBridge が実 API 経路を使います。"
