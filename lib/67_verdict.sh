#!/usr/bin/env bash
# ============================================================
# 67_verdict.sh — 第 11 章：适用场景与购买建议 + FAQ
#
# 结论全部从实测数据推出来，没测到的项目不下结论，
# 免得报告看着头头是道其实是编的。
# ============================================================

# 数值比较：$1 <op> $2，op 取 lt/le/gt/ge
_num() {
  [ -z "$1" ] && return 1
  awk -v a="$1" -v b="$3" -v op="$2" 'BEGIN{
    if(op=="lt") exit !(a<b); if(op=="le") exit !(a<=b);
    if(op=="gt") exit !(a>b); if(op=="ge") exit !(a>=b); exit 1 }'
}

_unlocked() {
  # 某个服务在 IPv4 解锁表里是否为可用
  local name="$1" line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    case "${ROW_F[0]}" in
      *"$name"*) case "${ROW_F[1]}" in ✅*) return 0 ;; esac ;;
    esac
  done <<< "$(rows_get unlock4)"
  return 1
}

build_verdict() {
  module_enabled verdict || return 0
  step "适用场景与购买建议"

  local cn_lat net_dl disk_w cpu_s ul_ok
  cn_lat="$(kv_get ping.cn.avg)"
  net_dl="$(kv_get speed.auto.down)"
  disk_w="$(kv_get disk.dd.write_avg)"
  cpu_s="$(kv_get cpu.sysbench.single)"
  [ -z "$cpu_s" ] && cpu_s="$(kv_get cpu.gb6.single)"

  # ---------- 适合的场景 ----------
  if _num "$cn_lat" lt 80; then
    row_add fit_yes "国内访问的网站 / 面板 / 小型服务" \
      "国内三网平均延迟 ${cn_lat} ms，交互体验顺畅"
  elif _num "$cn_lat" lt 150; then
    row_add fit_yes "对延迟不敏感的国内业务" \
      "国内平均延迟 ${cn_lat} ms，网页可用但不适合强交互"
  fi
  if _num "$net_dl" ge 500; then
    row_add fit_yes "大流量下载 / 分发 / 备份" "就近节点下行 ${net_dl} Mbps，带宽充裕"
  fi
  if _num "$disk_w" ge 300; then
    row_add fit_yes "数据库 / 频繁读写的应用" "磁盘顺序写均值 ${disk_w} MB/s"
  fi
  if _unlocked "Netflix" || _unlocked "Disney+"; then
    row_add fit_yes "流媒体解锁自用" "Netflix / Disney+ 等主流平台已解锁"
  fi
  if _unlocked "ChatGPT" || _unlocked "Claude"; then
    row_add fit_yes "AI 服务访问" "ChatGPT / Claude 等 AI 服务可用"
  fi
  case "$(kv_get ipq.native)" in
    *原生*) row_add fit_yes "需要原生 IP 的场景" "IP 为原生段，注册地与定位地一致" ;;
  esac
  local mem_kb; mem_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
  if [ "${mem_kb:-0}" -ge 1900000 ] 2>/dev/null; then
    row_add fit_yes "容器 / 多服务共存" "内存 $(kv_get sys.mem.total)，余量充足"
  fi

  # ---------- 不适合的场景 ----------
  if _num "$cn_lat" ge 150; then
    row_add fit_no "国内强交互业务（游戏 / 远程桌面）" "国内平均延迟 ${cn_lat} ms 偏高"
  fi
  if [ -n "$net_dl" ] && _num "$net_dl" lt 200; then
    row_add fit_no "大流量分发" "就近节点下行仅 ${net_dl} Mbps"
  fi
  if [ -n "$disk_w" ] && _num "$disk_w" lt 150; then
    row_add fit_no "IO 密集型应用" "磁盘顺序写仅 ${disk_w} MB/s"
  fi
  case "$(kv_get ipq.port25)" in
    *封锁*) row_add fit_no "自建邮件服务器" "出站 25 端口被封锁" ;;
  esac
  if [ "${mem_kb:-0}" -lt 1100000 ] 2>/dev/null; then
    row_add fit_no "吃内存的应用（大型数据库 / 编译）" "内存仅 $(kv_get sys.mem.total)"
  fi
  if [ "$(kv_get sys.cpu.cores)" = "1" ]; then
    row_add fit_no "多线程并发计算" "仅 1 核，多线程无收益"
  fi
  case "$(kv_get ipq.native)" in
    *广播*) row_add fit_no "严格校验 IP 归属地的服务" "IP 为广播段，注册地与定位地不一致" ;;
  esac
  local black; black="$(kv_get ipq.rbl_black)"
  if [ "${black:-0}" -gt 0 ] 2>/dev/null; then
    row_add fit_no "发信 / 需要干净 IP 信誉的业务" "命中 ${black} 个主流黑名单"
  fi

  rows_have fit_yes || na_set fit_yes "有效测试数据不足，无法给出适用场景结论"
  rows_have fit_no  || row_add fit_no "—" "未发现明显短板"

  # ---------- 价格与线路建议 ----------
  local price; price="$(kv_get profile.price)"
  if [ -n "$price" ]; then
    row_add buy "价格" "$price"
    # 流量单价：把月流量统一换算成 GB 再除，单位不明就不算
    local pnum traffic tnum tgb
    pnum="$(printf '%s' "$price" | grep -Eo '[0-9.]+' | head -1)"
    traffic="$(kv_get profile.traffic)"
    tnum="$(printf '%s' "$traffic" | grep -Eo '[0-9.]+' | head -1)"
    tgb=""
    case "$traffic" in
      *TB|*tb|*Tb) tgb="$(calc "$tnum*1024" 2)" ;;
      *GB|*gb|*Gb) tgb="$tnum" ;;
      *TiB)        tgb="$(calc "$tnum*1024" 2)" ;;
      *GiB)        tgb="$tnum" ;;
    esac
    if [ -n "$pnum" ] && [ -n "$tgb" ] && _num "$tgb" gt 0; then
      row_add buy "流量单价" "$(calc "$pnum/$tgb" 4) ${P_CURRENCY} / GB（${price} ÷ ${traffic}）"
    fi
  else
    row_add buy "价格" "未填写（可用 --price / --config 提供后重跑）"
  fi

  # 去程和回程是两条不同的路，分开写，别混成一句
  local back fwd
  back="$(kv_get route.verdict)"
  fwd="$(kv_get inbound.route_verdict)"
  row_add buy "回程线路结论" "${back:-本次未取得回程路由数据}"
  row_add buy "去程线路结论" "${fwd:-本次未取得去程路由数据}"
  if [ -n "$cn_lat" ]; then
    row_add buy "国内延迟（回程 ping）" "平均 ${cn_lat} ms"
  fi
  [ -n "$(kv_get inbound.avg)" ] &&
    row_add buy "国内延迟（去程探针）" "平均 $(kv_get inbound.avg) ms，$(kv_get inbound.samples) 个样本"
  row_add buy "使用建议" "$(_buy_advice "$cn_lat" "$net_dl" "$back" "$fwd")"

  # ---------- FAQ ----------
  _build_faq
  log_ok "已生成适用场景、购买建议与 FAQ"
}

_buy_advice() {
  local lat="$1" dl="$2" back="$3" fwd="$4"
  local s=""
  # 回程对国内体验影响更大，优先按回程下结论；回程没测出再退而看去程
  local basis="$back" who="回程"
  if [ -z "$basis" ]; then basis="$fwd"; who="去程"; fi
  case "$basis" in
    "")          s="去程和回程都没测出来，建议补测路由后再决定；" ;;
    *CN2\ GIA*)  s="${who}走 CN2 GIA，晚高峰相对稳，适合看重国内体验的用户；" ;;
    *9929*)      s="${who}走联通 9929，联通用户体验最好，电信/移动一般；" ;;
    *CMIN2*)     s="${who}走移动 CMIN2，移动用户优先考虑；" ;;
    *CMI*)       s="${who}走移动 CMI，国内体验一般，适合国际用途；" ;;
    *163*)       s="${who}走电信 163 普通线路，晚高峰可能拥堵，价格敏感可选；" ;;
    *4837*)      s="${who}走联通 169 普通线路，晚高峰可能拥堵；" ;;
    *)           s="${who}未识别到已知优化骨干；" ;;
  esac
  # 回程已有结论但去程另有说法时，补一句提示
  if [ -n "$back" ] && [ -n "$fwd" ] && [ "$back" != "$fwd" ]; then
    s="${s}（去程为：${fwd}）"
  fi
  if _num "$lat" lt 80 && _num "$dl" ge 500; then
    s="${s}延迟与带宽都不错，按标价买不亏。"
  elif _num "$lat" lt 80; then
    s="${s}延迟表现好，带宽一般，适合轻量业务。"
  elif _num "$dl" ge 500; then
    s="${s}带宽足但延迟偏高，适合当下载/中转机。"
  else
    s="${s}综合表现一般，建议对比同价位其它机型。"
  fi
  printf '%s' "$s"
}

_build_faq() {
  # 原生还是广播
  row_add faq "这个 IP 是原生还是广播？" \
    "$(kv_or ipq.native '未测出')。$(kv_or ipq.native_reason '')"

  # 能否解锁港区流媒体
  local hk=""
  _unlocked "Netflix"    && hk="${hk}Netflix "
  _unlocked "Disney+"    && hk="${hk}Disney+ "
  _unlocked "Viu"        && hk="${hk}Viu "
  _unlocked "MyTVSuper"  && hk="${hk}MyTVSuper "
  _unlocked "Now E"      && hk="${hk}NowE "
  if [ -n "$hk" ]; then
    row_add faq "能解锁港区流媒体吗？" "可用：${hk}。完整结果见流媒体解锁章节。"
  elif rows_have unlock4; then
    row_add faq "能解锁港区流媒体吗？" "本次未检测到可用的港区流媒体，详见解锁章节。"
  else
    row_add faq "能解锁港区流媒体吗？" "本次未做解锁检测。"
  fi

  # 回程 / 去程分别是什么
  row_add faq "回程走的是什么线路？" \
    "$(kv_or route.verdict '本次未取得回程路由数据')"
  row_add faq "去程走的是什么线路？" \
    "$(kv_or inbound.route_verdict '本次未取得去程路由数据（需国内探针，用 --import-route 导入）')"

  # 性能够不够
  local perf="$(kv_get score.cpu)"
  row_add faq "性能够用吗？" \
    "CPU $(kv_or sys.cpu.model '未知') × $(kv_get sys.cpu.cores) 核，单核 sysbench $(kv_or cpu.sysbench.single 'N/A') events/s；磁盘顺序写 $(kv_or disk.dd.write_avg 'N/A') MB/s。评分 CPU ${perf:-N/A}/25、磁盘 $(kv_or score.disk 'N/A')/20。"

  # 适合谁
  local who=""
  if rows_have fit_yes; then
    local line
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      row_split "$line"
      who="${who:+$who、}${ROW_F[0]}"
    done <<< "$(rows_get fit_yes)"
  fi
  row_add faq "适合谁买？" "${who:-测试数据不足，无法给出建议}"

  # 数据会不会变
  row_add faq "这些数据会变吗？" \
    "会。测速和路由受时段、对端负载、运营商策略影响很大，晚高峰和凌晨可能差一倍以上；流媒体解锁随 IP 段策略随时会变。本报告只代表 $(kv_get meta.time_local) 这一次的测试结果，建议不同时段多测几次。"
}
