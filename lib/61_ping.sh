#!/usr/bin/env bash
# ============================================================
# 61_ping.sh — 三网及全球节点延迟 / 丢包
# ============================================================

# 目标表：显示名|IP|分组
_ping_targets_cn() {
  cat <<'EOF'
北京电信|219.141.136.12|电信
上海电信|202.96.209.133|电信
广州电信|58.60.188.222|电信
北京联通|202.106.50.1|联通
上海联通|210.22.97.1|联通
广州联通|210.21.196.6|联通
北京移动|221.179.155.161|移动
上海移动|211.136.112.200|移动
广州移动|120.196.165.24|移动
北京教育网|101.6.15.130|教育网
EOF
}

_ping_targets_global() {
  cat <<'EOF'
香港 HKIX|123.255.90.1|亚太
日本 东京|210.130.0.1|亚太
新加坡|165.21.83.88|亚太
韩国 首尔|168.126.63.1|亚太
台湾 台北|168.95.1.1|亚太
美国 洛杉矶|4.2.2.1|美洲
德国 法兰克福|194.25.0.60|欧洲
EOF
}

# _ping_one <ip> -> "avg|loss"
_ping_one() {
  local ip="$1" cnt="${2:-5}" out avg loss
  out="$(run_to $((cnt + 6)) ping -c "$cnt" -W 1 -i 0.25 "$ip" 2>/dev/null)"
  [ -z "$out" ] && out="$(run_to $((cnt + 6)) ping -c "$cnt" -W 1 "$ip" 2>/dev/null)"
  [ -z "$out" ] && return 1
  loss="$(printf '%s' "$out" | grep -oE '[0-9.]+% packet loss' | grep -oE '^[0-9.]+')"
  avg="$(printf '%s' "$out" | grep -E 'min/avg|round-trip' | awk -F'/' '{print $5}')"
  [ -z "$avg" ] && avg="$(printf '%s' "$out" | grep -oE 'time=[0-9.]+' | tail -1 | cut -d= -f2)"
  printf '%s|%s' "${avg:-}" "${loss:-100}"
}

# 结果通过全局变量返回：进度是打在 stdout 上的，
# 用 $(...) 捕获返回值会把进度一起吞进去。
PING_AVG=""
_run_ping_list() {
  local table="$1" list="$2"
  local label ip grp res avg loss sum=0 n=0
  PING_AVG=""
  while IFS='|' read -r label ip grp; do
    [ -z "$label" ] && continue
    inline "$label ($ip) ..."
    res="$(_ping_one "$ip" 4)"
    if [ -n "$res" ]; then
      IFS='|' read -r avg loss <<< "$res"
      if [ -n "$avg" ]; then
        inline_done "$(calc "$avg" 1) ms / 丢包 ${loss}%"
        row_add "$table" "$label" "$grp" "$(calc "$avg" 1) ms" "${loss}%"
        sum="$(calc "$sum+$avg" 2)"; n=$((n + 1))
      else
        inline_done "超时"
        row_add "$table" "$label" "$grp" "超时" "${loss}%"
      fi
    else
      inline_done "不可达"
      row_add "$table" "$label" "$grp" "不可达" "100%"
    fi
  done <<< "$list"
  [ "$n" -gt 0 ] && PING_AVG="$(calc "$sum/$n" 1)"
}

test_ping() {
  module_enabled ping || { log_info "跳过延迟测试"
    skip_note "$SKIP_REASON_OPT" ping_cn ping_gl; return 0; }
  need_tool ping >/dev/null 2>&1 || true
  if ! have ping; then
    log_warn "系统缺少 ping 命令，跳过延迟测试"
    return 0
  fi

  step "三网延迟与丢包"
  _run_ping_list ping_cn "$(_ping_targets_cn)"
  [ -n "$PING_AVG" ] && { kv_set ping.cn.avg "$PING_AVG"; log_ok "国内均值: ${PING_AVG} ms"; }

  if [ "$FAST_MODE" != "1" ]; then
    step "全球节点延迟"
    _run_ping_list ping_gl "$(_ping_targets_global)"
    [ -n "$PING_AVG" ] && { kv_set ping.global.avg "$PING_AVG"; log_ok "全球均值: ${PING_AVG} ms"; }
  fi
}
