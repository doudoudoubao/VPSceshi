#!/usr/bin/env bash
# ============================================================
# build.sh — 把 lib/ 下的模块打包成单文件 dist/vpstest.sh
#
#   ./build.sh          构建
#   ./build.sh --check  构建并做语法检查
# ============================================================

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SELF_DIR/lib"
OUT="$SELF_DIR/dist/vpstest.sh"

VERSION="$(grep -m1 '^VPSTEST_VERSION=' "$LIB_DIR/00_core.sh" | cut -d'"' -f2)"

mkdir -p "$SELF_DIR/dist"

{
  cat <<EOF
#!/usr/bin/env bash
# ============================================================
# VPSceshi v${VERSION} — VPS / 服务器一键全能测评（单文件版）
#
# 本文件由 build.sh 自动生成，请勿直接编辑。
# 源码与模块： https://github.com/doudoudoubao/VPSceshi
#
# 一键运行：
#   bash <(curl -sL https://github.com/doudoudoubao/VPSceshi/raw/main/dist/vpstest.sh)
#
# 生成时间： $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# ============================================================

set -o pipefail
EOF

  for f in "$LIB_DIR"/*.sh; do
    printf '\n# ===== %s =====\n' "$(basename "$f")"
    # 去掉每个模块开头的 shebang
    sed '1{/^#!/d;}' "$f"
  done

  printf '\n# ===== 入口 =====\nmain "$@"\n'
} > "$OUT"

chmod +x "$OUT"

echo "[+] 已生成: $OUT"
echo "[+] 版本:   v${VERSION}"
echo "[+] 行数:   $(wc -l < "$OUT")"
echo "[+] 大小:   $(du -h "$OUT" | cut -f1)"

if [ "${1:-}" = "--check" ]; then
  echo "[*] 语法检查 ..."
  bash -n "$OUT" && echo "[+] dist/vpstest.sh 语法 OK"
  bash -n "$SELF_DIR/vpstest.sh" && echo "[+] vpstest.sh 语法 OK"
  for f in "$LIB_DIR"/*.sh; do
    bash -n "$f" || { echo "[x] 语法错误: $f"; exit 1; }
  done
  echo "[+] 所有模块语法 OK"
  if command -v shellcheck >/dev/null 2>&1; then
    echo "[*] shellcheck ..."
    shellcheck -S warning -e SC1090,SC1091,SC2086,SC2181 "$OUT" || true
  fi
fi
