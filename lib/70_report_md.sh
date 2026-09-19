#!/usr/bin/env bash
# ============================================================
# 70_report_md.sh — Markdown 报告（适配博客 / GitHub / Hexo）
# ============================================================

# md_table <表名> <表头1> <表头2> ...
md_table() {
  local t="$1"; shift
  rows_have "$t" || return 0
  local h sep
  h="|"; sep="|"
  for h2 in "$@"; do h="$h $h2 |"; sep="$sep :--- |"; done
  printf '%s\n%s\n' "$h" "$sep"
  local line f
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    printf '|'
    for f in "${ROW_F[@]}"; do printf ' %s |' "${f//|/\\|}"; done
    printf '\n'
  done <<< "$(rows_get "$t")"
  printf '\n'
}

md_kv_row() { printf '| %s | %s |\n' "$1" "$2"; }

gen_markdown() {
  local title
  title="$(kv_or meta.node_name "$(kv_get sys.cpu.model)")"

  cat <<EOF
# ${title} 服务器测评报告

> 测试时间：**$(kv_get meta.time_local)**（$(kv_get meta.time_utc)）
> 测试工具：[${VPSTEST_NAME} v${VPSTEST_VERSION}](${VPSTEST_REPO})
> 出口位置：$(kv_get net.location) · $(kv_or net.as '未知 ASN')

---

## 📊 综合评分

EOF

  if rows_have score; then
    printf '**总分：%s / 100 —— %s**\n\n' "$(kv_get score.total)" "$(kv_get score.grade)"
    md_table score "评分项" "得分" "满分"
  fi

  cat <<EOF
---

## 一、系统与硬件信息

| 项目 | 内容 |
| :--- | :--- |
EOF
  md_kv_row "CPU 型号"    "$(kv_get sys.cpu.model)"
  md_kv_row "CPU 核心数"  "$(kv_get sys.cpu.cores) 核"
  md_kv_row "CPU 频率"    "$(kv_get sys.cpu.freq)"
  md_kv_row "CPU 缓存"    "$(kv_get sys.cpu.cache)"
  md_kv_row "AES-NI"      "$(kv_get sys.cpu.aes)"
  md_kv_row "硬件虚拟化"  "$(kv_get sys.cpu.virt)"
  md_kv_row "内存"        "$(kv_get sys.mem.summary)"
  md_kv_row "Swap"        "$(kv_get sys.swap.summary)"
  md_kv_row "硬盘空间"    "$(kv_get sys.disk.summary)"
  md_kv_row "文件系统"    "$(kv_get sys.disk.fs)"
  md_kv_row "操作系统"    "$(kv_get sys.os)"
  md_kv_row "系统架构"    "$(kv_get sys.arch)"
  md_kv_row "内核版本"    "$(kv_get sys.kernel)"
  md_kv_row "虚拟化架构"  "$(kv_get sys.virt)"
  md_kv_row "TCP 加速"    "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  md_kv_row "协议栈"      "$(kv_get net.stack)"
  md_kv_row "系统负载"    "$(kv_get sys.load)"
  md_kv_row "运行时间"    "$(kv_get sys.uptime)"
  printf '\n'

  if rows_have cpu; then
    printf -- '---\n\n## 二、CPU 性能测试\n\n'
    md_table cpu "测试项" "结果"
    [ -n "$(kv_get cpu.sysbench.scale)" ] &&
      printf '> 多核扩展比：**%s**（理想值接近核心数）\n\n' "$(kv_get cpu.sysbench.scale)"
  fi

  if rows_have memory; then
    printf -- '---\n\n## 三、内存性能测试\n\n'
    md_table memory "测试项" "结果"
  fi

  if rows_have disk_dd || rows_have disk_fio; then
    printf -- '---\n\n## 四、磁盘 I/O 测试\n\n'
    if rows_have disk_dd; then
      printf '### 4.1 顺序读写（dd）\n\n'
      md_table disk_dd "块大小 × 数量" "写入速度" "读取速度"
    fi
    if rows_have disk_fio; then
      printf '### 4.2 随机读写（fio · 混合读写 iodepth=64）\n\n'
      md_table disk_fio "块大小" "读取" "写入" "合计"
    fi
  fi

  if rows_have ipq_base; then
    printf -- '---\n\n## 五、IP 质量体检\n\n'
    printf '### 5.1 基础画像\n\n'
    md_table ipq_base "项目" "内容"
    if rows_have ipq_type; then
      printf '### 5.2 IP 类型判定\n\n'
      md_table ipq_type "检测项" "结果"
    fi
    if rows_have ipq_risk; then
      printf '### 5.3 风险与信誉\n\n'
      md_table ipq_risk "检测项" "结果"
    fi
    if rows_have ipq_rbl; then
      printf '### 5.4 邮件黑名单（DNSBL）\n\n'
      printf '> 汇总：**%s**\n\n' "$(kv_get ipq.rbl_summary)"
      md_table ipq_rbl "黑名单库" "状态"
    fi
    if rows_have ipq_port; then
      printf '### 5.5 出站端口与连通性\n\n'
      md_table ipq_port "检测项" "结果"
    fi
  fi

  if rows_have unlock4 || rows_have unlock6; then
    printf -- '---\n\n## 六、流媒体 / AI 服务解锁\n\n'
    if rows_have unlock4; then
      printf '### 6.1 IPv4 解锁（通过率 %s）\n\n' "$(kv_or unlock.v4.summary 'N/A')"
      md_table unlock4 "服务" "结果"
      [ -n "$(kv_get unlock.v4.ytcdn)" ] &&
        printf '> YouTube CDN 节点：**%s**\n\n' "$(kv_get unlock.v4.ytcdn)"
    fi
    if rows_have unlock6; then
      printf '### 6.2 IPv6 解锁（通过率 %s）\n\n' "$(kv_or unlock.v6.summary 'N/A')"
      md_table unlock6 "服务" "结果"
    fi
  fi

  if rows_have ping_cn || rows_have ping_gl; then
    printf -- '---\n\n## 七、延迟与丢包\n\n'
    if rows_have ping_cn; then
      printf '### 7.1 国内三网（均值 %s ms）\n\n' "$(kv_or ping.cn.avg 'N/A')"
      md_table ping_cn "节点" "线路" "平均延迟" "丢包率"
    fi
    if rows_have ping_gl; then
      printf '### 7.2 全球节点（均值 %s ms）\n\n' "$(kv_or ping.global.avg 'N/A')"
      md_table ping_gl "节点" "区域" "平均延迟" "丢包率"
    fi
  fi

  if rows_have speed_auto || rows_have speed_cn || rows_have speed_gl; then
    printf -- '---\n\n## 八、网络测速（Speedtest）\n\n'
    if rows_have speed_auto; then
      printf '### 8.1 就近节点\n\n'
      md_table speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"
    fi
    if rows_have speed_cn; then
      printf '### 8.2 国内三网节点\n\n'
      md_table speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"
    fi
    if rows_have speed_gl; then
      printf '### 8.3 国际节点\n\n'
      md_table speed_gl "节点" "下载" "上传" "延迟" "抖动" "服务器"
    fi
  fi

  if rows_have route; then
    printf -- '---\n\n## 九、三网回程路由\n\n'
    md_table route "目标" "IP" "线路判定"
    if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
      printf '<details>\n<summary>展开完整路由追踪原始输出</summary>\n\n'
      local k
      for k in "${RAW_ORDER[@]}"; do
        printf '**%s**\n\n```\n%s\n```\n\n' "$k" "${RAWS[$k]}"
      done
      printf '</details>\n\n'
    fi
  fi

  cat <<EOF
---

## 测试说明

- 测试环境：$(kv_get sys.os) / $(kv_get sys.kernel) / $(kv_get sys.virt)
- 依赖情况：$(kv_or meta.deps '未记录')
- 总耗时：$(kv_or meta.duration '未记录')
- 测速与路由结果受测试时段、对端节点负载影响，建议在不同时段多次复测取平均。
- 本报告由 [${VPSTEST_NAME}](${VPSTEST_REPO}) 一键脚本自动生成。

\`\`\`bash
bash <(curl -sL ${VPSTEST_REPO}/raw/main/dist/vpstest.sh)
\`\`\`
EOF
}
