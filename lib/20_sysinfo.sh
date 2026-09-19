#!/usr/bin/env bash
# ============================================================
# 20_sysinfo.sh — 系统与硬件基础信息
# ============================================================

_cpuinfo_field() {
  grep -m1 -i "^$1" /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//'
}

detect_virt() {
  local v=""
  if have systemd-detect-virt; then
    v="$(systemd-detect-virt 2>/dev/null)"
    [ "$v" = "none" ] && v=""
  fi
  if [ -z "$v" ] && have virt-what && [ "$(id -u)" = "0" ]; then
    v="$(virt-what 2>/dev/null | head -1)"
  fi
  if [ -z "$v" ]; then
    local dmi=""
    [ -r /sys/class/dmi/id/product_name ] && dmi="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
    [ -r /sys/class/dmi/id/sys_vendor ] && dmi="$dmi $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)"
    case "$dmi" in
      *KVM*|*QEMU*)          v="KVM" ;;
      *VMware*)              v="VMware" ;;
      *VirtualBox*)          v="VirtualBox" ;;
      *Xen*)                 v="Xen" ;;
      *Hyper-V*|*Microsoft*) v="Hyper-V" ;;
      *Bochs*)               v="KVM" ;;
      *Alibaba*)             v="KVM (Alibaba)" ;;
      *Google*)              v="KVM (GCP)" ;;
      *Amazon*)              v="KVM (AWS)" ;;
    esac
  fi
  if [ -z "$v" ]; then
    if [ -d /proc/vz ]; then v="OpenVZ"
    elif [ -f /proc/user_beancounters ]; then v="OpenVZ"
    elif grep -qa 'container=lxc' /proc/1/environ 2>/dev/null; then v="LXC"
    elif [ -f /.dockerenv ]; then v="Docker"
    else v="独立服务器 / 未知"; fi
  fi
  printf '%s' "$v"
}

detect_os() {
  local name=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    name="$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-$NAME $VERSION_ID}")"
  fi
  [ -z "$name" ] && [ -r /etc/redhat-release ] && name="$(cat /etc/redhat-release)"
  [ -z "$name" ] && name="$(uname -s)"
  printf '%s' "$(trim "$name")"
}

collect_sysinfo() {
  step "采集系统与硬件信息"

  # --- CPU ---
  local model cores freq cache
  model="$(_cpuinfo_field 'model name')"
  [ -z "$model" ] && model="$(_cpuinfo_field 'Processor')"
  [ -z "$model" ] && model="$(_cpuinfo_field 'Hardware')"
  [ -z "$model" ] && have lscpu && model="$(lscpu 2>/dev/null | grep -m1 -i 'model name' | cut -d: -f2- | sed 's/^ *//')"
  [ -z "$model" ] && model="未知"

  cores="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
  [ -z "$cores" ] || [ "$cores" = "0" ] && cores="$(nproc 2>/dev/null || echo 1)"

  freq="$(_cpuinfo_field 'cpu MHz')"
  if [ -z "$freq" ] && have lscpu; then
    freq="$(lscpu 2>/dev/null | grep -m1 -i 'CPU max MHz' | cut -d: -f2- | sed 's/^ *//')"
  fi
  [ -n "$freq" ] && freq="$(calc "$freq/1" 1) MHz" || freq="未知"

  cache="$(_cpuinfo_field 'cache size')"
  # /proc/cpuinfo 里是 "266240 KB" 这种原始值，转成人类可读
  case "$cache" in
    *KB) cache="$(human_kb "$(printf '%s' "$cache" | grep -Eo '^[0-9]+')")" ;;
  esac
  if [ -z "$cache" ] && have lscpu; then
    local l1 l2 l3
    l1="$(lscpu 2>/dev/null | grep -m1 'L1d' | cut -d: -f2- | sed 's/^ *//')"
    l2="$(lscpu 2>/dev/null | grep -m1 'L2'  | cut -d: -f2- | sed 's/^ *//')"
    l3="$(lscpu 2>/dev/null | grep -m1 'L3'  | cut -d: -f2- | sed 's/^ *//')"
    cache="$(trim "${l1:+L1: $l1  }${l2:+L2: $l2  }${l3:+L3: $l3}")"
  fi
  [ -z "$cache" ] && cache="未知"

  kv_set sys.cpu.model "$(trim "$model")"
  kv_set sys.cpu.cores "$cores"
  kv_set sys.cpu.freq  "$freq"
  kv_set sys.cpu.cache "$cache"

  local flags; flags="$(_cpuinfo_field 'flags')"
  case " $flags " in *" aes "*) kv_set sys.cpu.aes "✔ 已启用";; *) kv_set sys.cpu.aes "✘ 未启用";; esac
  case " $flags " in
    *" vmx "*) kv_set sys.cpu.virt "✔ VT-x" ;;
    *" svm "*) kv_set sys.cpu.virt "✔ AMD-V" ;;
    *)         kv_set sys.cpu.virt "✘ 未启用" ;;
  esac

  # --- 内存 ---
  local memtotal memavail memused swaptotal swapfree
  memtotal="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
  memavail="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)"
  [ -z "$memavail" ] && memavail="$(awk '/^MemFree:/{print $2}' /proc/meminfo 2>/dev/null)"
  swaptotal="$(awk '/^SwapTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
  swapfree="$(awk '/^SwapFree:/{print $2}' /proc/meminfo 2>/dev/null)"
  memused=$(( ${memtotal:-0} - ${memavail:-0} ))
  kv_set sys.mem.total "$(human_kb "${memtotal:-0}")"
  kv_set sys.mem.used  "$(human_kb "$memused")"
  kv_set sys.mem.avail "$(human_kb "${memavail:-0}")"
  kv_set sys.mem.summary "$(human_kb "$memused") / $(human_kb "${memtotal:-0}")"
  # Buff/Cache：free 命令口径 = Buffers + Cached + SReclaimable
  local buffers cached sreclaim
  buffers="$(awk '/^Buffers:/{print $2}' /proc/meminfo 2>/dev/null)"
  cached="$(awk '/^Cached:/{print $2}' /proc/meminfo 2>/dev/null)"
  sreclaim="$(awk '/^SReclaimable:/{print $2}' /proc/meminfo 2>/dev/null)"
  kv_set sys.mem.buff "$(human_kb $(( ${buffers:-0} + ${cached:-0} + ${sreclaim:-0} )))"
  if [ "${swaptotal:-0}" -gt 0 ] 2>/dev/null; then
    kv_set sys.swap.summary "$(human_kb $(( swaptotal - ${swapfree:-0} ))) / $(human_kb "$swaptotal")"
  else
    kv_set sys.swap.summary "未启用"
  fi

  # --- 硬盘 ---
  local dline dtotal dused
  dline="$(df -k --total 2>/dev/null | tail -1)"
  if [ -z "$dline" ] || [ "${dline%% *}" != "total" ]; then
    dline="$(df -k / 2>/dev/null | tail -1)"
    dtotal="$(printf '%s' "$dline" | awk '{print $2}')"
    dused="$(printf '%s' "$dline" | awk '{print $3}')"
  else
    dtotal="$(printf '%s' "$dline" | awk '{print $2}')"
    dused="$(printf '%s' "$dline" | awk '{print $3}')"
  fi
  kv_set sys.disk.summary "$(human_kb "${dused:-0}") / $(human_kb "${dtotal:-0}")"
  local fstype; fstype="$(df -T / 2>/dev/null | tail -1 | awk '{print $2}')"
  kv_set sys.disk.fs "${fstype:-未知}"

  # --- 系统 ---
  kv_set sys.os      "$(detect_os)"
  kv_set sys.arch    "$(uname -m)"
  kv_set sys.kernel  "$(uname -r)"
  kv_set sys.virt    "$(detect_virt)"

  local up; up="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
  kv_set sys.uptime  "$(human_uptime "${up:-0}")"
  kv_set sys.load    "$(trim "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)")"

  # --- 网络内核参数 ---
  local cc qdisc
  cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
  [ -z "$cc" ] && cc="$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
  qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null)"
  [ -z "$qdisc" ] && qdisc="$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)"
  kv_set sys.tcp.cc    "${cc:-未知}"
  kv_set sys.tcp.qdisc "${qdisc:-未知}"

  # --- 时间 ---
  kv_set meta.time_utc   "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  kv_set meta.time_local "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  kv_set meta.tz         "$(date '+%Z %z')"
  kv_set meta.version    "$VPSTEST_VERSION"

  log_ok "CPU: $(kv_get sys.cpu.model) × $(kv_get sys.cpu.cores)"
  log_ok "内存: $(kv_get sys.mem.summary)   硬盘: $(kv_get sys.disk.summary)"
  log_ok "系统: $(kv_get sys.os) / $(kv_get sys.kernel) / $(kv_get sys.virt)"
  log_ok "TCP: $(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
}
