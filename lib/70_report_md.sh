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

# 章节未取得数据时的提示块
md_na() {
  local key="$1"
  na_has "$key" || return 1
  printf '> ⚠️ **本次未取得有效数据**：%s\n\n' "$(na_get "$key")"
  return 0
}

# 有数据就出表，没数据但有说明就出提示
md_table_or_na() {
  local t="$1"; shift
  if rows_have "$t"; then md_table "$t" "$@"; else md_na "$t"; fi
}

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

  # ========== 一、基本配置核对 ==========
  printf -- '---\n\n## 一、基本配置核对\n\n'
  if rows_have profile_base; then
    printf '### 1.1 商家与套餐\n\n'
    md_table profile_base "项目" "内容"
  else
    printf '> 未提供商家/套餐/价格信息。重跑时加 `--config` 或 `--vendor/--plan/--dc/--price` 等参数即可补全本节。\n\n'
  fi
  printf '### 1.2 宣传配置 vs 实测配置\n\n'
  md_table profile_cmp "项目" "宣传值" "实测值" "核对"

  # ========== 二、性能与硬件检测 ==========
  printf -- '---\n\n## 二、性能与硬件检测\n\n### 2.1 系统与硬件信息\n\n'
  printf '| 项目 | 内容 |\n| :--- | :--- |\n'
  md_kv_row "CPU 型号"    "$(kv_get sys.cpu.model)"
  md_kv_row "CPU 核心数"  "$(kv_get sys.cpu.cores) 核"
  md_kv_row "CPU 频率"    "$(kv_get sys.cpu.freq)"
  md_kv_row "CPU 缓存"    "$(kv_get sys.cpu.cache)"
  md_kv_row "AES-NI"      "$(kv_get sys.cpu.aes)"
  md_kv_row "硬件虚拟化"  "$(kv_get sys.cpu.virt)"
  md_kv_row "内存总量"    "$(kv_get sys.mem.total)"
  md_kv_row "内存可用"    "$(kv_get sys.mem.avail)"
  md_kv_row "内存 Buff/Cache" "$(kv_get sys.mem.buff)"
  md_kv_row "Swap"        "$(kv_get sys.swap.summary)"
  md_kv_row "硬盘空间"    "$(kv_get sys.disk.summary)"
  md_kv_row "文件系统"    "$(kv_get sys.disk.fs)"
  md_kv_row "操作系统"    "$(kv_get sys.os)"
  md_kv_row "系统架构"    "$(kv_get sys.arch)"
  md_kv_row "内核版本"    "$(kv_get sys.kernel)"
  md_kv_row "虚拟化类型"  "$(kv_get sys.virt)"
  md_kv_row "TCP 加速"    "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  md_kv_row "协议栈"      "$(kv_get net.stack)"
  md_kv_row "系统负载"    "$(kv_get sys.load)"
  md_kv_row "运行时间"    "$(kv_get sys.uptime)"
  printf '\n'

  if rows_have cpu; then
    printf '### 2.2 CPU 性能\n\n'
    md_table cpu "测试项" "结果"
    [ -n "$(kv_get cpu.sysbench.scale)" ] &&
      printf '> 多核扩展比：**%s**（理想值接近核心数）\n\n' "$(kv_get cpu.sysbench.scale)"
    [ -n "$(kv_get cpu.gb6.link)" ] &&
      printf '> Geekbench 6 完整结果：<%s>\n\n' "$(kv_get cpu.gb6.link)"
  fi
  if rows_have memory; then
    printf '### 2.3 内存性能\n\n'
    md_table memory "测试项" "结果"
  fi
  if rows_have disk_dd || rows_have disk_fio; then
    printf '### 2.4 磁盘 I/O\n\n'
    rows_have disk_dd  && { printf '**顺序读写（dd）**\n\n'; md_table disk_dd "块大小 × 数量" "写入速度" "读取速度"; }
    rows_have disk_fio && { printf '**随机读写（fio · iodepth=64）**\n\n'; md_table disk_fio "块大小" "读取" "写入" "合计"; }
  fi

  # ========== 三、去程延迟 ==========
  printf -- '---\n\n## 三、去程延迟测试（国内 → VPS）\n\n'
  if rows_have inbound_isp; then
    [ -n "$(kv_get inbound.samples)" ] &&
      printf '> 样本总数：**%s** 个，整体平均延迟：**%s ms**\n\n' \
        "$(kv_get inbound.samples)" "$(kv_get inbound.avg)"
    printf '### 3.1 分运营商汇总\n\n'
    md_table inbound_isp "运营商" "样本数" "平均延迟" "最低（最快节点）" "最高（最慢节点）"
    if rows_have inbound_region; then
      printf '### 3.2 分大区汇总\n\n'
      md_table inbound_region "大区" "样本数" "平均延迟" "最低" "最高"
    fi
    if rows_have inbound_raw; then
      printf '<details>\n<summary>展开各探针节点原始数据</summary>\n\n'
      md_table inbound_raw "节点" "运营商" "省份/地区" "大区" "延迟"
      printf '</details>\n\n'
    fi
  else
    md_na inbound_isp || printf '> 本节未测试。\n\n'
  fi

  # ========== 四、去程路由 ==========
  printf -- '---\n\n## 四、去程路由测试（IPIP 探针）\n\n'
  if rows_have inbound_route; then
    md_table inbound_route "探针节点" "线路识别"
    [ -n "$(kv_get inbound.route_verdict)" ] &&
      printf '> **去程线路结论**：%s\n\n' "$(kv_get inbound.route_verdict)"
  else
    md_na inbound_route || printf '> 本节未测试。\n\n'
  fi

  # ========== 五、去程 MTR ==========
  printf -- '---\n\n## 五、去程 MTR\n\n'
  if [ -n "$(kv_get inbound.mtr)" ]; then
    printf '> 去程 MTR 原始数据已导入，详见第十二章「原始结果归档」。\n\n'
  else
    md_na inbound_mtr || printf '> 本节未测试。\n\n'
  fi

  # ========== 六、回程网络质量 ==========
  printf -- '---\n\n## 六、回程网络质量（NetQuality）\n\n'
  if rows_have nq_bgp; then
    printf '### 6.1 BGP 与注册信息\n\n'
    md_table nq_bgp "项目" "内容"
  else
    md_na nq_bgp
  fi
  if rows_have nq_peer; then
    printf '### 6.2 上游与对等互联\n\n'
    md_table nq_peer "项目" "内容"
  fi
  if rows_have nq_ixp; then
    printf '### 6.3 互联网交换点（IXP）\n\n'
    md_table nq_ixp "交换点" "端口速率"
  fi
  if rows_have nq_local; then
    printf '### 6.4 本地网络策略\n\n'
    md_table nq_local "项目" "内容"
  fi
  if rows_have mtr_out; then
    printf '### 6.5 回程 MTR（丢包 / 抖动）\n\n'
    md_table mtr_out "目标" "IP" "丢包率" "平均延迟" "最优 / 最差" "抖动 StDev"
  else
    md_na mtr_out
  fi

  # ========== 七、回程路由 ==========
  printf -- '---\n\n## 七、回程路由测试（NextTrace 三网）\n\n'
  if rows_have route; then
    md_table route "目标" "IP" "线路识别"
    [ -n "$(kv_get route.verdict)" ] &&
      printf '> **回程线路结论**：%s\n\n' "$(kv_get route.verdict)"
  else
    md_na route || printf '> 本节未测试。\n\n'
  fi

  # ========== 八、网络测速 ==========
  printf -- '---\n\n## 八、网络测速\n\n'
  if rows_have iperf; then
    printf '### 8.1 国际节点带宽（iperf3）\n\n'
    md_table iperf "节点" "下载" "上传" "延迟"
  else
    printf '### 8.1 国际节点带宽（iperf3）\n\n'
    md_na iperf
  fi
  if rows_have speed_auto || rows_have speed_gl; then
    printf '### 8.2 Speedtest 国际节点\n\n'
    rows_have speed_auto && md_table speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"
    rows_have speed_gl   && md_table speed_gl   "节点" "下载" "上传" "延迟" "抖动" "服务器"
  fi
  printf '### 8.3 国内三网测速\n\n'
  if rows_have speed_cn; then
    md_table speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"
  else
    printf '> ⚠️ **本次未取得有效数据**：国内测速节点未返回有效结果。\n\n'
  fi
  if rows_have ping_cn || rows_have ping_gl; then
    printf '### 8.4 回程延迟与丢包（VPS → 各地）\n\n'
    rows_have ping_cn && { printf '**国内三网（均值 %s ms）**\n\n' "$(kv_or ping.cn.avg 'N/A')"
                           md_table ping_cn "节点" "线路" "平均延迟" "丢包率"; }
    rows_have ping_gl && { printf '**全球节点（均值 %s ms）**\n\n' "$(kv_or ping.global.avg 'N/A')"
                           md_table ping_gl "节点" "区域" "平均延迟" "丢包率"; }
  fi

  # ========== 九、流媒体解锁 ==========
  printf -- '---\n\n## 九、流媒体与在线服务解锁\n\n'
  if rows_have unlock_net; then
    printf '### 9.1 网络识别\n\n'
    md_table unlock_net "项目" "内容"
  fi
  if rows_have unlock4; then
    printf '### 9.2 IPv4 结果（通过率 %s）\n\n' "$(kv_or unlock.v4.summary 'N/A')"
    printf '> 可用 **%s** ｜ 不可用 **%s** ｜ 待确认 **%s** ｜ 难归类 **%s**\n\n' \
      "$(kv_or unlock4.ok 0)" "$(kv_or unlock4.no 0)" "$(kv_or unlock4.err 0)" "$(kv_or unlock4.misc 0)"
    rows_have unlock4_ok   && { printf '**✅ 可用**\n\n';   md_table unlock4_ok   "服务" "结果"; }
    rows_have unlock4_no   && { printf '**❌ 不可用**\n\n'; md_table unlock4_no   "服务" "结果"; }
    rows_have unlock4_err  && { printf '**⚠️ 失败 / 待确认**\n\n'; md_table unlock4_err "服务" "结果"; }
    rows_have unlock4_misc && { printf '**ℹ️ 难归类（地区码 / CDN 等信息类结果）**\n\n'; md_table unlock4_misc "服务" "结果"; }
    printf '<details>\n<summary>展开 IPv4 完整清单</summary>\n\n'
    md_table unlock4 "服务" "结果"
    printf '</details>\n\n'
  fi
  if rows_have unlock6; then
    printf '### 9.3 IPv6 结果（通过率 %s）\n\n' "$(kv_or unlock.v6.summary 'N/A')"
    md_table unlock6 "服务" "结果"
  else
    printf '### 9.3 IPv6 结果\n\n> %s\n\n' "$(kv_or unlock.v6.summary '本次未检测')"
  fi

  # ========== 十、IP 质量 ==========
  printf -- '---\n\n## 十、IP 质量检测\n\n'
  if rows_have ipq_base; then
    printf '### 10.1 基础画像\n\n'
    md_table ipq_base "项目" "内容"
    rows_have ipq_native && { printf '### 10.2 原生 / 广播判定\n\n'; md_table ipq_native "检测项" "结果"; }
    rows_have ipq_type   && { printf '### 10.3 IP 类型\n\n'; md_table ipq_type "检测项" "结果"; }
    rows_have ipq_risk   && { printf '### 10.4 风险评分\n\n'; md_table ipq_risk "检测项" "结果"; }
    if rows_have ipq_rbl; then
      printf '### 10.5 黑名单扫描\n\n> 汇总：**%s**\n\n' "$(kv_get ipq.rbl_summary)"
      md_table ipq_rbl "黑名单库" "级别" "状态"
    fi
    rows_have ipq_port && { printf '### 10.6 出站端口与连通性\n\n'; md_table ipq_port "检测项" "结果"; }
    printf '> **综合判断**：%s——%s\n\n' "$(kv_or ipq.native '未判定')" "$(kv_or ipq.native_reason '')"
  else
    printf '> 本节未测试。\n\n'
  fi

  # ========== 十一、适用场景与购买建议 ==========
  printf -- '---\n\n## 十一、适用场景与购买建议\n\n'
  if rows_have fit_yes; then
    printf '### 11.1 适合的场景\n\n'
    md_table fit_yes "场景" "依据"
  else
    md_na fit_yes
  fi
  rows_have fit_no && { printf '### 11.2 不适合的场景\n\n'; md_table fit_no "场景" "依据"; }
  rows_have buy    && { printf '### 11.3 价格与线路建议\n\n'; md_table buy "项目" "内容"; }
  rows_have faq    && { printf '### 11.4 FAQ\n\n'; md_table faq "问题" "回答"; }

  # ========== 十二、原始结果归档 ==========
  printf -- '---\n\n## 十二、原始结果归档\n\n'
  printf '- 测试开始时间：%s（%s）\n' "$(kv_get meta.time_local)" "$(kv_get meta.time_utc)"
  printf '- 总耗时：%s\n' "$(kv_or meta.duration '未记录')"
  printf '- 采集工具：%s v%s，依赖情况：%s\n\n' "$VPSTEST_NAME" "$VPSTEST_VERSION" "$(kv_or meta.deps '未记录')"
  if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
    printf '<details>\n<summary>展开全部原始输出（共 %s 段）</summary>\n\n' "${#RAW_ORDER[@]}"
    local k
    for k in "${RAW_ORDER[@]}"; do
      printf '**%s**\n\n```\n%s\n```\n\n' "$k" "${RAWS[$k]}"
    done
    printf '</details>\n\n'
  else
    printf '> 本次未产生可归档的原始输出。\n\n'
  fi

  cat <<EOF
---

## 测试说明

- 测试环境：$(kv_get sys.os) / $(kv_get sys.kernel) / $(kv_get sys.virt)
- 测速与路由结果受测试时段、对端节点负载影响，建议在不同时段多次复测取平均。
- 「去程」章节的数据需由国内探针采集，VPS 自身无法测量，未导入时会标注为未取得。
- 本报告由 [${VPSTEST_NAME}](${VPSTEST_REPO}) 一键脚本自动采集整理。

\`\`\`bash
bash <(curl -sL ${VPSTEST_REPO}/raw/main/dist/vpstest.sh)
\`\`\`
EOF
}
