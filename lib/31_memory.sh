#!/usr/bin/env bash
# ============================================================
# 31_memory.sh — 内存读写性能
# ============================================================

_sysbench_mem() {
  local op="$1" out v
  out="$(run_to 90 sysbench memory --memory-block-size=1M --memory-total-size=20G \
        --memory-oper="$op" --threads=1 run 2>/dev/null)"
  # 形如: 20480.00 MiB transferred (5120.52 MiB/sec)
  v="$(printf '%s' "$out" | grep -m1 -Eo '\(([0-9.]+) MiB/sec\)' | grep -Eo '[0-9.]+')"
  printf '%s' "$v"
}

test_memory() {
  module_enabled memory || { log_info "跳过内存测试"
    skip_note "$SKIP_REASON_OPT" memory; return 0; }
  step "内存性能测试"

  if have sysbench; then
    inline "sysbench 内存顺序读 ..."
    local r; r="$(_sysbench_mem read)"
    inline_done "${r:-失败}"
    inline "sysbench 内存顺序写 ..."
    local w; w="$(_sysbench_mem write)"
    inline_done "${w:-失败}"

    if [ -n "$r" ]; then
      kv_set mem.read "$(calc "$r" 2)"
      row_add memory "内存读取 (sysbench 1M)" "$(calc "$r/1024" 2) GB/s  ($(calc "$r" 0) MB/s)"
    fi
    if [ -n "$w" ]; then
      kv_set mem.write "$(calc "$w" 2)"
      row_add memory "内存写入 (sysbench 1M)" "$(calc "$w/1024" 2) GB/s  ($(calc "$w" 0) MB/s)"
    fi
  fi

  # dd 走 tmpfs 的回退/补充测试
  if ! rows_have memory; then
    local tdir=""
    for d in /dev/shm /run/shm /tmp; do
      [ -d "$d" ] && [ -w "$d" ] && { tdir="$d"; break; }
    done
    if [ -n "$tdir" ]; then
      inline "dd 内存写入 (tmpfs) ..."
      local o v
      o="$(run_to 60 dd if=/dev/zero of="$tdir/.vpstest_mem" bs=1M count=512 conv=fsync 2>&1)"
      v="$(printf '%s' "$o" | tail -1 | grep -Eo '[0-9.]+ [KMG]B/s' | tail -1)"
      rm -f "$tdir/.vpstest_mem" 2>/dev/null
      inline_done "${v:-失败}"
      [ -n "$v" ] && row_add memory "内存写入 (dd 1M×512)" "$v"
    fi
  fi

  rows_have memory || row_add memory "内存测试" "未能获取结果（缺少 sysbench）"
}
