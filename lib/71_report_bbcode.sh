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

  bb_h "一、系统与硬件信息"
  printf '[table]\n'
  bb_kv "CPU 型号"   "$(kv_get sys.cpu.model)"
  bb_kv "CPU 核心数" "$(kv_get sys.cpu.cores) 核"
  bb_kv "CPU 频率"   "$(kv_get sys.cpu.freq)"
  bb_kv "CPU 缓存"   "$(kv_get sys.cpu.cache)"
  bb_kv "AES-NI"     "$(kv_get sys.cpu.aes)"
  bb_kv "硬件虚拟化" "$(kv_get sys.cpu.virt)"
  bb_kv "内存"       "$(kv_get sys.mem.summary)"
  bb_kv "Swap"       "$(kv_get sys.swap.summary)"
  bb_kv "硬盘空间"   "$(kv_get sys.disk.summary)（$(kv_get sys.disk.fs)）"
  bb_kv "操作系统"   "$(kv_get sys.os)"
  bb_kv "内核版本"   "$(kv_get sys.kernel)"
  bb_kv "虚拟化架构" "$(kv_get sys.virt)"
  bb_kv "TCP 加速"   "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  bb_kv "协议栈"     "$(kv_get net.stack)"
  printf '[/table]\n\n'

  if rows_have cpu; then
    bb_h "二、CPU 性能测试"
    bb_table cpu "测试项" "结果"
  fi

  if rows_have memory; then
    bb_h "三、内存性能测试"
    bb_table memory "测试项" "结果"
  fi

  if rows_have disk_dd || rows_have disk_fio; then
    bb_h "四、磁盘 I/O 测试"
    rows_have disk_dd  && { bb_h2 "顺序读写（dd）";   bb_table disk_dd "块大小 × 数量" "写入" "读取"; }
    rows_have disk_fio && { bb_h2 "随机读写（fio）"; bb_table disk_fio "块大小" "读取" "写入" "合计"; }
  fi

  if rows_have ipq_base; then
    bb_h "五、IP 质量体检"
    bb_table ipq_base "项目" "内容"
    rows_have ipq_type && { bb_h2 "IP 类型判定"; bb_table ipq_type "检测项" "结果"; }
    rows_have ipq_risk && { bb_h2 "风险与信誉"; bb_table ipq_risk "检测项" "结果"; }
    if rows_have ipq_rbl; then
      bb_h2 "邮件黑名单（$(kv_get ipq.rbl_summary)）"
      bb_table ipq_rbl "黑名单库" "状态"
    fi
    rows_have ipq_port && { bb_h2 "出站端口与连通性"; bb_table ipq_port "检测项" "结果"; }
  fi

  if rows_have unlock4 || rows_have unlock6; then
    bb_h "六、流媒体 / AI 解锁"
    if rows_have unlock4; then
      bb_h2 "IPv4（通过率 $(kv_or unlock.v4.summary 'N/A')）"
      bb_table unlock4 "服务" "结果"
    fi
    if rows_have unlock6; then
      bb_h2 "IPv6（通过率 $(kv_or unlock.v6.summary 'N/A')）"
      bb_table unlock6 "服务" "结果"
    fi
  fi

  if rows_have ping_cn || rows_have ping_gl; then
    bb_h "七、延迟与丢包"
    rows_have ping_cn && {
      bb_h2 "国内三网（均值 $(kv_or ping.cn.avg 'N/A') ms）"
      bb_table ping_cn "节点" "线路" "平均延迟" "丢包率"; }
    rows_have ping_gl && {
      bb_h2 "全球节点（均值 $(kv_or ping.global.avg 'N/A') ms）"
      bb_table ping_gl "节点" "区域" "平均延迟" "丢包率"; }
  fi

  if rows_have speed_auto || rows_have speed_cn || rows_have speed_gl; then
    bb_h "八、网络测速"
    rows_have speed_auto && bb_table speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"
    rows_have speed_cn   && { bb_h2 "国内三网"; bb_table speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
    rows_have speed_gl   && { bb_h2 "国际节点"; bb_table speed_gl "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  fi

  if rows_have route; then
    bb_h "九、三网回程路由"
    bb_table route "目标" "IP" "线路判定"
    if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
      local k
      for k in "${RAW_ORDER[@]}"; do
        printf '[b]%s[/b]\n[code]%s[/code]\n' "$k" "${RAWS[$k]}"
      done
      printf '\n'
    fi
  fi

  printf '[hr]\n'
  printf '[color=#888]测试环境：%s / %s / %s ｜ 总耗时：%s[/color]\n' \
    "$(kv_get sys.os)" "$(kv_get sys.kernel)" "$(kv_get sys.virt)" "$(kv_or meta.duration '未记录')"
  printf '[color=#888]本报告由 [url=%s]%s v%s[/url] 一键脚本生成：[/color]\n' \
    "$VPSTEST_REPO" "$VPSTEST_NAME" "$VPSTEST_VERSION"
  printf '[code]bash <(curl -sL %s/raw/main/dist/vpstest.sh)[/code]\n' "$VPSTEST_REPO"
}
