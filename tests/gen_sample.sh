#!/usr/bin/env bash
# ============================================================
# tests/gen_sample.sh — 用样例数据跑通全部报告生成路径
#
# 网络测试依赖外网，CI / 沙箱里跑不了。这个脚本直接给结果存储
# 灌入一份完整的样例数据，验证 5 种报告格式的渲染是否正确，
# 同时产出 docs/ 下的示例报告。
#
#   ./tests/gen_sample.sh [输出目录]
# ============================================================

set -o pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SELF_DIR")"
OUT="${1:-$ROOT/docs}"

for f in "$ROOT"/lib/*.sh; do
  # shellcheck disable=SC1090
  . "$f"
done

# ---------- 灌入样例数据（仿 DMIT HKG 小鸡的典型结果） ----------
kv_set meta.node_name  "DMIT HKG.AN5.EB.Tiny"
kv_set meta.time_local "2026-09-19 16:20:31 CST"
kv_set meta.time_utc   "2026-09-19 08:20:31 UTC"
kv_set meta.duration   "14 分 08 秒"
kv_set meta.deps       "可用: curl wget bc jq sysbench fio ping dig tar"

kv_set sys.cpu.model "Intel(R) Xeon(R) Platinum 8375C CPU @ 2.90GHz"
kv_set sys.cpu.cores "1"
kv_set sys.cpu.freq  "2899.9 MHz"
kv_set sys.cpu.cache "L1d: 48 KiB  L2: 1.3 MiB  L3: 54 MiB"
kv_set sys.cpu.aes   "✔ 已启用"
kv_set sys.cpu.virt  "✘ 未启用"
kv_set sys.mem.summary  "128.44 MB / 984.27 MB"
kv_set sys.swap.summary "0 B / 512.00 MB"
kv_set sys.disk.summary "2.13 GB / 19.56 GB"
kv_set sys.disk.fs      "ext4"
kv_set sys.os      "Debian GNU/Linux 12 (bookworm)"
kv_set sys.arch    "x86_64"
kv_set sys.kernel  "6.1.0-23-amd64"
kv_set sys.virt    "KVM"
kv_set sys.tcp.cc    "bbr"
kv_set sys.tcp.qdisc "fq"
kv_set sys.load   "0.00 0.01 0.05"
kv_set sys.uptime "3 天 7 小时 12 分"

kv_set net.ip4      "154.31.*.*"
kv_set net.ip6      "2404:f4c0:f45::****"
kv_set net.stack    "IPv4 + IPv6"
kv_set net.location "中国香港 Hong Kong"
kv_set net.as       "AS3335 DMIT"
kv_set net.org      "DMIT Cloud Services"
kv_set net.isp      "DMIT"
kv_set net.rdns     "无"
kv_set net.tz       "Asia/Hong_Kong"

# CPU
row_add cpu "sysbench 单核"          "1462.38 events/s"
row_add cpu "7-Zip 综合 (1 线程)"    "4211 MIPS"
row_add cpu "OpenSSL AES-256-CBC"    "1382 MB/s (8KB 块)"
kv_set cpu.sysbench.single "1462.38"

# 内存
row_add memory "内存读取 (sysbench 1M)" "11.82 GB/s  (12103 MB/s)"
row_add memory "内存写入 (sysbench 1M)" "9.47 GB/s  (9697 MB/s)"

# 磁盘
row_add disk_dd "1M × 1000"   "512 MB/s"  "1.1 GB/s"
row_add disk_dd "1M × 1000"   "498 MB/s"  "1.2 GB/s"
row_add disk_dd "128K × 8000" "421 MB/s"  "903 MB/s"
kv_set disk.dd.write_avg "477"
row_add disk_fio "4k"   "112.44 MB/s (28784 IOPS)" "112.61 MB/s (28828 IOPS)" "225.05 MB/s (57612 IOPS)"
row_add disk_fio "64k"  "398.21 MB/s (6371 IOPS)"  "400.35 MB/s (6405 IOPS)"  "798.56 MB/s (12776 IOPS)"
row_add disk_fio "512k" "612.88 MB/s (1225 IOPS)"  "615.02 MB/s (1230 IOPS)"  "1227.90 MB/s (2455 IOPS)"
row_add disk_fio "1m"   "644.10 MB/s (644 IOPS)"   "647.33 MB/s (647 IOPS)"   "1291.43 MB/s (1291 IOPS)"

# IP 质量
row_add ipq_base "IP 地址"      "154.31.*.*"
row_add ipq_base "ASN"          "AS3335 DMIT"
row_add ipq_base "归属组织"     "DMIT Cloud Services"
row_add ipq_base "运营商 ISP"   "DMIT"
row_add ipq_base "地理位置"     "中国香港 Hong Kong"
row_add ipq_base "反向解析 PTR" "无"
row_add ipq_base "时区"         "Asia/Hong_Kong"
row_add ipq_type "IDC / 机房 IP"   "是"
row_add ipq_type "代理 Proxy"      "否"
row_add ipq_type "VPN"             "否"
row_add ipq_type "Tor 出口节点"    "否"
row_add ipq_type "滥用记录 Abuser" "否"
row_add ipq_type "爬虫 Crawler"    "否"
row_add ipq_type "ASN 类型"        "hosting"
row_add ipq_risk "Scamalytics 欺诈分" "12 / 100（低风险）"
row_add ipq_risk "AbuseIPDB 滥用置信度" "0%"
row_add ipq_risk "Cloudflare 接入 POP"  "HKG（国家判定: HK）"
kv_set ipq.scamalytics "12"
for rbl in zen.spamhaus.org bl.spamcop.net b.barracudacentral.org dnsbl.sorbs.net psbl.surriel.com; do
  row_add ipq_rbl "$rbl" "✅ 干净"
done
row_add ipq_rbl "dnsbl-1.uceprotect.net" "❌ 已列入黑名单"
kv_set ipq.rbl_listed "1"
kv_set ipq.rbl_summary "5 个干净 / 1 个命中（共 6 个库）"
row_add ipq_port "TCP 25（SMTP 明文）"   "❌ 封锁"
row_add ipq_port "TCP 465（SMTPS）"      "✅ 放行"
row_add ipq_port "TCP 587（Submission）" "✅ 放行"
row_add ipq_port "Google (www.google.com:443)" "✅ 可达"
row_add ipq_port "GitHub (github.com:443)"     "✅ 可达"

# 解锁
add_ul() { row_add unlock4 "$1" "$2"; }
add_ul "Netflix"              "✅ 解锁（区域: HK）"
add_ul "Disney+"              "✅ 解锁（区域: HK）"
add_ul "YouTube Premium"      "✅ 解锁（区域: HK）"
add_ul "Amazon Prime Video"   "✅ 解锁（区域: HK）"
add_ul "Max (HBO Max)"        "❌ 失败"
add_ul "Paramount+"           "❌ 失败"
add_ul "DAZN"                 "✅ 解锁（区域: HK）"
add_ul "Spotify 注册"         "✅ 解锁（区域: HK）"
add_ul "TikTok"               "✅ 解锁（区域: HK）"
add_ul "Steam 商店"           "✅ 解锁（货币区: HKD）"
add_ul "ChatGPT"              "✅ 解锁（区域: HK）"
add_ul "Google Gemini"        "✅ 解锁"
add_ul "Claude AI"            "✅ 解锁"
add_ul "巴哈姆特動畫瘋"       "❌ 失败"
add_ul "AbemaTV"              "⚠️ 仅海外内容（HK）"
add_ul "DMM"                  "❌ 失败"
add_ul "Hulu 日本"            "❌ 失败"
add_ul "TVB Anywhere+"        "✅ 解锁"
add_ul "Bilibili 港澳台"      "✅ 解锁"
add_ul "Bilibili 台湾限定"    "❌ 失败"
add_ul "维基百科"             "✅ 解锁"
add_ul "Google 搜索"          "✅ 正常"
kv_set unlock.v4.summary "16/22"
kv_set unlock.v4.ytcdn   "hkg07s25"
row_add unlock6 "Netflix"         "✅ 解锁（区域: HK）"
row_add unlock6 "YouTube Premium" "✅ 解锁（区域: HK）"
row_add unlock6 "ChatGPT"         "❌ 失败"
kv_set unlock.v6.summary "2/3"

# 延迟
row_add ping_cn "北京电信"   "电信"   "48.2 ms"  "0%"
row_add ping_cn "上海电信"   "电信"   "31.6 ms"  "0%"
row_add ping_cn "广州电信"   "电信"   "12.4 ms"  "0%"
row_add ping_cn "北京联通"   "联通"   "52.8 ms"  "0%"
row_add ping_cn "上海联通"   "联通"   "35.1 ms"  "0%"
row_add ping_cn "广州联通"   "联通"   "14.7 ms"  "0%"
row_add ping_cn "北京移动"   "移动"   "61.3 ms"  "0%"
row_add ping_cn "上海移动"   "移动"   "44.9 ms"  "0%"
row_add ping_cn "广州移动"   "移动"   "18.2 ms"  "0%"
row_add ping_cn "北京教育网" "教育网" "78.5 ms"  "0%"
kv_set ping.cn.avg "39.8"
row_add ping_gl "香港 HKIX"      "亚太" "1.2 ms"   "0%"
row_add ping_gl "日本 东京"      "亚太" "48.6 ms"  "0%"
row_add ping_gl "新加坡"         "亚太" "34.2 ms"  "0%"
row_add ping_gl "美国 洛杉矶"    "美洲" "152.7 ms" "0%"
row_add ping_gl "德国 法兰克福"  "欧洲" "198.4 ms" "0%"
kv_set ping.global.avg "87.0"

# 测速
row_add speed_auto "就近节点" "946.21 Mbps" "912.55 Mbps" "1.84 ms" "0.21 ms" "HKBN Hong Kong"
kv_set speed.auto.down "946.21"
row_add speed_cn "上海电信" "412.33 Mbps" "88.21 Mbps"  "31.44 ms" "1.82 ms" "China Telecom Shanghai"
row_add speed_cn "上海联通" "508.77 Mbps" "102.65 Mbps" "34.91 ms" "2.10 ms" "China Unicom Shanghai"
row_add speed_cn "上海移动" "266.54 Mbps" "71.38 Mbps"  "45.02 ms" "3.44 ms" "China Mobile Shanghai"
row_add speed_cn "广州电信" "633.18 Mbps" "121.44 Mbps" "12.61 ms" "0.95 ms" "China Telecom Guangdong"
row_add speed_gl "日本 东京"   "878.42 Mbps" "702.11 Mbps" "48.33 ms"  "1.12 ms" "IIJ Tokyo"
row_add speed_gl "新加坡 SG"   "812.09 Mbps" "655.73 Mbps" "34.18 ms"  "0.88 ms" "StarHub Singapore"
row_add speed_gl "美国 洛杉矶" "421.66 Mbps" "310.24 Mbps" "152.91 ms" "4.07 ms" "Zenlayer Los Angeles"

# 路由
row_add route "北京电信" "219.141.140.10" "CN2 GIA (AS4809/59.43)"
row_add route "上海电信" "202.96.209.133" "CN2 GIA (AS4809/59.43)"
row_add route "广州电信" "58.60.188.222"  "CN2 GIA (AS4809/59.43)"
row_add route "北京联通" "202.106.195.68" "联通 A网 CUII (AS9929)"
row_add route "上海联通" "210.22.97.1"    "联通 A网 CUII (AS9929)"
row_add route "北京移动" "221.183.129.101" "移动 CMIN2 (AS58807)"
raw_add "回程路由 · 上海电信 (202.96.209.133)" "$(cat <<'RAW'
traceroute to 202.96.209.133, 30 hops max
 1  10.0.0.1                        0.42 ms  AS*     局域网
 2  154.31.112.1                    0.88 ms  AS3335  中国 香港 DMIT
 3  59.43.187.29                    2.14 ms  AS4809  中国 香港 电信 CN2
 4  59.43.130.77                   28.66 ms  AS4809  中国 上海 电信 CN2
 5  202.97.94.153                  31.02 ms  AS4134  中国 上海 电信
 6  202.96.209.133                 31.44 ms  AS4134  中国 上海 电信
RAW
)"

# ---------- 评分并出报告 ----------
calc_score >/dev/null 2>&1

mkdir -p "$OUT"
gen_markdown > "$OUT/sample-report.md"
gen_bbcode   > "$OUT/sample-report.bbcode"
gen_html     > "$OUT/sample-report.html"
gen_json     > "$OUT/sample-report.json"
gen_txt      > "$OUT/sample-report.txt"

echo "[+] 样例报告已生成到: $OUT"
for e in md bbcode html json txt; do
  printf '    %-28s %s\n' "sample-report.$e" "$(wc -c < "$OUT/sample-report.$e") 字节"
done

# ---------- 基本校验 ----------
fail=0
check() { if eval "$2"; then echo "  [OK]  $1"; else echo "  [FAIL] $1"; fail=1; fi; }
echo
echo "校验:"
check "JSON 合法"          "jq -e . '$OUT/sample-report.json' >/dev/null 2>&1 || ! command -v jq >/dev/null"
check "Markdown 含评分表"  "grep -q '综合评分' '$OUT/sample-report.md'"
check "Markdown 含所有章节" "[ \$(grep -c '^## ' '$OUT/sample-report.md') -ge 9 ]"
check "BBCode 表格闭合"    "[ \$(grep -c '\[table\]' '$OUT/sample-report.bbcode') -eq \$(grep -c '\[/table\]' '$OUT/sample-report.bbcode') ]"
check "BBCode 无残留 emoji" "! grep -q '✅' '$OUT/sample-report.bbcode'"
check "HTML 结构完整"      "grep -q '</html>' '$OUT/sample-report.html'"
check "HTML 无未闭合表格"  "[ \$(grep -o '<table' '$OUT/sample-report.html' | wc -l) -eq \$(grep -o '</table>' '$OUT/sample-report.html' | wc -l) ]"
check "TXT 含路由章节"     "grep -q '回程路由' '$OUT/sample-report.txt'"
exit "$fail"
