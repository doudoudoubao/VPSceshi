#!/usr/bin/env bash
# ============================================================
# VPSceshi — VPS / 服务器一键全能测评（开发入口）
#
# 本文件用于从源码目录运行（会加载 lib/ 下的模块）。
# 单文件一键版请使用 dist/vpstest.sh，由 build.sh 生成。
# ============================================================

set -o pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="$_SELF_DIR/lib"

if [ ! -d "$_LIB_DIR" ]; then
  echo "[x] 未找到 lib/ 目录：$_LIB_DIR" >&2
  echo "    请在源码目录运行，或改用单文件版 dist/vpstest.sh" >&2
  exit 1
fi

for _f in "$_LIB_DIR"/*.sh; do
  # shellcheck disable=SC1090
  . "$_f" || { echo "[x] 加载模块失败: $_f" >&2; exit 1; }
done

main "$@"
