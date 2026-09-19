#!/usr/bin/env bash
# ============================================================
# 64_mtr.sh — 回程 MTR：丢包与抖动
#
# 去程 MTR 需要国内探针（见 63_inbound.sh），这里测的是
# VPS → 国内方向的逐跳丢包 / 延迟 / 抖动。
# ============================================================

_mtr_targets() {
  cat <<'EOF'
广州电信|58.60.188.222
上海联通|210.22.97.1
上海移动|211.136.112.200
EOF
}

# 解析 mtr --report 输出的末跳汇总
# 返回 "丢包%|平均ms|最优ms|最差ms|抖动ms|跳数"
_mtr_parse() {
  local out="$1"
  local last hops
  # 取最后一条有效数据行（目标主机那一跳）
  last="$(printf '%s' "$out" | grep -E '^[[:space:]]*[0-9]+\.\|--' | tail -1)"
  [ -z "$last" ] && last="$(printf '%s' "$out" | tail -1)"
  hops="$(printf '%s' "$out" | grep -cE '^[[:space:]]*[0-9]+\.\|--')"
  # mtr --report 列：Host Loss% Snt Last Avg Best Wrst StDev
  local loss avg best wrst stdev
  loss="$(printf  '%s' "$last" | awk '{print $(NF-6)}' | tr -d '%')"
  avg="$(printf   '%s' "$last" | awk '{print $(NF-3)}')"
  best="$(printf  '%s' "$last" | awk '{print $(NF-2)}')"
  wrst="$(printf  '%s' "$last" | awk '{print $(NF-1)}')"
  stdev="$(printf '%s' "$last" | awk '{print $NF}')"
  case "$loss$avg" in ''|*[!0-9.]*) return 1 ;; esac
  printf '%s|%s|%s|%s|%s|%s' "$loss" "$avg" "$best" "$wrst" "$stdev" "$hops"
}

test_mtr() {
  module_enabled mtr || { log_info "跳过 MTR 测试"
    skip_note "$SKIP_REASON_OPT" mtr_out; return 0; }
  step "回程 MTR（丢包 / 抖动）"

  if ! have mtr; then
    ensure_cmd mtr >/dev/null 2>&1 || true
  fi
  if ! have mtr; then
    na_set mtr_out "系统未安装 mtr 且自动安装失败，回程丢包/抖动未评估"
    log_warn "未安装 mtr，跳过"
    return 0
  fi

  local label ip out res n=0
  while IFS='|' read -r label ip; do
    [ -z "$label" ] && continue
    n=$((n + 1))
    [ "$FAST_MODE" = "1" ] && [ "$n" -gt 1 ] && break
    inline "$label ($ip) ..."
    out="$(run_to 60 mtr --report --report-cycles=5 -n "$ip" 2>/dev/null)"
    if [ -z "$out" ]; then
      inline_done "失败"
      row_add mtr_out "$label" "$ip" "N/A" "N/A" "N/A" "N/A"
      continue
    fi
    res="$(_mtr_parse "$out")"
    if [ -n "$res" ]; then
      local loss avg best wrst stdev hops
      IFS='|' read -r loss avg best wrst stdev hops <<< "$res"
      inline_done "丢包 ${loss}% 平均 ${avg}ms 抖动 ${stdev}ms"
      row_add mtr_out "$label" "$ip" "${loss}%" "${avg} ms" "${best} / ${wrst} ms" "${stdev} ms"
      raw_add "回程 MTR · $label ($ip)" "$out"
    else
      inline_done "解析失败"
      row_add mtr_out "$label" "$ip" "N/A" "N/A" "N/A" "N/A"
      raw_add "回程 MTR · $label ($ip)" "$out"
    fi
  done <<< "$(_mtr_targets)"

  rows_have mtr_out || na_set mtr_out "本次未取得有效回程 MTR 数据"
}
