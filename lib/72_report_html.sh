#!/usr/bin/env bash
# ============================================================
# 72_report_html.sh — 独立 HTML 报告页（可直接上传博客 / 静态托管）
#
# 设计语言：像一篇正经的服务器测评博客，而不是数据表格堆砌。
# 单值信息（CPU 型号、BGP 前缀……）用图标+规格卡片一项一项列出来；
# 通过/失败类信息（解锁、黑名单、端口……）用彩色药丸标签；
# 真正需要横向对比的表格（测速、延迟、fio 多档位）才保留 <table>。
# ============================================================

html_escape() {
  local s="$*"
  s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"
  printf '%s' "$s"
}

# ---------- 状态药丸 ----------
# 短小的通过/失败/警告类值渲染成彩色胶囊；长文本（公司名等）不套壳，
# 否则会被撑成一个丑陋的长条。_dw 是 00_core.sh 里现成的显示宽度函数。
_pill_html() {
  local v="$1" cls="plain"
  case "$v" in
    ✅*) cls="ok" ;;
    ❌*) cls="no" ;;
    ⚠️*) cls="warn" ;;
    📡*) cls="warn" ;;
    是)  cls="ok" ;;
    否)  cls="muted" ;;
  esac
  if [ "$cls" = "plain" ] && [ "$(_dw "$v")" -gt 28 ]; then
    html_escape "$v"; return
  fi
  printf '<span class="pill %s">%s</span>' "$cls" "$(html_escape "$v")"
}

# 规格卡片里的值：状态类走药丸，其余直接加粗展示
_fact_val() {
  case "$1" in
    ✅*|❌*|⚠️*|📡*|是|否) _pill_html "$1" ;;
    *) html_escape "$1" ;;
  esac
}

# 按标签关键词给个应景的图标，纯装饰，猜不准也无所谓
_fact_icon() {
  case "$1" in
    *CPU*型号*|*CPU*Model*) printf '🧠' ;;
    *核心数*|*核数*)         printf '🔢' ;;
    *频率*)                  printf '⚡' ;;
    *缓存*)                  printf '🗃️' ;;
    AES-NI)                  printf '🔐' ;;
    *虚拟化*|*虚拟架构*)     printf '📦' ;;
    *内存*)                  printf '💾' ;;
    Swap)                    printf '🔄' ;;
    *硬盘*)                  printf '💿' ;;
    *文件系统*)              printf '🗂️' ;;
    *操作系统*)              printf '🐧' ;;
    *架构*)                  printf '🏗️' ;;
    *内核*)                  printf '⚙️' ;;
    *TCP*|*拥塞*|*队列*)     printf '🚦' ;;
    *协议栈*)                printf '🌐' ;;
    *负载*)                  printf '📈' ;;
    *运行时间*)              printf '🕐' ;;
    *商家*)                  printf '🏢' ;;
    *套餐*)                  printf '🏷️' ;;
    *机房*)                  printf '🏭' ;;
    *线路结论*)              printf '🛰️' ;;
    *线路*)                  printf '🛣️' ;;
    *流量*)                  printf '📊' ;;
    *带宽*)                  printf '🚀' ;;
    *价格*)                  printf '💰' ;;
    IPv4*)                   printf '4️⃣' ;;
    IPv6*)                   printf '6️⃣' ;;
    *ASN*|*Origin\ AS*)      printf '🔖' ;;
    *IP\ 地址*)              printf '📍' ;;
    *ISP*|*运营商*)          printf '📡' ;;
    *地理位置*|*地区*|*定位*) printf '📍' ;;
    PTR*|*反向解析*)         printf '🔄' ;;
    *时区*)                  printf '🕒' ;;
    *前缀*|Prefix*)          printf '🔢' ;;
    *注册*)                  printf '📋' ;;
    *RIR*)                   printf '🌍' ;;
    *上游*)                  printf '⬆️' ;;
    *下游*)                  printf '⬇️' ;;
    *IXP*|*交换*)            printf '🔀' ;;
    *网络类型*|*覆盖范围*)   printf '🏷️' ;;
    *MTU*)                   printf '📏' ;;
    *转发*)                  printf '➡️' ;;
    *IPv6\ 支持*)            printf '6️⃣' ;;
    *单价*)                  printf '💰' ;;
    *延迟*)                  printf '⏱️' ;;
    *使用建议*)              printf '💡' ;;
    *)                       printf '▫️' ;;
  esac
}

# 单个规格卡片：<label> <value> → 一张卡
# _fact_row <标签> <值>
_fact_row() {
  printf '<div class="fact"><span class="fk">%s %s</span><span class="fv">%s</span></div>' \
    "$(_fact_icon "$1")" "$(html_escape "$1")" "$(_fact_val "$2")"
}

# html_facts <表名> —— 把 2 列（项目/内容）结果表渲成规格卡片网格
html_facts() {
  local t="$1"
  rows_have "$t" || return 0
  printf '<div class="facts">'
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    _fact_row "${ROW_F[0]}" "${ROW_F[1]}"
  done <<< "$(rows_get "$t")"
  printf '</div>\n'
}

# html_pillrows <表名> —— 2 列（名称/状态）渲成一行一个的药丸列表
# 适合解锁服务、端口连通性、IP 类型判定这类「一项一项过」的清单
html_pillrows() {
  local t="$1"
  rows_have "$t" || return 0
  printf '<div class="pillrows">'
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    printf '<div class="prow"><span class="pn">%s</span>%s</div>' \
      "$(html_escape "${ROW_F[0]}")" "$(_pill_html "${ROW_F[1]}")"
  done <<< "$(rows_get "$t")"
  printf '</div>\n'
}

# html_pillrows3 <表名> —— 3 列（名称/标签/状态），黑名单库那种场景
html_pillrows3() {
  local t="$1"
  rows_have "$t" || return 0
  printf '<div class="pillrows">'
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    printf '<div class="prow"><span class="pn">%s</span><span class="ptag">%s</span>%s</div>' \
      "$(html_escape "${ROW_F[0]}")" "$(html_escape "${ROW_F[1]}")" "$(_pill_html "${ROW_F[2]}")"
  done <<< "$(rows_get "$t")"
  printf '</div>\n'
}

# html_routelist <表名> —— 3 列（目标/IP/线路识别），卡片网格而不是表格，
# 每张卡片是一个探测目标，比一整行塞三列更好扫视
html_routelist() {
  local t="$1"
  rows_have "$t" || return 0
  printf '<div class="routelist">'
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    printf '<div class="rzitem"><div class="rz-name">📍 %s</div><div class="rz-ip">%s</div><div class="rz-line">%s</div></div>' \
      "$(html_escape "${ROW_F[0]}")" "$(html_escape "${ROW_F[1]}")" "$(html_escape "${ROW_F[2]}")"
  done <<< "$(rows_get "$t")"
  printf '</div>\n'
}

# html_scenarios <表名> <good|bad> —— 适合/不适合场景，左边一道彩色竖线的卡片
html_scenarios() {
  local t="$1" kind="$2" mark
  rows_have "$t" || return 0
  mark="$([ "$kind" = "good" ] && printf '✅' || printf '⚠️')"
  printf '<div class="scenarios %s">' "$kind"
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    printf '<div class="scen"><div class="scen-t">%s %s</div><div class="scen-d">%s</div></div>' \
      "$mark" "$(html_escape "${ROW_F[0]}")" "$(html_escape "${ROW_F[1]}")"
  done <<< "$(rows_get "$t")"
  printf '</div>\n'
}

# html_faq —— 问答手风琴，点开才展开答案，比一张大表好读
html_faq() {
  rows_have faq || return 0
  printf '<div class="faqlist">'
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    printf '<details class="faqitem"><summary>%s</summary><div class="faqa">%s</div></details>' \
      "$(html_escape "${ROW_F[0]}")" "$(html_escape "${ROW_F[1]}")"
  done <<< "$(rows_get faq)"
  printf '</div>\n'
}

# ---------- 真正需要横向对比的表格 ----------
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

html_section() {
  # $1=锚点id $2=图标 $3=标题
  printf '<section id="%s"><h2><span class="hico">%s</span>%s</h2>\n' \
    "$1" "$2" "$(html_escape "$3")"
}
html_section_end() { printf '</section>\n'; }

# ---------- 一键复制 ----------
#
# 把其它几种格式的全文塞进页面，配上复制按钮。这样报告页本身就是
# 交付物：打开网页点一下就能粘到论坛/博客，不用再回服务器 cat 文件。
# HTML_EMBED_BASE 由 write_reports 设置，指向同批报告的路径前缀。
HTML_EMBED_BASE=""

# 把文件内容塞进一个不会被执行的 script 标签
# _embed_format <元素id> <文件路径>
_embed_format() {
  local id="$1" f="$2"
  [ -r "$f" ] || return 1
  printf '<script type="text/plain" id="%s">' "$id"
  # script 块里唯一危险的序列是 </script，转义掉；& < 不用管，
  # text/plain 类型的 script 内容不按 HTML 解析
  sed 's|</script|<\\/script|gI' "$f"
  printf '</script>\n'
}

# 复制按钮条 + 配套 JS
html_copy_bar() {
  [ -z "$HTML_EMBED_BASE" ] && return 0
  local any=0
  # 先把各格式全文嵌进来
  _embed_format "fmt-nodeseek" "${HTML_EMBED_BASE}.nodeseek.md" && any=1
  _embed_format "fmt-md"       "${HTML_EMBED_BASE}.md"          && any=1
  _embed_format "fmt-bbcode"   "${HTML_EMBED_BASE}.bbcode"      && any=1
  _embed_format "fmt-txt"      "${HTML_EMBED_BASE}.txt"         && any=1
  _embed_format "fmt-json"     "${HTML_EMBED_BASE}.json"        && any=1
  [ "$any" = "0" ] && return 0

  cat <<'COPYEOF'
<div class="copybar">
  <b>📋 一键复制到发帖框</b>
  <div class="btns">
    <button data-fmt="fmt-nodeseek">NodeSeek 排版</button>
    <button data-fmt="fmt-md">Markdown（博客）</button>
    <button data-fmt="fmt-bbcode">BBCode（Discuz）</button>
    <button data-fmt="fmt-txt">纯文本</button>
    <button data-fmt="fmt-json">JSON</button>
  </div>
  <span class="tip" id="copytip"></span>
</div>
<script>
(function () {
  // clipboard API 只在 https / localhost 下可用，普通 http 页面必须有回退，
  // 否则点了没反应。这里两条路都留着。
  function legacyCopy(text) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.top = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    ta.setSelectionRange(0, ta.value.length);
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    document.body.removeChild(ta);
    return ok;
  }
  function tip(msg, bad) {
    var el = document.getElementById('copytip');
    el.textContent = msg;
    el.className = 'tip' + (bad ? ' bad' : ' good');
    clearTimeout(el._t);
    el._t = setTimeout(function () { el.textContent = ''; el.className = 'tip'; }, 2600);
  }
  document.querySelectorAll('.copybar button').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var src = document.getElementById(btn.dataset.fmt);
      if (!src) { tip('这份格式没有生成', true); return; }
      var text = src.textContent;
      var label = btn.textContent;
      var done = function () { tip('已复制 ' + label + '（' + text.length + ' 字）'); };
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(done, function () {
          legacyCopy(text) ? done() : tip('复制失败，请长按手动选择', true);
        });
      } else {
        legacyCopy(text) ? done() : tip('复制失败，请长按手动选择', true);
      }
    });
  });
})();
</script>
COPYEOF
}

# 章节未取得数据的提示块
html_na() {
  local key="$1"
  na_has "$key" || return 1
  printf '<p class="na">⚠️ %s</p>' "$(html_escape "$(na_get "$key")")"
  return 0
}

# 评分环：0-100 换算成 conic-gradient 的百分比
_score_pct() {
  awk -v t="$(kv_get score.total)" 'BEGIN{
    p=t+0; if(p<0)p=0; if(p>100)p=100; printf "%.0f", p }'
}
_score_icon() {
  case "$1" in
    *CPU*)      printf '🧠' ;;
    *磁盘*)     printf '💿' ;;
    *带宽*)     printf '🚀' ;;
    *延迟*)     printf '⏱️' ;;
    *解锁*)     printf '🔓' ;;
    *IP*质量*)  printf '🛡️' ;;
    *)          printf '📊' ;;
  esac
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
  --bg:#f3f4f7; --card:#ffffff; --fg:#1f2329; --muted:#6b7280; --line:#e5e7eb;
  --accent:#2b6cb0; --accent2:#7c3aed; --ok:#15803d; --no:#b91c1c; --warn:#b45309;
  --thead:#f1f5f9; --zebra:#fafbfc; --code:#f3f4f6;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --bg:#0c0e13; --card:#161920; --fg:#e5e7eb; --muted:#9ca3af; --line:#262b34;
    --accent:#63a4ff; --accent2:#a78bfa; --ok:#4ade80; --no:#f87171; --warn:#fbbf24;
    --thead:#1c2028; --zebra:#191d24; --code:#11141a;
  }
}
:root[data-theme="dark"]{
  --bg:#0c0e13; --card:#161920; --fg:#e5e7eb; --muted:#9ca3af; --line:#262b34;
  --accent:#63a4ff; --accent2:#a78bfa; --ok:#4ade80; --no:#f87171; --warn:#fbbf24;
  --thead:#1c2028; --zebra:#191d24; --code:#11141a;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
  line-height:1.65;font-size:15px}
.wrap{max-width:1040px;margin:0 auto;padding:32px 16px 64px}

/* ---- 页头 ---- */
header{text-align:center;margin-bottom:22px}
.kicker{display:inline-block;background:linear-gradient(135deg,var(--accent),var(--accent2));
  color:#fff;font-size:11px;font-weight:800;letter-spacing:1px;padding:5px 14px;
  border-radius:999px;margin-bottom:12px;text-transform:uppercase}
header h1{font-size:25px;margin:0 0 8px;letter-spacing:.2px;font-weight:800}
header .meta{color:var(--muted);font-size:13px}

/* ---- 顶部关键指标 ---- */
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;margin:20px 0}
.summary .si{background:var(--card);border:1px solid var(--line);border-radius:14px;
  padding:14px 10px;text-align:center;min-width:0}
.summary .si-ic{font-size:20px;margin-bottom:5px}
.summary .si span{display:block;color:var(--muted);font-size:11px;margin-bottom:3px}
.summary .si b{font-size:13.5px;word-break:break-word}

/* ---- 评分环 ---- */
.scorehero{background:var(--card);border:1px solid var(--line);border-radius:18px;
  padding:26px 20px;margin:0 0 20px;text-align:center}
.ring{width:148px;height:148px;border-radius:50%;margin:0 auto 12px;
  background:conic-gradient(var(--accent) calc(var(--pct)*1%), var(--line) 0);
  display:flex;align-items:center;justify-content:center}
.ringhole{width:116px;height:116px;border-radius:50%;background:var(--card);
  display:flex;flex-direction:column;align-items:center;justify-content:center}
.ringnum{font-size:34px;font-weight:800;color:var(--accent);line-height:1}
.ringmax{font-size:11.5px;color:var(--muted);margin-top:3px}
.gradebadge{display:inline-block;background:var(--thead);color:var(--fg);
  font-size:14px;font-weight:800;padding:6px 18px;border-radius:999px;margin-bottom:18px}
.scorebars{text-align:left;max-width:440px;margin:0 auto;display:grid;gap:12px}
.sbar-lab{display:flex;justify-content:space-between;font-size:13px;color:var(--muted);margin-bottom:5px}
.sbar-lab b{color:var(--fg);font-weight:600}
.sbar-track{height:8px;background:var(--line);border-radius:6px;overflow:hidden}
.sbar-fill{height:100%;background:linear-gradient(90deg,var(--accent),var(--accent2));border-radius:6px}

/* ---- 一键复制 ---- */
.copybar{background:var(--card);border:1px solid var(--line);border-radius:14px;
  padding:16px 18px;margin:0 0 20px}
.copybar>b{font-size:14px;display:block;margin-bottom:10px}
.copybar .btns{display:flex;flex-wrap:wrap;gap:8px}
.copybar button{font:inherit;font-size:13px;cursor:pointer;
  background:var(--accent);color:#fff;border:0;border-radius:8px;
  padding:8px 14px;transition:opacity .15s}
.copybar button:hover{opacity:.85}
.copybar button:active{transform:translateY(1px)}
.copybar .tip{display:inline-block;margin-top:10px;font-size:13px;min-height:1.2em}
.copybar .tip.good{color:var(--ok)}
.copybar .tip.bad{color:var(--no)}

/* ---- 目录 ---- */
.toc{background:var(--card);border:1px solid var(--line);border-radius:14px;
  padding:14px 20px;margin:0 0 20px}
.toc b{font-size:14px}
.toc ol{margin:8px 0 0;padding-left:20px;columns:2;column-gap:24px;font-size:14px}
.toc li{margin:3px 0;break-inside:avoid}
.toc a{text-decoration:none}
.toc a:hover{text-decoration:underline}

/* ---- 章节 ---- */
section{background:var(--card);border:1px solid var(--line);border-radius:16px;
  padding:20px 20px 22px;margin:0 0 20px;scroll-margin-top:16px}
section h2{font-size:18px;margin:0 0 16px;padding-bottom:12px;
  border-bottom:2px solid var(--accent);display:flex;align-items:center;gap:9px;font-weight:800}
section h2 .hico{font-size:20px}
section h3{font-size:14px;margin:22px 0 10px;font-weight:700;
  padding-left:10px;border-left:3px solid var(--accent);opacity:.9}
section h3:first-of-type{margin-top:6px}

/* ---- 规格卡片（一项一项列出来） ---- */
.facts{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:10px;margin:12px 0}
.fact{background:var(--thead);border-radius:10px;padding:11px 13px}
.fact .fk{display:block;font-size:12px;color:var(--muted);margin-bottom:5px;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.fact .fv{display:block;font-size:14.5px;font-weight:700;word-break:break-word;line-height:1.4}

/* ---- 药丸清单 ---- */
.pillrows{display:flex;flex-direction:column;gap:1px;background:var(--line);
  border:1px solid var(--line);border-radius:12px;overflow:hidden;margin:12px 0}
.prow{background:var(--card);padding:10px 14px;display:flex;align-items:center;
  justify-content:space-between;gap:12px;font-size:13.5px}
.prow .pn{color:var(--fg);word-break:break-word}
.prow .ptag{font-size:11px;color:var(--muted);background:var(--thead);
  padding:2px 9px;border-radius:6px;white-space:nowrap;margin-right:auto;margin-left:8px}
.pill{display:inline-block;padding:3px 11px;border-radius:999px;font-size:12.5px;
  font-weight:700;white-space:nowrap;flex-shrink:0}
.pill.ok{background:color-mix(in srgb, var(--ok) 16%, transparent);color:var(--ok)}
.pill.no{background:color-mix(in srgb, var(--no) 16%, transparent);color:var(--no)}
.pill.warn{background:color-mix(in srgb, var(--warn) 18%, transparent);color:var(--warn)}
.pill.muted{background:var(--thead);color:var(--muted)}
.pill.plain{background:var(--thead);color:var(--fg)}

/* ---- 路由卡片网格 ---- */
.routelist{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:10px;margin:12px 0}
.rzitem{background:var(--thead);border-radius:10px;padding:12px 14px}
.rz-name{font-weight:700;font-size:13.5px;margin-bottom:3px}
.rz-ip{font-size:11px;color:var(--muted);font-family:ui-monospace,SFMono-Regular,Menlo,monospace;margin-bottom:7px}
.rz-line{font-size:12.5px;line-height:1.5}

/* ---- 适合/不适合场景卡片 ---- */
.scenarios{display:grid;gap:10px;margin:12px 0}
.scen{border-radius:10px;padding:12px 14px;background:var(--thead);border-left:4px solid var(--ok)}
.scenarios.bad .scen{border-left-color:var(--warn)}
.scen-t{font-weight:700;font-size:14px;margin-bottom:4px}
.scen-d{font-size:13px;color:var(--muted);line-height:1.6}

/* ---- FAQ 手风琴 ---- */
.faqlist{display:flex;flex-direction:column;gap:8px;margin:12px 0}
.faqitem{background:var(--thead);border-radius:10px;padding:2px 14px}
.faqitem summary{font-weight:700;padding:11px 0;cursor:pointer;list-style:none;font-size:13.5px}
.faqitem summary::-webkit-details-marker{display:none}
.faqitem summary::before{content:'❯';color:var(--accent);display:inline-block;
  margin-right:8px;transition:transform .15s}
.faqitem[open] summary::before{transform:rotate(90deg)}
.faqa{padding:0 0 14px;color:var(--muted);font-size:13.5px;line-height:1.75}

/* ---- 表格（仅横向对比数据用） ---- */
.tw{overflow-x:auto;-webkit-overflow-scrolling:touch;border-radius:12px;
  border:1px solid var(--line);margin:12px 0}
table{width:100%;border-collapse:collapse;font-size:13.5px}
th,td{padding:10px 12px;border-bottom:1px solid var(--line);text-align:left;
  vertical-align:top;word-break:break-word}
table tr:last-child td{border-bottom:0}
thead th{background:var(--thead);font-weight:700;white-space:nowrap}
tbody tr:hover{background:var(--zebra)}
td.ok{color:var(--ok);font-weight:700}
td.no{color:var(--no);font-weight:700}
td.warn{color:var(--warn);font-weight:700}

pre{background:var(--code);border:1px solid var(--line);border-radius:8px;
  padding:12px;overflow-x:auto;font-size:12.5px;line-height:1.5}
details{margin:10px 0}
summary{cursor:pointer;color:var(--accent);font-size:14px;padding:4px 0}
.na{background:color-mix(in srgb, var(--warn) 10%, transparent);
  border-left:3px solid var(--warn);border-radius:0 8px 8px 0;
  padding:10px 14px;margin:10px 0;font-size:13.5px}
.na code{background:var(--code);padding:1px 5px;border-radius:4px}
footer{color:var(--muted);font-size:13px;text-align:center;margin-top:28px}
footer code{background:var(--code);padding:2px 6px;border-radius:4px}
a{color:var(--accent)}

@media (max-width:640px){
  .wrap{padding:20px 16px 48px}
  header h1{font-size:19px}
  section{padding:16px 14px 18px}
  .ring{width:128px;height:128px}
  .ringhole{width:100px;height:100px}
  .ringnum{font-size:28px}
  table{font-size:13px}
  .toc ol{columns:1}
  .facts{grid-template-columns:repeat(auto-fill,minmax(140px,1fr))}
  .routelist{grid-template-columns:1fr}
  .summary{grid-template-columns:repeat(auto-fit,minmax(110px,1fr))}
  .prow{flex-wrap:wrap}
}
</style>
CSSEOF
  printf '</head>\n<body>\n<div class="wrap">\n'

  printf '<header><span class="kicker">Server Benchmark Report</span>\n'
  printf '<h1>%s 服务器测评报告</h1>\n' "$(html_escape "$title")"
  printf '<div class="meta">测试时间：%s ｜ 出口位置：%s ｜ %s</div></header>\n' \
    "$(html_escape "$(kv_get meta.time_local)")" \
    "$(html_escape "$(kv_get net.location)")" \
    "$(html_escape "$(kv_or net.as '未知 ASN')")"

  # ---- 评分环：先给结论，这是整篇报告最该被看到的一眼 ----
  if rows_have score; then
    printf '<div class="scorehero"><div class="ring" style="--pct:%s"><div class="ringhole">' "$(_score_pct)"
    printf '<div class="ringnum">%s</div><div class="ringmax">/ 100</div></div></div>' \
      "$(html_escape "$(kv_get score.total)")"
    printf '<div class="gradebadge">🏆 %s</div>' "$(html_escape "$(kv_get score.grade)")"
    printf '<div class="scorebars">'
    local line name got max pct
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      IFS='|' read -r name got max <<< "$line"
      pct="$(awk -v g="$got" -v m="$max" 'BEGIN{ if(m>0) printf "%.0f", g/m*100; else print 0 }')"
      printf '<div class="sbar"><div class="sbar-lab"><span>%s %s</span><b>%s / %s</b></div>' \
        "$(_score_icon "$name")" "$(html_escape "$name")" "$(html_escape "$got")" "$(html_escape "$max")"
      printf '<div class="sbar-track"><div class="sbar-fill" style="width:%s%%"></div></div></div>' "$pct"
    done <<< "$(rows_get score)"
    printf '</div></div>\n'
  fi

  # ---- 摘要条：关键指标一眼扫完 ----
  printf '<div class="summary">'
  _sum_item() { [ -n "$3" ] && printf '<div class="si"><div class="si-ic">%s</div><span>%s</span><b>%s</b></div>' \
    "$1" "$(html_escape "$2")" "$(html_escape "$3")"; }
  _sum_item "🖥️" "配置" "$(kv_get sys.cpu.cores) 核 / $(kv_get sys.mem.total) / $(printf '%s' "$(kv_get sys.disk.summary)" | awk -F' / ' '{print $2}')"
  _sum_item "🏢" "商家套餐" "$([ -n "$(kv_get profile.vendor)" ] && printf '%s %s' "$(kv_get profile.vendor)" "$(kv_get profile.plan)")"
  _sum_item "💰" "价格"     "$(kv_get profile.price)"
  _sum_item "⏱️" "国内延迟" "$([ -n "$(kv_get ping.cn.avg)" ] && printf '%s ms' "$(kv_get ping.cn.avg)")"
  _sum_item "🚀" "就近下行" "$([ -n "$(kv_get speed.auto.down)" ] && printf '%s Mbps' "$(kv_get speed.auto.down)")"
  _sum_item "🔓" "解锁通过率" "$(kv_get unlock.v4.summary)"
  _sum_item "🛡️" "IP 类型"  "$(kv_get ipq.native)"
  _sum_item "🛰️" "回程线路" "$(kv_get route.verdict)"
  _sum_item "📥" "去程线路" "$(kv_get inbound.route_verdict)"
  unset -f _sum_item
  printf '</div>\n'

  html_copy_bar

  # ---- 目录：12 章的页面太长，给个锚点导航 ----
  printf '<nav class="toc"><b>📑 目录</b><ol>'
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
  html_section profile "📋" "一、基本配置核对"
  if rows_have profile_base; then
    printf '<h3>商家与套餐</h3>'
    html_facts profile_base
  else
    printf '<p class="na">未提供商家 / 套餐 / 价格信息，可用 <code>--config</code> 或 <code>--vendor/--plan/--dc/--price</code> 补全本节。</p>'
  fi
  printf '<h3>宣传配置 vs 实测配置</h3>'
  html_table profile_cmp "项目" "宣传值" "实测值" "核对"
  html_section_end

  # ===== 二、性能与硬件检测 =====
  html_section perf "⚙️" "二、性能与硬件检测"
  printf '<h3>系统与硬件信息</h3><div class="facts">'
  _fact_row "CPU 型号"        "$(kv_get sys.cpu.model)"
  _fact_row "CPU 核心数"      "$(kv_get sys.cpu.cores) 核"
  _fact_row "CPU 频率"        "$(kv_get sys.cpu.freq)"
  _fact_row "CPU 缓存"        "$(kv_get sys.cpu.cache)"
  _fact_row "AES-NI"          "$(kv_get sys.cpu.aes)"
  _fact_row "硬件虚拟化"      "$(kv_get sys.cpu.virt)"
  _fact_row "内存总量"        "$(kv_get sys.mem.total)"
  _fact_row "内存可用"        "$(kv_get sys.mem.avail)"
  _fact_row "内存 Buff/Cache" "$(kv_get sys.mem.buff)"
  _fact_row "Swap"            "$(kv_get sys.swap.summary)"
  _fact_row "硬盘空间"        "$(kv_get sys.disk.summary)（$(kv_get sys.disk.fs)）"
  _fact_row "操作系统"        "$(kv_get sys.os)"
  _fact_row "系统架构"        "$(kv_get sys.arch)"
  _fact_row "内核版本"        "$(kv_get sys.kernel)"
  _fact_row "虚拟化类型"      "$(kv_get sys.virt)"
  _fact_row "TCP 加速"        "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  _fact_row "协议栈"          "$(kv_get net.stack)"
  _fact_row "系统负载"        "$(kv_get sys.load)"
  _fact_row "运行时间"        "$(kv_get sys.uptime)"
  printf '</div>'
  if rows_have cpu; then
    printf '<h3>CPU 性能</h3>'; html_facts cpu
    [ -n "$(kv_get cpu.gb6.link)" ] &&
      printf '<p>Geekbench 6 完整结果：<a href="%s">%s</a></p>' \
        "$(html_escape "$(kv_get cpu.gb6.link)")" "$(html_escape "$(kv_get cpu.gb6.link)")"
  fi
  rows_have memory   && { printf '<h3>内存性能</h3>'; html_facts memory; }
  rows_have disk_dd  && { printf '<h3>磁盘顺序读写（dd）</h3>'; html_table disk_dd "块大小 × 数量" "写入速度" "读取速度"; }
  rows_have disk_fio && { printf '<h3>磁盘随机读写（fio · iodepth=64）</h3>'; html_table disk_fio "块大小" "读取" "写入" "合计"; }
  html_section_end

  # ===== 三、去程延迟 =====
  html_section inbound "📥" "三、去程延迟测试（国内 → VPS）"
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
  html_section inroute "🗺️" "四、去程路由测试（IPIP 探针）"
  if rows_have inbound_route; then
    html_routelist inbound_route
    [ -n "$(kv_get inbound.route_verdict)" ] &&
      printf '<p><b>去程线路结论：</b>%s</p>' "$(html_escape "$(kv_get inbound.route_verdict)")"
  else
    html_na inbound_route || printf '<p class="na">本节未测试。</p>'
  fi
  html_section_end

  # ===== 五、去程 MTR =====
  html_section inmtr "📶" "五、去程 MTR"
  if [ -n "$(kv_get inbound.mtr)" ]; then
    printf '<p>去程 MTR 原始数据已导入，详见第十二章「原始结果归档」。</p>'
  else
    html_na inbound_mtr || printf '<p class="na">本节未测试。</p>'
  fi
  html_section_end

  # ===== 六、回程网络质量 =====
  html_section netq "🌐" "六、回程网络质量（NetQuality）"
  if rows_have nq_bgp; then
    printf '<h3>BGP 与注册信息</h3>'; html_facts nq_bgp
  else
    html_na nq_bgp
  fi
  rows_have nq_peer  && { printf '<h3>上游与对等互联</h3>'; html_facts nq_peer; }
  rows_have nq_ixp   && { printf '<h3>互联网交换点（IXP）</h3>'; html_facts nq_ixp; }
  rows_have nq_local && { printf '<h3>本地网络策略</h3>'; html_facts nq_local; }
  if rows_have mtr_out; then
    printf '<h3>回程 MTR（丢包 / 抖动）</h3>'
    html_table mtr_out "目标" "IP" "丢包率" "平均延迟" "最优 / 最差" "抖动 StDev"
  else
    html_na mtr_out
  fi
  html_section_end

  # ===== 七、回程路由 =====
  html_section route "🛰️" "七、回程路由测试（NextTrace 三网）"
  if rows_have route; then
    html_routelist route
    [ -n "$(kv_get route.verdict)" ] &&
      printf '<p><b>回程线路结论：</b>%s</p>' "$(html_escape "$(kv_get route.verdict)")"
  else
    html_na route || printf '<p class="na">本节未测试。</p>'
  fi
  html_section_end

  # ===== 八、网络测速 =====
  html_section speed "🚀" "八、网络测速"
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
  html_section unlock "🔓" "九、流媒体与在线服务解锁"
  rows_have unlock_net && { printf '<h3>网络识别</h3>'; html_facts unlock_net; }
  if rows_have unlock4; then
    printf '<h3>IPv4 结果（通过率 %s）</h3>' "$(html_escape "$(kv_or unlock.v4.summary 'N/A')")"
    printf '<p>可用 <b>%s</b> ｜ 不可用 <b>%s</b> ｜ 待确认 <b>%s</b> ｜ 难归类 <b>%s</b></p>' \
      "$(kv_or unlock4.ok 0)" "$(kv_or unlock4.no 0)" "$(kv_or unlock4.err 0)" "$(kv_or unlock4.misc 0)"
    rows_have unlock4_ok   && { printf '<h3>✅ 可用</h3>';   html_pillrows unlock4_ok; }
    rows_have unlock4_no   && { printf '<h3>❌ 不可用</h3>'; html_pillrows unlock4_no; }
    rows_have unlock4_err  && { printf '<h3>⚠️ 待确认</h3>'; html_pillrows unlock4_err; }
    rows_have unlock4_misc && { printf '<h3>ℹ️ 难归类（地区码 / CDN 等）</h3>'; html_pillrows unlock4_misc; }
    printf '<details><summary>展开 IPv4 完整清单</summary>'
    html_pillrows unlock4
    printf '</details>'
  fi
  if rows_have unlock6; then
    printf '<h3>IPv6 结果（通过率 %s）</h3>' "$(html_escape "$(kv_or unlock.v6.summary 'N/A')")"
    html_pillrows unlock6
  else
    printf '<h3>IPv6 结果</h3>'
    html_na unlock6 || printf '<p class="na">%s</p>' "$(html_escape "$(kv_or unlock.v6.summary '本次未检测')")"
  fi
  html_section_end

  # ===== 十、IP 质量 =====
  html_section ipq "🛡️" "十、IP 质量检测"
  if rows_have ipq_base; then
    printf '<h3>基础画像</h3>'; html_facts ipq_base
    rows_have ipq_native && { printf '<h3>原生 / 广播判定</h3>'; html_facts ipq_native; }
    rows_have ipq_type   && { printf '<h3>IP 类型</h3>'; html_pillrows ipq_type; }
    rows_have ipq_risk   && { printf '<h3>风险评分</h3>'; html_facts ipq_risk; }
    rows_have ipq_rbl    && { printf '<h3>黑名单扫描（%s）</h3>' "$(html_escape "$(kv_get ipq.rbl_summary)")"
                              html_pillrows3 ipq_rbl; }
    rows_have ipq_port   && { printf '<h3>出站端口与连通性</h3>'; html_pillrows ipq_port; }
    printf '<p><b>综合判断：</b>%s——%s</p>' \
      "$(html_escape "$(kv_or ipq.native '未判定')")" "$(html_escape "$(kv_or ipq.native_reason '')")"
  else
    html_na ipq_base || printf '<p class="na">本节未测试。</p>'
  fi
  html_section_end

  # ===== 十一、适用场景与购买建议 =====
  html_section verdict "💡" "十一、适用场景与购买建议"
  if rows_have fit_yes; then printf '<h3>适合的场景</h3>'; html_scenarios fit_yes good
  else html_na fit_yes; fi
  rows_have fit_no && { printf '<h3>不适合的场景</h3>'; html_scenarios fit_no bad; }
  rows_have buy    && { printf '<h3>价格与线路建议</h3>'; html_facts buy; }
  rows_have faq    && { printf '<h3>FAQ</h3>'; html_faq; }
  html_section_end

  # ===== 十二、原始结果归档 =====
  html_section raw "🗄️" "十二、原始结果归档"
  printf '<div class="facts">'
  _fact_row "测试开始时间" "$(kv_get meta.time_local)（$(kv_get meta.time_utc)）"
  _fact_row "总耗时"       "$(kv_or meta.duration '未记录')"
  _fact_row "采集工具"     "$VPSTEST_NAME v$VPSTEST_VERSION"
  _fact_row "依赖情况"     "$(kv_or meta.deps '未记录')"
  printf '</div>'
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
