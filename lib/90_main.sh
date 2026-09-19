#!/usr/bin/env bash
# ============================================================
# 90_main.sh — 参数解析、主流程、报告落盘
# ============================================================

MASK_IP="${MASK_IP:-1}"

usage() {
  cat <<EOF
${VPSTEST_NAME} v${VPSTEST_VERSION} — VPS / 服务器一键全能测评

用法:
  bash vpstest.sh [选项]
  bash <(curl -sL ${VPSTEST_REPO}/raw/main/dist/vpstest.sh) [选项]

测试内容:
  系统硬件信息 · CPU/内存/磁盘性能 · IP 质量体检 · 流媒体与 AI 解锁
  三网延迟丢包 · 三网与国际测速 · 三网回程路由 · 综合评分

选项:
  -n, --name <名称>       报告标题使用的机器名（如 "DMIT HKG.AN5.EB.Tiny"）
  -o, --output <目录>     报告输出目录（默认 ./vpstest-result）
  -m, --only <模块,...>   只跑指定模块
  -s, --skip <模块,...>   跳过指定模块
      --fast              快速模式（缩短时长、减少节点）
      --full              完整模式（含 Geekbench，耗时最长）
      --speedtest <模式>  cn | global | all | off（默认 cn）
      --geekbench         启用 Geekbench 6 跑分（联网上传结果）
      --show-ip           报告中显示完整出口 IP（默认部分遮蔽）
      --no-color          关闭彩色输出
  -q, --quiet             安静模式，只输出最终结果路径
  -h, --help              显示本帮助
  -v, --version           显示版本

可用模块名:
  cpu memory disk ipquality unlock ping speedtest route

示例:
  # 全量测试
  bash vpstest.sh -n "DMIT HKG.AN5.EB.Tiny"
  # 只测解锁和 IP 质量
  bash vpstest.sh --only unlock,ipquality
  # 不跑测速（省流量）
  bash vpstest.sh --speedtest off
  # 国内 + 国际全测速
  bash vpstest.sh --speedtest all --full
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--name)      NODE_NAME="$2"; shift 2 ;;
      -o|--output)    OUT_DIR="$2"; shift 2 ;;
      -m|--only)      ONLY_MODULES="$2"; shift 2 ;;
      -s|--skip)      SKIP_MODULES="$2"; shift 2 ;;
      --fast)         FAST_MODE=1; shift ;;
      --full)         FAST_MODE=0; ENABLE_GEEKBENCH=1; SPEEDTEST_MODE="all"; shift ;;
      --speedtest)    SPEEDTEST_MODE="$2"; shift 2 ;;
      --geekbench)    ENABLE_GEEKBENCH=1; shift ;;
      --show-ip)      MASK_IP=0; shift ;;
      --no-color)     USE_COLOR=0; _c_init; shift ;;
      -q|--quiet)     QUIET=1; USE_COLOR=0; _c_init; shift ;;
      -h|--help)      usage; exit 0 ;;
      -v|--version)   printf '%s v%s\n' "$VPSTEST_NAME" "$VPSTEST_VERSION"; exit 0 ;;
      *)              log_err "未知参数: $1"; usage; exit 1 ;;
    esac
  done
  case "$SPEEDTEST_MODE" in
    cn|global|all|off) ;;
    *) log_err "--speedtest 仅支持 cn / global / all / off"; exit 1 ;;
  esac
}

banner() {
  [ "$QUIET" = "1" ] && return 0
  cat <<EOF
${C_B}${C_C}
 ╦  ╦╔═╗╔═╗  ╔╦╗╔═╗╔═╗╔╦╗
 ╚╗╔╝╠═╝╚═╗   ║ ║╣ ╚═╗ ║
  ╚╝ ╩  ╚═╝   ╩ ╚═╝╚═╝ ╩   ${C_RST}${C_DIM}v${VPSTEST_VERSION}${C_RST}
${C_DIM} 一键全能服务器测评 · 输出适配博客/论坛
 ${VPSTEST_REPO}${C_RST}

EOF
}

cleanup() {
  [ -n "$BIN_DIR" ] && [ -d "$BIN_DIR" ] && rm -rf "$BIN_DIR" 2>/dev/null
  [ -n "$DISK_WORKDIR" ] && rm -f "$DISK_WORKDIR/.vpstest_dd" "$DISK_WORKDIR/.vpstest_fio" 2>/dev/null
}

write_reports() {
  step "生成报告"
  mkdir -p "$OUT_DIR" 2>/dev/null || {
    log_err "无法创建输出目录: $OUT_DIR"; OUT_DIR="$(mktemp -d)"; log_warn "改用: $OUT_DIR"; }

  local stamp base
  stamp="$(date '+%Y%m%d-%H%M%S')"
  base="$OUT_DIR/report-$stamp"

  gen_markdown > "${base}.md"       2>/dev/null && log_ok "Markdown : ${base}.md"
  gen_bbcode   > "${base}.bbcode"   2>/dev/null && log_ok "BBCode   : ${base}.bbcode"
  gen_html     > "${base}.html"     2>/dev/null && log_ok "HTML     : ${base}.html"
  gen_json     > "${base}.json"     2>/dev/null && log_ok "JSON     : ${base}.json"
  gen_txt      > "${base}.txt"      2>/dev/null && log_ok "纯文本   : ${base}.txt"

  # 同时维护一份 latest.* 方便脚本化取用
  local ext
  for ext in md bbcode html json txt; do
    cp -f "${base}.${ext}" "$OUT_DIR/latest.${ext}" 2>/dev/null
  done

  kv_set meta.report_base "$base"
  REPORT_BASE="$base"
}

print_summary() {
  [ "$QUIET" = "1" ] && { printf '%s\n' "$REPORT_BASE"; return 0; }
  printf '\n%s%s══════════════ 测试完成 ══════════════%s\n' "$C_B" "$C_G" "$C_RST"
  printf '  机器      : %s\n' "$(kv_or meta.node_name "$(kv_get sys.cpu.model)")"
  printf '  出口      : %s | %s\n' "$(kv_get net.location)" "$(kv_or net.as 'N/A')"
  printf '  综合评分  : %s%s / 100 — %s%s\n' "$C_B" "$(kv_or score.total 'N/A')" "$(kv_or score.grade '')" "$C_RST"
  printf '  总耗时    : %s\n' "$(kv_or meta.duration 'N/A')"
  printf '\n  报告文件:\n'
  printf '    博客 Markdown : %s.md\n'     "$REPORT_BASE"
  printf '    论坛 BBCode   : %s.bbcode\n' "$REPORT_BASE"
  printf '    网页 HTML     : %s.html\n'   "$REPORT_BASE"
  printf '    数据 JSON     : %s.json\n'   "$REPORT_BASE"
  printf '    纯文本 TXT    : %s.txt\n'    "$REPORT_BASE"
  printf '\n  %s发论坛直接复制:%s cat %s.bbcode\n' "$C_C" "$C_RST" "$REPORT_BASE"
  printf '  %s发博客直接复制:%s cat %s.md\n\n'     "$C_C" "$C_RST" "$REPORT_BASE"
}

main() {
  parse_args "$@"
  banner

  if [ -z "$BASH_VERSION" ]; then
    log_err "请使用 bash 运行本脚本（当前不是 bash）"; exit 1
  fi
  case "$BASH_VERSION" in
    [123].*) log_err "需要 bash 4.0 及以上版本，当前 $BASH_VERSION"; exit 1 ;;
  esac

  trap cleanup EXIT INT TERM
  local t_start; t_start="$(date +%s)"

  setup_bin_dir
  install_deps
  collect_sysinfo
  [ -n "$NODE_NAME" ] && kv_set meta.node_name "$NODE_NAME"

  detect_ip
  test_cpu
  test_memory
  test_disk
  test_ipquality
  test_unlock
  test_ping
  test_speedtest
  test_route

  local dur=$(( $(date +%s) - t_start ))
  kv_set meta.duration "$((dur / 60)) 分 $((dur % 60)) 秒"

  calc_score
  write_reports
  print_summary
}
