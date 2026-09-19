#!/usr/bin/env bash
# ============================================================
# 71_report_bbcode.sh — BBCode 报告（Discuz / hostloc / NodeSeek 等论坛）
# ============================================================

# 论坛里 emoji 表现不稳定，统一替换为纯文本标记
bb_plain() {
  local s="$*"
  s="${s//✅/[OK] }"; s="${s//❌/[NO] }"; s="${s//⚠️/[?] }"
  s="${s//✔/[Y] }";  s="${s//✘/[N] }"
  printf '%s' "$s"
}

bb_table() {
  local t="$1"; shift
  rows_have "$t" || return 0
  printf '[table]\n[tr]'
  local h
  for h in "$@"; do printf '[td][b]%s[/b][/td]' "$h"; done
  printf '[/tr]\n'
  local line f
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    printf '[tr]'
    for f in "${ROW_F[@]}"; do printf '[td]%s[/td]' "$(bb_plain "$f")"; done
    printf '[/tr]\n'
  done <<< "$(rows_get "$t")"
  printf '[/table]\n\n'
}

bb_h() { printf '[size=4][b][color=#2b6cb0]%s[/color][/b][/size]\n' "$*"; }
bb_h2() { printf '[b]%s[/b]\n' "$*"; }
bb_kv() { printf '[tr][td][b]%s[/b][/td][td]%s[/td][/tr]\n' "$1" "$(bb_plain "$2")"; }

# 章节未取得数据的提示
bb_na() {
  local key="$1"
  na_has "$key" || return 1
  printf '[color=#b45309][b]本次未取得有效数据：[/b]%s[/color]\n\n' "$(bb_plain "$(na_get "$key")")"
  return 0
}

gen_bbcode() {
  local title
  title="$(kv_or meta.node_name "$(kv_get sys.cpu.model)")"

  printf '[align=center][size=5][b]%s 服务器测评报告[/b][/size][/align]\n' "$title"
  printf '[align=center][color=#888]测试时间：%s ｜ 出口：%s ｜ %s[/color][/align]\n\n' \
    "$(kv_get meta.time_local)" "$(kv_get net.location)" "$(kv_or net.as '未知 ASN')"

  if rows_have score; then
    bb_h "综合评分"
    printf '[size=4][b][color=#c53030]总分：%s / 100 —— %s[/color][/b][/size]\n\n' \
      "$(kv_get score.total)" "$(kv_get score.grade)"
    bb_table score "评分项" "得分" "满分"
  fi

  # ===== 一、基本配置核对 =====
  bb_h "一、基本配置核对"
  if rows_have profile_base; then
    bb_h2 "商家与套餐"
    bb_table profile_base "项目" "内容"
  fi
  bb_h2 "宣传配置 vs 实测配置"
  bb_table profile_cmp "项目" "宣传值" "实测值" "核对"

  # ===== 二、性能与硬件 =====
  bb_h "二、性能与硬件检测"
  bb_h2 "系统与硬件信息"
  printf '[table]\n'
  bb_kv "CPU 型号"        "$(kv_get sys.cpu.model)"
  bb_kv "CPU 核心数"      "$(kv_get sys.cpu.cores) 核"
  bb_kv "CPU 频率"        "$(kv_get sys.cpu.freq)"
  bb_kv "CPU 缓存"        "$(kv_get sys.cpu.cache)"
  bb_kv "AES-NI"          "$(kv_get sys.cpu.aes)"
  bb_kv "硬件虚拟化"      "$(kv_get sys.cpu.virt)"
  bb_kv "内存总量"        "$(kv_get sys.mem.total)"
  bb_kv "内存可用"        "$(kv_get sys.mem.avail)"
  bb_kv "内存 Buff/Cache" "$(kv_get sys.mem.buff)"
  bb_kv "Swap"            "$(kv_get sys.swap.summary)"
  bb_kv "硬盘空间"        "$(kv_get sys.disk.summary)（$(kv_get sys.disk.fs)）"
  bb_kv "操作系统"        "$(kv_get sys.os)"
  bb_kv "内核版本"        "$(kv_get sys.kernel)"
  bb_kv "虚拟化类型"      "$(kv_get sys.virt)"
  bb_kv "TCP 加速"        "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  bb_kv "协议栈"          "$(kv_get net.stack)"
  printf '[/table]\n\n'
  rows_have cpu && { bb_h2 "CPU 性能"; bb_table cpu "测试项" "结果"; }
  [ -n "$(kv_get cpu.gb6.link)" ] &&
    printf 'Geekbench 6 完整结果：[url=%s]%s[/url]\n\n' "$(kv_get cpu.gb6.link)" "$(kv_get cpu.gb6.link)"
  rows_have memory   && { bb_h2 "内存性能"; bb_table memory "测试项" "结果"; }
  rows_have disk_dd  && { bb_h2 "磁盘顺序读写（dd）"; bb_table disk_dd "块大小 × 数量" "写入" "读取"; }
  rows_have disk_fio && { bb_h2 "磁盘随机读写（fio）"; bb_table disk_fio "块大小" "读取" "写入" "合计"; }

  # ===== 三、去程延迟 =====
  bb_h "三、去程延迟测试（国内 → VPS）"
  if rows_have inbound_isp; then
    [ -n "$(kv_get inbound.samples)" ] &&
      printf '样本总数：[b]%s[/b] 个，整体平均延迟：[b]%s ms[/b]\n\n' \
        "$(kv_get inbound.samples)" "$(kv_get inbound.avg)"
    bb_h2 "分运营商汇总"
    bb_table inbound_isp "运营商" "样本数" "平均延迟" "最低（最快节点）" "最高（最慢节点）"
    rows_have inbound_region && { bb_h2 "分大区汇总"
      bb_table inbound_region "大区" "样本数" "平均延迟" "最低" "最高"; }
    rows_have inbound_raw && { bb_h2 "各探针节点明细"
      bb_table inbound_raw "节点" "运营商" "省份/地区" "大区" "延迟"; }
  else
    bb_na inbound_isp
  fi

  # ===== 四、去程路由 =====
  bb_h "四、去程路由测试（IPIP 探针）"
  if rows_have inbound_route; then
    bb_table inbound_route "探针节点" "线路识别"
    [ -n "$(kv_get inbound.route_verdict)" ] &&
      printf '[b]去程线路结论：[/b]%s\n\n' "$(bb_plain "$(kv_get inbound.route_verdict)")"
  else
    bb_na inbound_route
  fi

  # ===== 五、去程 MTR =====
  bb_h "五、去程 MTR"
  if [ -n "$(kv_get inbound.mtr)" ]; then
    printf '去程 MTR 原始数据已导入，见文末原始结果归档。\n\n'
  else
    bb_na inbound_mtr
  fi

  # ===== 六、回程网络质量 =====
  bb_h "六、回程网络质量（NetQuality）"
  if rows_have nq_bgp; then
    bb_h2 "BGP 与注册信息"; bb_table nq_bgp "项目" "内容"
  else
    bb_na nq_bgp
  fi
  rows_have nq_peer  && { bb_h2 "上游与对等互联"; bb_table nq_peer "项目" "内容"; }
  rows_have nq_ixp   && { bb_h2 "互联网交换点 IXP"; bb_table nq_ixp "交换点" "端口速率"; }
  rows_have nq_local && { bb_h2 "本地网络策略"; bb_table nq_local "项目" "内容"; }
  if rows_have mtr_out; then
    bb_h2 "回程 MTR（丢包 / 抖动）"
    bb_table mtr_out "目标" "IP" "丢包率" "平均延迟" "最优 / 最差" "抖动"
  else
    bb_na mtr_out
  fi

  # ===== 七、回程路由 =====
  bb_h "七、回程路由测试（NextTrace 三网）"
  if rows_have route; then
    bb_table route "目标" "IP" "线路识别"
    [ -n "$(kv_get route.verdict)" ] &&
      printf '[b]回程线路结论：[/b]%s\n\n' "$(bb_plain "$(kv_get route.verdict)")"
  else
    bb_na route
  fi

  # ===== 八、网络测速 =====
  bb_h "八、网络测速"
  if rows_have iperf; then
    bb_h2 "国际节点带宽（iperf3）"; bb_table iperf "节点" "下载" "上传" "延迟"
  else
    bb_h2 "国际节点带宽（iperf3）"; bb_na iperf
  fi
  rows_have speed_auto && { bb_h2 "Speedtest 就近节点"
    bb_table speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  rows_have speed_gl && { bb_h2 "Speedtest 国际节点"
    bb_table speed_gl "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  bb_h2 "国内三网测速"
  if rows_have speed_cn; then
    bb_table speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"
  else
    printf '[color=#b45309][b]本次未取得有效数据：[/b]国内测速节点未返回有效结果。[/color]\n\n'
  fi
  rows_have ping_cn && { bb_h2 "回程延迟 · 国内三网（均值 $(kv_or ping.cn.avg 'N/A') ms）"
    bb_table ping_cn "节点" "线路" "平均延迟" "丢包率"; }
  rows_have ping_gl && { bb_h2 "回程延迟 · 全球节点（均值 $(kv_or ping.global.avg 'N/A') ms）"
    bb_table ping_gl "节点" "区域" "平均延迟" "丢包率"; }

  # ===== 九、流媒体解锁 =====
  bb_h "九、流媒体与在线服务解锁"
  rows_have unlock_net && { bb_h2 "网络识别"; bb_table unlock_net "项目" "内容"; }
  if rows_have unlock4; then
    bb_h2 "IPv4 结果（通过率 $(kv_or unlock.v4.summary 'N/A')）"
    printf '可用 [b]%s[/b] ｜ 不可用 [b]%s[/b] ｜ 待确认 [b]%s[/b] ｜ 难归类 [b]%s[/b]\n\n' \
      "$(kv_or unlock4.ok 0)" "$(kv_or unlock4.no 0)" "$(kv_or unlock4.err 0)" "$(kv_or unlock4.misc 0)"
    rows_have unlock4_ok   && { bb_h2 "可用";              bb_table unlock4_ok   "服务" "结果"; }
    rows_have unlock4_no   && { bb_h2 "不可用";            bb_table unlock4_no   "服务" "结果"; }
    rows_have unlock4_err  && { bb_h2 "失败 / 待确认";     bb_table unlock4_err  "服务" "结果"; }
    rows_have unlock4_misc && { bb_h2 "难归类（地区码 / CDN）"; bb_table unlock4_misc "服务" "结果"; }
  fi
  if rows_have unlock6; then
    bb_h2 "IPv6 结果（通过率 $(kv_or unlock.v6.summary 'N/A')）"
    bb_table unlock6 "服务" "结果"
  else
    bb_h2 "IPv6 结果"
    printf '%s\n\n' "$(kv_or unlock.v6.summary '本次未检测')"
  fi

  # ===== 十、IP 质量 =====
  bb_h "十、IP 质量检测"
  if rows_have ipq_base; then
    bb_table ipq_base "项目" "内容"
    rows_have ipq_native && { bb_h2 "原生 / 广播判定"; bb_table ipq_native "检测项" "结果"; }
    rows_have ipq_type   && { bb_h2 "IP 类型"; bb_table ipq_type "检测项" "结果"; }
    rows_have ipq_risk   && { bb_h2 "风险评分"; bb_table ipq_risk "检测项" "结果"; }
    rows_have ipq_rbl    && { bb_h2 "黑名单扫描（$(kv_get ipq.rbl_summary)）"
                              bb_table ipq_rbl "黑名单库" "级别" "状态"; }
    rows_have ipq_port   && { bb_h2 "出站端口与连通性"; bb_table ipq_port "检测项" "结果"; }
    printf '[b]综合判断：[/b]%s——%s\n\n' \
      "$(bb_plain "$(kv_or ipq.native '未判定')")" "$(bb_plain "$(kv_or ipq.native_reason '')")"
  fi

  # ===== 十一、适用场景与购买建议 =====
  bb_h "十一、适用场景与购买建议"
  rows_have fit_yes && { bb_h2 "适合的场景"; bb_table fit_yes "场景" "依据"; }
  rows_have fit_no  && { bb_h2 "不适合的场景"; bb_table fit_no "场景" "依据"; }
  rows_have buy     && { bb_h2 "价格与线路建议"; bb_table buy "项目" "内容"; }
  rows_have faq     && { bb_h2 "FAQ"; bb_table faq "问题" "回答"; }

  # ===== 十二、原始结果归档 =====
  bb_h "十二、原始结果归档"
  printf '测试时间：%s ｜ 总耗时：%s ｜ 采集工具：%s v%s\n\n' \
    "$(kv_get meta.time_local)" "$(kv_or meta.duration '未记录')" "$VPSTEST_NAME" "$VPSTEST_VERSION"
  if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
    local k
    for k in "${RAW_ORDER[@]}"; do
      printf '[b]%s[/b]\n[code]%s[/code]\n' "$k" "${RAWS[$k]}"
    done
    printf '\n'
  else
    printf '本次未产生可归档的原始输出。\n\n'
  fi

  printf '[hr]\n'
  printf '[color=#888]测试环境：%s / %s / %s｜去程章节需国内探针采集，未导入时标注为未取得[/color]\n' \
    "$(kv_get sys.os)" "$(kv_get sys.kernel)" "$(kv_get sys.virt)"
  printf '[color=#888]本报告由 [url=%s]%s v%s[/url] 一键脚本自动采集整理：[/color]\n' \
    "$VPSTEST_REPO" "$VPSTEST_NAME" "$VPSTEST_VERSION"
  printf '[code]bash <(curl -sL %s/raw/main/dist/vpstest.sh)[/code]\n' "$VPSTEST_REPO"
}
