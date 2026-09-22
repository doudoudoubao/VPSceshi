#!/usr/bin/env bash
# ============================================================
# 40_ipinfo.sh — 出口 IP / ASN / 地理位置 / 双栈检测
# ============================================================

IP4=""; IP6=""

_mask_ip() {
  # 报告默认对出口 IP 做部分遮蔽，避免直接公开完整地址
  local ip="$1"
  [ "$MASK_IP" = "0" ] && { printf '%s' "$ip"; return 0; }
  case "$ip" in
    *:*) printf '%s' "$(printf '%s' "$ip" | cut -d: -f1-3):****" ;;
    *.*) printf '%s.%s.*.*' "$(printf '%s' "$ip" | cut -d. -f1)" "$(printf '%s' "$ip" | cut -d. -f2)" ;;
    *)   printf '%s' "$ip" ;;
  esac
}

detect_ip() {
  step "出口 IP 与网络归属"

  local u4=(
    "https://api.ipify.org"
    "https://ipv4.icanhazip.com"
    "https://api-ipv4.ip.sb/ip"
    "https://ipinfo.io/ip"
  )
  local u6=(
    "https://api6.ipify.org"
    "https://ipv6.icanhazip.com"
    "https://api-ipv6.ip.sb/ip"
  )

  inline "检测 IPv4 出口"
  local u
  for u in "${u4[@]}"; do
    IP4="$(trim "$(xcurl4 "$u")")"
    case "$IP4" in *.*.*.*) break ;; *) IP4="" ;; esac
  done
  inline_done "${IP4:-无}"
  [ -n "$IP4" ] && IPV4_OK=1

  inline "检测 IPv6 出口"
  for u in "${u6[@]}"; do
    IP6="$(trim "$(xcurl6 "$u")")"
    case "$IP6" in *:*) break ;; *) IP6="" ;; esac
  done
  inline_done "${IP6:-无}"
  [ -n "$IP6" ] && IPV6_OK=1

  kv_set net.ip4 "$(_mask_ip "$IP4")"
  kv_set net.ip6 "$(_mask_ip "$IP6")"
  kv_set net.stack "$([ "$IPV4_OK" = 1 ] && printf 'IPv4' ; [ "$IPV6_OK" = 1 ] && printf '%s' "$([ "$IPV4_OK" = 1 ] && echo ' + ')IPv6")"
  [ -z "$(kv_get net.stack)" ] && kv_set net.stack "无公网出口"

  # ---- 归属信息（ip-api.com 免费无需 key）----
  if [ -n "$IP4" ]; then
    local j
    j="$(xcurl4 "http://ip-api.com/json/${IP4}?fields=status,country,countryCode,regionName,city,isp,org,as,asname,reverse,mobile,proxy,hosting,timezone,lat,lon&lang=zh-CN")"
    if [ -n "$j" ] && [ "$(jget "$j" '.status')" = "success" ]; then
      kv_set net.country  "$(jget "$j" '.country')"
      kv_set net.cc       "$(jget "$j" '.countryCode')"
      kv_set net.region   "$(jget "$j" '.regionName')"
      kv_set net.city     "$(jget "$j" '.city')"
      kv_set net.isp      "$(jget "$j" '.isp')"
      kv_set net.org      "$(jget "$j" '.org')"
      kv_set net.as       "$(jget "$j" '.as')"
      kv_set net.asname   "$(jget "$j" '.asname')"
      kv_set net.rdns     "$(jget "$j" '.reverse')"
      kv_set net.tz       "$(jget "$j" '.timezone')"
      kv_set net.flag_proxy   "$(jget "$j" '.proxy')"
      kv_set net.flag_hosting "$(jget "$j" '.hosting')"
      kv_set net.flag_mobile  "$(jget "$j" '.mobile')"
    fi
    # ipinfo 作为补充（ASN / 组织更规范）
    local j2; j2="$(xcurl4 "https://ipinfo.io/${IP4}/json")"
    if [ -n "$j2" ]; then
      [ -z "$(kv_get net.org)" ] && kv_set net.org "$(jget "$j2" '.org')"
      [ -z "$(kv_get net.city)" ] && kv_set net.city "$(jget "$j2" '.city')"
      kv_set net.ipinfo_org "$(jget "$j2" '.org')"
    fi
  fi

  local loc
  loc="$(trim "$(kv_get net.country) $(kv_get net.region) $(kv_get net.city)")"
  kv_set net.location "${loc:-未知}"

  log_ok "出口 IPv4: $(kv_or net.ip4 '无')   IPv6: $(kv_or net.ip6 '无')"
  log_ok "归属: $(kv_get net.location) / $(kv_or net.as '未知')"
  log_ok "运营商: $(kv_or net.isp '未知')"
}
