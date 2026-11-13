#!/usr/bin/env bash
# ============================================================
# 05_profile.sh — 第 1 章：基本配置核对
#
# 商家/套餐/机房/价格这些是买的时候的信息，机器上探测不到，
# 由命令行参数或配置文件提供；同时把能自动探测的（CPU/内存/
# 硬盘/IP 数量）拉出来跟宣传值并排放，方便一眼看出缩水。
# ============================================================

# 宣传值（用户提供）
P_VENDOR=""      # 商家
P_PLAN=""        # 套餐名
P_DC=""          # 机房
P_LINE=""        # 线路宣传
P_CPU=""         # 宣传 CPU 核数
P_RAM=""         # 宣传内存
P_DISK=""        # 宣传硬盘
P_TRAFFIC=""     # 月流量
P_BANDWIDTH=""   # 带宽
P_IPV4=""        # IPv4 数量
P_IPV6=""        # IPv6 数量
P_PRICE=""       # 价格
P_CURRENCY="AUD" # 币种
P_CYCLE="月付"   # 付费周期

# 从配置文件读取（KEY=VALUE，# 开头为注释）
load_profile_file() {
  local f="$1"
  [ -r "$f" ] || { log_err "配置文件不可读: $f"; return 1; }
  local line k v
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    k="${line%%=*}"; v="${line#*=}"
    k="$(trim "$k")"; v="$(trim "$v")"
    # 去掉可能的引号
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    case "$k" in
      VENDOR)    P_VENDOR="$v" ;;
      PLAN)      P_PLAN="$v" ;;
      DC)        P_DC="$v" ;;
      LINE)      P_LINE="$v" ;;
      CPU)       P_CPU="$v" ;;
      RAM)       P_RAM="$v" ;;
      DISK)      P_DISK="$v" ;;
      TRAFFIC)   P_TRAFFIC="$v" ;;
      BANDWIDTH) P_BANDWIDTH="$v" ;;
      IPV4)      P_IPV4="$v" ;;
      IPV6)      P_IPV6="$v" ;;
      PRICE)     P_PRICE="$v" ;;
      CURRENCY)  P_CURRENCY="$v" ;;
      CYCLE)     P_CYCLE="$v" ;;
      NAME)      NODE_NAME="$v" ;;
      *) log_warn "配置文件中未知字段: $k" ;;
    esac
  done < "$f"
  log_ok "已载入配置: $f"
}

# 统计本机绑定的公网 IP 数量
_count_local_ips() {
  local v4=0 v6=0
  if have ip; then
    v4="$(ip -4 addr show scope global 2>/dev/null | grep -c 'inet ')"
    # 排除 fe80:: 链路本地与 ::1
    v6="$(ip -6 addr show scope global 2>/dev/null | grep -c 'inet6 ')"
  elif have ifconfig; then
    v4="$(ifconfig 2>/dev/null | grep -c 'inet ')"
    v6="$(ifconfig 2>/dev/null | grep -c 'inet6 .*global')"
  fi
  printf '%s|%s' "${v4:-0}" "${v6:-0}"
}

# 解析容量字符串里的单位倍率（相对 MB）。无单位返回空。
_size_unit() {
  case "$1" in
    *[Tt][Ii][Bb]|*[Tt][Bb]) printf '1048576' ;;
    *[Gg][Ii][Bb]|*[Gg][Bb]) printf '1024' ;;
    *[Mm][Ii][Bb]|*[Mm][Bb]) printf '1' ;;
    *[Kk][Ii][Bb]|*[Kk][Bb]) printf '0.0009765625' ;;
    *) printf '' ;;
  esac
}

# 宣传值 vs 实测值的一致性标记。
# 容量类要先统一单位再比，否则 "1GB" 和 "984.27 MB" 会被当成 1 对 984。
_cmp_mark() {
  local claim="$1" actual="$2"
  [ -z "$claim" ] && { printf '—'; return; }
  local cn an cu au
  cn="$(printf '%s' "$claim"  | grep -Eo '[0-9.]+' | head -1)"
  an="$(printf '%s' "$actual" | grep -Eo '[0-9.]+' | head -1)"
  [ -z "$cn" ] || [ -z "$an" ] && { printf '—'; return; }

  cu="$(_size_unit "$claim")"
  au="$(_size_unit "$actual")"
  # 一边有单位另一边没有时，按有单位的那边解释，避免跨量级误判
  [ -z "$cu" ] && [ -n "$au" ] && cu="$au"
  [ -n "$cu" ] && [ -z "$au" ] && au="$cu"
  if [ -n "$cu" ] && [ -n "$au" ]; then
    cn="$(calc "$cn*$cu" 4)"
    an="$(calc "$an*$au" 4)"
  fi

  # 实测 >= 宣传的 95% 视为相符，>= 80% 记略低
  awk -v c="$cn" -v a="$an" 'BEGIN{
    if (c <= 0) { print "—"; exit }
    if (a >= c*0.95) print "✅ 相符";
    else if (a >= c*0.8) print "⚠️ 略低";
    else print "❌ 不符" }'
}

collect_profile() {
  step "基本配置核对"

  local ipc v4c v6c
  ipc="$(_count_local_ips)"
  v4c="${ipc%%|*}"; v6c="${ipc##*|}"
  kv_set profile.ip4_count "$v4c"
  kv_set profile.ip6_count "$v6c"

  kv_set profile.vendor    "$P_VENDOR"
  kv_set profile.plan      "$P_PLAN"
  kv_set profile.dc        "$P_DC"
  kv_set profile.line      "$P_LINE"
  kv_set profile.traffic   "$P_TRAFFIC"
  kv_set profile.bandwidth "$P_BANDWIDTH"
  [ -n "$P_PRICE" ] && kv_set profile.price "${P_PRICE} ${P_CURRENCY} / ${P_CYCLE}"

  # 商家信息表（宣传值）
  [ -n "$P_VENDOR" ]    && row_add profile_base "商家"     "$P_VENDOR"
  [ -n "$P_PLAN" ]      && row_add profile_base "套餐名"   "$P_PLAN"
  [ -n "$P_DC" ]        && row_add profile_base "机房"     "$P_DC"
  [ -n "$P_LINE" ]      && row_add profile_base "线路宣传" "$P_LINE"
  [ -n "$P_TRAFFIC" ]   && row_add profile_base "月流量"   "$P_TRAFFIC"
  [ -n "$P_BANDWIDTH" ] && row_add profile_base "带宽"     "$P_BANDWIDTH"
  [ -n "$P_PRICE" ]     && row_add profile_base "价格"     "${P_PRICE} ${P_CURRENCY} / ${P_CYCLE}"

  # 配置核对表：宣传 vs 实测
  local a_cpu a_ram a_disk
  a_cpu="$(kv_get sys.cpu.cores) 核"
  a_ram="$(kv_get sys.mem.total)"
  a_disk="$(printf '%s' "$(kv_get sys.disk.summary)" | awk -F' / ' '{print $2}')"

  row_add profile_cmp "CPU 核数"  "${P_CPU:-未填写}"  "$a_cpu"  "$(_cmp_mark "$P_CPU" "$a_cpu")"
  row_add profile_cmp "内存"      "${P_RAM:-未填写}"  "$a_ram"  "$(_cmp_mark "$P_RAM" "$a_ram")"
  row_add profile_cmp "硬盘"      "${P_DISK:-未填写}" "$a_disk" "$(_cmp_mark "$P_DISK" "$a_disk")"
  row_add profile_cmp "IPv4 数量" "${P_IPV4:-未填写}" "$v4c 个" "$(_cmp_mark "$P_IPV4" "$v4c")"
  row_add profile_cmp "IPv6 数量" "${P_IPV6:-未填写}" "$v6c 个" "$(_cmp_mark "$P_IPV6" "$v6c")"

  if [ -n "$P_VENDOR$P_PLAN$P_DC" ]; then
    log_ok "${P_VENDOR} ${P_PLAN} @ ${P_DC}"
  else
    log_info "未提供商家/套餐信息（可用 --config 补充）"
  fi
  log_ok "本机公网 IP：IPv4 ${v4c} 个 / IPv6 ${v6c} 个"
}
