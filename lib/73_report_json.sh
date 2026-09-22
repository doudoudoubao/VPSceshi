#!/usr/bin/env bash
# ============================================================
# 73_report_json.sh — JSON（机器可读）与纯文本报告
# ============================================================

gen_json() {
  printf '{\n'
  printf '  "tool": {"name": "%s", "version": "%s", "repo": "%s"},\n' \
    "$VPSTEST_NAME" "$VPSTEST_VERSION" "$VPSTEST_REPO"

  # --- 单值区 ---
  printf '  "kv": {\n'
  local first=1 k
  for k in $(printf '%s\n' "${!KV[@]}" | sort); do
    [ "$first" = "1" ] || printf ',\n'
    first=0
    printf '    "%s": "%s"' "$(json_escape "$k")" "$(json_escape "${KV[$k]}")"
  done
  printf '\n  },\n'

  # --- 表格区 ---
  printf '  "tables": {\n'
  first=1
  for k in $(printf '%s\n' "${!ROWS[@]}" | sort); do
    [ "$first" = "1" ] || printf ',\n'
    first=0
    printf '    "%s": [' "$(json_escape "$k")"
    local rfirst=1 line
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      [ "$rfirst" = "1" ] || printf ','
      rfirst=0
      printf '\n      ['
      local ffirst=1 f
      row_split "$line"
      for f in "${ROW_F[@]}"; do
        [ "$ffirst" = "1" ] || printf ', '
        ffirst=0
        printf '"%s"' "$(json_escape "$f")"
      done
      printf ']'
    done <<< "${ROWS[$k]}"
    printf '\n    ]'
  done
  printf '\n  },\n'

  # --- 原始输出区 ---
  printf '  "raw": {\n'
  first=1
  if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
    for k in "${RAW_ORDER[@]}"; do
      [ "$first" = "1" ] || printf ',\n'
      first=0
      printf '    "%s": "%s"' "$(json_escape "$k")" "$(json_escape "${RAWS[$k]}")"
    done
  fi
  printf '\n  }\n'
  printf '}\n'
}

# ---------- 纯文本（终端友好 / 粘贴到任何地方） ----------
txt_line() { printf '%s\n' "----------------------------------------------------------------------"; }

txt_table() {
  local t="$1"; shift
  rows_have "$t" || return 0
  local line
  printf '%-30s' "$1"; shift
  local h
  for h in "$@"; do printf '%-22s' "$h"; done
  printf '\n'
  txt_line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local first=1 f
    row_split "$line"
    for f in "${ROW_F[@]}"; do
      if [ "$first" = "1" ]; then printf '%-30s' "$f"; first=0
      else printf '%-22s' "$f"; fi
    done
    printf '\n'
  done <<< "$(rows_get "$t")"
  printf '\n'
}

txt_kv() { printf ' %-14s : %s\n' "$1" "$2"; }

txt_na() {
  local key="$1"
  na_has "$key" || return 1
  printf ' [!] %s\n\n' "$(na_get "$key")"
  return 0
}

gen_txt() {
  local title; title="$(kv_or meta.node_name "$(kv_get sys.cpu.model)")"
  txt_line
  printf ' %s 服务器测评报告\n' "$title"
  printf ' 测试时间: %s\n' "$(kv_get meta.time_local)"
  printf ' 出口位置: %s | %s\n' "$(kv_get net.location)" "$(kv_or net.as '未知 ASN')"
  printf ' 测试工具: %s v%s  %s\n' "$VPSTEST_NAME" "$VPSTEST_VERSION" "$VPSTEST_REPO"
  txt_line

  if rows_have score; then
    printf '\n[ 综合评分 ]  %s / 100  —  %s\n\n' "$(kv_get score.total)" "$(kv_get score.grade)"
    txt_table score "评分项" "得分" "满分"
  fi

  printf '\n[ 一、基本配置核对 ]\n'
  rows_have profile_base && txt_table profile_base "项目" "内容"
  txt_table profile_cmp "项目" "宣传值" "实测值" "核对"

  printf '[ 二、性能与硬件检测 ]\n'
  txt_kv "CPU 型号"        "$(kv_get sys.cpu.model)"
  txt_kv "CPU 核心数"      "$(kv_get sys.cpu.cores) 核"
  txt_kv "CPU 频率"        "$(kv_get sys.cpu.freq)"
  txt_kv "CPU 缓存"        "$(kv_get sys.cpu.cache)"
  txt_kv "AES-NI"          "$(kv_get sys.cpu.aes)"
  txt_kv "硬件虚拟化"      "$(kv_get sys.cpu.virt)"
  txt_kv "内存总量"        "$(kv_get sys.mem.total)"
  txt_kv "内存可用"        "$(kv_get sys.mem.avail)"
  txt_kv "内存 Buff"       "$(kv_get sys.mem.buff)"
  txt_kv "Swap"            "$(kv_get sys.swap.summary)"
  txt_kv "硬盘空间"        "$(kv_get sys.disk.summary) ($(kv_get sys.disk.fs))"
  txt_kv "操作系统"        "$(kv_get sys.os)"
  txt_kv "内核版本"        "$(kv_get sys.kernel)"
  txt_kv "虚拟化类型"      "$(kv_get sys.virt)"
  txt_kv "TCP 加速"        "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  txt_kv "协议栈"          "$(kv_get net.stack)"
  printf '\n'
  rows_have cpu      && txt_table cpu "CPU 测试项" "结果"
  [ -n "$(kv_get cpu.gb6.link)" ] && printf ' Geekbench 6 结果: %s\n\n' "$(kv_get cpu.gb6.link)"
  rows_have memory   && txt_table memory "内存测试项" "结果"
  rows_have disk_dd  && txt_table disk_dd "磁盘 dd 块大小" "写入" "读取"
  rows_have disk_fio && txt_table disk_fio "磁盘 fio 块大小" "读取" "写入" "合计"

  printf '[ 三、去程延迟测试（国内 -> VPS）]\n'
  if rows_have inbound_isp; then
    printf ' 样本总数: %s  整体均值: %s ms\n\n' "$(kv_or inbound.samples 'N/A')" "$(kv_or inbound.avg 'N/A')"
    txt_table inbound_isp "运营商" "样本数" "平均" "最低" "最高"
    rows_have inbound_region && txt_table inbound_region "大区" "样本数" "平均" "最低" "最高"
    rows_have inbound_raw && txt_table inbound_raw "节点" "运营商" "省份" "大区" "延迟"
  else
    txt_na inbound_isp || printf ' 本节未测试。\n\n'
  fi

  printf '[ 四、去程路由测试（IPIP）]\n'
  if rows_have inbound_route; then
    txt_table inbound_route "探针节点" "线路识别"
    [ -n "$(kv_get inbound.route_verdict)" ] && printf ' 去程线路结论: %s\n\n' "$(kv_get inbound.route_verdict)"
  else
    txt_na inbound_route || printf ' 本节未测试。\n\n'
  fi

  printf '[ 五、去程 MTR ]\n'
  if [ -n "$(kv_get inbound.mtr)" ]; then
    printf ' 去程 MTR 原始数据已导入，见文末原始结果归档。\n\n'
  else
    txt_na inbound_mtr || printf ' 本节未测试。\n\n'
  fi

  printf '[ 六、回程网络质量（NetQuality）]\n'
  if rows_have nq_bgp; then txt_table nq_bgp "BGP 项目" "内容"; else txt_na nq_bgp; fi
  rows_have nq_peer  && txt_table nq_peer "上游/对等" "内容"
  rows_have nq_ixp   && txt_table nq_ixp "交换点 IXP" "端口速率"
  rows_have nq_local && txt_table nq_local "本地策略" "内容"
  if rows_have mtr_out; then
    txt_table mtr_out "回程 MTR 目标" "IP" "丢包" "平均" "最优/最差" "抖动"
  else
    txt_na mtr_out
  fi

  printf '[ 七、回程路由测试（NextTrace）]\n'
  if rows_have route; then
    txt_table route "目标" "IP" "线路识别"
    [ -n "$(kv_get route.verdict)" ] && printf ' 回程线路结论: %s\n\n' "$(kv_get route.verdict)"
  else
    txt_na route || printf ' 本节未测试。\n\n'
  fi

  printf '[ 八、网络测速 ]\n'
  if rows_have iperf; then txt_table iperf "国际节点 iperf3" "下载" "上传" "延迟"; else txt_na iperf; fi
  rows_have speed_auto && txt_table speed_auto "就近节点" "下载" "上传" "延迟" "抖动" "服务器"
  rows_have speed_gl   && txt_table speed_gl "国际节点" "下载" "上传" "延迟" "抖动" "服务器"
  if rows_have speed_cn; then
    txt_table speed_cn "国内三网" "下载" "上传" "延迟" "抖动" "服务器"
  else
    txt_na speed_cn || printf ' 本节未测试。\n\n'
  fi
  rows_have ping_cn && { printf ' 回程延迟 · 国内三网（均值 %s ms）\n' "$(kv_or ping.cn.avg 'N/A')"
                         txt_table ping_cn "节点" "线路" "延迟" "丢包"; }
  rows_have ping_gl && { printf ' 回程延迟 · 全球节点（均值 %s ms）\n' "$(kv_or ping.global.avg 'N/A')"
                         txt_table ping_gl "节点" "区域" "延迟" "丢包"; }

  printf '[ 九、流媒体与在线服务解锁 ]\n'
  rows_have unlock_net && txt_table unlock_net "网络识别" "内容"
  if rows_have unlock4; then
    printf ' IPv4 通过率 %s — 可用 %s / 不可用 %s / 待确认 %s / 难归类 %s\n\n' \
      "$(kv_or unlock.v4.summary 'N/A')" "$(kv_or unlock4.ok 0)" "$(kv_or unlock4.no 0)" \
      "$(kv_or unlock4.err 0)" "$(kv_or unlock4.misc 0)"
    txt_table unlock4 "服务" "结果"
  fi
  if rows_have unlock6; then
    printf ' IPv6 通过率 %s\n\n' "$(kv_or unlock.v6.summary 'N/A')"
    txt_table unlock6 "服务" "结果"
  fi

  printf '[ 十、IP 质量检测 ]\n'
  rows_have ipq_base   && txt_table ipq_base "项目" "内容"
  rows_have ipq_native && txt_table ipq_native "原生/广播" "结果"
  rows_have ipq_type   && txt_table ipq_type "IP 类型" "结果"
  rows_have ipq_risk   && txt_table ipq_risk "风险评分" "结果"
  rows_have ipq_rbl    && { printf ' 黑名单汇总: %s\n' "$(kv_get ipq.rbl_summary)"
                            txt_table ipq_rbl "黑名单库" "级别" "状态"; }
  rows_have ipq_port   && txt_table ipq_port "端口/连通性" "结果"
  [ -n "$(kv_get ipq.native)" ] && printf ' 综合判断: %s — %s\n\n' \
    "$(kv_get ipq.native)" "$(kv_get ipq.native_reason)"

  printf '[ 十一、适用场景与购买建议 ]\n'
  rows_have fit_yes && txt_table fit_yes "适合的场景" "依据"
  rows_have fit_no  && txt_table fit_no "不适合的场景" "依据"
  rows_have buy     && txt_table buy "购买建议" "内容"
  rows_have faq     && txt_table faq "FAQ" "回答"

  printf '[ 十二、原始结果归档 ]\n'
  printf ' 测试时间: %s (%s)\n' "$(kv_get meta.time_local)" "$(kv_get meta.time_utc)"
  printf ' 总耗时:   %s\n' "$(kv_or meta.duration '未记录')"
  printf ' 依赖情况: %s\n' "$(kv_or meta.deps '未记录')"
  if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
    local k
    for k in "${RAW_ORDER[@]}"; do
      printf '\n--- %s ---\n%s\n' "$k" "${RAWS[$k]}"
    done
  else
    printf ' 本次未产生可归档的原始输出。\n'
  fi

  printf '\n'
  txt_line
  printf ' 由 %s v%s 自动采集整理 — %s\n' "$VPSTEST_NAME" "$VPSTEST_VERSION" "$VPSTEST_REPO"
  txt_line
}
