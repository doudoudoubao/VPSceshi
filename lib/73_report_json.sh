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

  printf '\n[ 一、系统与硬件信息 ]\n'
  txt_kv "CPU 型号"   "$(kv_get sys.cpu.model)"
  txt_kv "CPU 核心数" "$(kv_get sys.cpu.cores) 核"
  txt_kv "CPU 频率"   "$(kv_get sys.cpu.freq)"
  txt_kv "CPU 缓存"   "$(kv_get sys.cpu.cache)"
  txt_kv "AES-NI"     "$(kv_get sys.cpu.aes)"
  txt_kv "硬件虚拟化" "$(kv_get sys.cpu.virt)"
  txt_kv "内存"       "$(kv_get sys.mem.summary)"
  txt_kv "Swap"       "$(kv_get sys.swap.summary)"
  txt_kv "硬盘空间"   "$(kv_get sys.disk.summary) ($(kv_get sys.disk.fs))"
  txt_kv "操作系统"   "$(kv_get sys.os)"
  txt_kv "内核版本"   "$(kv_get sys.kernel)"
  txt_kv "虚拟化架构" "$(kv_get sys.virt)"
  txt_kv "TCP 加速"   "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  txt_kv "协议栈"     "$(kv_get net.stack)"
  printf '\n'

  rows_have cpu      && { printf '[ 二、CPU 性能 ]\n';      txt_table cpu "测试项" "结果"; }
  rows_have memory   && { printf '[ 三、内存性能 ]\n';      txt_table memory "测试项" "结果"; }
  rows_have disk_dd  && { printf '[ 四、磁盘顺序读写 ]\n';  txt_table disk_dd "块大小×数量" "写入" "读取"; }
  rows_have disk_fio && { printf '[ 四、磁盘随机读写 ]\n';  txt_table disk_fio "块大小" "读取" "写入" "合计"; }
  rows_have ipq_base && { printf '[ 五、IP 基础画像 ]\n';   txt_table ipq_base "项目" "内容"; }
  rows_have ipq_type && { printf '[ 五、IP 类型判定 ]\n';   txt_table ipq_type "检测项" "结果"; }
  rows_have ipq_risk && { printf '[ 五、风险与信誉 ]\n';    txt_table ipq_risk "检测项" "结果"; }
  rows_have ipq_rbl  && { printf '[ 五、邮件黑名单 ] %s\n' "$(kv_get ipq.rbl_summary)"
                          txt_table ipq_rbl "黑名单库" "状态"; }
  rows_have ipq_port && { printf '[ 五、端口与连通性 ]\n';  txt_table ipq_port "检测项" "结果"; }
  rows_have unlock4  && { printf '[ 六、IPv4 解锁 ] 通过率 %s\n' "$(kv_or unlock.v4.summary 'N/A')"
                          txt_table unlock4 "服务" "结果"; }
  rows_have unlock6  && { printf '[ 六、IPv6 解锁 ] 通过率 %s\n' "$(kv_or unlock.v6.summary 'N/A')"
                          txt_table unlock6 "服务" "结果"; }
  rows_have ping_cn  && { printf '[ 七、国内三网延迟 ] 均值 %s ms\n' "$(kv_or ping.cn.avg 'N/A')"
                          txt_table ping_cn "节点" "线路" "延迟" "丢包"; }
  rows_have ping_gl  && { printf '[ 七、全球节点延迟 ] 均值 %s ms\n' "$(kv_or ping.global.avg 'N/A')"
                          txt_table ping_gl "节点" "区域" "延迟" "丢包"; }
  rows_have speed_auto && { printf '[ 八、就近节点测速 ]\n'; txt_table speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  rows_have speed_cn   && { printf '[ 八、国内三网测速 ]\n'; txt_table speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  rows_have speed_gl   && { printf '[ 八、国际节点测速 ]\n'; txt_table speed_gl "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  rows_have route      && { printf '[ 九、三网回程路由 ]\n'; txt_table route "目标" "IP" "线路判定"; }

  if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
    printf '\n[ 路由追踪原始输出 ]\n'
    local k
    for k in "${RAW_ORDER[@]}"; do
      printf '\n--- %s ---\n%s\n' "$k" "${RAWS[$k]}"
    done
  fi

  txt_line
  printf ' 总耗时: %s | 依赖: %s\n' "$(kv_or meta.duration '未记录')" "$(kv_or meta.deps '未记录')"
  txt_line
}
