#!/usr/bin/env bash
# ============================================================
# 60_speedtest.sh — 三网 / 国际节点测速（Ookla Speedtest CLI）
# ============================================================

ST_BIN=""

install_speedtest() {
  have speedtest && { ST_BIN="$(command -v speedtest)"; return 0; }
  [ -n "$ST_BIN" ] && [ -x "$ST_BIN" ] && return 0

  local arch tag
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)  tag="x86_64" ;;
    aarch64|arm64) tag="aarch64" ;;
    armv7l|armv7)  tag="armhf" ;;
    i386|i686)     tag="i386" ;;
    *) log_warn "Speedtest CLI 不支持架构 $arch"; return 1 ;;
  esac

  local f="$BIN_DIR/st.tgz"
  log_info "下载 Ookla Speedtest CLI ($tag) ..."
  if ! fetch_first "$f" \
      "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${tag}.tgz" \
      "https://install.speedtest.net/app/cli/ookla-speedtest-1.1.1-linux-${tag}.tgz"; then
    log_warn "Speedtest CLI 下载失败"
    return 1
  fi
  tar -xzf "$f" -C "$BIN_DIR" 2>/dev/null
  if [ -x "$BIN_DIR/speedtest" ]; then
    ST_BIN="$BIN_DIR/speedtest"
    "$ST_BIN" --accept-license --accept-gdpr --version >/dev/null 2>&1
    return 0
  fi
  log_warn "Speedtest CLI 解压失败"
  return 1
}

# 按关键词搜索服务器 ID
st_find_server() {
  local kw="$1"
  local j
  j="$(xcurl --get --data-urlencode "search=$kw" \
      "https://www.speedtest.net/api/js/servers?engine=js&limit=5")"
  [ -z "$j" ] && return 1
  local id
  if have jq; then
    id="$(printf '%s' "$j" | jq -r '.[0].id // empty' 2>/dev/null)"
  else
    id="$(printf '%s' "$j" | grep -oE '"id":"?[0-9]+' | head -1 | grep -oE '[0-9]+')"
  fi
  [ -n "$id" ] && printf '%s' "$id"
}

# 运行一次测速：st_run <服务器ID或空>
# 输出 "下载Mbps|上传Mbps|延迟ms|抖动ms|服务器名|城市"
st_run() {
  local sid="$1" out args=()
  args=(--accept-license --accept-gdpr -f json -P 8)
  [ -n "$sid" ] && args+=(-s "$sid")
  out="$(run_to 120 "$ST_BIN" "${args[@]}" 2>/dev/null | tail -1)"
  [ -z "$out" ] && return 1
  case "$out" in *'"type":"result"'*) ;; *) return 1 ;; esac

  local dbw ubw ping jit name loc
  if have jq; then
    dbw="$(printf  '%s' "$out" | jq -r '.download.bandwidth // 0')"
    ubw="$(printf  '%s' "$out" | jq -r '.upload.bandwidth // 0')"
    ping="$(printf '%s' "$out" | jq -r '.ping.latency // 0')"
    jit="$(printf  '%s' "$out" | jq -r '.ping.jitter // 0')"
    name="$(printf '%s' "$out" | jq -r '.server.name // ""')"
    loc="$(printf  '%s' "$out" | jq -r '.server.location // ""')"
  else
    dbw="$(printf  '%s' "$out" | grep -oE '"download":\{"bandwidth":[0-9]+' | grep -oE '[0-9]+$')"
    ubw="$(printf  '%s' "$out" | grep -oE '"upload":\{"bandwidth":[0-9]+'   | grep -oE '[0-9]+$')"
    ping="$(printf '%s' "$out" | grep -oE '"latency":[0-9.]+' | head -1 | cut -d: -f2)"
    jit="$(printf  '%s' "$out" | grep -oE '"jitter":[0-9.]+'  | head -1 | cut -d: -f2)"
    name="$(printf '%s' "$out" | grep -oE '"name":"[^"]*"' | tail -1 | cut -d'"' -f4)"
    loc=""
  fi
  # bandwidth 单位为 byte/s
  printf '%s|%s|%s|%s|%s|%s' \
    "$(calc "${dbw:-0}*8/1000000" 2)" "$(calc "${ubw:-0}*8/1000000" 2)" \
    "$(calc "${ping:-0}" 2)" "$(calc "${jit:-0}" 2)" "$name" "$loc"
}

# 节点表：显示名 | 搜索关键词 | 备用ID
# 默认只跑前 6 个（三网各 2 个，南北各一），够看出线路差异了。
# 想全跑用 --speedtest-full；每个节点约 100-500MB 流量，别浪费。
_st_nodes_cn() {
  cat <<'EOF'
上海电信|China Telecom Shanghai|3633
上海联通|China Unicom Shanghai|24447
上海移动|China Mobile Shanghai|25858
广州电信|China Telecom Guangdong|27594
广州联通|China Unicom Guangzhou|26678
广州移动|China Mobile Guangdong|31490
北京电信|China Telecom Beijing|27377
北京联通|China Unicom Beijing|5145
北京移动|China Mobile Beijing|41839
成都电信|China Telecom Chengdu|17320
EOF
}

_st_nodes_global() {
  cat <<'EOF'
香港 HK|Hong Kong|22126
日本 东京|Tokyo Japan|21569
新加坡 SG|Singapore|13623
韩国 首尔|Seoul Korea|6527
台湾 台北|Taipei Taiwan|18445
美国 洛杉矶|Los Angeles|10493
美国 纽约|New York|17383
德国 法兰克福|Frankfurt|26852
英国 伦敦|London|24215
EOF
}

_run_node_list() {
  local table="$1" list="$2" limit="$3"
  local n=0 label kw fbid sid res
  while IFS='|' read -r label kw fbid; do
    [ -z "$label" ] && continue
    [ "$limit" -gt 0 ] && [ "$n" -ge "$limit" ] && break
    n=$((n + 1))
    inline "$label ..."
    sid="$(st_find_server "$kw")"
    [ -z "$sid" ] && sid="$fbid"
    res="$(st_run "$sid")"
    if [ -z "$res" ] && [ -n "$fbid" ] && [ "$sid" != "$fbid" ]; then
      res="$(st_run "$fbid")"
    fi
    if [ -n "$res" ]; then
      local dl ul pg jt nm lc
      IFS='|' read -r dl ul pg jt nm lc <<< "$res"
      inline_done "↓ ${dl} Mbps  ↑ ${ul} Mbps  ${pg} ms"
      row_add "$table" "$label" "${dl} Mbps" "${ul} Mbps" "${pg} ms" "${jt} ms" "${nm:-$kw}"
    else
      inline_done "失败"
      row_add "$table" "$label" "N/A" "N/A" "N/A" "N/A" "测速失败"
    fi
  done <<< "$list"
}

test_speedtest() {
  module_enabled speedtest || { log_info "跳过测速"
    skip_note "$SKIP_REASON_OPT" speed_auto speed_cn speed_gl; return 0; }
  if [ "$SPEEDTEST_MODE" = "off" ]; then
    log_info "已禁用测速"
    skip_note "本次未运行测速（--speedtest off）" speed_auto speed_cn speed_gl
    return 0
  fi

  # 只测了一边时，另一边要说清是「没测」而不是「测了没结果」
  case "$SPEEDTEST_MODE" in
    cn)     skip_note "本次只测了国内节点（--speedtest cn），未测国际节点" speed_gl ;;
    global) skip_note "本次只测了国际节点（--speedtest global），未测国内三网" speed_cn ;;
  esac

  step "三网 / 国际节点测速"
  log_warn "测速会消耗较多流量（每节点约 100-500MB），如流量敏感请用 --speedtest off"

  if ! install_speedtest; then
    log_warn "Speedtest CLI 不可用，跳过测速"
    skip_note "Speedtest CLI 下载失败或不支持当前架构，测速未执行" speed_auto speed_cn speed_gl
    return 0
  fi

  # 先跑一次自动就近节点
  inline "自动就近节点 ..."
  local auto; auto="$(st_run "")"
  if [ -n "$auto" ]; then
    local dl ul pg jt nm lc
    IFS='|' read -r dl ul pg jt nm lc <<< "$auto"
    inline_done "↓ ${dl} Mbps  ↑ ${ul} Mbps  ${pg} ms  @${nm}"
    row_add speed_auto "就近节点" "${dl} Mbps" "${ul} Mbps" "${pg} ms" "${jt} ms" "${nm} ${lc}"
    kv_set speed.auto.down "$dl"; kv_set speed.auto.up "$ul"; kv_set speed.auto.ping "$pg"
  else
    inline_done "失败"
  fi

  # 默认 6 个节点，--fast 只跑 3 个，--speedtest-full 才全跑
  local limit=6
  [ "$FAST_MODE" = "1" ] && limit=3
  [ "$SPEEDTEST_FULL" = "1" ] && limit=0

  case "$SPEEDTEST_MODE" in
    cn)     _run_node_list speed_cn "$(_st_nodes_cn)" "$limit" ;;
    global) _run_node_list speed_gl "$(_st_nodes_global)" "$limit" ;;
    all)
      _run_node_list speed_cn "$(_st_nodes_cn)" "$limit"
      _run_node_list speed_gl "$(_st_nodes_global)" "$limit"
      ;;
  esac

  # 跑了但一行结果都没有，这时才是真正的「未取得有效数据」
  case "$SPEEDTEST_MODE" in
    cn|all)     rows_have speed_cn || na_set speed_cn "本次未取得有效数据：测速节点均未返回有效结果" ;;
  esac
  case "$SPEEDTEST_MODE" in
    global|all) rows_have speed_gl || na_set speed_gl "本次未取得有效数据：测速节点均未返回有效结果" ;;
  esac
  rows_have speed_auto || na_set speed_auto "本次未取得有效数据：就近节点测速未返回结果"
}
