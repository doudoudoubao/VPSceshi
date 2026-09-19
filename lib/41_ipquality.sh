#!/usr/bin/env bash
# ============================================================
# 41_ipquality.sh — IP 质量体检：欺诈分、IP 类型、黑名单、端口
# ============================================================

_yn() { case "$1" in true|1|yes|Yes|YES) printf '是';; false|0|no|No|NO|"") printf '否';; *) printf '%s' "$1";; esac; }

# TCP 端口连通性（不依赖 nc）
_port_open() {
  local host="$1" port="$2" to="${3:-5}"
  if have timeout; then
    timeout "$to" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null && return 0 || return 1
  else
    (exec 3<>/dev/tcp/"$host"/"$port") 2>/dev/null && return 0 || return 1
  fi
}

# DNSBL 黑名单查询
_rbl_check() {
  local ip="$1" rbl="$2" rev
  rev="$(printf '%s' "$ip" | awk -F. '{print $4"."$3"."$2"."$1}')"
  local q="${rev}.${rbl}"
  local r=""
  if have dig; then
    r="$(run_to 6 dig +short +time=3 +tries=1 A "$q" 2>/dev/null | head -1)"
  elif have host; then
    r="$(run_to 6 host -t A "$q" 2>/dev/null | grep -m1 'has address' | awk '{print $NF}')"
  elif have nslookup; then
    r="$(run_to 6 nslookup -type=A "$q" 2>/dev/null | grep -A2 'Name:' | grep -m1 'Address' | awk '{print $NF}')"
  else
    printf 'SKIP'; return
  fi
  case "$r" in 127.0.0.*) printf 'LISTED' ;; *) printf 'CLEAN' ;; esac
}

test_ipquality() {
  module_enabled ipquality || { log_info "跳过 IP 质量体检"; return 0; }
  step "IP 质量体检"

  if [ -z "$IP4" ]; then
    log_warn "无 IPv4 出口，跳过 IP 质量体检"
    return 0
  fi

  # ---------- 1. 基础画像 ----------
  row_add ipq_base "IP 地址" "$(kv_get net.ip4)"
  row_add ipq_base "ASN" "$(kv_or net.as '未知')"
  row_add ipq_base "归属组织" "$(kv_or net.org '未知')"
  row_add ipq_base "运营商 ISP" "$(kv_or net.isp '未知')"
  row_add ipq_base "地理位置" "$(kv_get net.location)"
  row_add ipq_base "反向解析 PTR" "$(kv_or net.rdns '无')"
  row_add ipq_base "时区" "$(kv_or net.tz '未知')"

  # ---------- 2. IP 类型判定 ----------
  inline "IP 类型判定 ..."
  local usetype="未知" company="" abuser=""
  local j; j="$(xcurl4 "https://api.ipapi.is/?q=${IP4}")"
  if [ -n "$j" ]; then
    local is_dc is_proxy is_vpn is_tor is_abuser is_crawler asn_type
    is_dc="$(jget "$j" '.is_datacenter')"; is_proxy="$(jget "$j" '.is_proxy')"
    is_vpn="$(jget "$j" '.is_vpn')";       is_tor="$(jget "$j" '.is_tor')"
    is_abuser="$(jget "$j" '.is_abuser')"; is_crawler="$(jget "$j" '.is_crawler')"
    asn_type="$(jget "$j" '.asn.type')"
    company="$(jget "$j" '.company.name')"
    abuser="$(jget "$j" '.company.abuser_score')"
    case "$asn_type" in
      hosting|isp|business|education|government) usetype="$asn_type" ;;
    esac
    row_add ipq_type "IDC / 机房 IP"   "$(_yn "$is_dc")"
    row_add ipq_type "代理 Proxy"      "$(_yn "$is_proxy")"
    row_add ipq_type "VPN"             "$(_yn "$is_vpn")"
    row_add ipq_type "Tor 出口节点"    "$(_yn "$is_tor")"
    row_add ipq_type "滥用记录 Abuser" "$(_yn "$is_abuser")"
    row_add ipq_type "爬虫 Crawler"    "$(_yn "$is_crawler")"
    [ -n "$asn_type" ] && row_add ipq_type "ASN 类型" "$asn_type"
    [ -n "$company" ]  && row_add ipq_type "注册公司" "$company"
    [ -n "$abuser" ]   && row_add ipq_type "滥用评分" "$abuser（越低越好）"
    kv_set ipq.datacenter "$(_yn "$is_dc")"
  fi
  # ip-api 的补充标记
  [ -n "$(kv_get net.flag_proxy)" ] &&
    row_add ipq_type "ip-api 代理标记" "$(_yn "$(kv_get net.flag_proxy)")"
  [ -n "$(kv_get net.flag_hosting)" ] &&
    row_add ipq_type "ip-api 托管标记" "$(_yn "$(kv_get net.flag_hosting)")"
  inline_done "$usetype"
  kv_set ipq.usetype "$usetype"

  # ---------- 3. 欺诈分 / 风险分 ----------
  inline "Scamalytics 欺诈分 ..."
  local html score risk
  html="$(xcurl4 "https://scamalytics.com/ip/${IP4}")"
  if [ -n "$html" ]; then
    score="$(printf '%s' "$html" | grep -o 'Fraud Score: *[0-9]*' | head -1 | grep -Eo '[0-9]+')"
    risk="$(printf '%s' "$html" | grep -o '"risk":"[^"]*"' | head -1 | cut -d'"' -f4)"
    [ -z "$risk" ] && risk="$(printf '%s' "$html" | grep -oE '(Low|Medium|High|Very High) Risk' | head -1)"
  fi
  inline_done "${score:-N/A}"
  if [ -n "$score" ]; then
    kv_set ipq.scamalytics "$score"
    local lvl="低风险"
    [ "$score" -ge 25 ] 2>/dev/null && lvl="中风险"
    [ "$score" -ge 50 ] 2>/dev/null && lvl="高风险"
    [ "$score" -ge 75 ] 2>/dev/null && lvl="极高风险"
    row_add ipq_risk "Scamalytics 欺诈分" "$score / 100（$lvl）"
  fi
  [ -n "$risk" ] && row_add ipq_risk "Scamalytics 风险等级" "$risk"

  # AbuseIPDB 公开页面（无 key 时抓取概要）
  inline "AbuseIPDB 举报记录 ..."
  local ab conf
  ab="$(xcurl4 -H 'Accept: text/html' "https://www.abuseipdb.com/check/${IP4}")"
  if [ -n "$ab" ]; then
    conf="$(printf '%s' "$ab" | grep -o 'Confidence of Abuse[^%]*%' | grep -Eo '[0-9]+%' | head -1)"
  fi
  inline_done "${conf:-N/A}"
  [ -n "$conf" ] && { kv_set ipq.abuseipdb "$conf"; row_add ipq_risk "AbuseIPDB 滥用置信度" "$conf"; }

  # Cloudflare 边缘信息（判断走哪个 POP，间接体现线路）
  local cf; cf="$(xcurl4 "https://www.cloudflare.com/cdn-cgi/trace")"
  if [ -n "$cf" ]; then
    local colo loc
    colo="$(printf '%s' "$cf" | grep -m1 '^colo=' | cut -d= -f2)"
    loc="$(printf '%s' "$cf" | grep -m1 '^loc=' | cut -d= -f2)"
    [ -n "$colo" ] && { kv_set ipq.cf_colo "$colo"; row_add ipq_risk "Cloudflare 接入 POP" "$colo（国家判定: ${loc:-N/A}）"; }
  fi

  # ---------- 4. 原生 / 广播判定 ----------
  # 判据：IP 段的注册国（RDAP）与实际地理定位国是否一致。
  # 一致 = 原生 IP；不一致 = 该段在别处注册、广播到当前位置使用。
  inline "原生 / 广播判定 ..."
  local reg_cc geo_cc verdict reason
  reg_cc="$(kv_get nq.rdap_cc)"
  geo_cc="$(kv_get net.cc)"
  if [ -z "$reg_cc" ] || [ -z "$geo_cc" ]; then
    verdict="⚠️ 无法判定"
    reason="缺少注册国或定位国信息"
  elif [ "$reg_cc" = "$geo_cc" ]; then
    verdict="✅ 原生 IP"
    reason="注册地 ${reg_cc} 与定位地 ${geo_cc} 一致"
  else
    verdict="📡 广播 IP"
    reason="注册地 ${reg_cc}，实际广播/定位在 ${geo_cc}"
  fi
  inline_done "$verdict"
  kv_set ipq.native "$verdict"
  kv_set ipq.native_reason "$reason"
  row_add ipq_native "IP 类型判定" "$verdict"
  row_add ipq_native "判定依据"   "$reason"
  [ -n "$reg_cc" ] && row_add ipq_native "注册国（RDAP）" "$reg_cc"
  [ -n "$geo_cc" ] && row_add ipq_native "定位国（GeoIP）" "$geo_cc"
  [ -n "$(kv_get nq.prefix)" ]    && row_add ipq_native "所属前缀" "$(kv_get nq.prefix)"
  [ -n "$(kv_get nq.rdap_name)" ] && row_add ipq_native "注册主体" "$(kv_get nq.rdap_name)"
  [ -n "$(kv_get nq.rir)" ]       && row_add ipq_native "注册局 RIR" "$(kv_get nq.rir)"

  # ---------- 5. 邮件黑名单 ----------
  # 分两档：主流黑名单命中影响大（黑名单），次级库命中记为「已标记」
  inline "DNSBL 黑名单检测 ..."
  local rbls_major=(
    "zen.spamhaus.org"
    "bl.spamcop.net"
    "b.barracudacentral.org"
    "cbl.abuseat.org"
  )
  local rbls_minor=(
    "dnsbl.sorbs.net"
    "spam.dnsbl.sorbs.net"
    "psbl.surriel.com"
    "dnsbl-1.uceprotect.net"
    "ubl.unsubscore.com"
    "all.s5h.net"
  )
  local blacklisted=0 flagged=0 clean=0 skipped=0 r rbl
  for rbl in "${rbls_major[@]}"; do
    r="$(_rbl_check "$IP4" "$rbl")"
    case "$r" in
      LISTED) blacklisted=$((blacklisted + 1)); row_add ipq_rbl "$rbl" "主流" "❌ 黑名单" ;;
      CLEAN)  clean=$((clean + 1));             row_add ipq_rbl "$rbl" "主流" "✅ 正常" ;;
      *)      skipped=$((skipped + 1)) ;;
    esac
  done
  for rbl in "${rbls_minor[@]}"; do
    r="$(_rbl_check "$IP4" "$rbl")"
    case "$r" in
      LISTED) flagged=$((flagged + 1)); row_add ipq_rbl "$rbl" "次级" "⚠️ 已标记" ;;
      CLEAN)  clean=$((clean + 1));     row_add ipq_rbl "$rbl" "次级" "✅ 正常" ;;
      *)      skipped=$((skipped + 1)) ;;
    esac
  done
  local valid=$(( clean + flagged + blacklisted ))
  inline_done "正常 ${clean} / 标记 ${flagged} / 黑名单 ${blacklisted}"
  kv_set ipq.rbl_listed "$(( blacklisted + flagged ))"
  kv_set ipq.rbl_black  "$blacklisted"
  kv_set ipq.rbl_flag   "$flagged"
  kv_set ipq.rbl_clean  "$clean"
  kv_set ipq.rbl_valid  "$valid"
  if [ "$valid" = "0" ]; then
    kv_set ipq.rbl_summary "未检测（缺少 dig/host 等解析工具）"
  else
    kv_set ipq.rbl_summary "有效 ${valid} 个 / 正常 ${clean} 个 / 已标记 ${flagged} 个 / 黑名单 ${blacklisted} 个"
  fi

  # ---------- 6. 端口与邮局 ----------
  inline "出站端口检测 ..."
  local p25 p465 p587
  _port_open "smtp.gmail.com" 25  6 && p25="✅ 放行"  || p25="❌ 封锁"
  _port_open "smtp.gmail.com" 465 6 && p465="✅ 放行" || p465="❌ 封锁"
  _port_open "smtp.gmail.com" 587 6 && p587="✅ 放行" || p587="❌ 封锁"
  inline_done "25:${p25%% *} 465:${p465%% *} 587:${p587%% *}"
  row_add ipq_port "TCP 25（SMTP 明文）"  "$p25"
  row_add ipq_port "TCP 465（SMTPS）"     "$p465"
  row_add ipq_port "TCP 587（Submission）" "$p587"
  kv_set ipq.port25 "$p25"

  # 常见服务连通性
  local svc
  for svc in "www.google.com:443:Google" "github.com:443:GitHub" \
             "registry.npmjs.org:443:npm" "hub.docker.com:443:DockerHub"; do
    local h="${svc%%:*}" rest="${svc#*:}" port="${rest%%:*}" name="${rest#*:}"
    if _port_open "$h" "$port" 5; then
      row_add ipq_port "$name ($h:$port)" "✅ 可达"
    else
      row_add ipq_port "$name ($h:$port)" "❌ 不可达"
    fi
  done

  log_ok "欺诈分 $(kv_or ipq.scamalytics 'N/A') | 黑名单 $(kv_get ipq.rbl_summary) | 25 端口 $p25"
}
