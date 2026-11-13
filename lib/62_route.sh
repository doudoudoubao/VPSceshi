#!/usr/bin/env bash
# ============================================================
# 62_route.sh — 三网回程路由追踪（nexttrace，回退 traceroute/mtr）
# ============================================================

NT_BIN=""

install_nexttrace() {
  have nexttrace && { NT_BIN="$(command -v nexttrace)"; return 0; }
  local arch; arch="$(arch_tag)"
  case "$arch" in
    amd64) a="amd64" ;; arm64) a="arm64" ;; armv7) a="armv7" ;; i386) a="386" ;;
    *) log_warn "nexttrace 不支持架构 $(uname -m)"; return 1 ;;
  esac
  local f="$BIN_DIR/nexttrace"
  log_info "下载 nexttrace ($a) ..."
  if fetch_first "$f" \
      "https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${a}" \
      "https://ghfast.top/https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${a}" \
      "https://gh-proxy.com/https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${a}"; then
    chmod +x "$f" 2>/dev/null
    if "$f" --version >/dev/null 2>&1; then NT_BIN="$f"; return 0; fi
  fi
  log_warn "nexttrace 下载失败，将回退到 traceroute/mtr"
  return 1
}

# 回程路由目标
_route_targets() {
  cat <<'EOF'
广州电信|58.60.188.222
北京电信|219.141.140.10
上海电信|202.96.209.133
茂名联通|120.234.0.1
北京联通|202.106.195.68
上海联通|210.22.97.1
广州联通|210.21.196.6
上海移动|211.136.112.200
深圳移动|120.196.165.24
北京移动|221.183.129.101
EOF
}

_trace_one() {
  local ip="$1" out=""
  if [ -n "$NT_BIN" ]; then
    # 不要加 -n：那会关掉解析，输出里就没有 AS 号，线路判定全废。
    # 也不要 -M / --map=false 混用，两者互相矛盾。
    out="$(run_to 35 "$NT_BIN" -q 1 --nocolor "$ip" 2>/dev/null)"
    [ -z "$out" ] && out="$(run_to 35 "$NT_BIN" -q 1 "$ip" 2>/dev/null)"
  fi
  # nexttrace 没结果就退回系统工具（这些没有 AS 标注，只能靠 IP 段识别）
  if [ -z "$out" ] && have mtr; then
    out="$(run_to 35 mtr -r -c 3 "$ip" 2>/dev/null)"
  fi
  if [ -z "$out" ] && have traceroute; then
    out="$(run_to 35 traceroute -q 1 -w 1 -m 20 "$ip" 2>/dev/null)"
  fi
  if [ -z "$out" ] && have tracepath; then
    out="$(run_to 35 tracepath -m 20 "$ip" 2>/dev/null)"
  fi
  printf '%s' "$out"
}

# 数有效跳数（能识别出 IP 的跳），用来判断追踪是不是根本没走通
_trace_hops() {
  printf '%s' "$1" | grep -cE '^[[:space:]]*[0-9]+[.|[:space:]]' 2>/dev/null
}
# 数「无响应」的跳
_trace_stars() {
  printf '%s' "$1" | grep -cE '\*|\?\?\?' 2>/dev/null
}

# 从路由文本粗略识别线路类型（去程/回程通用）
_guess_line() {
  local txt="$1"
  local hit=""
  _hit() { case "$hit" in *"$1"*) ;; *) hit="${hit:+$hit / }$1" ;; esac; }

  # —— 国内三网骨干 ——
  case "$txt" in *59.43.*)                  _hit "电信 CN2 GIA (AS4809)" ;; esac
  case "$txt" in *202.97.*)                 _hit "电信 163 骨干 (AS4134)" ;; esac
  case "$txt" in *AS9929*|*218.105.*|*218.241.*) _hit "联通 A网 CUII (AS9929)" ;; esac
  case "$txt" in *AS4837*|*219.158.*)       _hit "联通 169 骨干 (AS4837)" ;; esac
  case "$txt" in *AS58807*|*CMIN2*|*223.118.*) _hit "移动 CMIN2 (AS58807)" ;; esac
  case "$txt" in *AS58453*|*CMI*|*223.120.*)   _hit "移动 CMI (AS58453)" ;; esac
  case "$txt" in *AS9808*|*AS56048*)        _hit "移动 CMNET (AS9808)" ;; esac

  # —— 国际骨干 ——
  case "$txt" in *AS2914*|*NTT*|*129.250.*) _hit "NTT (AS2914)" ;; esac
  case "$txt" in *AS3356*|*Level3*|*Lumen*|*4.68.*|*4.69.*) _hit "Lumen/Level3 (AS3356)" ;; esac
  case "$txt" in *AS174*|*Cogent*|*154.54.*) _hit "Cogent (AS174)" ;; esac
  case "$txt" in *AS6939*|*"Hurricane"*)    _hit "HE.net (AS6939)" ;; esac
  case "$txt" in *AS1299*|*Arelion*|*Telia*) _hit "Arelion/Telia (AS1299)" ;; esac
  case "$txt" in *AS3257*|*GTT*)            _hit "GTT (AS3257)" ;; esac
  case "$txt" in *AS6453*|*TATA*)           _hit "TATA (AS6453)" ;; esac
  case "$txt" in *AS7473*|*Singtel*)        _hit "Singtel (AS7473)" ;; esac
  case "$txt" in *AS4637*|*Telstra*)        _hit "Telstra Global (AS4637)" ;; esac
  case "$txt" in *AS3491*|*PCCW*|*63.218.*|*202.79.*) _hit "PCCW (AS3491)" ;; esac
  case "$txt" in *AS2497*|*IIJ*)            _hit "IIJ (AS2497)" ;; esac
  case "$txt" in *AS17676*|*Softbank*|*SoftBank*) _hit "Softbank (AS17676)" ;; esac
  case "$txt" in *AS4134*)                  _hit "电信 163 骨干 (AS4134)" ;; esac
  case "$txt" in *AS4809*)                  _hit "电信 CN2 (AS4809)" ;; esac

  unset -f _hit
  if [ -z "$hit" ]; then
    # 没匹配到骨干时，把原因说清楚：是追踪没走通，还是走通了但线路不在识别表里
    local hops stars
    hops="$(_trace_hops "$txt")"
    stars="$(_trace_stars "$txt")"
    if [ "${hops:-0}" -lt 3 ]; then
      hit="追踪受阻（仅 ${hops:-0} 跳，ICMP 可能被限制）"
    elif [ "${stars:-0}" -ge "$(( ${hops:-1} / 2 ))" ]; then
      hit="多数跳无响应（${hops} 跳中 ${stars} 跳超时）"
    else
      hit="未识别到已知骨干（${hops} 跳，详见原始输出）"
    fi
  fi
  printf '%s' "$hit"
}

test_route() {
  module_enabled route || { log_info "跳过路由追踪"
    skip_note "$SKIP_REASON_OPT" route; return 0; }
  step "三网回程路由追踪"

  if [ "$(id -u)" != "0" ]; then
    log_warn "非 root 运行，路由追踪可能无法发送 ICMP 探测包"
  fi
  install_nexttrace || true
  if [ -z "$NT_BIN" ] && ! have mtr && ! have traceroute && ! have tracepath; then
    log_warn "无可用的路由追踪工具，跳过"
    skip_note "系统无可用的路由追踪工具（nexttrace / mtr / traceroute 均不可用）" route
    return 0
  fi

  local label ip out line n=0
  while IFS='|' read -r label ip; do
    [ -z "$label" ] && continue
    n=$((n + 1))
    # 默认 6 个（三网各 2），--fast 3 个，--route-full 全部 10 个
    local rlimit=6
    [ "$FAST_MODE" = "1" ] && rlimit=3
    [ "$ROUTE_FULL" = "1" ] && rlimit=99
    [ "$n" -gt "$rlimit" ] && break
    inline "$label"
    out="$(_trace_one "$ip")"
    if [ -n "$out" ]; then
      line="$(_guess_line "$out")"
      inline_done "$line"
      row_add route "$label" "$ip" "$line"
      raw_add "回程路由 · $label ($ip)" "$out"
    else
      inline_done "失败"
      row_add route "$label" "$ip" "追踪失败"
    fi
  done <<< "$(_route_targets)"

  if rows_have route; then
    _summarize_route route route.verdict
    [ -n "$(kv_get route.verdict)" ] && log_ok "回程线路：$(kv_get route.verdict)"
  else
    na_set route "本次未取得有效回程路由数据（追踪工具不可用或全部超时）"
  fi
}
