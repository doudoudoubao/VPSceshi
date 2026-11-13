#!/usr/bin/env bash
# ============================================================
# 42_netquality.sh — 第 6 章：回程网络质量 / BGP 注册信息
#
# 数据来源都是公开免费 API，不需要 key：
#   RIPEstat  https://stat.ripe.net/data/...   前缀、ASN、邻居、whois
#   RDAP      https://rdap.org/ip/<ip>          注册主体、注册地、修改日期
#   PeeringDB https://www.peeringdb.com/api/... IXP、对等互联
#   BGP.HE    https://bgp.he.net/               辅助（HTML，作兜底）
# ============================================================

ASN_NUM=""   # 形如 3335（不带 AS 前缀）

_asn_number() {
  local a; a="$(kv_get net.as)"
  printf '%s' "$a" | grep -Eo 'AS[0-9]+' | head -1 | tr -dc '0-9'
}

_ripestat() {
  local path="$1" res="$2"
  xcurl4 "https://stat.ripe.net/data/${path}/data.json?resource=${res}&sourceapp=vpsceshi"
}

test_netquality() {
  module_enabled netquality || { log_info "跳过回程网络质量检测"
    skip_note "$SKIP_REASON_OPT" nq_bgp nq_peer nq_ixp nq_local; return 0; }
  step "回程网络质量 / BGP 注册信息"

  if [ -z "$IP4" ]; then
    na_set nq_bgp "无 IPv4 出口，无法查询 BGP 注册信息"
    log_warn "无 IPv4 出口，跳过"
    return 0
  fi

  # ---------- 1. 前缀与 Origin AS ----------
  inline "BGP 前缀 / Origin AS"
  local j prefix asns
  j="$(_ripestat network-info "$IP4")"
  prefix="$(jget "$j" '.data.prefix')"
  asns="$(jget "$j" '.data.asns | join(", ")')"
  [ -z "$asns" ] && asns="$(printf '%s' "$j" | grep -oE '"asns":\[[^]]*\]' | grep -oE '[0-9]+' | head -3 | tr '\n' ',' | sed 's/,$//')"
  inline_done "${prefix:-N/A}"
  ASN_NUM="$(printf '%s' "$asns" | grep -Eo '[0-9]+' | head -1)"
  [ -z "$ASN_NUM" ] && ASN_NUM="$(_asn_number)"

  [ -n "$prefix" ] && { kv_set nq.prefix "$prefix"; row_add nq_bgp "BGP 前缀 Prefix" "$prefix"; }
  [ -n "$asns" ]   && row_add nq_bgp "Origin AS" "AS${asns}"

  # ---------- 2. ASN 概览 ----------
  if [ -n "$ASN_NUM" ]; then
    inline "ASN 概览"
    local jo holder
    jo="$(_ripestat as-overview "AS${ASN_NUM}")"
    holder="$(jget "$jo" '.data.holder')"
    inline_done "${holder:-N/A}"
    [ -n "$holder" ] && { kv_set nq.holder "$holder"; row_add nq_bgp "网络组织 Holder" "$holder"; }

    # 宣告前缀数量
    local jr announced
    jr="$(_ripestat routing-status "AS${ASN_NUM}")"
    announced="$(jget "$jr" '.data.announced_space.v4.prefixes')"
    [ -n "$announced" ] && row_add nq_bgp "宣告 IPv4 前缀数" "$announced 条"
    local announced6; announced6="$(jget "$jr" '.data.announced_space.v6.prefixes')"
    [ -n "$announced6" ] && row_add nq_bgp "宣告 IPv6 前缀数" "$announced6 条"
  fi

  # ---------- 3. RDAP 注册信息（注册主体 / 注册地 / 日期）----------
  inline "RDAP 注册信息"
  local jd name country reg_date upd_date rir
  jd="$(xcurl4 -H 'Accept: application/rdap+json' "https://rdap.org/ip/${IP4}")"
  if [ -n "$jd" ]; then
    name="$(jget "$jd" '.name')"
    country="$(jget "$jd" '.country')"
    reg_date="$(jget "$jd" '.events[] | select(.eventAction=="registration") | .eventDate')"
    upd_date="$(jget "$jd" '.events[] | select(.eventAction=="last changed") | .eventDate')"
    rir="$(jget "$jd" '.port43')"
    [ -z "$rir" ] && rir="$(jget "$jd" '.links[0].value')"
  fi
  inline_done "${name:-N/A}"
  [ -n "$name" ]     && { kv_set nq.rdap_name "$name"; row_add nq_bgp "注册主体 Netname" "$name"; }
  [ -n "$country" ]  && { kv_set nq.rdap_cc "$country"; row_add nq_bgp "注册地区" "$country"; }
  [ -n "$reg_date" ] && row_add nq_bgp "注册日期" "${reg_date%%T*}"
  [ -n "$upd_date" ] && row_add nq_bgp "最后修改日期" "${upd_date%%T*}"
  # RIR 归属（ARIN / RIPE / APNIC …）
  local rirname=""
  case "$rir" in
    *arin*)    rirname="ARIN（北美）" ;;
    *ripe*)    rirname="RIPE NCC（欧洲/中东）" ;;
    *apnic*)   rirname="APNIC（亚太）" ;;
    *lacnic*)  rirname="LACNIC（拉美）" ;;
    *afrinic*) rirname="AFRINIC（非洲）" ;;
  esac
  [ -n "$rirname" ] && { kv_set nq.rir "$rirname"; row_add nq_bgp "注册局 RIR" "$rirname"; }

  # ---------- 4. 上游 / 对等互联（RIPEstat 邻居）----------
  if [ -n "$ASN_NUM" ]; then
    inline "上游 / 对等互联"
    local jn up down peer
    jn="$(_ripestat asn-neighbours "AS${ASN_NUM}")"
    if have jq; then
      up="$(printf   '%s' "$jn" | jq -r '[.data.neighbours[]? | select(.type=="left")]  | length' 2>/dev/null)"
      down="$(printf '%s' "$jn" | jq -r '[.data.neighbours[]? | select(.type=="right")] | length' 2>/dev/null)"
      peer="$(printf '%s' "$jn" | jq -r '[.data.neighbours[]? | select(.type=="uncertain")] | length' 2>/dev/null)"
    fi
    inline_done "上游 ${up:-?} / 下游 ${down:-?}"
    [ -n "$up" ]   && { kv_set nq.upstreams "$up";  row_add nq_peer "上游数量 Upstream" "$up 个"; }
    [ -n "$down" ] && row_add nq_peer "下游数量 Downstream" "$down 个"
    [ -n "$peer" ] && row_add nq_peer "不确定方向邻居" "$peer 个"

    # ---------- 5. PeeringDB：IXP 与对等 ----------
    inline "PeeringDB IXP"
    local jp netid ixcount
    jp="$(xcurl4 "https://www.peeringdb.com/api/net?asn=${ASN_NUM}")"
    netid="$(jget "$jp" '.data[0].id')"
    if [ -n "$netid" ]; then
      local pdb_name pdb_type pdb_scope
      pdb_name="$(jget "$jp" '.data[0].name')"
      pdb_type="$(jget "$jp" '.data[0].info_type')"
      pdb_scope="$(jget "$jp" '.data[0].info_scope')"
      [ -n "$pdb_name" ]  && row_add nq_peer "PeeringDB 名称" "$pdb_name"
      [ -n "$pdb_type" ]  && row_add nq_peer "网络类型" "$pdb_type"
      [ -n "$pdb_scope" ] && row_add nq_peer "覆盖范围" "$pdb_scope"

      local jx
      jx="$(xcurl4 "https://www.peeringdb.com/api/netixlan?net_id=${netid}")"
      if have jq; then
        ixcount="$(printf '%s' "$jx" | jq -r '.data | length' 2>/dev/null)"
        # 列出前 8 个 IXP
        local ixlist
        ixlist="$(printf '%s' "$jx" | jq -r '.data[0:8][]? | "\(.name)|\(.speed)"' 2>/dev/null)"
        local ixn ixs
        while IFS='|' read -r ixn ixs; do
          [ -z "$ixn" ] && continue
          row_add nq_ixp "$ixn" "$(calc "${ixs:-0}/1000" 0) Gbps"
        done <<< "$ixlist"
      fi
    fi
    inline_done "${ixcount:-0} 个"
    [ -n "$ixcount" ] && { kv_set nq.ixp_count "$ixcount"
                           row_add nq_peer "互联网交换点 IXP 数量" "$ixcount 个"; }
  fi

  # ---------- 6. 本机网络策略 ----------
  row_add nq_local "TCP 拥塞控制算法" "$(kv_get sys.tcp.cc)"
  row_add nq_local "队列调度算法"     "$(kv_get sys.tcp.qdisc)"
  local avail
  avail="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)"
  [ -z "$avail" ] && avail="$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)"
  [ -n "$avail" ] && row_add nq_local "可用拥塞算法" "$avail"
  local fwd; fwd="$(sysctl -n net.ipv4.ip_forward 2>/dev/null)"
  [ -n "$fwd" ] && row_add nq_local "IP 转发" "$([ "$fwd" = "1" ] && echo '已开启' || echo '未开启')"
  local mtu
  mtu="$(ip route get 1.1.1.1 2>/dev/null | grep -oE 'mtu [0-9]+' | awk '{print $2}')"
  [ -z "$mtu" ] && mtu="$(ip link show 2>/dev/null | grep -m1 -oE 'mtu [0-9]+' | awk '{print $2}')"
  [ -n "$mtu" ] && row_add nq_local "接口 MTU" "$mtu"
  row_add nq_local "IPv6 支持" "$([ "$IPV6_OK" = "1" ] && echo '✅ 可用' || echo '❌ 不可用')"

  rows_have nq_bgp || na_set nq_bgp "BGP 查询接口未返回数据（RIPEstat / RDAP 不可达或限频）"
  log_ok "AS${ASN_NUM:-?} $(kv_or nq.holder '') | 前缀 $(kv_or nq.prefix 'N/A') | IXP $(kv_or nq.ixp_count '?') 个"
}
