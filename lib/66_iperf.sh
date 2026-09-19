#!/usr/bin/env bash
# ============================================================
# 66_iperf.sh — 第 8 章：国际节点带宽（YABS 同款 iperf3 公共节点）
#
# 用的是 YABS 里那批公开 iperf3 服务器，测上传/下载带宽与延迟。
# 这些是志愿者提供的公共服务，忙时可能连不上，失败即跳过。
# ============================================================

# 显示名|主机|端口区间
_iperf_nodes() {
  cat <<'EOF'
新加坡 Leaseweb 10G|speedtest.sin1.sg.leaseweb.net|5201-5210
洛杉矶 Clouvider 10G|la.speedtest.clouvider.net|5200-5209
伦敦 Clouvider 10G|lon.speedtest.clouvider.net|5200-5209
阿姆斯特丹 Eranium 100G|speedtest.ams1.nl.leaseweb.net|5201-5210
纽约 Leaseweb 10G|speedtest.nyc1.us.leaseweb.net|5201-5210
EOF
}

# 从端口区间里随机挑一个，避开被占用的固定端口
_pick_port() {
  local range="$1" lo hi
  lo="${range%%-*}"; hi="${range##*-}"
  printf '%s' $(( lo + RANDOM % (hi - lo + 1) ))
}

# 跑一次 iperf3，方向由 $3 决定：down 用 -R
# 输出 Mbps
_iperf_run() {
  local host="$1" port="$2" dir="$3"
  local args=(-c "$host" -p "$port" -P 8 -t 10 -J --connect-timeout 5000)
  [ "$dir" = "down" ] && args+=(-R)
  local out; out="$(run_to 60 iperf3 "${args[@]}" 2>/dev/null)"
  [ -z "$out" ] && return 1
  case "$out" in *'"error"'*) return 1 ;; esac
  local bps
  if have jq; then
    if [ "$dir" = "down" ]; then
      bps="$(printf '%s' "$out" | jq -r '.end.sum_received.bits_per_second // 0' 2>/dev/null)"
    else
      bps="$(printf '%s' "$out" | jq -r '.end.sum_sent.bits_per_second // 0' 2>/dev/null)"
    fi
  else
    bps="$(printf '%s' "$out" | grep -oE '"bits_per_second":[[:space:]]*[0-9.]+' | tail -1 |
           grep -oE '[0-9.]+')"
  fi
  [ -z "$bps" ] || [ "$bps" = "0" ] && return 1
  calc "$bps/1000000" 2
}

test_iperf() {
  module_enabled iperf || { log_info "跳过国际带宽测试"; return 0; }
  # 默认不跑：每节点 1-3GB 流量，得用户明确开启
  if [ "$ENABLE_IPERF" != "1" ]; then
    na_set iperf "本次未启用国际带宽测试（流量消耗大，用 --iperf 或 --full 开启）"
    log_info "未启用 iperf3 国际带宽测试（--iperf 开启）"
    return 0
  fi
  step "国际节点带宽（iperf3）"

  if ! have iperf3; then
    ensure_cmd iperf3 >/dev/null 2>&1 || true
  fi
  if ! have iperf3; then
    na_set iperf "系统未安装 iperf3 且自动安装失败，国际带宽未测"
    log_warn "未安装 iperf3，跳过"
    return 0
  fi

  log_warn "iperf3 测试会跑满带宽，每节点约消耗 1-3GB 流量"

  local label host range port up down lat n=0
  while IFS='|' read -r label host range; do
    [ -z "$label" ] && continue
    n=$((n + 1))
    [ "$FAST_MODE" = "1" ] && [ "$n" -gt 2 ] && break

    # 延迟顺带用 ping 量一下，拿不到就算了
    lat=""
    if have ping; then
      lat="$(run_to 12 ping -c 3 -W 2 "$host" 2>/dev/null |
             grep -E 'min/avg|round-trip' | awk -F'/' '{print $5}')"
      [ -n "$lat" ] && lat="$(calc "$lat" 1) ms"
    fi

    inline "$label 上传 ..."
    port="$(_pick_port "$range")"
    up="$(_iperf_run "$host" "$port" up)"
    inline_done "${up:+${up} Mbps}${up:-失败}"

    inline "$label 下载 ..."
    port="$(_pick_port "$range")"
    down="$(_iperf_run "$host" "$port" down)"
    inline_done "${down:+${down} Mbps}${down:-失败}"

    if [ -n "$up" ] || [ -n "$down" ]; then
      row_add iperf "$label" "${down:+${down} Mbps}${down:-N/A}" \
              "${up:+${up} Mbps}${up:-N/A}" "${lat:-N/A}"
    else
      row_add iperf "$label" "N/A" "N/A" "${lat:-N/A}"
    fi
  done <<< "$(_iperf_nodes)"

  rows_have iperf || na_set iperf "所有公共 iperf3 节点均未连通，国际带宽未取得有效数据"
}
