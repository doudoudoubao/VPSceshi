#!/usr/bin/env bash
# ============================================================
# 74_report_nodeseek.sh — NodeSeek 专用排版（https://www.nodeseek.com）
#
# NodeSeek 用的是 markdown-it，不是 Discuz 那套 BBCode，并且启用了
# markdown-it-container 扩展，支持两个对测评贴特别有用的容器：
#
#   折叠：  ::: details 标题
#           被折叠的内容
#           :::
#
#   标签页：:::: tabs
#           ::: tab-item 标签1
#           内容
#           :::
#           ::: tab-item 标签2
#           内容
#           :::
#           ::::
#
# 容器语法只在 NodeSeek 生效，贴到 GitHub / Hexo 会变成裸文本，
# 所以单独出一份 .nodeseek.md，不动原来的博客版 Markdown。
#
# 万一哪天论坛改了关键字，改下面两个变量即可，不用动正文逻辑。
# ============================================================

NS_DETAILS_KW="details"    # 折叠容器关键字
NS_TABS_KW="tabs"          # 标签页外层关键字
NS_TAB_ITEM_KW="tab-item"  # 标签页内层关键字
NS_USE_TABS=1              # 0 = 不用标签页，退化成三级标题

# ---------- 容器辅助 ----------
ns_details_open()  { printf '::: %s %s\n\n' "$NS_DETAILS_KW" "$1"; }
ns_details_close() { printf '\n:::\n\n'; }

ns_tabs_open()  { [ "$NS_USE_TABS" = "1" ] && printf ':::: %s\n\n' "$NS_TABS_KW"; }
ns_tabs_close() { [ "$NS_USE_TABS" = "1" ] && printf '::::\n\n'; }
# 开一个标签页；关掉 tabs 时退化成 ### 标题
ns_tab() {
  if [ "$NS_USE_TABS" = "1" ]; then printf '::: %s %s\n\n' "$NS_TAB_ITEM_KW" "$1"
  else printf '### %s\n\n' "$1"; fi
}
ns_tab_close() { [ "$NS_USE_TABS" = "1" ] && printf ':::\n\n'; }

# 一个标签页 = 标题 + 一张表，最常用的组合
# ns_tab_table <标签名> <表名> <表头...>
ns_tab_table() {
  local label="$1" t="$2"; shift 2
  rows_have "$t" || return 0
  ns_tab "$label"
  md_table "$t" "$@"
  ns_tab_close
}

# 「未取得数据」提示
ns_na() {
  local key="$1"
  na_has "$key" || return 1
  printf '> ⚠️ **本次未取得有效数据**：%s\n\n' "$(na_get "$key")"
  return 0
}

# 纯文本进度条，论坛里没有 CSS，用方块字符画
# ns_bar <当前值> <满分> [宽度]
ns_bar() {
  awk -v v="$1" -v m="$2" -v w="${3:-16}" 'BEGIN{
    if (m <= 0) { m = 1 }
    n = int(v / m * w + 0.5);
    if (n < 0) n = 0; if (n > w) n = w;
    for (i = 0; i < n; i++) printf "█";
    for (i = n; i < w; i++) printf "░";
  }'
}

gen_nodeseek() {
  local title
  title="$(kv_or meta.node_name "$(kv_get sys.cpu.model)")"

  # ---------- 标题与摘要 ----------
  printf '# %s 测评报告\n\n' "$title"

  # 开头先给结论，论坛读者最关心这几行
  printf '> **测试时间**：%s\n' "$(kv_get meta.time_local)"
  printf '> **出口位置**：%s ｜ %s\n' "$(kv_get net.location)" "$(kv_or net.as '未知 ASN')"
  [ -n "$(kv_get profile.vendor)" ] &&
    printf '> **商家套餐**：%s %s ｜ %s\n' \
      "$(kv_get profile.vendor)" "$(kv_get profile.plan)" "$(kv_or profile.price '价格未填')"
  [ -n "$(kv_get score.total)" ] &&
    printf '> **综合评分**：**%s / 100** — %s\n' "$(kv_get score.total)" "$(kv_get score.grade)"
  [ -n "$(kv_get route.verdict)" ] &&
    printf '> **回程线路**：%s\n' "$(kv_get route.verdict)"
  printf '\n'

  # ---------- 评分卡 ----------
  # 用表格而不是代码块：printf 的 %-12s 按字节补位，中文一个字 3 字节
  # 却只占 2 列，等宽块里必然错行；表格让论坛自己去对齐。
  if rows_have score; then
    printf '## 综合评分\n\n'
    printf '| 评分项 | 进度 | 得分 |\n| :--- | :--- | ---: |\n'
    local line name got max
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      IFS='|' read -r name got max <<< "$line"
      printf '| %s | `%s` | %s / %s |\n' "$name" "$(ns_bar "$got" "$max")" "$got" "$max"
    done <<< "$(rows_get score)"
    printf '| **总分** | `%s` | **%s / 100** |\n\n' \
      "$(ns_bar "$(kv_get score.total)" 100)" "$(kv_get score.total)"
    printf '**评级：%s**\n\n' "$(kv_get score.grade)"
  fi

  # ========== 一、基本配置核对 ==========
  printf '## 一、基本配置核对\n\n'
  if rows_have profile_base; then
    md_table profile_base "项目" "内容"
  else
    printf '> 未提供商家 / 套餐 / 价格信息。\n\n'
  fi
  printf '**宣传配置 vs 实测配置**\n\n'
  md_table profile_cmp "项目" "宣传值" "实测值" "核对"

  # ========== 二、性能与硬件检测 ==========
  printf '## 二、性能与硬件检测\n\n'
  ns_tabs_open
  ns_tab "系统硬件"
  printf '| 项目 | 内容 |\n| :--- | :--- |\n'
  md_kv_row "CPU 型号"        "$(kv_get sys.cpu.model)"
  md_kv_row "CPU 核心数"      "$(kv_get sys.cpu.cores) 核"
  md_kv_row "CPU 频率"        "$(kv_get sys.cpu.freq)"
  md_kv_row "CPU 缓存"        "$(kv_get sys.cpu.cache)"
  md_kv_row "AES-NI"          "$(kv_get sys.cpu.aes)"
  md_kv_row "硬件虚拟化"      "$(kv_get sys.cpu.virt)"
  md_kv_row "内存总量"        "$(kv_get sys.mem.total)"
  md_kv_row "内存可用"        "$(kv_get sys.mem.avail)"
  md_kv_row "内存 Buff/Cache" "$(kv_get sys.mem.buff)"
  md_kv_row "Swap"            "$(kv_get sys.swap.summary)"
  md_kv_row "硬盘空间"        "$(kv_get sys.disk.summary)（$(kv_get sys.disk.fs)）"
  md_kv_row "操作系统"        "$(kv_get sys.os)"
  md_kv_row "内核版本"        "$(kv_get sys.kernel)"
  md_kv_row "虚拟化类型"      "$(kv_get sys.virt)"
  md_kv_row "TCP 加速"        "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  md_kv_row "协议栈"          "$(kv_get net.stack)"
  printf '\n'
  ns_tab_close

  if rows_have cpu; then
    ns_tab "CPU 性能"
    md_table cpu "测试项" "结果"
    [ -n "$(kv_get cpu.sysbench.scale)" ] &&
      printf '多核扩展比：**%s**\n\n' "$(kv_get cpu.sysbench.scale)"
    [ -n "$(kv_get cpu.gb6.link)" ] &&
      printf 'Geekbench 6 完整结果：%s\n\n' "$(kv_get cpu.gb6.link)"
    ns_tab_close
  fi
  ns_tab_table "内存性能" memory "测试项" "结果"
  ns_tab_table "磁盘顺序读写" disk_dd "块大小 × 数量" "写入速度" "读取速度"
  ns_tab_table "磁盘随机读写" disk_fio "块大小" "读取" "写入" "合计"
  ns_tabs_close

  # ========== 三、去程延迟 ==========
  printf '## 三、去程延迟测试（国内 → VPS）\n\n'
  if rows_have inbound_isp; then
    [ -n "$(kv_get inbound.samples)" ] &&
      printf '> 样本总数 **%s** 个，整体平均延迟 **%s ms**\n\n' \
        "$(kv_get inbound.samples)" "$(kv_get inbound.avg)"
    ns_tabs_open
    ns_tab_table "分运营商" inbound_isp "运营商" "样本数" "平均延迟" "最低（最快节点）" "最高（最慢节点）"
    ns_tab_table "分大区"   inbound_region "大区" "样本数" "平均延迟" "最低" "最高"
    ns_tab_table "节点明细" inbound_raw "节点" "运营商" "省份/地区" "大区" "延迟"
    ns_tabs_close
  else
    ns_na inbound_isp || printf '> 本节未测试。\n\n'
  fi

  # ========== 四、去程路由 ==========
  printf '## 四、去程路由测试（IPIP 探针）\n\n'
  if rows_have inbound_route; then
    md_table inbound_route "探针节点" "线路识别"
    [ -n "$(kv_get inbound.route_verdict)" ] &&
      printf '> **去程线路结论**：%s\n\n' "$(kv_get inbound.route_verdict)"
  else
    ns_na inbound_route || printf '> 本节未测试。\n\n'
  fi

  # ========== 五、去程 MTR ==========
  printf '## 五、去程 MTR\n\n'
  if [ -n "$(kv_get inbound.mtr)" ]; then
    printf '> 去程 MTR 原始数据见文末「原始结果归档」。\n\n'
  else
    ns_na inbound_mtr || printf '> 本节未测试。\n\n'
  fi

  # ========== 六、回程网络质量 ==========
  printf '## 六、回程网络质量（NetQuality）\n\n'
  if rows_have nq_bgp || rows_have nq_peer || rows_have nq_local || rows_have mtr_out; then
    ns_tabs_open
    ns_tab_table "BGP 注册信息" nq_bgp "项目" "内容"
    ns_tab_table "上游与对等"   nq_peer "项目" "内容"
    ns_tab_table "交换点 IXP"   nq_ixp "交换点" "端口速率"
    ns_tab_table "本地策略"     nq_local "项目" "内容"
    ns_tab_table "回程 MTR"     mtr_out "目标" "IP" "丢包率" "平均延迟" "最优 / 最差" "抖动"
    ns_tabs_close
  fi
  rows_have nq_bgp   || ns_na nq_bgp
  rows_have mtr_out  || ns_na mtr_out

  # ========== 七、回程路由 ==========
  printf '## 七、回程路由测试（NextTrace 三网）\n\n'
  if rows_have route; then
    md_table route "目标" "IP" "线路识别"
    [ -n "$(kv_get route.verdict)" ] &&
      printf '> **回程线路结论**：%s\n\n' "$(kv_get route.verdict)"
  else
    ns_na route || printf '> 本节未测试。\n\n'
  fi

  # ========== 八、网络测速 ==========
  printf '## 八、网络测速\n\n'
  ns_tabs_open
  if rows_have iperf; then
    ns_tab_table "国际带宽 iperf3" iperf "节点" "下载" "上传" "延迟"
  fi
  ns_tab_table "Speedtest 就近" speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"
  ns_tab_table "Speedtest 国际" speed_gl   "节点" "下载" "上传" "延迟" "抖动" "服务器"
  if rows_have speed_cn; then
    ns_tab_table "国内三网" speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"
  fi
  if rows_have ping_cn; then
    ns_tab "回程延迟 · 国内"
    printf '均值 **%s ms**\n\n' "$(kv_or ping.cn.avg 'N/A')"
    md_table ping_cn "节点" "线路" "平均延迟" "丢包率"
    ns_tab_close
  fi
  if rows_have ping_gl; then
    ns_tab "回程延迟 · 全球"
    printf '均值 **%s ms**\n\n' "$(kv_or ping.global.avg 'N/A')"
    md_table ping_gl "节点" "区域" "平均延迟" "丢包率"
    ns_tab_close
  fi
  ns_tabs_close
  rows_have iperf    || ns_na iperf
  rows_have speed_cn || printf '> ⚠️ **国内测速本次未取得有效数据**。\n\n'

  # ========== 九、流媒体解锁 ==========
  printf '## 九、流媒体与在线服务解锁\n\n'
  if rows_have unlock4; then
    printf '> IPv4 通过率 **%s** ｜ 可用 **%s** ｜ 不可用 **%s** ｜ 待确认 **%s** ｜ 难归类 **%s**\n\n' \
      "$(kv_or unlock.v4.summary 'N/A')" "$(kv_or unlock4.ok 0)" \
      "$(kv_or unlock4.no 0)" "$(kv_or unlock4.err 0)" "$(kv_or unlock4.misc 0)"
    ns_tabs_open
    ns_tab_table "✅ 可用"     unlock4_ok   "服务" "结果"
    ns_tab_table "❌ 不可用"   unlock4_no   "服务" "结果"
    ns_tab_table "⚠️ 待确认"   unlock4_err  "服务" "结果"
    ns_tab_table "ℹ️ 难归类"   unlock4_misc "服务" "结果"
    ns_tab_table "IPv6"        unlock6      "服务" "结果"
    ns_tab_table "网络识别"    unlock_net   "项目" "内容"
    ns_tabs_close
    # 完整清单放折叠里，免得刷屏
    ns_details_open "展开 IPv4 完整清单（$(kv_or unlock.v4.summary 'N/A')）"
    md_table unlock4 "服务" "结果"
    ns_details_close
  else
    printf '> 本节未测试。\n\n'
  fi

  # ========== 十、IP 质量 ==========
  printf '## 十、IP 质量检测\n\n'
  if rows_have ipq_base; then
    [ -n "$(kv_get ipq.native)" ] &&
      printf '> **综合判断**：%s —— %s\n\n' "$(kv_get ipq.native)" "$(kv_get ipq.native_reason)"
    ns_tabs_open
    ns_tab_table "基础画像"     ipq_base   "项目" "内容"
    ns_tab_table "原生 / 广播"  ipq_native "检测项" "结果"
    ns_tab_table "IP 类型"      ipq_type   "检测项" "结果"
    ns_tab_table "风险评分"     ipq_risk   "检测项" "结果"
    if rows_have ipq_rbl; then
      ns_tab "黑名单"
      printf '%s\n\n' "$(kv_get ipq.rbl_summary)"
      md_table ipq_rbl "黑名单库" "级别" "状态"
      ns_tab_close
    fi
    ns_tab_table "端口与连通性" ipq_port "检测项" "结果"
    ns_tabs_close
  else
    printf '> 本节未测试。\n\n'
  fi

  # ========== 十一、适用场景与购买建议 ==========
  printf '## 十一、适用场景与购买建议\n\n'
  if rows_have fit_yes; then
    printf '**👍 适合的场景**\n\n'
    md_table fit_yes "场景" "依据"
  else
    ns_na fit_yes
  fi
  if rows_have fit_no; then
    printf '**👎 不适合的场景**\n\n'
    md_table fit_no "场景" "依据"
  fi
  if rows_have buy; then
    printf '**💰 价格与线路建议**\n\n'
    md_table buy "项目" "内容"
  fi
  if rows_have faq; then
    printf '**❓ FAQ**\n\n'
    local line q a
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      row_split "$line"
      q="${ROW_F[0]}"; a="${ROW_F[1]}"
      printf '**Q：%s**\n\nA：%s\n\n' "$q" "$a"
    done <<< "$(rows_get faq)"
  fi

  # ========== 十二、原始结果归档 ==========
  printf '## 十二、原始结果归档\n\n'
  printf '测试时间 %s ｜ 总耗时 %s ｜ 采集工具 %s v%s\n\n' \
    "$(kv_get meta.time_local)" "$(kv_or meta.duration '未记录')" \
    "$VPSTEST_NAME" "$VPSTEST_VERSION"
  if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
    # 每段单独折叠，点开哪段看哪段
    local k
    for k in "${RAW_ORDER[@]}"; do
      ns_details_open "$k"
      printf '```\n%s\n```' "${RAWS[$k]}"
      ns_details_close
    done
  else
    printf '> 本次未产生可归档的原始输出。\n\n'
  fi

  # ---------- 页脚 ----------
  printf -- '---\n\n'
  printf '测试环境：%s / %s / %s\n\n' \
    "$(kv_get sys.os)" "$(kv_get sys.kernel)" "$(kv_get sys.virt)"
  printf '数据受测试时段与对端负载影响较大，建议不同时段多测几次。'
  printf '「去程」章节需国内探针采集，未导入时已标注为未取得。\n\n'
  printf '本报告由 [%s](%s) 一键脚本自动生成：\n\n' "$VPSTEST_NAME" "$VPSTEST_REPO"
  printf '```bash\nbash <(curl -sL %s/raw/main/dist/vpstest.sh)\n```\n' "$VPSTEST_REPO"
}
