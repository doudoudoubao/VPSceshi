#!/usr/bin/env bash
# ============================================================
# 65_score.sh — 综合评分（CPU / 磁盘 / 网络 / 解锁 / IP 质量）
# ============================================================

# 归一化：value 相对 base 得满分 full，线性截断
_norm() {
  local v="$1" base="$2" full="$3"
  [ -z "$v" ] && { printf '0'; return; }
  local s; s="$(calc "$v/$base*$full" 1)"
  local cmp; cmp="$(awk -v a="$s" -v b="$full" 'BEGIN{print (a>b)?1:0}')"
  [ "$cmp" = "1" ] && s="$full"
  printf '%s' "$s"
}

calc_score() {
  step "综合评分"
  local total=0

  # --- CPU（满分 25）：以 sysbench 单核 2000 events/s 为满分参考 ---
  local cpu_s=0 v
  v="$(kv_get cpu.sysbench.single)"
  if [ -n "$v" ]; then
    cpu_s="$(_norm "$v" 2000 25)"
  elif [ -n "$(kv_get cpu.gb6.single)" ]; then
    cpu_s="$(_norm "$(kv_get cpu.gb6.single)" 1800 25)"
  elif [ -n "$(kv_get cpu.fallback)" ]; then
    cpu_s="$(_norm "$(kv_get cpu.fallback)" 300 25)"
  fi
  kv_set score.cpu "$cpu_s"
  total="$(calc "$total+$cpu_s" 1)"

  # --- 磁盘（满分 20）：dd 写入 500MB/s 为满分 ---
  local disk_s=0
  v="$(kv_get disk.dd.write_avg)"
  [ -n "$v" ] && disk_s="$(_norm "$v" 500 20)"
  kv_set score.disk "$disk_s"
  total="$(calc "$total+$disk_s" 1)"

  # --- 网络带宽（满分 25）：就近节点下行 1000Mbps 为满分 ---
  local net_s=0
  v="$(kv_get speed.auto.down)"
  [ -n "$v" ] && net_s="$(_norm "$v" 1000 25)"
  kv_set score.net "$net_s"
  total="$(calc "$total+$net_s" 1)"

  # --- 国内延迟（满分 15）：<=60ms 满分，>=250ms 0 分 ---
  local lat_s=0
  v="$(kv_get ping.cn.avg)"
  if [ -n "$v" ]; then
    lat_s="$(awk -v p="$v" 'BEGIN{
      if(p<=60) s=15; else if(p>=250) s=0; else s=15*(250-p)/190;
      printf "%.1f", s }')"
  fi
  kv_set score.latency "$lat_s"
  total="$(calc "$total+$lat_s" 1)"

  # --- 解锁（满分 10）---
  local ul_s=0 sm pass tot
  sm="$(kv_get unlock.v4.summary)"
  if [ -n "$sm" ]; then
    pass="${sm%%/*}"; tot="${sm##*/}"
    [ "${tot:-0}" -gt 0 ] 2>/dev/null && ul_s="$(calc "$pass/$tot*10" 1)"
  fi
  kv_set score.unlock "$ul_s"
  total="$(calc "$total+$ul_s" 1)"

  # --- IP 质量（满分 5）：欺诈分越低越好 + 黑名单 ---
  # 模块未执行（无 IP 或被跳过）时不白送分
  local ipq_s=0 fs
  rows_have ipq_base && ipq_s=5
  fs="$(kv_get ipq.scamalytics)"
  if [ -n "$fs" ]; then
    ipq_s="$(awk -v f="$fs" 'BEGIN{ s=5*(100-f)/100; if(s<0)s=0; printf "%.1f", s }')"
  fi
  local listed; listed="$(kv_get ipq.rbl_listed)"
  if [ "${listed:-0}" -gt 0 ] 2>/dev/null; then
    ipq_s="$(awk -v s="$ipq_s" -v n="$listed" 'BEGIN{ v=s-n*0.5; if(v<0)v=0; printf "%.1f", v }')"
  fi
  kv_set score.ipq "$ipq_s"
  total="$(calc "$total+$ipq_s" 1)"

  kv_set score.total "$(calc "$total" 1)"

  local grade
  grade="$(awk -v t="$total" 'BEGIN{
    if(t>=85) print "S 级 · 优秀";
    else if(t>=70) print "A 级 · 良好";
    else if(t>=55) print "B 级 · 中等";
    else if(t>=40) print "C 级 · 一般";
    else print "D 级 · 较弱" }')"
  kv_set score.grade "$grade"

  row_add score "CPU 性能"   "$(kv_get score.cpu)"     "25"
  row_add score "磁盘 I/O"   "$(kv_get score.disk)"    "20"
  row_add score "网络带宽"   "$(kv_get score.net)"     "25"
  row_add score "国内延迟"   "$(kv_get score.latency)" "15"
  row_add score "流媒体解锁" "$(kv_get score.unlock)"  "10"
  row_add score "IP 质量"    "$(kv_get score.ipq)"     "5"

  log_ok "综合得分: $(kv_get score.total) / 100  —  $grade"
}
