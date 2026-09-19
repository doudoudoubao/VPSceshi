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
footer{color:var(--muted);font-size:13px;text-align:center;margin-top:28px}
footer code{background:var(--code);padding:2px 6px;border-radius:4px}
a{color:var(--accent)}
@media (max-width:640px){
  .wrap{padding:20px 16px 48px}
  header h1{font-size:20px}
  .score .big{font-size:32px}
  table{font-size:13px}
  table.kv th{width:110px}
}
</style>
CSSEOF
  printf '</head>\n<body>\n<div class="wrap">\n'

  printf '<header><h1>%s 服务器测评报告</h1>\n' "$(html_escape "$title")"
  printf '<div class="meta">测试时间：%s ｜ 出口位置：%s ｜ %s</div></header>\n' \
    "$(html_escape "$(kv_get meta.time_local)")" \
    "$(html_escape "$(kv_get net.location)")" \
    "$(html_escape "$(kv_or net.as '未知 ASN')")"

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

  # ---- 系统信息 ----
  html_section sys "一、系统与硬件信息"
  printf '<div class="tw"><table class="kv"><tbody>'
  html_kv "CPU 型号"   "$(kv_get sys.cpu.model)"
  html_kv "CPU 核心数" "$(kv_get sys.cpu.cores) 核"
  html_kv "CPU 频率"   "$(kv_get sys.cpu.freq)"
  html_kv "CPU 缓存"   "$(kv_get sys.cpu.cache)"
  html_kv "AES-NI"     "$(kv_get sys.cpu.aes)"
  html_kv "硬件虚拟化" "$(kv_get sys.cpu.virt)"
  html_kv "内存"       "$(kv_get sys.mem.summary)"
  html_kv "Swap"       "$(kv_get sys.swap.summary)"
  html_kv "硬盘空间"   "$(kv_get sys.disk.summary)（$(kv_get sys.disk.fs)）"
  html_kv "操作系统"   "$(kv_get sys.os)"
  html_kv "系统架构"   "$(kv_get sys.arch)"
  html_kv "内核版本"   "$(kv_get sys.kernel)"
  html_kv "虚拟化架构" "$(kv_get sys.virt)"
  html_kv "TCP 加速"   "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  html_kv "协议栈"     "$(kv_get net.stack)"
  html_kv "系统负载"   "$(kv_get sys.load)"
  html_kv "运行时间"   "$(kv_get sys.uptime)"
  printf '</tbody></table></div>'
  html_section_end

  if rows_have cpu; then
    html_section cpu "二、CPU 性能测试"
    html_table cpu "测试项" "结果"
    html_section_end
  fi
  if rows_have memory; then
    html_section mem "三、内存性能测试"
    html_table memory "测试项" "结果"
    html_section_end
  fi
  if rows_have disk_dd || rows_have disk_fio; then
    html_section disk "四、磁盘 I/O 测试"
    rows_have disk_dd && { printf '<h3>顺序读写（dd）</h3>'; html_table disk_dd "块大小 × 数量" "写入速度" "读取速度"; }
    rows_have disk_fio && { printf '<h3>随机读写（fio · iodepth=64）</h3>'; html_table disk_fio "块大小" "读取" "写入" "合计"; }
    html_section_end
  fi
  if rows_have ipq_base; then
    html_section ipq "五、IP 质量体检"
    html_table ipq_base "项目" "内容"
    rows_have ipq_type && { printf '<h3>IP 类型判定</h3>'; html_table ipq_type "检测项" "结果"; }
    rows_have ipq_risk && { printf '<h3>风险与信誉</h3>'; html_table ipq_risk "检测项" "结果"; }
    rows_have ipq_rbl  && { printf '<h3>邮件黑名单（%s）</h3>' "$(html_escape "$(kv_get ipq.rbl_summary)")"
                            html_table ipq_rbl "黑名单库" "状态"; }
    rows_have ipq_port && { printf '<h3>出站端口与连通性</h3>'; html_table ipq_port "检测项" "结果"; }
    html_section_end
  fi
  if rows_have unlock4 || rows_have unlock6; then
    html_section unlock "六、流媒体 / AI 服务解锁"
    rows_have unlock4 && { printf '<h3>IPv4（通过率 %s）</h3>' "$(html_escape "$(kv_or unlock.v4.summary 'N/A')")"
                           html_table unlock4 "服务" "结果"; }
    [ -n "$(kv_get unlock.v4.ytcdn)" ] &&
      printf '<p style="color:var(--muted);font-size:13px">YouTube CDN 节点：<b>%s</b></p>' \
        "$(html_escape "$(kv_get unlock.v4.ytcdn)")"
    rows_have unlock6 && { printf '<h3>IPv6（通过率 %s）</h3>' "$(html_escape "$(kv_or unlock.v6.summary 'N/A')")"
                           html_table unlock6 "服务" "结果"; }
    html_section_end
  fi
  if rows_have ping_cn || rows_have ping_gl; then
    html_section ping "七、延迟与丢包"
    rows_have ping_cn && { printf '<h3>国内三网（均值 %s ms）</h3>' "$(html_escape "$(kv_or ping.cn.avg 'N/A')")"
                           html_table ping_cn "节点" "线路" "平均延迟" "丢包率"; }
    rows_have ping_gl && { printf '<h3>全球节点（均值 %s ms）</h3>' "$(html_escape "$(kv_or ping.global.avg 'N/A')")"
                           html_table ping_gl "节点" "区域" "平均延迟" "丢包率"; }
    html_section_end
  fi
  if rows_have speed_auto || rows_have speed_cn || rows_have speed_gl; then
    html_section speed "八、网络测速（Speedtest）"
    rows_have speed_auto && { printf '<h3>就近节点</h3>'; html_table speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
    rows_have speed_cn   && { printf '<h3>国内三网节点</h3>'; html_table speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
    rows_have speed_gl   && { printf '<h3>国际节点</h3>'; html_table speed_gl "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
    html_section_end
  fi
  if rows_have route; then
    html_section route "九、三网回程路由"
    html_table route "目标" "IP" "线路判定"
    if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
      printf '<details><summary>展开完整路由追踪原始输出</summary>'
      local k
      for k in "${RAW_ORDER[@]}"; do
        printf '<h3>%s</h3><pre>%s</pre>' "$(html_escape "$k")" "$(html_escape "${RAWS[$k]}")"
      done
      printf '</details>'
    fi
    html_section_end
  fi

  printf '<footer><p>测试环境：%s / %s / %s ｜ 总耗时：%s</p>' \
    "$(html_escape "$(kv_get sys.os)")" "$(html_escape "$(kv_get sys.kernel)")" \
    "$(html_escape "$(kv_get sys.virt)")" "$(html_escape "$(kv_or meta.duration '未记录')")"
  printf '<p>本报告由 <a href="%s">%s v%s</a> 一键脚本自动生成</p>' \
    "$VPSTEST_REPO" "$VPSTEST_NAME" "$VPSTEST_VERSION"
  printf '<p><code>bash &lt;(curl -sL %s/raw/main/dist/vpstest.sh)</code></p></footer>\n' "$VPSTEST_REPO"
  printf '</div>\n</body>\n</html>\n'
}
