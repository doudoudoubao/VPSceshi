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
kv_set sys.mem.total    "984.27 MB"
kv_set sys.mem.avail    "855.83 MB"
kv_set sys.mem.buff     "212.60 MB"
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

# —— 第 1 章：基本配置核对 ——
P_VENDOR="DMIT"; P_PLAN="HKG.AN5.EB.Tiny"; P_DC="中国香港 HKG"
P_LINE="三网优化 / 去程直连回程 CN2 GIA"
P_CPU="1"; P_RAM="1GB"; P_DISK="20GB"; P_TRAFFIC="1TB"; P_BANDWIDTH="1Gbps"
P_IPV4="1"; P_IPV6="1"; P_PRICE="9.90"; P_CURRENCY="AUD"; P_CYCLE="月付"
row_add profile_base "商家"     "DMIT"
row_add profile_base "套餐名"   "HKG.AN5.EB.Tiny"
row_add profile_base "机房"     "中国香港 HKG"
row_add profile_base "线路宣传" "三网优化 / 去程直连回程 CN2 GIA"
row_add profile_base "月流量"   "1TB"
row_add profile_base "带宽"     "1Gbps"
row_add profile_base "价格"     "9.90 AUD / 月付"
row_add profile_cmp "CPU 核数"  "1"     "1 核"       "✅ 相符"
row_add profile_cmp "内存"      "1GB"   "984.27 MB"  "⚠️ 略低"
row_add profile_cmp "硬盘"      "20GB"  "19.56 GB"   "✅ 相符"
row_add profile_cmp "IPv4 数量" "1"     "1 个"       "✅ 相符"
row_add profile_cmp "IPv6 数量" "1"     "1 个"       "✅ 相符"
kv_set profile.price "9.90 AUD / 月付"
kv_set profile.traffic "1TB"
# 真实流程里这些由 collect_profile 写入，摘要块要用
kv_set profile.vendor "DMIT"
kv_set profile.plan   "HKG.AN5.EB.Tiny"
kv_set profile.dc     "中国香港 HKG"
kv_set profile.line   "三网优化 / 去程直连回程 CN2 GIA"
kv_set profile.bandwidth "1Gbps"
kv_set profile.ip4_count "1"
kv_set profile.ip6_count "1"

# CPU
row_add cpu "sysbench 单核"          "1462.38 events/s"
row_add cpu "7-Zip 综合 (1 线程)"    "4211 MIPS"
row_add cpu "OpenSSL AES-256-CBC"    "1382 MB/s (8KB 块)"
row_add cpu "Geekbench 6 单核"       "1688"
row_add cpu "Geekbench 6 多核"       "1702"
kv_set cpu.sysbench.single "1462.38"
kv_set cpu.gb6.single "1688"
kv_set cpu.gb6.multi  "1702"
kv_set cpu.gb6.link   "https://browser.geekbench.com/v6/cpu/12345678"

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

# —— 第 6 章：回程网络质量 / BGP ——
kv_set nq.prefix "154.31.112.0/24"
kv_set nq.holder "DMIT-AS"
kv_set nq.rdap_cc "US"
kv_set nq.rdap_name "DMIT-HK-NET"
kv_set nq.rir "ARIN（北美）"
kv_set nq.ixp_count "4"
row_add nq_bgp "BGP 前缀 Prefix"   "154.31.112.0/24"
row_add nq_bgp "Origin AS"         "AS3335"
row_add nq_bgp "网络组织 Holder"   "DMIT-AS"
row_add nq_bgp "宣告 IPv4 前缀数"  "37 条"
row_add nq_bgp "宣告 IPv6 前缀数"  "12 条"
row_add nq_bgp "注册主体 Netname"  "DMIT-HK-NET"
row_add nq_bgp "注册地区"          "US"
row_add nq_bgp "注册日期"          "2019-04-11"
row_add nq_bgp "最后修改日期"      "2025-11-02"
row_add nq_bgp "注册局 RIR"        "ARIN（北美）"
row_add nq_peer "上游数量 Upstream"        "6 个"
row_add nq_peer "下游数量 Downstream"      "2 个"
row_add nq_peer "PeeringDB 名称"           "DMIT"
row_add nq_peer "网络类型"                 "NSP"
row_add nq_peer "覆盖范围"                 "Global"
row_add nq_peer "互联网交换点 IXP 数量"    "4 个"
row_add nq_ixp "HKIX"          "10 Gbps"
row_add nq_ixp "Equinix HK"    "10 Gbps"
row_add nq_ixp "Megaport HK"   "10 Gbps"
row_add nq_ixp "AMS-IX HK"     "10 Gbps"
row_add nq_local "TCP 拥塞控制算法" "bbr"
row_add nq_local "队列调度算法"     "fq"
row_add nq_local "可用拥塞算法"     "reno cubic bbr"
row_add nq_local "IP 转发"          "未开启"
row_add nq_local "接口 MTU"         "1500"
row_add nq_local "IPv6 支持"        "✅ 可用"

# 回程 MTR
row_add mtr_out "广州电信" "58.60.188.222"  "0.0%" "12.8 ms" "12.1 / 14.6 ms" "0.7 ms"
row_add mtr_out "上海联通" "210.22.97.1"    "0.0%" "35.4 ms" "34.8 / 38.2 ms" "1.1 ms"
row_add mtr_out "上海移动" "211.136.112.200" "1.0%" "45.2 ms" "44.1 / 62.7 ms" "5.4 ms"

# —— 原生 / 广播判定 ——
kv_set ipq.native "📡 广播 IP"
kv_set ipq.native_reason "注册地 US，实际广播/定位在 HK"
row_add ipq_native "IP 类型判定"    "📡 广播 IP"
row_add ipq_native "判定依据"       "注册地 US，实际广播/定位在 HK"
row_add ipq_native "注册国（RDAP）"  "US"
row_add ipq_native "定位国（GeoIP）" "HK"
row_add ipq_native "所属前缀"        "154.31.112.0/24"
row_add ipq_native "注册主体"        "DMIT-HK-NET"
row_add ipq_native "注册局 RIR"      "ARIN（北美）"
for rbl in zen.spamhaus.org bl.spamcop.net b.barracudacentral.org cbl.abuseat.org; do
  row_add ipq_rbl "$rbl" "主流" "✅ 正常"
done
for rbl in dnsbl.sorbs.net spam.dnsbl.sorbs.net psbl.surriel.com ubl.unsubscore.com all.s5h.net; do
  row_add ipq_rbl "$rbl" "次级" "✅ 正常"
done
row_add ipq_rbl "dnsbl-1.uceprotect.net" "次级" "⚠️ 已标记"
kv_set ipq.rbl_listed "1"
kv_set ipq.rbl_black  "0"
kv_set ipq.rbl_flag   "1"
kv_set ipq.rbl_clean  "9"
kv_set ipq.rbl_valid  "10"
kv_set ipq.rbl_summary "有效 10 个 / 正常 9 个 / 已标记 1 个 / 黑名单 0 个"
row_add ipq_port "TCP 25（SMTP 明文）"   "❌ 封锁"
row_add ipq_port "TCP 465（SMTPS）"      "✅ 放行"
row_add ipq_port "TCP 587（Submission）" "✅ 放行"
row_add ipq_port "Google (www.google.com:443)" "✅ 可达"
row_add ipq_port "GitHub (github.com:443)"     "✅ 可达"

# —— 第 9 章：流媒体与在线服务解锁 ——
row_add unlock_net "出口网络"  "AS3335 DMIT"
row_add unlock_net "归属组织"  "DMIT Cloud Services"
row_add unlock_net "IPv4 出口" "154.31.*.*"
row_add unlock_net "IPv6 出口" "2404:f4c0:f45::****"
row_add unlock_net "IPv4 前缀" "154.31.112.0/24"

# 灌数据时同时写入总表和分组表，模拟 _run_unlock_suite 的行为
n_ok=0; n_no=0; n_err=0; n_misc=0
add_ul() {
  row_add unlock4 "$1" "$2"
  case "$2" in
    ✅*) n_ok=$((n_ok+1));   row_add unlock4_ok   "$1" "$2" ;;
    ❌*) n_no=$((n_no+1));   row_add unlock4_no   "$1" "$2" ;;
    ⚠️*) n_err=$((n_err+1)); row_add unlock4_err  "$1" "$2" ;;
    *)   n_misc=$((n_misc+1)); row_add unlock4_misc "$1" "$2" ;;
  esac
}
add_ul "Netflix"                        "✅ 解锁（区域: HK）"
add_ul "Netflix 优选 CDN"               "ipv4-c003-hkg001 (Hong Kong)"
add_ul "Disney+"                        "✅ 解锁（区域: HK）"
add_ul "YouTube Premium"                "✅ 解锁（区域: HK）"
add_ul "YouTube CDN 节点"               "hkg07s25"
add_ul "Amazon Prime Video"             "✅ 解锁（区域: HK）"
add_ul "Max (HBO Max)"                  "❌ 失败"
add_ul "Paramount+"                     "❌ 失败"
add_ul "DAZN"                           "✅ 解锁（区域: HK）"
add_ul "Viu.com"                        "✅ 解锁"
add_ul "Viu.TV"                         "✅ 解锁（香港）"
add_ul "MyTVSuper"                      "✅ 解锁（香港）"
add_ul "Now E"                          "✅ 解锁（香港）"
add_ul "TVB Anywhere+"                  "✅ 解锁"
add_ul "巴哈姆特動畫瘋"                 "❌ 失败"
add_ul "Bilibili 港澳台"                "✅ 解锁"
add_ul "Bilibili 台湾限定"              "❌ 失败"
add_ul "AbemaTV"                        "⚠️ 仅海外内容（HK）"
add_ul "DMM"                            "❌ 失败"
add_ul "Hulu 日本"                      "❌ 失败"
add_ul "SonyLiv"                        "❌ 失败"
add_ul "iQiyi 海外版"                   "✅ 解锁（intl）"
add_ul "SD Gundam G Generation Eternal" "⚠️ 待确认"
add_ul "TikTok"                         "✅ 解锁（区域: HK）"
add_ul "ChatGPT"                        "✅ 解锁（区域: HK）"
add_ul "Google Gemini"                  "✅ 解锁"
add_ul "Claude AI"                      "✅ 解锁"
add_ul "Google 搜索无验证码"            "✅ 正常"
add_ul "Google Play 商店地区"           "✅ HK"
add_ul "Apple 地区"                     "✅ HK"
add_ul "Bing 地区"                      "✅ HK"
add_ul "OneTrust 地区"                  "✅ HK / HK"
add_ul "Spotify 注册"                   "✅ 解锁（区域: HK）"
add_ul "Steam 货币区"                   "✅ 解锁（货币区: HKD）"
add_ul "Reddit"                         "✅ 解锁"
add_ul "维基百科访问"                   "✅ 解锁"
add_ul "维基百科可编辑性"               "❌ 不可编辑（IP 段被封）"
kv_set unlock.v4.summary "$((n_ok))/$((n_ok+n_no+n_err+n_misc))"
kv_set unlock4.ok "$n_ok"; kv_set unlock4.no "$n_no"
kv_set unlock4.err "$n_err"; kv_set unlock4.misc "$n_misc"
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

# —— 第 8 章：国际节点带宽（iperf3）——
row_add iperf "新加坡 Leaseweb 10G"     "921.44 Mbps" "887.12 Mbps" "34.2 ms"
row_add iperf "洛杉矶 Clouvider 10G"    "412.88 Mbps" "388.51 Mbps" "152.9 ms"
row_add iperf "伦敦 Clouvider 10G"      "288.31 Mbps" "265.07 Mbps" "196.4 ms"
row_add iperf "阿姆斯特丹 Eranium 100G" "301.62 Mbps" "279.88 Mbps" "188.7 ms"
row_add iperf "纽约 Leaseweb 10G"       "342.19 Mbps" "318.44 Mbps" "212.3 ms"

# —— 第 3/4/5 章：去程数据，直接用 examples/ 下的样例文件跑真实解析 ——
[ -r "$ROOT/examples/inbound-ping.csv" ]  && parse_inbound_ping  "$ROOT/examples/inbound-ping.csv"  >/dev/null 2>&1
[ -r "$ROOT/examples/inbound-route.txt" ] && parse_inbound_route "$ROOT/examples/inbound-route.txt" >/dev/null 2>&1
na_set inbound_mtr "本次未取得有效去程 MTR 数据，丢包与抖动未评估"

# 回程路由结论：真实流程里由 test_route 汇总，这里补上
_summarize_route route route.verdict

# ---------- 评分、结论并出报告 ----------
calc_score >/dev/null 2>&1
build_verdict >/dev/null 2>&1

mkdir -p "$OUT"
gen_markdown > "$OUT/sample-report.md"
gen_nodeseek > "$OUT/sample-report.nodeseek.md"
gen_bbcode   > "$OUT/sample-report.bbcode"
gen_html     > "$OUT/sample-report.html"
gen_json     > "$OUT/sample-report.json"
gen_txt      > "$OUT/sample-report.txt"

echo "[+] 样例报告已生成到: $OUT"
for e in md nodeseek.md bbcode html json txt; do
  printf '    %-28s %s\n' "sample-report.$e" "$(wc -c < "$OUT/sample-report.$e") 字节"
done

# ---------- 基本校验 ----------
fail=0
check() { if eval "$2"; then echo "  [OK]  $1"; else echo "  [FAIL] $1"; fail=1; fi; }
echo
echo "校验:"
check "JSON 合法"           "jq -e . '$OUT/sample-report.json' >/dev/null 2>&1 || ! command -v jq >/dev/null"
check "Markdown 含评分表"   "grep -q '综合评分' '$OUT/sample-report.md'"
check "Markdown 含 12 章"   "[ \$(grep -c '^## [一二三四五六七八九十]' '$OUT/sample-report.md') -eq 12 ]"
check "BBCode 表格闭合"     "[ \$(grep -c '\[table\]' '$OUT/sample-report.bbcode') -eq \$(grep -c '\[/table\]' '$OUT/sample-report.bbcode') ]"
check "BBCode 无残留 emoji"  "! grep -q '✅' '$OUT/sample-report.bbcode'"
check "HTML 结构完整"       "grep -q '</html>' '$OUT/sample-report.html'"
check "HTML 表格闭合"       "[ \$(grep -o '<table' '$OUT/sample-report.html' | wc -l) -eq \$(grep -o '</table>' '$OUT/sample-report.html' | wc -l) ]"
check "HTML section 闭合"   "[ \$(grep -o '<section' '$OUT/sample-report.html' | wc -l) -eq \$(grep -o '</section>' '$OUT/sample-report.html' | wc -l) ]"
check "HTML details 闭合"   "[ \$(grep -o '<details' '$OUT/sample-report.html' | wc -l) -eq \$(grep -o '</details>' '$OUT/sample-report.html' | wc -l) ]"
# 逐章检查，防止改报告生成器时漏掉某一节
for sec in 基本配置核对 性能与硬件检测 去程延迟测试 去程路由测试 去程MTR \
           回程网络质量 回程路由测试 网络测速 流媒体与在线服务解锁 \
           IP质量检测 适用场景与购买建议 原始结果归档; do
  pat="$(printf '%s' "$sec" | sed 's/MTR/ MTR/; s/IP质量/IP 质量/')"
  check "MD 含「$pat」" "grep -q '$pat' '$OUT/sample-report.md'"
  check "HTML 含「$pat」" "grep -q '$pat' '$OUT/sample-report.html'"
done
check "去程延迟已按运营商汇总" "grep -q '中国电信' '$OUT/sample-report.md'"
check "去程延迟已按大区汇总"   "grep -q '华东' '$OUT/sample-report.md'"
check "去程路由识别出线路"     "grep -q 'CN2 GIA' '$OUT/sample-report.md'"
check "去程 MTR 标注未取得"    "grep -q '未取得有效去程 MTR 数据' '$OUT/sample-report.md'"
check "解锁结果已分组"         "grep -q '难归类' '$OUT/sample-report.md'"
check "含原生/广播判定"        "grep -q '广播 IP' '$OUT/sample-report.md'"
check "含 BGP 前缀"            "grep -q '154.31.112.0/24' '$OUT/sample-report.md'"
check "含 FAQ"                 "grep -q '数据会变吗\|这些数据会变吗' '$OUT/sample-report.md'"
check "含 Geekbench 链接"      "grep -q 'browser.geekbench.com' '$OUT/sample-report.md'"
check "TXT 含 12 章"           "[ \$(grep -c '^\[ [一二三四五六七八九十]' '$OUT/sample-report.txt') -eq 12 ]"
# 摘要块与目录：读者先拿结论，长页面要能跳转
check "MD 摘要含商家套餐"   "grep -q '商家套餐.*DMIT' '$OUT/sample-report.md'"
check "MD 摘要含回程线路"   "grep -q '回程线路.*CN2 GIA' '$OUT/sample-report.md'"
check "MD 摘要含解锁通过率" "grep -q '解锁通过率' '$OUT/sample-report.md'"
check "HTML 有摘要条"       "grep -q 'class=\"summary\"' '$OUT/sample-report.html'"
check "HTML 有目录"         "grep -q 'class=\"toc\"' '$OUT/sample-report.html'"
check "HTML 目录锚点齐全"   "[ \$(grep -o 'href=\"#[a-z]*\"' '$OUT/sample-report.html' | sort -u | wc -l) -eq 12 ]"
# 目录里每个锚点都必须真有对应的 section，否则点了跳不动
check "HTML 锚点都有对应章节" '
  for a in $(grep -o "href=\"#[a-z]*\"" "'"$OUT"'/sample-report.html" | sed "s/.*#//; s/\"//"); do
    grep -q "<section id=\"$a\"" "'"$OUT"'/sample-report.html" || exit 1
  done'
# 「未运行」和「未取得」不能混为一谈
check "报告无自相矛盾措辞"  "! grep -q '未取得有效数据：本次未运行' '$OUT/sample-report.md'"

# ---------- NodeSeek 版：容器嵌套必须闭合，否则整贴排版崩掉 ----------
NS="$OUT/sample-report.nodeseek.md"
ns_balance() {
  awk '
    # 代码块里的 ::: 是原始输出，不算容器
    /^```/ { fence = !fence; next }
    fence  { next }
    /^:::: [^ ]/ { d4++; next }
    /^::::$/     { d4--; if (d4 < 0) { print "4 级容器提前闭合，行 " NR; bad=1 } next }
    /^::: [^ ]/  { d3++; next }
    /^:::$/      { d3--; if (d3 < 0) { print "3 级容器提前闭合，行 " NR; bad=1 } next }
    END {
      if (d4 != 0) { print "tabs 容器未闭合，差 " d4; bad=1 }
      if (d3 != 0) { print "tab-item/details 容器未闭合，差 " d3; bad=1 }
      exit bad
    }' "$1"
}
check "NodeSeek 容器闭合"       "ns_balance '$NS'"
check "NodeSeek 含 12 章"       "[ \$(grep -c '^## [一二三四五六七八九十]' '$NS') -eq 12 ]"
check "NodeSeek 用了 tabs 容器"  "grep -q '^:::: tabs' '$NS'"
check "NodeSeek 用了 tab-item"   "grep -q '^::: tab-item ' '$NS'"
check "NodeSeek 用了 details"    "grep -q '^::: details ' '$NS'"
check "NodeSeek 无 HTML details" "! grep -q '<details>' '$NS'"
check "NodeSeek 无 BBCode 残留"  "! grep -q '\[table\]\|\[/td\]\|\[size=' '$NS'"
check "NodeSeek 有评分进度条"    "grep -q '█' '$NS'"
check "NodeSeek 摘要含结论"      "grep -q '综合评分.*100' '$NS'"
check "NodeSeek FAQ 展开成问答"  "grep -q '^\*\*Q：' '$NS'"
# 关掉 tabs 后必须仍然闭合，且退化成三级标题
NS_USE_TABS=0
gen_nodeseek > "$OUT/.ns-notabs.md"
check "NodeSeek 无 tabs 模式闭合"   "ns_balance '$OUT/.ns-notabs.md'"
check "NodeSeek 无 tabs 模式无容器" "! grep -q '^:::: tabs' '$OUT/.ns-notabs.md'"
check "NodeSeek 无 tabs 模式有标题" "grep -q '^### ' '$OUT/.ns-notabs.md'"
rm -f "$OUT/.ns-notabs.md"
NS_USE_TABS=1
exit "$fail"
