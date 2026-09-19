#!/usr/bin/env bash
# ============================================================
# 72_report_html.sh — 独立 HTML 报告页（可直接上传博客 / 静态托管）
# ============================================================

html_escape() {
  local s="$*"
  s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"
  printf '%s' "$s"
}

# 给结果上色
_html_cell() {
  local v="$1"
  case "$v" in
    ✅*|*"✔"*) printf '<td class="ok">%s</td>' "$(html_escape "$v")" ;;
    ❌*|*"✘"*) printf '<td class="no">%s</td>' "$(html_escape "$v")" ;;
    ⚠️*)       printf '<td class="warn">%s</td>' "$(html_escape "$v")" ;;
    *)         printf '<td>%s</td>' "$(html_escape "$v")" ;;
  esac
}

html_table() {
  local t="$1"; shift
  rows_have "$t" || return 0
  printf '<div class="tw"><table><thead><tr>'
  local h
  for h in "$@"; do printf '<th>%s</th>' "$(html_escape "$h")"; done
  printf '</tr></thead><tbody>'
  local line f
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    printf '<tr>'
    for f in "${ROW_F[@]}"; do _html_cell "$f"; done
    printf '</tr>'
  done <<< "$(rows_get "$t")"
  printf '</tbody></table></div>\n'
}

html_kv() {
  printf '<tr><th>%s</th><td>%s</td></tr>' "$(html_escape "$1")" "$(html_escape "$2")"
}

html_section() { printf '<section id="%s"><h2>%s</h2>\n' "$1" "$(html_escape "$2")"; }
html_section_end() { printf '</section>\n'; }

# 章节未取得数据的提示块
html_na() {
  local key="$1"
  na_has "$key" || return 1
  printf '<p class="na">⚠️ %s</p>' "$(html_escape "$(na_get "$key")")"
  return 0
}

gen_html() {
  local title
  title="$(kv_or meta.node_name "$(kv_get sys.cpu.model)")"

  printf '<!DOCTYPE html>\n<html lang="zh-CN">\n<head>\n'
  printf '<meta charset="utf-8">\n'
  printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<title>%s 服务器测评报告</title>\n' "$(html_escape "$title")"
  cat <<'CSSEOF'
<style>
:root{
  --bg:#f6f7f9; --card:#ffffff; --fg:#1f2329; --muted:#6b7280; --line:#e5e7eb;
  --accent:#2b6cb0; --ok:#15803d; --no:#b91c1c; --warn:#b45309;
  --thead:#f1f5f9; --zebra:#fafbfc; --code:#f3f4f6;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --bg:#0f1115; --card:#171a21; --fg:#e5e7eb; --muted:#9ca3af; --line:#262b34;
    --accent:#63a4ff; --ok:#4ade80; --no:#f87171; --warn:#fbbf24;
    --thead:#1e222a; --zebra:#1b1e25; --code:#11141a;
  }
}
:root[data-theme="dark"]{
  --bg:#0f1115; --card:#171a21; --fg:#e5e7eb; --muted:#9ca3af; --line:#262b34;
  --accent:#63a4ff; --ok:#4ade80; --no:#f87171; --warn:#fbbf24;
  --thead:#1e222a; --zebra:#1b1e25; --code:#11141a;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
  line-height:1.65;font-size:15px}
.wrap{max-width:1040px;margin:0 auto;padding:32px 16px 64px}
header{text-align:center;margin-bottom:28px}
header h1{font-size:26px;margin:0 0 8px;letter-spacing:.3px}
header .meta{color:var(--muted);font-size:13px}
.score{background:var(--card);border:1px solid var(--line);border-radius:14px;
  padding:20px;margin:0 0 24px;text-align:center}
.score .big{font-size:40px;font-weight:700;color:var(--accent);line-height:1.1}
.score .grade{font-size:15px;color:var(--muted);margin-top:4px}
.bars{margin-top:16px;text-align:left}
.bar{margin:8px 0}
.bar .lab{display:flex;justify-content:space-between;font-size:13px;color:var(--muted);margin-bottom:3px}
.bar .track{height:8px;background:var(--line);border-radius:6px;overflow:hidden}
.bar .fill{height:100%;background:var(--accent);border-radius:6px}
section{background:var(--card);border:1px solid var(--line);border-radius:14px;
  padding:18px 20px;margin:0 0 20px}
section h2{font-size:18px;margin:0 0 14px;padding-bottom:8px;border-bottom:2px solid var(--accent);
  display:inline-block}
section h3{font-size:15px;margin:18px 0 8px;color:var(--muted)}
.tw{overflow-x:auto;-webkit-overflow-scrolling:touch}
table{width:100%;border-collapse:collapse;font-size:14px;margin:0 0 6px}
th,td{padding:8px 10px;border:1px solid var(--line);text-align:left;vertical-align:top;
  word-break:break-word}
thead th{background:var(--thead);font-weight:600;white-space:nowrap}
tbody tr:nth-child(even){background:var(--zebra)}
table.kv th{background:var(--thead);width:150px;white-space:nowrap}
td.ok{color:var(--ok);font-weight:600}
td.no{color:var(--no);font-weight:600}
td.warn{color:var(--warn);font-weight:600}
pre{background:var(--code);border:1px solid var(--line);border-radius:8px;
  padding:12px;overflow-x:auto;font-size:12.5px;line-height:1.5}
details{margin:10px 0}
summary{cursor:pointer;color:var(--accent);font-size:14px;padding:4px 0}
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1px;
  background:var(--line);border:1px solid var(--line);border-radius:14px;
  overflow:hidden;margin:0 0 20px}
.summary .si{background:var(--card);padding:12px 14px;min-width:0}
.summary .si span{display:block;color:var(--muted);font-size:12px;margin-bottom:2px}
.summary .si b{font-size:14px;word-break:break-word}
.toc{background:var(--card);border:1px solid var(--line);border-radius:14px;
  padding:14px 20px;margin:0 0 20px}
.toc b{font-size:14px}
.toc ol{margin:8px 0 0;padding-left:20px;columns:2;column-gap:24px;font-size:14px}
.toc li{margin:3px 0;break-inside:avoid}
.toc a{text-decoration:none}
.toc a:hover{text-decoration:underline}
section{scroll-margin-top:16px}
.na{background:color-mix(in srgb, var(--warn) 12%, transparent);
  border-left:3px solid var(--warn);border-radius:0 8px 8px 0;
  padding:10px 14px;margin:10px 0;font-size:14px}
.na code{background:var(--code);padding:1px 5px;border-radius:4px}
footer{color:var(--muted);font-size:13px;text-align:center;margin-top:28px}
footer code{background:var(--code);padding:2px 6px;border-radius:4px}
a{color:var(--accent)}
@media (max-width:640px){
  .wrap{padding:20px 16px 48px}
  header h1{font-size:20px}
  .score .big{font-size:32px}
  table{font-size:13px}
  table.kv th{width:110px}
  .toc ol{columns:1}
  .summary{grid-template-columns:repeat(auto-fit,minmax(140px,1fr))}
}
</style>
CSSEOF
  printf '</head>\n<body>\n<div class="wrap">\n'

  printf '<header><h1>%s 服务器测评报告</h1>\n' "$(html_escape "$title")"
  printf '<div class="meta">测试时间：%s ｜ 出口位置：%s ｜ %s</div></header>\n' \
    "$(html_escape "$(kv_get meta.time_local)")" \
    "$(html_escape "$(kv_get net.location)")" \
    "$(html_escape "$(kv_or net.as '未知 ASN')")"

  # ---- 摘要条：先给结论 ----
  printf '<div class="summary">'
  _sum_item() { [ -n "$2" ] && printf '<div class="si"><span>%s</span><b>%s</b></div>' \
    "$(html_escape "$1")" "$(html_escape "$2")"; }
  _sum_item "配置" "$(kv_get sys.cpu.cores) 核 / $(kv_get sys.mem.total) / $(printf '%s' "$(kv_get sys.disk.summary)" | awk -F' / ' '{print $2}')"
  _sum_item "商家套餐" "$([ -n "$(kv_get profile.vendor)" ] && printf '%s %s' "$(kv_get profile.vendor)" "$(kv_get profile.plan)")"
  _sum_item "价格"     "$(kv_get profile.price)"
  _sum_item "国内延迟" "$([ -n "$(kv_get ping.cn.avg)" ] && printf '%s ms' "$(kv_get ping.cn.avg)")"
  _sum_item "就近下行" "$([ -n "$(kv_get speed.auto.down)" ] && printf '%s Mbps' "$(kv_get speed.auto.down)")"
  _sum_item "解锁通过率" "$(kv_get unlock.v4.summary)"
  _sum_item "IP 类型"  "$(kv_get ipq.native)"
  _sum_item "回程线路" "$(kv_get route.verdict)"
  _sum_item "去程线路" "$(kv_get inbound.route_verdict)"
  unset -f _sum_item
  printf '</div>\n'

  # ---- 评分卡 ----
  if rows_have score; then
    printf '<div class="score"><div class="big">%s<span style="font-size:18px;color:var(--muted)"> / 100</span></div>' \
      "$(html_escape "$(kv_get score.total)")"
    printf '<div class="grade">%s</div><div class="bars">' "$(html_escape "$(kv_get score.grade)")"
    local line name got max pct
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      IFS='|' read -r name got max <<< "$line"
      pct="$(awk -v g="$got" -v m="$max" 'BEGIN{ if(m>0) printf "%.0f", g/m*100; else print 0 }')"
      printf '<div class="bar"><div class="lab"><span>%s</span><span>%s / %s</span></div>' \
        "$(html_escape "$name")" "$(html_escape "$got")" "$(html_escape "$max")"
      printf '<div class="track"><div class="fill" style="width:%s%%"></div></div></div>' "$pct"
    done <<< "$(rows_get score)"
    printf '</div></div>\n'
  fi

  # ---- 目录：12 章的页面太长，给个锚点导航 ----
  printf '<nav class="toc"><b>目录</b><ol>'
  printf '<li><a href="#profile">基本配置核对</a></li>'
  printf '<li><a href="#perf">性能与硬件检测</a></li>'
  printf '<li><a href="#inbound">去程延迟</a></li>'
  printf '<li><a href="#inroute">去程路由</a></li>'
  printf '<li><a href="#inmtr">去程 MTR</a></li>'
  printf '<li><a href="#netq">回程网络质量</a></li>'
  printf '<li><a href="#route">回程路由</a></li>'
  printf '<li><a href="#speed">网络测速</a></li>'
  printf '<li><a href="#unlock">流媒体解锁</a></li>'
  printf '<li><a href="#ipq">IP 质量检测</a></li>'
  printf '<li><a href="#verdict">适用场景与建议</a></li>'
  printf '<li><a href="#raw">原始结果归档</a></li>'
  printf '</ol></nav>\n'


  # ===== 一、基本配置核对 =====
  html_section profile "一、基本配置核对"
  if rows_have profile_base; then
    printf '<h3>商家与套餐</h3>'
    html_table profile_base "项目" "内容"
  else
    printf '<p class="na">未提供商家 / 套餐 / 价格信息，可用 <code>--config</code> 或 <code>--vendor/--plan/--dc/--price</code> 补全本节。</p>'
  fi
  printf '<h3>宣传配置 vs 实测配置</h3>'
  html_table profile_cmp "项目" "宣传值" "实测值" "核对"
  html_section_end

  # ===== 二、性能与硬件检测 =====
  html_section perf "二、性能与硬件检测"
  printf '<h3>系统与硬件信息</h3><div class="tw"><table class="kv"><tbody>'
  html_kv "CPU 型号"        "$(kv_get sys.cpu.model)"
  html_kv "CPU 核心数"      "$(kv_get sys.cpu.cores) 核"
  html_kv "CPU 频率"        "$(kv_get sys.cpu.freq)"
  html_kv "CPU 缓存"        "$(kv_get sys.cpu.cache)"
  html_kv "AES-NI"          "$(kv_get sys.cpu.aes)"
  html_kv "硬件虚拟化"      "$(kv_get sys.cpu.virt)"
  html_kv "内存总量"        "$(kv_get sys.mem.total)"
  html_kv "内存可用"        "$(kv_get sys.mem.avail)"
  html_kv "内存 Buff/Cache" "$(kv_get sys.mem.buff)"
  html_kv "Swap"            "$(kv_get sys.swap.summary)"
  html_kv "硬盘空间"        "$(kv_get sys.disk.summary)（$(kv_get sys.disk.fs)）"
  html_kv "操作系统"        "$(kv_get sys.os)"
  html_kv "系统架构"        "$(kv_get sys.arch)"
  html_kv "内核版本"        "$(kv_get sys.kernel)"
  html_kv "虚拟化类型"      "$(kv_get sys.virt)"
  html_kv "TCP 加速"        "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  html_kv "协议栈"          "$(kv_get net.stack)"
  html_kv "系统负载"        "$(kv_get sys.load)"
  html_kv "运行时间"        "$(kv_get sys.uptime)"
  printf '</tbody></table></div>'
  if rows_have cpu; then
    printf '<h3>CPU 性能</h3>'; html_table cpu "测试项" "结果"
    [ -n "$(kv_get cpu.gb6.link)" ] &&
      printf '<p>Geekbench 6 完整结果：<a href="%s">%s</a></p>' \
        "$(html_escape "$(kv_get cpu.gb6.link)")" "$(html_escape "$(kv_get cpu.gb6.link)")"
  fi
  rows_have memory   && { printf '<h3>内存性能</h3>'; html_table memory "测试项" "结果"; }
  rows_have disk_dd  && { printf '<h3>磁盘顺序读写（dd）</h3>'; html_table disk_dd "块大小 × 数量" "写入速度" "读取速度"; }
  rows_have disk_fio && { printf '<h3>磁盘随机读写（fio · iodepth=64）</h3>'; html_table disk_fio "块大小" "读取" "写入" "合计"; }
  html_section_end

  # ===== 三、去程延迟 =====
  html_section inbound "三、去程延迟测试（国内 → VPS）"
  if rows_have inbound_isp; then
    [ -n "$(kv_get inbound.samples)" ] &&
      printf '<p>样本总数：<b>%s</b> 个，整体平均延迟：<b>%s ms</b></p>' \
        "$(html_escape "$(kv_get inbound.samples)")" "$(html_escape "$(kv_get inbound.avg)")"
    printf '<h3>分运营商汇总</h3>'
    html_table inbound_isp "运营商" "样本数" "平均延迟" "最低（最快节点）" "最高（最慢节点）"
    rows_have inbound_region && { printf '<h3>分大区汇总</h3>'
      html_table inbound_region "大区" "样本数" "平均延迟" "最低" "最高"; }
    if rows_have inbound_raw; then
      printf '<details><summary>展开各探针节点原始数据</summary>'
      html_table inbound_raw "节点" "运营商" "省份/地区" "大区" "延迟"
      printf '</details>'
    fi
  else
    html_na inbound_isp || printf '<p class="na">本节未测试。</p>'
  fi
  html_section_end

  # ===== 四、去程路由 =====
  html_section inroute "四、去程路由测试（IPIP 探针）"
  if rows_have inbound_route; then
    html_table inbound_route "探针节点" "线路识别"
    [ -n "$(kv_get inbound.route_verdict)" ] &&
      printf '<p><b>去程线路结论：</b>%s</p>' "$(html_escape "$(kv_get inbound.route_verdict)")"
  else
    html_na inbound_route || printf '<p class="na">本节未测试。</p>'
  fi
  html_section_end

  # ===== 五、去程 MTR =====
  html_section inmtr "五、去程 MTR"
  if [ -n "$(kv_get inbound.mtr)" ]; then
    printf '<p>去程 MTR 原始数据已导入，详见第十二章「原始结果归档」。</p>'
  else
    html_na inbound_mtr || printf '<p class="na">本节未测试。</p>'
  fi
  html_section_end

  # ===== 六、回程网络质量 =====
  html_section netq "六、回程网络质量（NetQuality）"
  if rows_have nq_bgp; then
    printf '<h3>BGP 与注册信息</h3>'; html_table nq_bgp "项目" "内容"
  else
    html_na nq_bgp
  fi
  rows_have nq_peer  && { printf '<h3>上游与对等互联</h3>'; html_table nq_peer "项目" "内容"; }
  rows_have nq_ixp   && { printf '<h3>互联网交换点（IXP）</h3>'; html_table nq_ixp "交换点" "端口速率"; }
  rows_have nq_local && { printf '<h3>本地网络策略</h3>'; html_table nq_local "项目" "内容"; }
  if rows_have mtr_out; then
    printf '<h3>回程 MTR（丢包 / 抖动）</h3>'
    html_table mtr_out "目标" "IP" "丢包率" "平均延迟" "最优 / 最差" "抖动 StDev"
  else
    html_na mtr_out
  fi
  html_section_end

  # ===== 七、回程路由 =====
  html_section route "七、回程路由测试（NextTrace 三网）"
  if rows_have route; then
    html_table route "目标" "IP" "线路识别"
    [ -n "$(kv_get route.verdict)" ] &&
      printf '<p><b>回程线路结论：</b>%s</p>' "$(html_escape "$(kv_get route.verdict)")"
  else
    html_na route || printf '<p class="na">本节未测试。</p>'
  fi
  html_section_end

  # ===== 八、网络测速 =====
  html_section speed "八、网络测速"
  printf '<h3>国际节点带宽（iperf3）</h3>'
  if rows_have iperf; then html_table iperf "节点" "下载" "上传" "延迟"; else html_na iperf; fi
  rows_have speed_auto && { printf '<h3>Speedtest 就近节点</h3>'
    html_table speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  rows_have speed_gl && { printf '<h3>Speedtest 国际节点</h3>'
    html_table speed_gl "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  printf '<h3>国内三网测速</h3>'
  if rows_have speed_cn; then
    html_table speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"
  else
    html_na speed_cn || printf '<p class="na">本节未测试。</p>'
  fi
  rows_have ping_cn && { printf '<h3>回程延迟 · 国内三网（均值 %s ms）</h3>' "$(html_escape "$(kv_or ping.cn.avg 'N/A')")"
    html_table ping_cn "节点" "线路" "平均延迟" "丢包率"; }
  rows_have ping_gl && { printf '<h3>回程延迟 · 全球节点（均值 %s ms）</h3>' "$(html_escape "$(kv_or ping.global.avg 'N/A')")"
    html_table ping_gl "节点" "区域" "平均延迟" "丢包率"; }
  html_section_end

  # ===== 九、流媒体解锁 =====
  html_section unlock "九、流媒体与在线服务解锁"
  rows_have unlock_net && { printf '<h3>网络识别</h3>'; html_table unlock_net "项目" "内容"; }
  if rows_have unlock4; then
    printf '<h3>IPv4 结果（通过率 %s）</h3>' "$(html_escape "$(kv_or unlock.v4.summary 'N/A')")"
    printf '<p>可用 <b>%s</b> ｜ 不可用 <b>%s</b> ｜ 待确认 <b>%s</b> ｜ 难归类 <b>%s</b></p>' \
      "$(kv_or unlock4.ok 0)" "$(kv_or unlock4.no 0)" "$(kv_or unlock4.err 0)" "$(kv_or unlock4.misc 0)"
    rows_have unlock4_ok   && { printf '<h3>✅ 可用</h3>';   html_table unlock4_ok   "服务" "结果"; }
    rows_have unlock4_no   && { printf '<h3>❌ 不可用</h3>'; html_table unlock4_no   "服务" "结果"; }
    rows_have unlock4_err  && { printf '<h3>⚠️ 失败 / 待确认</h3>'; html_table unlock4_err "服务" "结果"; }
    rows_have unlock4_misc && { printf '<h3>ℹ️ 难归类（地区码 / CDN 等）</h3>'; html_table unlock4_misc "服务" "结果"; }
    printf '<details><summary>展开 IPv4 完整清单</summary>'
    html_table unlock4 "服务" "结果"
    printf '</details>'
  fi
  if rows_have unlock6; then
    printf '<h3>IPv6 结果（通过率 %s）</h3>' "$(html_escape "$(kv_or unlock.v6.summary 'N/A')")"
    html_table unlock6 "服务" "结果"
  else
    printf '<h3>IPv6 结果</h3>'
    html_na unlock6 || printf '<p class="na">%s</p>' "$(html_escape "$(kv_or unlock.v6.summary '本次未检测')")"
  fi
  html_section_end

  # ===== 十、IP 质量 =====
  html_section ipq "十、IP 质量检测"
  if rows_have ipq_base; then
    printf '<h3>基础画像</h3>'; html_table ipq_base "项目" "内容"
    rows_have ipq_native && { printf '<h3>原生 / 广播判定</h3>'; html_table ipq_native "检测项" "结果"; }
    rows_have ipq_type   && { printf '<h3>IP 类型</h3>'; html_table ipq_type "检测项" "结果"; }
    rows_have ipq_risk   && { printf '<h3>风险评分</h3>'; html_table ipq_risk "检测项" "结果"; }
    rows_have ipq_rbl    && { printf '<h3>黑名单扫描（%s）</h3>' "$(html_escape "$(kv_get ipq.rbl_summary)")"
                              html_table ipq_rbl "黑名单库" "级别" "状态"; }
    rows_have ipq_port   && { printf '<h3>出站端口与连通性</h3>'; html_table ipq_port "检测项" "结果"; }
    printf '<p><b>综合判断：</b>%s——%s</p>' \
      "$(html_escape "$(kv_or ipq.native '未判定')")" "$(html_escape "$(kv_or ipq.native_reason '')")"
  else
    html_na ipq_base || printf '<p class="na">本节未测试。</p>'
  fi
  html_section_end

  # ===== 十一、适用场景与购买建议 =====
  html_section verdict "十一、适用场景与购买建议"
  if rows_have fit_yes; then printf '<h3>适合的场景</h3>'; html_table fit_yes "场景" "依据"
  else html_na fit_yes; fi
  rows_have fit_no && { printf '<h3>不适合的场景</h3>'; html_table fit_no "场景" "依据"; }
  rows_have buy    && { printf '<h3>价格与线路建议</h3>'; html_table buy "项目" "内容"; }
  rows_have faq    && { printf '<h3>FAQ</h3>'; html_table faq "问题" "回答"; }
  html_section_end

  # ===== 十二、原始结果归档 =====
  html_section raw "十二、原始结果归档"
  printf '<div class="tw"><table class="kv"><tbody>'
  html_kv "测试开始时间" "$(kv_get meta.time_local)（$(kv_get meta.time_utc)）"
  html_kv "总耗时"       "$(kv_or meta.duration '未记录')"
  html_kv "采集工具"     "$VPSTEST_NAME v$VPSTEST_VERSION"
  html_kv "依赖情况"     "$(kv_or meta.deps '未记录')"
  printf '</tbody></table></div>'
  if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
    printf '<details><summary>展开全部原始输出（共 %s 段）</summary>' "${#RAW_ORDER[@]}"
    local k
    for k in "${RAW_ORDER[@]}"; do
      printf '<h3>%s</h3><pre>%s</pre>' "$(html_escape "$k")" "$(html_escape "${RAWS[$k]}")"
    done
    printf '</details>'
  else
    printf '<p class="na">本次未产生可归档的原始输出。</p>'
  fi
  html_section_end

  printf '<footer><p>测试环境：%s / %s / %s</p>' \
    "$(html_escape "$(kv_get sys.os)")" "$(html_escape "$(kv_get sys.kernel)")" \
    "$(html_escape "$(kv_get sys.virt)")"
  printf '<p>「去程」章节的数据需由国内探针采集，VPS 自身无法测量，未导入时标注为未取得。</p>'
  printf '<p>本报告由 <a href="%s">%s v%s</a> 一键脚本自动采集整理</p>' \
    "$VPSTEST_REPO" "$VPSTEST_NAME" "$VPSTEST_VERSION"
  printf '<p><code>bash &lt;(curl -sL %s/raw/main/dist/vpstest.sh)</code></p></footer>\n' "$VPSTEST_REPO"
  printf '</div>\n</body>\n</html>\n'
}
