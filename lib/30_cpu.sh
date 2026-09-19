#!/usr/bin/env bash
# ============================================================
# 30_cpu.sh — CPU 性能测试（sysbench / 7z / Geekbench 可选）
# ============================================================

_sysbench_cpu() {
  local threads="$1" secs="$2" out score
  out="$(run_to $((secs + 30)) sysbench cpu --cpu-max-prime=20000 \
        --threads="$threads" --time="$secs" run 2>/dev/null)"
  score="$(printf '%s' "$out" | grep -m1 'events per second' | awk '{print $NF}')"
  [ -z "$score" ] && score="$(printf '%s' "$out" | grep -m1 'total number of events' | awk '{print $NF}')"
  printf '%s' "$score"
}

test_cpu() {
  module_enabled cpu || { log_info "跳过 CPU 测试"
    skip_note "$SKIP_REASON_OPT" cpu; return 0; }
  step "CPU 性能测试"

  local cores secs
  cores="$(kv_get sys.cpu.cores)"; [ -z "$cores" ] && cores=1
  secs=10; [ "$FAST_MODE" = "1" ] && secs=5

  need_tool sysbench >/dev/null 2>&1 || true
  if have sysbench; then
    inline "sysbench 单核 (${secs}s) ..."
    local s1; s1="$(_sysbench_cpu 1 "$secs")"
    inline_done "${s1:-失败}"
    if [ -n "$s1" ]; then
      kv_set cpu.sysbench.single "$(calc "$s1" 2)"
      row_add cpu "sysbench 单核" "$(calc "$s1" 2) events/s"
    fi

    if [ "$cores" -gt 1 ]; then
      inline "sysbench 多核 ×${cores} (${secs}s) ..."
      local sm; sm="$(_sysbench_cpu "$cores" "$secs")"
      inline_done "${sm:-失败}"
      if [ -n "$sm" ]; then
        kv_set cpu.sysbench.multi "$(calc "$sm" 2)"
        row_add cpu "sysbench ${cores} 核" "$(calc "$sm" 2) events/s"
        [ -n "$s1" ] && kv_set cpu.sysbench.scale "$(calc "$sm/$s1" 2)x"
      fi
    else
      kv_set cpu.sysbench.multi "$(kv_get cpu.sysbench.single)"
    fi
  else
    log_warn "未安装 sysbench，使用内置算力回退测试"
    _fallback_cpu "$cores"
  fi

  # 7z 压缩基准（可选，很多系统自带 p7zip）
  if have 7z || have 7za || have 7zr; then
    local bin; bin="$(command -v 7z || command -v 7za || command -v 7zr)"
    inline "7-Zip 压缩基准 ..."
    local o mips
    o="$(run_to 120 "$bin" b -mmt="$cores" 2>/dev/null | tail -20)"
    mips="$(printf '%s' "$o" | grep -m1 -E '^Tot:' | awk '{print $NF}')"
    inline_done "${mips:-跳过}"
    if [ -n "$mips" ]; then
      kv_set cpu.7z "$mips"
      row_add cpu "7-Zip 综合 (${cores} 线程)" "$mips MIPS"
    fi
  fi

  # OpenSSL AES 吞吐（衡量 AES-NI 实效）
  if have openssl; then
    inline "OpenSSL AES-256 吞吐 ..."
    local o v
    o="$(run_to 90 openssl speed -elapsed -evp aes-256-cbc 2>/dev/null | tail -3)"
    # openssl 1.x 输出 aes-256-cbc，3.x 输出 AES-256-CBC，统一忽略大小写
    v="$(printf '%s' "$o" | grep -m1 -i 'aes-256' | awk '{print $NF}')"
    local mb=""
    # 数值单位为 1000 bytes/s
    [ -n "$v" ] && mb="$(printf '%s' "$v" | sed 's/[^0-9.]//g')"
    if [ -n "$mb" ]; then
      local mbs; mbs="$(calc "$mb/1000" 0)"
      kv_set cpu.openssl "$mbs"
      row_add cpu "OpenSSL AES-256-CBC" "${mbs} MB/s (8KB 块)"
      inline_done "${mbs} MB/s"
    else
      inline_done "跳过"
    fi
  fi

  [ "$ENABLE_GEEKBENCH" = "1" ] && test_geekbench
  rows_have cpu || row_add cpu "CPU 测试" "未能获取结果"
}

# 无 sysbench 时的纯 shell/awk 回退基准
_fallback_cpu() {
  local cores="$1"
  inline "内置整数运算基准 ..."
  local t0 t1 score
  t0="$(date +%s%N 2>/dev/null || echo 0)"
  awk 'BEGIN{n=0; for(i=2;i<60000;i++){p=1; for(j=2;j*j<=i;j++){if(i%j==0){p=0;break}} n+=p} print n}' >/dev/null 2>&1
  t1="$(date +%s%N 2>/dev/null || echo 0)"
  if [ "$t0" != "0" ] && [ "$t1" != "0" ]; then
    local ms=$(( (t1 - t0) / 1000000 ))
    [ "$ms" -lt 1 ] && ms=1
    score="$(calc "100000/$ms" 2)"
    kv_set cpu.fallback "$score"
    row_add cpu "内置素数基准 (单核)" "$score 分（越高越好，耗时 ${ms}ms）"
    inline_done "$score"
  else
    inline_done "失败"
  fi
}

test_geekbench() {
  step "Geekbench 6 跑分（联网、耗时较长）"
  local arch tmp url
  arch="$(arch_tag)"
  case "$arch" in
    amd64) url="https://cdn.geekbench.com/Geekbench-6.3.0-Linux.tar.gz" ;;
    arm64) url="https://cdn.geekbench.com/Geekbench-6.3.0-LinuxARMPreview.tar.gz" ;;
    *) log_warn "Geekbench 不支持该架构: $arch"; return 0 ;;
  esac
  local mem_kb; mem_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
  if [ "${mem_kb:-0}" -lt 900000 ]; then
    log_warn "内存不足 1GB，Geekbench 可能 OOM，已跳过"
    return 0
  fi
  tmp="$BIN_DIR/gb"
  mkdir -p "$tmp"
  log_info "下载 Geekbench ..."
  if ! fetch_first "$tmp/gb.tar.gz" "$url"; then
    log_warn "Geekbench 下载失败，跳过"
    return 0
  fi
  tar -xzf "$tmp/gb.tar.gz" -C "$tmp" 2>/dev/null
  local bin; bin="$(find "$tmp" -maxdepth 2 -name 'geekbench6' -type f 2>/dev/null | head -1)"
  [ -z "$bin" ] && bin="$(find "$tmp" -maxdepth 2 -name 'geekbench_*' -type f 2>/dev/null | head -1)"
  if [ -z "$bin" ]; then log_warn "未找到 Geekbench 可执行文件"; return 0; fi
  chmod +x "$bin" 2>/dev/null
  log_info "运行 Geekbench 6（约 5-10 分钟）..."
  local out; out="$(run_to 1500 "$bin" --upload 2>/dev/null)"
  local single multi link
  single="$(printf '%s' "$out" | grep -A3 -i 'single-core score' | grep -Eo '[0-9]{3,6}' | head -1)"
  multi="$(printf '%s' "$out" | grep -A3 -i 'multi-core score' | grep -Eo '[0-9]{3,6}' | head -1)"
  link="$(printf '%s' "$out" | grep -Eo 'https://browser\.geekbench\.com/v6/cpu/[0-9]+' | head -1)"
  if [ -n "$single" ]; then
    kv_set cpu.gb6.single "$single"; kv_set cpu.gb6.multi "$multi"; kv_set cpu.gb6.link "$link"
    row_add cpu "Geekbench 6 单核" "$single"
    row_add cpu "Geekbench 6 多核" "${multi:-N/A}"
    [ -n "$link" ] && row_add cpu "Geekbench 结果链接" "$link"
    log_ok "Geekbench 6: 单核 $single / 多核 ${multi:-N/A}"
  else
    log_warn "Geekbench 未返回有效分数"
  fi
}
