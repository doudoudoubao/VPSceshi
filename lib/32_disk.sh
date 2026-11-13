#!/usr/bin/env bash
# ============================================================
# 32_disk.sh — 磁盘 I/O 测试（dd + fio 多块大小混合读写）
# ============================================================

DISK_WORKDIR=""

_pick_disk_dir() {
  local d
  for d in "$PWD" /root /var/tmp /tmp; do
    [ -d "$d" ] && [ -w "$d" ] || continue
    # 需要至少 2GB 可用空间
    local avail; avail="$(df -k "$d" 2>/dev/null | tail -1 | awk '{print $4}')"
    [ "${avail:-0}" -gt 2200000 ] 2>/dev/null && { printf '%s' "$d"; return 0; }
  done
  # 放宽到 600MB
  for d in "$PWD" /root /var/tmp /tmp; do
    [ -d "$d" ] && [ -w "$d" ] || continue
    local avail; avail="$(df -k "$d" 2>/dev/null | tail -1 | awk '{print $4}')"
    [ "${avail:-0}" -gt 600000 ] 2>/dev/null && { printf '%s' "$d"; return 0; }
  done
  return 1
}

_dd_write() {
  local bs="$1" count="$2" f="$DISK_WORKDIR/.vpstest_dd"
  local o
  # dd 把速度统计写在 stderr，必须用 run_to2 合并过来
  o="$(run_to2 90 dd if=/dev/zero of="$f" bs="$bs" count="$count" oflag=direct conv=fsync)"
  if ! printf '%s' "$o" | grep -qE 'copied|bytes'; then
    # 部分文件系统 / 容器不支持 O_DIRECT，退回普通写入
    o="$(run_to2 90 dd if=/dev/zero of="$f" bs="$bs" count="$count" conv=fsync)"
  fi
  printf '%s' "$o" | grep -Eo '[0-9.]+ [KMG]?B/s' | tail -1
}

_dd_read() {
  local bs="$1" count="$2" f="$DISK_WORKDIR/.vpstest_dd"
  [ -f "$f" ] || return 1
  sync 2>/dev/null
  [ -w /proc/sys/vm/drop_caches ] && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
  local o
  o="$(run_to2 90 dd if="$f" of=/dev/null bs="$bs" count="$count" iflag=direct)"
  if ! printf '%s' "$o" | grep -qE 'copied|bytes'; then
    o="$(run_to2 90 dd if="$f" of=/dev/null bs="$bs" count="$count")"
  fi
  printf '%s' "$o" | grep -Eo '[0-9.]+ [KMG]?B/s' | tail -1
}

# 挑一个当前 fio 真的支持的 ioengine：
# libaio 要装 libaio 库，最小化系统上常常没有；io_uring 要新内核；
# psync 一定有，只是 iodepth 用不上。探测一次缓存下来。
FIO_ENGINE=""
_fio_pick_engine() {
  [ -n "$FIO_ENGINE" ] && return 0
  local avail e
  avail="$(fio --enghelp 2>/dev/null)"
  for e in libaio io_uring psync; do
    case "$avail" in *"$e"*) FIO_ENGINE="$e"; break ;; esac
  done
  [ -z "$FIO_ENGINE" ] && FIO_ENGINE="psync"
  [ "$FIO_ENGINE" != "libaio" ] && log_info "fio 使用 ioengine=$FIO_ENGINE"
  return 0
}

# fio 单项：<块大小> <读写模式> <文件大小> <运行秒数>
# 输出 "读IOPS|读MB/s|写IOPS|写MB/s"
_fio_one() {
  local bs="$1" rw="$2" size="$3" secs="$4"
  local out riops wiops rbw wbw
  _fio_pick_engine

  # direct=1 在 tmpfs / 某些 overlayfs 上不被支持，失败就退回缓冲 IO
  local direct
  for direct in 1 0; do
    out="$(run_to $((secs + 60)) fio --name=vpstest --directory="$DISK_WORKDIR" \
          --filename=.vpstest_fio --rw="$rw" --bs="$bs" --size="$size" \
          --ioengine="$FIO_ENGINE" --direct="$direct" --iodepth=64 --numjobs=1 \
          --runtime="$secs" --time_based --group_reporting \
          --output-format=json --unlink=0 2>/dev/null)"
    case "$out" in *'"jobs"'*) break ;; *) out="" ;; esac
  done
  [ -z "$out" ] && return 1
  if have jq; then
    riops="$(printf '%s' "$out" | jq -r '.jobs[0].read.iops // 0'  2>/dev/null)"
    wiops="$(printf '%s' "$out" | jq -r '.jobs[0].write.iops // 0' 2>/dev/null)"
    rbw="$(printf '%s'   "$out" | jq -r '.jobs[0].read.bw // 0'    2>/dev/null)"
    wbw="$(printf '%s'   "$out" | jq -r '.jobs[0].write.bw // 0'   2>/dev/null)"
  else
    riops="$(printf '%s' "$out" | grep -m1 -A20 '"read"'  | grep -m1 '"iops"' | grep -Eo '[0-9.]+' | head -1)"
    wiops="$(printf '%s' "$out" | grep -m1 -A20 '"write"' | grep -m1 '"iops"' | grep -Eo '[0-9.]+' | head -1)"
    rbw="$(printf '%s'   "$out" | grep -m1 -A20 '"read"'  | grep -m1 '"bw"'   | grep -Eo '[0-9.]+' | head -1)"
    wbw="$(printf '%s'   "$out" | grep -m1 -A20 '"write"' | grep -m1 '"bw"'   | grep -Eo '[0-9.]+' | head -1)"
  fi
  # bw 单位为 KiB/s；IOPS 取整
  printf '%s|%s|%s|%s' \
    "$(calc "${riops:-0}/1" 0)" "$(calc "${rbw:-0}/1024" 2)" \
    "$(calc "${wiops:-0}/1" 0)" "$(calc "${wbw:-0}/1024" 2)"
}

test_disk() {
  module_enabled disk || { log_info "跳过磁盘测试"
    skip_note "$SKIP_REASON_OPT" disk_dd disk_fio; return 0; }
  step "磁盘 I/O 测试"

  if ! DISK_WORKDIR="$(_pick_disk_dir)"; then
    log_warn "磁盘可用空间不足，跳过 I/O 测试"
    row_add disk_dd "磁盘测试" "跳过（可用空间不足）"
    return 0
  fi
  log_info "测试目录: $DISK_WORKDIR （文件系统: $(kv_get sys.disk.fs)）"

  # ---------- dd 顺序读写 ----------
  local specs
  if [ "$FAST_MODE" = "1" ]; then
    specs="1M:512 128K:2000"
  else
    specs="1M:1000 128K:8000"
  fi
  local i=0 sum_w=0 n_w=0
  for s in $specs; do
    i=$((i + 1))
    local bs="${s%%:*}" cnt="${s##*:}"
    inline "dd 写入 ${bs}×${cnt}"
    local w; w="$(_dd_write "$bs" "$cnt")"
    inline_done "${w:-失败}"
    inline "dd 读取 ${bs}×${cnt}"
    local r; r="$(_dd_read "$bs" "$cnt")"
    inline_done "${r:-失败}"
    row_add disk_dd "${bs} × ${cnt}" "${w:-N/A}" "${r:-N/A}"
    # 记录写入均值用于评分
    local wn; wn="$(printf '%s' "$w" | grep -Eo '^[0-9.]+')"
    case "$w" in
      *GB/s) wn="$(calc "$wn*1024" 2)" ;;
      *KB/s) wn="$(calc "$wn/1024" 2)" ;;
    esac
    [ -n "$wn" ] && { sum_w="$(calc "$sum_w+$wn" 2)"; n_w=$((n_w + 1)); }
  done
  [ "$n_w" -gt 0 ] && kv_set disk.dd.write_avg "$(calc "$sum_w/$n_w" 2)"
  rm -f "$DISK_WORKDIR/.vpstest_dd" 2>/dev/null

  # ---------- fio 随机读写 ----------
  need_tool fio >/dev/null 2>&1 || true
  if have fio; then
    local size secs
    if [ "$FAST_MODE" = "1" ]; then size="256M"; secs=8; else size="512M"; secs=10; fi
    local bsl="4k 64k 512k 1m"
    for bs in $bsl; do
      inline "fio 随机读写 ${bs}"
      local res; res="$(_fio_one "$bs" randrw "$size" "$secs")"
      if [ -n "$res" ]; then
        local ri rb wi wb
        IFS='|' read -r ri rb wi wb <<< "$res"
        inline_done "读 ${rb}MB/s ${ri}IOPS / 写 ${wb}MB/s ${wi}IOPS"
        row_add disk_fio "$bs" "${rb} MB/s (${ri} IOPS)" "${wb} MB/s (${wi} IOPS)" \
                "$(calc "$rb+$wb" 2) MB/s ($(calc "($ri+$wi)/1" 0) IOPS)"
        [ "$bs" = "4k" ] && { kv_set disk.fio.4k_riops "$ri"; kv_set disk.fio.4k_wiops "$wi"; }
      else
        inline_done "失败"
        row_add disk_fio "$bs" "N/A" "N/A" "N/A"
      fi
    done
    rm -f "$DISK_WORKDIR/.vpstest_fio" 2>/dev/null
  else
    log_warn "未安装 fio，跳过随机 IOPS 测试"
  fi
}
