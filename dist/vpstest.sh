#!/usr/bin/env bash
# ============================================================
# VPSceshi v1.0.0 — VPS / 服务器一键全能测评（单文件版）
#
# 本文件由 build.sh 自动生成，请勿直接编辑。
# 源码与模块： https://github.com/doudoudoubao/VPSceshi
#
# 一键运行：
#   bash <(curl -sL https://github.com/doudoudoubao/VPSceshi/raw/main/dist/vpstest.sh)
#
# 生成时间： 2026-09-19 08:32:00 UTC
# ============================================================

set -o pipefail

# ===== 00_core.sh =====
# ============================================================
# 00_core.sh — 核心工具：日志、结果存储、通用函数
# ============================================================

VPSTEST_VERSION="1.0.0"
VPSTEST_NAME="VPSceshi"
VPSTEST_REPO="https://github.com/doudoudoubao/VPSceshi"

# ---------- 运行时参数（可被命令行覆盖） ----------
OUT_DIR="${OUT_DIR:-$PWD/vpstest-result}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"
CURL_CONNECT="${CURL_CONNECT:-5}"
USE_COLOR=1
QUIET=0
NODE_NAME=""          # 机器名，用于报告标题
ONLY_MODULES=""       # 逗号分隔白名单
SKIP_MODULES=""       # 逗号分隔黑名单
ENABLE_GEEKBENCH=0
ENABLE_UPLOAD=0
FAST_MODE=0
SPEEDTEST_MODE="cn"   # cn | global | all | off
IPV6_OK=0
IPV4_OK=0

UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

# ---------- 颜色 ----------
_c_init() {
  if [ "$USE_COLOR" = "1" ] && [ -t 1 ]; then
    C_RST=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
    C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'
    C_BL=$'\033[34m'; C_M=$'\033[35m'; C_C=$'\033[36m'; C_W=$'\033[37m'
  else
    C_RST=""; C_B=""; C_DIM=""; C_R=""; C_G=""; C_Y=""
    C_BL=""; C_M=""; C_C=""; C_W=""
  fi
}
_c_init

# ---------- 日志 ----------
log()      { [ "$QUIET" = "1" ] && return 0; printf '%s\n' "$*"; }
log_info() { [ "$QUIET" = "1" ] && return 0; printf '%s[*]%s %s\n' "$C_C" "$C_RST" "$*"; }
log_ok()   { [ "$QUIET" = "1" ] && return 0; printf '%s[+]%s %s\n' "$C_G" "$C_RST" "$*"; }
log_warn() { [ "$QUIET" = "1" ] && return 0; printf '%s[!]%s %s\n' "$C_Y" "$C_RST" "$*" >&2; }
log_err()  { printf '%s[x]%s %s\n' "$C_R" "$C_RST" "$*" >&2; }

STEP_NO=0
step() {
  STEP_NO=$((STEP_NO + 1))
  [ "$QUIET" = "1" ] && return 0
  printf '\n%s%s━━━ [%02d] %s ━━━━━━━━━━━━━━━━━━━━%s\n' \
    "$C_B" "$C_BL" "$STEP_NO" "$*" "$C_RST"
}

# ---------- 结果存储 ----------
declare -A KV      # 单值：KV[section.key]=value
declare -A ROWS    # 表格：ROWS[table]=多行，字段以 | 分隔
declare -a RAWLOGS # 原始输出片段（路由等）

kv_set() { KV["$1"]="$2"; }
kv_get() { printf '%s' "${KV[$1]-}"; }
kv_or()  { local v="${KV[$1]-}"; [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"; }
kv_has() { [ -n "${KV[$1]+x}" ]; }

# row_add <表名> <字段1> <字段2> ...
row_add() {
  local k="$1"; shift
  local IFS='|'
  ROWS["$k"]="${ROWS[$k]-}$*"$'\n'
}
rows_get()  { printf '%s' "${ROWS[$1]-}"; }
rows_have() { [ -n "${ROWS[$1]-}" ]; }

# 把一行拆成字段数组 ROW_F（保留空字段，避免列错位）
declare -a ROW_F
row_split() {
  ROW_F=()
  local IFS='|'
  read -r -a ROW_F <<< "$1"
  # read -a 会丢弃末尾空字段，这里按分隔符个数补齐
  local want cnt
  cnt="${1//[^|]/}"
  want=$(( ${#cnt} + 1 ))
  while [ "${#ROW_F[@]}" -lt "$want" ]; do ROW_F+=(""); done
}

# raw_add <标题> <内容>
declare -A RAWS
declare -a RAW_ORDER
raw_add() {
  RAWS["$1"]="$2"
  RAW_ORDER+=("$1")
}

# ---------- 通用工具 ----------
have() { command -v "$1" >/dev/null 2>&1; }

# 带超时执行，失败不影响主流程（丢弃 stderr）
run_to() {
  local sec="$1"; shift
  if have timeout; then
    timeout --signal=KILL "$sec" "$@" 2>/dev/null
  else
    "$@" 2>/dev/null
  fi
}

# 同上，但把 stderr 合并进 stdout。
# dd 之类把统计信息写在 stderr 的命令必须用这个，否则拿不到结果。
run_to2() {
  local sec="$1"; shift
  if have timeout; then
    timeout --signal=KILL "$sec" "$@" 2>&1
  else
    "$@" 2>&1
  fi
}

# 统一 curl 封装
# xcurl [-6|-4] <额外参数...> <url>
xcurl() {
  curl -sS -L \
    --connect-timeout "$CURL_CONNECT" --max-time "$CURL_TIMEOUT" \
    -A "$UA_BROWSER" "$@" 2>/dev/null
}
xcurl4() { xcurl -4 "$@"; }
xcurl6() { xcurl -6 "$@"; }

# 去掉首尾空白
trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 浮点计算并四舍五入到 n 位小数
# 先用高精度算出结果，再统一格式化——否则 bc 的 scale 只作用于除法，
# 像 "80306.8366" 这种直接传进来的值不会被截断。
calc() {
  local expr="$1" scale="${2:-2}" v=""
  if have bc; then
    v="$(echo "scale=8; $expr" | bc -l 2>/dev/null)"
  fi
  [ -z "$v" ] && v="$(awk "BEGIN{print ($expr)}" 2>/dev/null)"
  [ -z "$v" ] && { printf '0'; return; }
  awk -v v="$v" -v s="$scale" 'BEGIN{ printf "%.*f", s, v }' 2>/dev/null
}

# 字节 -> 人类可读
human_bytes() {
  local b="${1:-0}"
  awk -v b="$b" 'BEGIN{
    split("B KB MB GB TB PB", u, " ");
    i=1; while (b>=1024 && i<6) { b/=1024; i++ }
    printf (i==1 ? "%d %s" : "%.2f %s"), b, u[i]
  }'
}

# KB -> 人类可读
human_kb() { human_bytes "$(( ${1:-0} * 1024 ))"; }

# 秒 -> x天x小时x分
human_uptime() {
  local s="${1:-0}"
  printf '%d 天 %d 小时 %d 分' $((s/86400)) $((s%86400/3600)) $((s%3600/60))
}

# JSON 字符串转义
json_escape() {
  local s="$*"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# 从 JSON 中取值（优先 jq，退化到 grep）
jget() {
  local json="$1" key="$2"
  if have jq; then
    local v
    v="$(printf '%s' "$json" | jq -r "$key // empty" 2>/dev/null)"
    [ "$v" = "null" ] && v=""
    printf '%s' "$v"
  else
    # 退化模式：仅支持 .key 形式
    local k="${key#.}"
    printf '%s' "$json" | grep -o "\"$k\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" |
      head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'
  fi
}

# 判断模块是否需要执行
module_enabled() {
  local m="$1"
  if [ -n "$ONLY_MODULES" ]; then
    case ",$ONLY_MODULES," in *",$m,"*) ;; *) return 1;; esac
  fi
  if [ -n "$SKIP_MODULES" ]; then
    case ",$SKIP_MODULES," in *",$m,"*) return 1;; esac
  fi
  return 0
}

# 结果标记：解锁类统一符号
mark_yes()  { printf '是'; }
mark_no()   { printf '否'; }

# 计时
timer_start() { _T0=$(date +%s); }
timer_end()   { echo $(( $(date +%s) - ${_T0:-0} )); }

# 进度条式的行内提示
inline() { [ "$QUIET" = "1" ] && return 0; printf '    %s%-32s%s' "$C_DIM" "$1" "$C_RST"; }
inline_done() { [ "$QUIET" = "1" ] && return 0; printf '%s\n' "$1"; }

# ===== 10_deps.sh =====
# ============================================================
# 10_deps.sh — 依赖检测与自动安装
# ============================================================

PKG_MGR=""
PKG_INSTALL=""
PKG_UPDATED=0

detect_pkg_mgr() {
  if   have apt-get; then PKG_MGR=apt;    PKG_INSTALL="apt-get install -y -qq"
  elif have dnf;     then PKG_MGR=dnf;    PKG_INSTALL="dnf install -y -q"
  elif have yum;     then PKG_MGR=yum;    PKG_INSTALL="yum install -y -q"
  elif have apk;     then PKG_MGR=apk;    PKG_INSTALL="apk add --no-cache"
  elif have pacman;  then PKG_MGR=pacman; PKG_INSTALL="pacman -S --noconfirm --needed"
  elif have zypper;  then PKG_MGR=zypper; PKG_INSTALL="zypper --non-interactive install"
  elif have opkg;    then PKG_MGR=opkg;   PKG_INSTALL="opkg install"
  else PKG_MGR=""; fi
}

pkg_update_once() {
  [ "$PKG_UPDATED" = "1" ] && return 0
  PKG_UPDATED=1
  case "$PKG_MGR" in
    apt)    run_to 180 apt-get update -qq >/dev/null 2>&1 ;;
    apk)    run_to 120 apk update >/dev/null 2>&1 ;;
    pacman) run_to 180 pacman -Sy --noconfirm >/dev/null 2>&1 ;;
  esac
}

# 各发行版的包名差异映射
pkg_name_for() {
  local generic="$1"
  case "$generic:$PKG_MGR" in
    ping:apt|ping:dnf|ping:yum|ping:zypper) echo "iputils-ping" ;;
    ping:apk)     echo "iputils" ;;
    ping:pacman)  echo "iputils" ;;
    dig:apt)      echo "dnsutils" ;;
    dig:dnf|dig:yum|dig:zypper) echo "bind-utils" ;;
    dig:apk)      echo "bind-tools" ;;
    dig:pacman)   echo "bind" ;;
    ifconfig:apt) echo "net-tools" ;;
    ifconfig:*)   echo "net-tools" ;;
    tar:*)        echo "tar" ;;
    *)            echo "$generic" ;;
  esac
}

# ensure_cmd <命令> [包名]
# 返回 0 表示命令可用
ensure_cmd() {
  local cmd="$1" pkg="${2:-}"
  have "$cmd" && return 0
  [ -z "$PKG_MGR" ] && return 1
  [ "$(id -u)" != "0" ] && return 1
  [ -z "$pkg" ] && pkg="$(pkg_name_for "$cmd")"
  pkg_update_once
  # shellcheck disable=SC2086
  run_to 300 $PKG_INSTALL "$pkg" >/dev/null 2>&1
  have "$cmd"
}

# ping 在部分发行版名为 ping，Debian 12 最小镜像默认不带
ensure_ping() {
  have ping && return 0
  case "$PKG_MGR" in
    apt)          ensure_cmd ping iputils-ping ;;
    dnf|yum)      ensure_cmd ping iputils ;;
    apk)          ensure_cmd ping iputils ;;
    pacman)       ensure_cmd ping iputils ;;
    zypper)       ensure_cmd ping iputils ;;
    *)            return 1 ;;
  esac
}

DEPS_REPORT=""
install_deps() {
  step "检测并安装依赖"
  detect_pkg_mgr
  if [ -z "$PKG_MGR" ]; then
    log_warn "未识别包管理器，仅使用系统自带工具运行"
  else
    log_info "包管理器: $PKG_MGR"
  fi
  if [ "$(id -u)" != "0" ]; then
    log_warn "非 root 运行，无法自动安装依赖，部分测试可能降级或跳过"
  fi

  local base=(curl wget tar gzip)
  local opt=(bc jq sysbench fio unzip)
  local c
  for c in "${base[@]}"; do
    if ensure_cmd "$c"; then :; else log_warn "缺少基础工具: $c"; fi
  done
  ensure_ping || log_warn "缺少 ping，延迟测试将跳过"
  ensure_cmd dig  >/dev/null 2>&1 || true
  for c in "${opt[@]}"; do
    ensure_cmd "$c" >/dev/null 2>&1 || true
  done

  local ok=() miss=()
  for c in curl wget bc jq sysbench fio ping dig tar; do
    if have "$c"; then ok+=("$c"); else miss+=("$c"); fi
  done
  DEPS_REPORT="可用: ${ok[*]}"
  [ ${#miss[@]} -gt 0 ] && DEPS_REPORT="$DEPS_REPORT / 缺失: ${miss[*]}"
  log_ok "$DEPS_REPORT"
  kv_set "meta.deps" "$DEPS_REPORT"
}

# ---------- 外部二进制下载 ----------
BIN_DIR=""
setup_bin_dir() {
  BIN_DIR="$(mktemp -d /tmp/vpstest-bin.XXXXXX 2>/dev/null)" || BIN_DIR="/tmp/vpstest-bin.$$"
  mkdir -p "$BIN_DIR"
  export PATH="$BIN_DIR:$PATH"
}

arch_tag() {
  case "$(uname -m)" in
    x86_64|amd64)   echo "amd64" ;;
    aarch64|arm64)  echo "arm64" ;;
    armv7l|armv7)   echo "armv7" ;;
    i386|i686)      echo "i386" ;;
    *)              echo "unknown" ;;
  esac
}

# 多镜像下载，任一成功即可
fetch_first() {
  local out="$1"; shift
  local u
  for u in "$@"; do
    if run_to 120 curl -sSL --connect-timeout 8 --max-time 110 -o "$out" "$u" 2>/dev/null &&
       [ -s "$out" ]; then
      return 0
    fi
  done
  return 1
}

# ===== 20_sysinfo.sh =====
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
  kv_set sys.mem.summary "$(human_kb "$memused") / $(human_kb "${memtotal:-0}")"
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

# ===== 30_cpu.sh =====
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
  module_enabled cpu || { log_info "跳过 CPU 测试"; return 0; }
  step "CPU 性能测试"

  local cores secs
  cores="$(kv_get sys.cpu.cores)"; [ -z "$cores" ] && cores=1
  secs=10; [ "$FAST_MODE" = "1" ] && secs=5

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

# ===== 31_memory.sh =====
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
  module_enabled memory || { log_info "跳过内存测试"; return 0; }
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

# ===== 32_disk.sh =====
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
  o="$(run_to2 180 dd if=/dev/zero of="$f" bs="$bs" count="$count" oflag=direct conv=fsync)"
  if ! printf '%s' "$o" | grep -qE 'copied|bytes'; then
    # 部分文件系统 / 容器不支持 O_DIRECT，退回普通写入
    o="$(run_to2 180 dd if=/dev/zero of="$f" bs="$bs" count="$count" conv=fsync)"
  fi
  printf '%s' "$o" | grep -Eo '[0-9.]+ [KMG]?B/s' | tail -1
}

_dd_read() {
  local bs="$1" count="$2" f="$DISK_WORKDIR/.vpstest_dd"
  [ -f "$f" ] || return 1
  sync 2>/dev/null
  [ -w /proc/sys/vm/drop_caches ] && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
  local o
  o="$(run_to2 180 dd if="$f" of=/dev/null bs="$bs" count="$count" iflag=direct)"
  if ! printf '%s' "$o" | grep -qE 'copied|bytes'; then
    o="$(run_to2 180 dd if="$f" of=/dev/null bs="$bs" count="$count")"
  fi
  printf '%s' "$o" | grep -Eo '[0-9.]+ [KMG]?B/s' | tail -1
}

# fio 单项：<块大小> <读写模式> <文件大小> <运行秒数>
# 输出 "IOPS|带宽MB/s"
_fio_one() {
  local bs="$1" rw="$2" size="$3" secs="$4"
  local out riops wiops rbw wbw
  out="$(run_to $((secs + 60)) fio --name=vpstest --directory="$DISK_WORKDIR" \
        --filename=.vpstest_fio --rw="$rw" --bs="$bs" --size="$size" \
        --ioengine=libaio --direct=1 --iodepth=64 --numjobs=1 \
        --runtime="$secs" --time_based --group_reporting \
        --output-format=json --unlink=0 2>/dev/null)"
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
  module_enabled disk || { log_info "跳过磁盘测试"; return 0; }
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
    specs="1M:1000 1M:1000 128K:8000"
  fi
  local i=0 sum_w=0 n_w=0
  for s in $specs; do
    i=$((i + 1))
    local bs="${s%%:*}" cnt="${s##*:}"
    inline "dd 写入 ${bs}×${cnt} (第${i}次) ..."
    local w; w="$(_dd_write "$bs" "$cnt")"
    inline_done "${w:-失败}"
    inline "dd 读取 ${bs}×${cnt} (第${i}次) ..."
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
  if have fio; then
    local size secs
    if [ "$FAST_MODE" = "1" ]; then size="256M"; secs=8; else size="512M"; secs=15; fi
    local bsl="4k 64k 512k 1m"
    for bs in $bsl; do
      inline "fio 混合随机读写 ${bs} ..."
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

# ===== 40_ipinfo.sh =====
# ============================================================
# 40_ipinfo.sh — 出口 IP / ASN / 地理位置 / 双栈检测
# ============================================================

IP4=""; IP6=""

_mask_ip() {
  # 报告默认对出口 IP 做部分遮蔽，避免直接公开完整地址
  local ip="$1"
  [ "$MASK_IP" = "0" ] && { printf '%s' "$ip"; return 0; }
  case "$ip" in
    *:*) printf '%s' "$(printf '%s' "$ip" | cut -d: -f1-3):****" ;;
    *.*) printf '%s.%s.*.*' "$(printf '%s' "$ip" | cut -d. -f1)" "$(printf '%s' "$ip" | cut -d. -f2)" ;;
    *)   printf '%s' "$ip" ;;
  esac
}

detect_ip() {
  step "出口 IP 与网络归属"

  local u4=(
    "https://api.ipify.org"
    "https://ipv4.icanhazip.com"
    "https://api-ipv4.ip.sb/ip"
    "https://ipinfo.io/ip"
  )
  local u6=(
    "https://api6.ipify.org"
    "https://ipv6.icanhazip.com"
    "https://api-ipv6.ip.sb/ip"
  )

  inline "检测 IPv4 出口 ..."
  local u
  for u in "${u4[@]}"; do
    IP4="$(trim "$(xcurl4 "$u")")"
    case "$IP4" in *.*.*.*) break ;; *) IP4="" ;; esac
  done
  inline_done "${IP4:-无}"
  [ -n "$IP4" ] && IPV4_OK=1

  inline "检测 IPv6 出口 ..."
  for u in "${u6[@]}"; do
    IP6="$(trim "$(xcurl6 "$u")")"
    case "$IP6" in *:*) break ;; *) IP6="" ;; esac
  done
  inline_done "${IP6:-无}"
  [ -n "$IP6" ] && IPV6_OK=1

  kv_set net.ip4 "$(_mask_ip "$IP4")"
  kv_set net.ip6 "$(_mask_ip "$IP6")"
  kv_set net.stack "$([ "$IPV4_OK" = 1 ] && printf 'IPv4' ; [ "$IPV6_OK" = 1 ] && printf '%s' "$([ "$IPV4_OK" = 1 ] && echo ' + ')IPv6")"
  [ -z "$(kv_get net.stack)" ] && kv_set net.stack "无公网出口"

  # ---- 归属信息（ip-api.com 免费无需 key）----
  if [ -n "$IP4" ]; then
    local j
    j="$(xcurl4 "http://ip-api.com/json/${IP4}?fields=status,country,countryCode,regionName,city,isp,org,as,asname,reverse,mobile,proxy,hosting,timezone,lat,lon&lang=zh-CN")"
    if [ -n "$j" ] && [ "$(jget "$j" '.status')" = "success" ]; then
      kv_set net.country  "$(jget "$j" '.country')"
      kv_set net.cc       "$(jget "$j" '.countryCode')"
      kv_set net.region   "$(jget "$j" '.regionName')"
      kv_set net.city     "$(jget "$j" '.city')"
      kv_set net.isp      "$(jget "$j" '.isp')"
      kv_set net.org      "$(jget "$j" '.org')"
      kv_set net.as       "$(jget "$j" '.as')"
      kv_set net.asname   "$(jget "$j" '.asname')"
      kv_set net.rdns     "$(jget "$j" '.reverse')"
      kv_set net.tz       "$(jget "$j" '.timezone')"
      kv_set net.flag_proxy   "$(jget "$j" '.proxy')"
      kv_set net.flag_hosting "$(jget "$j" '.hosting')"
      kv_set net.flag_mobile  "$(jget "$j" '.mobile')"
    fi
    # ipinfo 作为补充（ASN / 组织更规范）
    local j2; j2="$(xcurl4 "https://ipinfo.io/${IP4}/json")"
    if [ -n "$j2" ]; then
      [ -z "$(kv_get net.org)" ] && kv_set net.org "$(jget "$j2" '.org')"
      [ -z "$(kv_get net.city)" ] && kv_set net.city "$(jget "$j2" '.city')"
      kv_set net.ipinfo_org "$(jget "$j2" '.org')"
    fi
  fi

  local loc
  loc="$(trim "$(kv_get net.country) $(kv_get net.region) $(kv_get net.city)")"
  kv_set net.location "${loc:-未知}"

  log_ok "出口 IPv4: $(kv_or net.ip4 '无')   IPv6: $(kv_or net.ip6 '无')"
  log_ok "归属: $(kv_get net.location) / $(kv_or net.as '未知')"
  log_ok "运营商: $(kv_or net.isp '未知')"
}

# ===== 41_ipquality.sh =====
# ============================================================
# 41_ipquality.sh — IP 质量体检：欺诈分、IP 类型、黑名单、端口
# ============================================================

_yn() { case "$1" in true|1|yes|Yes|YES) printf '是';; false|0|no|No|NO|"") printf '否';; *) printf '%s' "$1";; esac; }

# TCP 端口连通性（不依赖 nc）
_port_open() {
  local host="$1" port="$2" to="${3:-5}"
  if have timeout; then
    timeout "$to" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null && return 0 || return 1
  else
    (exec 3<>/dev/tcp/"$host"/"$port") 2>/dev/null && return 0 || return 1
  fi
}

# DNSBL 黑名单查询
_rbl_check() {
  local ip="$1" rbl="$2" rev
  rev="$(printf '%s' "$ip" | awk -F. '{print $4"."$3"."$2"."$1}')"
  local q="${rev}.${rbl}"
  local r=""
  if have dig; then
    r="$(run_to 6 dig +short +time=3 +tries=1 A "$q" 2>/dev/null | head -1)"
  elif have host; then
    r="$(run_to 6 host -t A "$q" 2>/dev/null | grep -m1 'has address' | awk '{print $NF}')"
  elif have nslookup; then
    r="$(run_to 6 nslookup -type=A "$q" 2>/dev/null | grep -A2 'Name:' | grep -m1 'Address' | awk '{print $NF}')"
  else
    printf 'SKIP'; return
  fi
  case "$r" in 127.0.0.*) printf 'LISTED' ;; *) printf 'CLEAN' ;; esac
}

test_ipquality() {
  module_enabled ipquality || { log_info "跳过 IP 质量体检"; return 0; }
  step "IP 质量体检"

  if [ -z "$IP4" ]; then
    log_warn "无 IPv4 出口，跳过 IP 质量体检"
    return 0
  fi

  # ---------- 1. 基础画像 ----------
  row_add ipq_base "IP 地址" "$(kv_get net.ip4)"
  row_add ipq_base "ASN" "$(kv_or net.as '未知')"
  row_add ipq_base "归属组织" "$(kv_or net.org '未知')"
  row_add ipq_base "运营商 ISP" "$(kv_or net.isp '未知')"
  row_add ipq_base "地理位置" "$(kv_get net.location)"
  row_add ipq_base "反向解析 PTR" "$(kv_or net.rdns '无')"
  row_add ipq_base "时区" "$(kv_or net.tz '未知')"

  # ---------- 2. IP 类型判定 ----------
  inline "IP 类型判定 ..."
  local usetype="未知" company="" abuser=""
  local j; j="$(xcurl4 "https://api.ipapi.is/?q=${IP4}")"
  if [ -n "$j" ]; then
    local is_dc is_proxy is_vpn is_tor is_abuser is_crawler asn_type
    is_dc="$(jget "$j" '.is_datacenter')"; is_proxy="$(jget "$j" '.is_proxy')"
    is_vpn="$(jget "$j" '.is_vpn')";       is_tor="$(jget "$j" '.is_tor')"
    is_abuser="$(jget "$j" '.is_abuser')"; is_crawler="$(jget "$j" '.is_crawler')"
    asn_type="$(jget "$j" '.asn.type')"
    company="$(jget "$j" '.company.name')"
    abuser="$(jget "$j" '.company.abuser_score')"
    case "$asn_type" in
      hosting|isp|business|education|government) usetype="$asn_type" ;;
    esac
    row_add ipq_type "IDC / 机房 IP"   "$(_yn "$is_dc")"
    row_add ipq_type "代理 Proxy"      "$(_yn "$is_proxy")"
    row_add ipq_type "VPN"             "$(_yn "$is_vpn")"
    row_add ipq_type "Tor 出口节点"    "$(_yn "$is_tor")"
    row_add ipq_type "滥用记录 Abuser" "$(_yn "$is_abuser")"
    row_add ipq_type "爬虫 Crawler"    "$(_yn "$is_crawler")"
    [ -n "$asn_type" ] && row_add ipq_type "ASN 类型" "$asn_type"
    [ -n "$company" ]  && row_add ipq_type "注册公司" "$company"
    [ -n "$abuser" ]   && row_add ipq_type "滥用评分" "$abuser（越低越好）"
    kv_set ipq.datacenter "$(_yn "$is_dc")"
  fi
  # ip-api 的补充标记
  [ -n "$(kv_get net.flag_proxy)" ] &&
    row_add ipq_type "ip-api 代理标记" "$(_yn "$(kv_get net.flag_proxy)")"
  [ -n "$(kv_get net.flag_hosting)" ] &&
    row_add ipq_type "ip-api 托管标记" "$(_yn "$(kv_get net.flag_hosting)")"
  inline_done "$usetype"
  kv_set ipq.usetype "$usetype"

  # ---------- 3. 欺诈分 / 风险分 ----------
  inline "Scamalytics 欺诈分 ..."
  local html score risk
  html="$(xcurl4 "https://scamalytics.com/ip/${IP4}")"
  if [ -n "$html" ]; then
    score="$(printf '%s' "$html" | grep -o 'Fraud Score: *[0-9]*' | head -1 | grep -Eo '[0-9]+')"
    risk="$(printf '%s' "$html" | grep -o '"risk":"[^"]*"' | head -1 | cut -d'"' -f4)"
    [ -z "$risk" ] && risk="$(printf '%s' "$html" | grep -oE '(Low|Medium|High|Very High) Risk' | head -1)"
  fi
  inline_done "${score:-N/A}"
  if [ -n "$score" ]; then
    kv_set ipq.scamalytics "$score"
    local lvl="低风险"
    [ "$score" -ge 25 ] 2>/dev/null && lvl="中风险"
    [ "$score" -ge 50 ] 2>/dev/null && lvl="高风险"
    [ "$score" -ge 75 ] 2>/dev/null && lvl="极高风险"
    row_add ipq_risk "Scamalytics 欺诈分" "$score / 100（$lvl）"
  fi
  [ -n "$risk" ] && row_add ipq_risk "Scamalytics 风险等级" "$risk"

  # AbuseIPDB 公开页面（无 key 时抓取概要）
  inline "AbuseIPDB 举报记录 ..."
  local ab conf
  ab="$(xcurl4 -H 'Accept: text/html' "https://www.abuseipdb.com/check/${IP4}")"
  if [ -n "$ab" ]; then
    conf="$(printf '%s' "$ab" | grep -o 'Confidence of Abuse[^%]*%' | grep -Eo '[0-9]+%' | head -1)"
  fi
  inline_done "${conf:-N/A}"
  [ -n "$conf" ] && { kv_set ipq.abuseipdb "$conf"; row_add ipq_risk "AbuseIPDB 滥用置信度" "$conf"; }

  # Cloudflare 边缘信息（判断走哪个 POP，间接体现线路）
  local cf; cf="$(xcurl4 "https://www.cloudflare.com/cdn-cgi/trace")"
  if [ -n "$cf" ]; then
    local colo loc
    colo="$(printf '%s' "$cf" | grep -m1 '^colo=' | cut -d= -f2)"
    loc="$(printf '%s' "$cf" | grep -m1 '^loc=' | cut -d= -f2)"
    [ -n "$colo" ] && { kv_set ipq.cf_colo "$colo"; row_add ipq_risk "Cloudflare 接入 POP" "$colo（国家判定: ${loc:-N/A}）"; }
  fi

  # ---------- 4. 邮件黑名单 ----------
  inline "DNSBL 黑名单检测 ..."
  local rbls=(
    "zen.spamhaus.org"
    "bl.spamcop.net"
    "b.barracudacentral.org"
    "dnsbl.sorbs.net"
    "spam.dnsbl.sorbs.net"
    "psbl.surriel.com"
    "cbl.abuseat.org"
    "dnsbl-1.uceprotect.net"
    "ubl.unsubscore.com"
    "all.s5h.net"
  )
  local listed=0 clean=0 skipped=0 r
  for rbl in "${rbls[@]}"; do
    r="$(_rbl_check "$IP4" "$rbl")"
    case "$r" in
      LISTED) listed=$((listed + 1)); row_add ipq_rbl "$rbl" "❌ 已列入黑名单" ;;
      CLEAN)  clean=$((clean + 1));   row_add ipq_rbl "$rbl" "✅ 干净" ;;
      *)      skipped=$((skipped + 1)) ;;
    esac
  done
  inline_done "干净 ${clean} / 命中 ${listed}"
  kv_set ipq.rbl_listed "$listed"
  kv_set ipq.rbl_clean  "$clean"
  if [ "$skipped" -gt 0 ] && [ "$clean" = "0" ] && [ "$listed" = "0" ]; then
    kv_set ipq.rbl_summary "未检测（缺少 dig/host）"
  else
    kv_set ipq.rbl_summary "${clean} 个干净 / ${listed} 个命中（共 $((clean + listed)) 个库）"
  fi

  # ---------- 5. 端口与邮局 ----------
  inline "出站端口检测 ..."
  local p25 p465 p587
  _port_open "smtp.gmail.com" 25  6 && p25="✅ 放行"  || p25="❌ 封锁"
  _port_open "smtp.gmail.com" 465 6 && p465="✅ 放行" || p465="❌ 封锁"
  _port_open "smtp.gmail.com" 587 6 && p587="✅ 放行" || p587="❌ 封锁"
  inline_done "25:${p25%% *} 465:${p465%% *} 587:${p587%% *}"
  row_add ipq_port "TCP 25（SMTP 明文）"  "$p25"
  row_add ipq_port "TCP 465（SMTPS）"     "$p465"
  row_add ipq_port "TCP 587（Submission）" "$p587"
  kv_set ipq.port25 "$p25"

  # 常见服务连通性
  local svc
  for svc in "www.google.com:443:Google" "github.com:443:GitHub" \
             "registry.npmjs.org:443:npm" "hub.docker.com:443:DockerHub"; do
    local h="${svc%%:*}" rest="${svc#*:}" port="${rest%%:*}" name="${rest#*:}"
    if _port_open "$h" "$port" 5; then
      row_add ipq_port "$name ($h:$port)" "✅ 可达"
    else
      row_add ipq_port "$name ($h:$port)" "❌ 不可达"
    fi
  done

  log_ok "欺诈分 $(kv_or ipq.scamalytics 'N/A') | 黑名单 $(kv_get ipq.rbl_summary) | 25 端口 $p25"
}

# ===== 50_unlock.sh =====
# ============================================================
# 50_unlock.sh — 流媒体 / AI 服务解锁检测（IPv4 与 IPv6 分别测）
# ============================================================

UA_UNLOCK="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

# 当前检测使用的协议栈：4 或 6
UL_STACK=4
ucurl() {
  curl -sS -"$UL_STACK" --connect-timeout 6 --max-time 14 \
    -A "$UA_UNLOCK" "$@" 2>/dev/null
}
ucode() { # 只取 HTTP 状态码
  curl -sS -"$UL_STACK" -o /dev/null -w '%{http_code}' \
    --connect-timeout 6 --max-time 14 -A "$UA_UNLOCK" "$@" 2>/dev/null
}

OK="✅ 解锁"
NO="❌ 失败"
NA="⚠️ 待确认"

# res_add <表名> <服务名> <结果>
res_add() { row_add "$1" "$2" "$3"; }

# ---------------- 各服务检测 ----------------

u_netflix() {
  # 81280792 = 非自制剧；70143836 = 自制剧
  local c1 c2
  c1="$(ucode "https://www.netflix.com/title/81280792")"
  c2="$(ucode "https://www.netflix.com/title/70143836")"
  if [ "$c1" = "404" ] && [ "$c2" = "404" ]; then
    printf '%s' "❌ 仅自制剧"; return
  fi
  if [ "$c1" = "403" ] || [ "$c2" = "403" ]; then
    printf '%s' "$NO"; return
  fi
  if [ "$c1" = "200" ] || [ "$c2" = "200" ]; then
    local region body
    body="$(ucurl -H 'Accept-Language: en-US,en;q=0.9' "https://www.netflix.com/title/80018499" -D - -o /dev/null)"
    region="$(printf '%s' "$body" | grep -i '^location:' | grep -oE 'netflix\.com/([a-z]{2})-' | head -1 |
              cut -d/ -f2 | tr -d '-' | tr '[:lower:]' '[:upper:]')"
    [ -z "$region" ] && region="US"
    printf '%s（区域: %s）' "$OK" "$region"; return
  fi
  printf '%s' "$NA"
}

u_disney() {
  local tok assertion
  assertion="$(ucurl -X POST -H 'authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84' \
    -H 'content-type: application/json' \
    -d '{"deviceFamily":"browser","applicationRuntime":"chrome","deviceProfile":"windows","attributes":{}}' \
    "https://disney.api.edge.bamgrid.com/devices")"
  tok="$(jget "$assertion" '.assertion')"
  [ -z "$tok" ] && { printf '%s' "$NO"; return; }
  local r
  r="$(ucurl -X POST -H 'authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84' \
    -H 'content-type: application/x-www-form-urlencoded' \
    -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange&latitude=0&longitude=0&platform=browser&subject_token=${tok}&subject_token_type=urn:bamtech:params:oauth:token-type:device" \
    "https://disney.api.edge.bamgrid.com/token")"
  case "$r" in
    *forbidden-location*|*invalid-grant*) printf '%s' "$NO"; return ;;
  esac
  # 从 disneyplus.com 的跳转地址里取区域，形如 /zh-hk/ 或 /en-gb/
  local region
  region="$(ucurl -H 'Accept-Language: en' -D - -o /dev/null "https://www.disneyplus.com/" |
            grep -i '^location:' | grep -oE '/[a-z]{2}-[a-z]{2}/' | head -1 |
            tr -d '/' | cut -d- -f2 | tr '[:lower:]' '[:upper:]')"
  if [ -n "$region" ]; then
    printf '%s（区域: %s）' "$OK" "$region"
  else
    printf '%s' "$OK"
  fi
}

u_youtube_premium() {
  local body
  body="$(ucurl -H 'Accept-Language: en-US,en;q=0.9' "https://www.youtube.com/premium")"
  [ -z "$body" ] && { printf '%s' "$NA"; return; }
  case "$body" in
    *"Premium is not available in your country"*) printf '%s' "$NO"; return ;;
  esac
  local cc
  cc="$(printf '%s' "$body" | grep -oE '"countryCode":"[A-Z]{2}"' | head -1 | cut -d'"' -f4)"
  [ -z "$cc" ] && cc="$(printf '%s' "$body" | grep -oE '"GL":"[A-Z]{2}"' | head -1 | cut -d'"' -f4)"
  case "$body" in
    *"ad-free"*|*"YouTube Premium"*|*"premium_"*)
        printf '%s（区域: %s）' "$OK" "${cc:-未知}" ;;
    *)  printf '%s' "$NA" ;;
  esac
}

u_youtube_cdn() {
  local body cdn
  body="$(ucurl "https://redirector.googlevideo.com/report_mapping?di=no")"
  cdn="$(printf '%s' "$body" | grep -oE '=> [a-z]{3}[0-9]{2}' | head -1 | awk '{print $2}')"
  [ -z "$cdn" ] && cdn="$(printf '%s' "$body" | grep -oE '[a-z]{3}[0-9]{2}s[0-9]{2}' | head -1)"
  if [ -n "$cdn" ]; then printf '%s' "$cdn"; else printf '%s' "未知"; fi
}

u_primevideo() {
  local body region
  body="$(ucurl "https://www.primevideo.com")"
  [ -z "$body" ] && { printf '%s' "$NO"; return; }
  region="$(printf '%s' "$body" | grep -oE '"currentTerritory":"[A-Z]{2}"' | head -1 | cut -d'"' -f4)"
  [ -z "$region" ] && region="$(printf '%s' "$body" | grep -oE 'currentTerritory[^A-Z]{0,8}[A-Z]{2}' | head -1 | grep -oE '[A-Z]{2}$')"
  case "$body" in
    *"isServiceRestricted"*) printf '%s' "$NO"; return ;;
  esac
  if [ -n "$region" ]; then printf '%s（区域: %s）' "$OK" "$region"; else printf '%s' "$NA"; fi
}

u_spotify() {
  local r
  r="$(ucurl -X POST -H 'Accept: application/json' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d 'creation_point=https://login.app.spotify.com&password_repeat=&platform=www&referrer=&iagree=1' \
    "https://spclient.wg.spotify.com/signup/public/v1/account")"
  local st cc
  st="$(jget "$r" '.status')"; cc="$(jget "$r" '.country')"
  case "$st" in
    320|120) printf '%s' "$NO" ;;
    311)     printf '%s（区域: %s）' "$OK" "${cc:-未知}" ;;
    *)       [ -n "$cc" ] && printf '%s（区域: %s）' "$OK" "$cc" || printf '%s' "$NA" ;;
  esac
}

u_steam() {
  local body cur
  body="$(ucurl "https://store.steampowered.com/app/761830")"
  cur="$(printf '%s' "$body" | grep -oE '"priceCurrency" content="[A-Z]{3}"' | head -1 | cut -d'"' -f4)"
  [ -z "$cur" ] && cur="$(printf '%s' "$body" | grep -oE 'currency=[A-Z]{3}' | head -1 | cut -d= -f2)"
  if [ -n "$cur" ]; then printf '%s（货币区: %s）' "$OK" "$cur"; else printf '%s' "$NA"; fi
}

u_chatgpt() {
  local ios web cc
  ios="$(ucode "https://ios.chat.openai.com/")"
  web="$(ucurl "https://api.openai.com/compliance/cookie_requirements" \
        -H 'Content-Type: application/json' -H 'Origin: https://platform.openai.com')"
  cc="$(ucurl "https://chat.openai.com/cdn-cgi/trace" | grep -m1 '^loc=' | cut -d= -f2)"
  local ok_ios=0 ok_web=0
  case "$ios" in 200|403) ok_ios=1 ;; esac
  case "$web" in *unsupported_country*) ok_web=0 ;; *) ok_web=1 ;; esac
  if [ "$ok_ios" = "1" ] && [ "$ok_web" = "1" ]; then
    printf '%s（区域: %s）' "$OK" "${cc:-未知}"
  elif [ "$ok_web" = "1" ]; then
    printf '⚠️ 仅网页版（区域: %s）' "${cc:-未知}"
  else
    printf '%s' "$NO"
  fi
}

u_gemini() {
  local body
  body="$(ucurl "https://gemini.google.com")"
  [ -z "$body" ] && { printf '%s' "$NO"; return; }
  case "$body" in
    *"45631641,null,true"*|*"Gemini"*) printf '%s' "$OK" ;;
    *) printf '%s' "$NO" ;;
  esac
}

u_claude() {
  local c; c="$(ucode "https://claude.ai/login")"
  case "$c" in 200|307|308) printf '%s' "$OK" ;; 403) printf '%s' "$NO" ;; *) printf '%s' "$NA" ;; esac
}

u_tiktok() {
  local body region
  body="$(ucurl "https://www.tiktok.com/")"
  region="$(printf '%s' "$body" | grep -oE '"region":"[A-Z]{2}"' | head -1 | cut -d'"' -f4)"
  if [ -n "$region" ]; then printf '%s（区域: %s）' "$OK" "$region"; else printf '%s' "$NA"; fi
}

u_bahamut() {
  local r device
  device="$(ucurl "https://ani.gamer.com.tw/ajax/getdeviceid.php" | grep -oE '"deviceid":"[^"]+"' | cut -d'"' -f4)"
  [ -z "$device" ] && { printf '%s' "$NA"; return; }
  r="$(ucurl "https://ani.gamer.com.tw/ajax/token.php?adID=89692&sn=14667&device=${device}")"
  case "$r" in
    *animeSn*) printf '%s（台湾）' "$OK" ;;
    *)         printf '%s' "$NO" ;;
  esac
}

u_abema() {
  local r cc
  r="$(ucurl "https://api.abema.io/v1/ip/check?device=android")"
  cc="$(jget "$r" '.isoCountryCode')"
  case "$cc" in
    JP) printf '%s（日本全部）' "$OK" ;;
    "") printf '%s' "$NO" ;;
    *)  printf '⚠️ 仅海外内容（%s）' "$cc" ;;
  esac
}

u_dmm() {
  local c; c="$(ucode "https://gateway.d.dmm.com/hls/v1/playback")"
  case "$c" in 000) printf '%s' "$NA" ;; 403) printf '%s' "$NO" ;; *) printf '%s' "$OK" ;; esac
}

u_hulujp() {
  local r; r="$(ucurl "https://id.hulu.jp/")"
  case "$r" in
    *"restricted"*|*"not available"*) printf '%s' "$NO" ;;
    "") printf '%s' "$NO" ;;
    *)  printf '%s' "$OK" ;;
  esac
}

u_hbomax() {
  local body region
  body="$(ucurl -D - -o /dev/null "https://www.max.com/")"
  region="$(printf '%s' "$body" | grep -i '^location:' | grep -oE '/[a-z]{2}/[a-z]{2}' | head -1 | cut -d/ -f2)"
  case "$body" in
    *"403"*) printf '%s' "$NO"; return ;;
  esac
  if [ -n "$region" ]; then
    printf '%s（区域: %s）' "$OK" "$(printf '%s' "$region" | tr '[:lower:]' '[:upper:]')"
  else
    local c; c="$(ucode "https://www.max.com/")"
    case "$c" in 200|301|302) printf '%s' "$OK" ;; *) printf '%s' "$NO" ;; esac
  fi
}

u_dazn() {
  local r cc
  r="$(ucurl -X POST -H 'Content-Type: application/json' \
      -d '{"LandingPageKey":"generic","Languages":"zh-CN,zh,en","Platform":"web","PlatformAttributes":{},"Manufacturer":"","PromoCode":"","Version":"2"}' \
      "https://startup.core.indazn.com/misl/v5/Startup")"
  cc="$(jget "$r" '.Region.isAllowed')"
  local country; country="$(jget "$r" '.Region.GeolocatedCountry')"
  case "$cc" in
    true)  printf '%s（区域: %s）' "$OK" "$(printf '%s' "${country:-未知}" | tr '[:lower:]' '[:upper:]')" ;;
    false) printf '%s' "$NO" ;;
    *)     printf '%s' "$NA" ;;
  esac
}

u_paramount() {
  local c; c="$(ucode "https://www.paramountplus.com/")"
  case "$c" in 200) printf '%s' "$OK" ;; 302|403) printf '%s' "$NO" ;; *) printf '%s' "$NA" ;; esac
}

u_tvbanywhere() {
  local r; r="$(ucurl "https://uapisfm.tvbanywhere.com.sg/geoip/check/platform/android")"
  local allow; allow="$(jget "$r" '.allow_in_this_country')"
  case "$allow" in
    true)  printf '%s' "$OK" ;;
    false) printf '%s' "$NO" ;;
    *)     printf '%s' "$NA" ;;
  esac
}

u_bilibili_hkmotw() {
  local r code
  r="$(ucurl "https://api.bilibili.com/pgc/player/web/playurl?avid=18281381&cid=29892777&qn=0&type=&otype=json&ep_id=183799&fourk=1&fnver=0&fnval=16&session=")"
  code="$(jget "$r" '.code')"
  case "$code" in 0) printf '%s' "$OK" ;; -10403|"") printf '%s' "$NO" ;; *) printf '%s' "$NO" ;; esac
}

u_bilibili_tw() {
  local r code
  r="$(ucurl "https://api.bilibili.com/pgc/player/web/playurl?avid=50762638&cid=100279344&qn=0&type=&otype=json&ep_id=268176&fourk=1&fnver=0&fnval=16&session=")"
  code="$(jget "$r" '.code')"
  case "$code" in 0) printf '%s' "$OK" ;; *) printf '%s' "$NO" ;; esac
}

u_wikipedia() {
  local c; c="$(ucode "https://zh.wikipedia.org/wiki/Wikipedia")"
  case "$c" in 200) printf '%s' "$OK" ;; *) printf '%s' "$NO" ;; esac
}

u_google_search() {
  local c; c="$(ucode "https://www.google.com/search?q=hello")"
  case "$c" in 200) printf '✅ 正常' ;; 429|403) printf '❌ 触发验证码' ;; *) printf '%s' "$NA" ;; esac
}

# ---------------- 主流程 ----------------

# 通过率通过全局变量返回，理由同 61_ping.sh
UNLOCK_RATE=""
_run_unlock_suite() {
  local table="$1"
  UNLOCK_RATE=""
  local -a items=(
    "Netflix|u_netflix"
    "Disney+|u_disney"
    "YouTube Premium|u_youtube_premium"
    "Amazon Prime Video|u_primevideo"
    "Max (HBO Max)|u_hbomax"
    "Paramount+|u_paramount"
    "DAZN|u_dazn"
    "Spotify 注册|u_spotify"
    "TikTok|u_tiktok"
    "Steam 商店|u_steam"
    "ChatGPT|u_chatgpt"
    "Google Gemini|u_gemini"
    "Claude AI|u_claude"
    "巴哈姆特動畫瘋|u_bahamut"
    "AbemaTV|u_abema"
    "DMM|u_dmm"
    "Hulu 日本|u_hulujp"
    "TVB Anywhere+|u_tvbanywhere"
    "Bilibili 港澳台|u_bilibili_hkmotw"
    "Bilibili 台湾限定|u_bilibili_tw"
    "维基百科|u_wikipedia"
    "Google 搜索|u_google_search"
  )
  local total=0 pass=0
  local it name fn r
  for it in "${items[@]}"; do
    name="${it%%|*}"; fn="${it##*|}"
    inline "$name ..."
    r="$($fn 2>/dev/null)"
    [ -z "$r" ] && r="$NA"
    inline_done "$r"
    res_add "$table" "$name" "$r"
    total=$((total + 1))
    case "$r" in ✅*) pass=$((pass + 1)) ;; esac
  done
  UNLOCK_RATE="${pass}/${total}"
}

test_unlock() {
  module_enabled unlock || { log_info "跳过流媒体解锁检测"; return 0; }

  if [ "$IPV4_OK" = "1" ]; then
    step "流媒体 / AI 解锁检测（IPv4）"
    UL_STACK=4
    _run_unlock_suite unlock4
    kv_set unlock.v4.summary "$UNLOCK_RATE"
    kv_set unlock.v4.ytcdn "$(u_youtube_cdn)"
    log_ok "IPv4 解锁通过率: $UNLOCK_RATE"
  fi

  if [ "$IPV6_OK" = "1" ]; then
    step "流媒体 / AI 解锁检测（IPv6）"
    UL_STACK=6
    _run_unlock_suite unlock6
    kv_set unlock.v6.summary "$UNLOCK_RATE"
    log_ok "IPv6 解锁通过率: $UNLOCK_RATE"
  else
    kv_set unlock.v6.summary "无 IPv6 出口"
  fi
  UL_STACK=4
}

# ===== 60_speedtest.sh =====
# ============================================================
# 60_speedtest.sh — 三网 / 国际节点测速（Ookla Speedtest CLI）
# ============================================================

ST_BIN=""

install_speedtest() {
  have speedtest && { ST_BIN="$(command -v speedtest)"; return 0; }
  [ -n "$ST_BIN" ] && [ -x "$ST_BIN" ] && return 0

  local arch tag
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)  tag="x86_64" ;;
    aarch64|arm64) tag="aarch64" ;;
    armv7l|armv7)  tag="armhf" ;;
    i386|i686)     tag="i386" ;;
    *) log_warn "Speedtest CLI 不支持架构 $arch"; return 1 ;;
  esac

  local f="$BIN_DIR/st.tgz"
  log_info "下载 Ookla Speedtest CLI ($tag) ..."
  if ! fetch_first "$f" \
      "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${tag}.tgz" \
      "https://install.speedtest.net/app/cli/ookla-speedtest-1.1.1-linux-${tag}.tgz"; then
    log_warn "Speedtest CLI 下载失败"
    return 1
  fi
  tar -xzf "$f" -C "$BIN_DIR" 2>/dev/null
  if [ -x "$BIN_DIR/speedtest" ]; then
    ST_BIN="$BIN_DIR/speedtest"
    "$ST_BIN" --accept-license --accept-gdpr --version >/dev/null 2>&1
    return 0
  fi
  log_warn "Speedtest CLI 解压失败"
  return 1
}

# 按关键词搜索服务器 ID
st_find_server() {
  local kw="$1"
  local j
  j="$(xcurl --get --data-urlencode "search=$kw" \
      "https://www.speedtest.net/api/js/servers?engine=js&limit=5")"
  [ -z "$j" ] && return 1
  local id
  if have jq; then
    id="$(printf '%s' "$j" | jq -r '.[0].id // empty' 2>/dev/null)"
  else
    id="$(printf '%s' "$j" | grep -oE '"id":"?[0-9]+' | head -1 | grep -oE '[0-9]+')"
  fi
  [ -n "$id" ] && printf '%s' "$id"
}

# 运行一次测速：st_run <服务器ID或空>
# 输出 "下载Mbps|上传Mbps|延迟ms|抖动ms|服务器名|城市"
st_run() {
  local sid="$1" out args=()
  args=(--accept-license --accept-gdpr -f json -P 8)
  [ -n "$sid" ] && args+=(-s "$sid")
  out="$(run_to 120 "$ST_BIN" "${args[@]}" 2>/dev/null | tail -1)"
  [ -z "$out" ] && return 1
  case "$out" in *'"type":"result"'*) ;; *) return 1 ;; esac

  local dbw ubw ping jit name loc
  if have jq; then
    dbw="$(printf  '%s' "$out" | jq -r '.download.bandwidth // 0')"
    ubw="$(printf  '%s' "$out" | jq -r '.upload.bandwidth // 0')"
    ping="$(printf '%s' "$out" | jq -r '.ping.latency // 0')"
    jit="$(printf  '%s' "$out" | jq -r '.ping.jitter // 0')"
    name="$(printf '%s' "$out" | jq -r '.server.name // ""')"
    loc="$(printf  '%s' "$out" | jq -r '.server.location // ""')"
  else
    dbw="$(printf  '%s' "$out" | grep -oE '"download":\{"bandwidth":[0-9]+' | grep -oE '[0-9]+$')"
    ubw="$(printf  '%s' "$out" | grep -oE '"upload":\{"bandwidth":[0-9]+'   | grep -oE '[0-9]+$')"
    ping="$(printf '%s' "$out" | grep -oE '"latency":[0-9.]+' | head -1 | cut -d: -f2)"
    jit="$(printf  '%s' "$out" | grep -oE '"jitter":[0-9.]+'  | head -1 | cut -d: -f2)"
    name="$(printf '%s' "$out" | grep -oE '"name":"[^"]*"' | tail -1 | cut -d'"' -f4)"
    loc=""
  fi
  # bandwidth 单位为 byte/s
  printf '%s|%s|%s|%s|%s|%s' \
    "$(calc "${dbw:-0}*8/1000000" 2)" "$(calc "${ubw:-0}*8/1000000" 2)" \
    "$(calc "${ping:-0}" 2)" "$(calc "${jit:-0}" 2)" "$name" "$loc"
}

# 节点表：显示名 | 搜索关键词 | 备用ID
_st_nodes_cn() {
  cat <<'EOF'
上海电信|China Telecom Shanghai|3633
上海联通|China Unicom Shanghai|24447
上海移动|China Mobile Shanghai|25858
北京电信|China Telecom Beijing|27377
北京联通|China Unicom Beijing|5145
北京移动|China Mobile Beijing|41839
广州电信|China Telecom Guangdong|27594
广州联通|China Unicom Guangzhou|26678
广州移动|China Mobile Guangdong|31490
成都电信|China Telecom Chengdu|17320
EOF
}

_st_nodes_global() {
  cat <<'EOF'
香港 HK|Hong Kong|22126
日本 东京|Tokyo Japan|21569
新加坡 SG|Singapore|13623
韩国 首尔|Seoul Korea|6527
台湾 台北|Taipei Taiwan|18445
美国 洛杉矶|Los Angeles|10493
美国 纽约|New York|17383
德国 法兰克福|Frankfurt|26852
英国 伦敦|London|24215
EOF
}

_run_node_list() {
  local table="$1" list="$2" limit="$3"
  local n=0 line label kw fbid sid res
  while IFS='|' read -r label kw fbid; do
    [ -z "$label" ] && continue
    [ "$limit" -gt 0 ] && [ "$n" -ge "$limit" ] && break
    n=$((n + 1))
    inline "$label ..."
    sid="$(st_find_server "$kw")"
    [ -z "$sid" ] && sid="$fbid"
    res="$(st_run "$sid")"
    if [ -z "$res" ] && [ -n "$fbid" ] && [ "$sid" != "$fbid" ]; then
      res="$(st_run "$fbid")"
    fi
    if [ -n "$res" ]; then
      local dl ul pg jt nm lc
      IFS='|' read -r dl ul pg jt nm lc <<< "$res"
      inline_done "↓ ${dl} Mbps  ↑ ${ul} Mbps  ${pg} ms"
      row_add "$table" "$label" "${dl} Mbps" "${ul} Mbps" "${pg} ms" "${jt} ms" "${nm:-$kw}"
    else
      inline_done "失败"
      row_add "$table" "$label" "N/A" "N/A" "N/A" "N/A" "测速失败"
    fi
  done <<< "$list"
}

test_speedtest() {
  module_enabled speedtest || { log_info "跳过测速"; return 0; }
  [ "$SPEEDTEST_MODE" = "off" ] && { log_info "已禁用测速"; return 0; }

  step "三网 / 国际节点测速"
  log_warn "测速会消耗较多流量（每节点约 100-500MB），如流量敏感请用 --speedtest off"

  if ! install_speedtest; then
    log_warn "Speedtest CLI 不可用，跳过测速"
    row_add speed_cn "测速" "Speedtest CLI 不可用" "" "" "" ""
    return 0
  fi

  # 先跑一次自动就近节点
  inline "自动就近节点 ..."
  local auto; auto="$(st_run "")"
  if [ -n "$auto" ]; then
    local dl ul pg jt nm lc
    IFS='|' read -r dl ul pg jt nm lc <<< "$auto"
    inline_done "↓ ${dl} Mbps  ↑ ${ul} Mbps  ${pg} ms  @${nm}"
    row_add speed_auto "就近节点" "${dl} Mbps" "${ul} Mbps" "${pg} ms" "${jt} ms" "${nm} ${lc}"
    kv_set speed.auto.down "$dl"; kv_set speed.auto.up "$ul"; kv_set speed.auto.ping "$pg"
  else
    inline_done "失败"
  fi

  local limit=0
  [ "$FAST_MODE" = "1" ] && limit=3

  case "$SPEEDTEST_MODE" in
    cn)     _run_node_list speed_cn "$(_st_nodes_cn)" "$limit" ;;
    global) _run_node_list speed_gl "$(_st_nodes_global)" "$limit" ;;
    all)
      _run_node_list speed_cn "$(_st_nodes_cn)" "$limit"
      _run_node_list speed_gl "$(_st_nodes_global)" "$limit"
      ;;
  esac
}

# ===== 61_ping.sh =====
# ============================================================
# 61_ping.sh — 三网及全球节点延迟 / 丢包
# ============================================================

# 目标表：显示名|IP|分组
_ping_targets_cn() {
  cat <<'EOF'
北京电信|219.141.136.12|电信
上海电信|202.96.209.133|电信
广州电信|58.60.188.222|电信
北京联通|202.106.50.1|联通
上海联通|210.22.97.1|联通
广州联通|210.21.196.6|联通
北京移动|221.179.155.161|移动
上海移动|211.136.112.200|移动
广州移动|120.196.165.24|移动
北京教育网|101.6.15.130|教育网
EOF
}

_ping_targets_global() {
  cat <<'EOF'
香港 HKIX|123.255.90.1|亚太
日本 东京|210.130.0.1|亚太
新加坡|165.21.83.88|亚太
韩国 首尔|168.126.63.1|亚太
台湾 台北|168.95.1.1|亚太
美国 洛杉矶|4.2.2.1|美洲
美国 圣何塞|208.67.222.222|美洲
德国 法兰克福|194.25.0.60|欧洲
英国 伦敦|8.8.8.8|欧洲
EOF
}

# _ping_one <ip> -> "avg|loss"
_ping_one() {
  local ip="$1" cnt="${2:-5}" out avg loss
  out="$(run_to $((cnt * 2 + 8)) ping -c "$cnt" -W 2 -i 0.3 "$ip" 2>/dev/null)"
  [ -z "$out" ] && out="$(run_to $((cnt * 2 + 8)) ping -c "$cnt" -W 2 "$ip" 2>/dev/null)"
  [ -z "$out" ] && return 1
  loss="$(printf '%s' "$out" | grep -oE '[0-9.]+% packet loss' | grep -oE '^[0-9.]+')"
  avg="$(printf '%s' "$out" | grep -E 'min/avg|round-trip' | awk -F'/' '{print $5}')"
  [ -z "$avg" ] && avg="$(printf '%s' "$out" | grep -oE 'time=[0-9.]+' | tail -1 | cut -d= -f2)"
  printf '%s|%s' "${avg:-}" "${loss:-100}"
}

# 结果通过全局变量返回：进度是打在 stdout 上的，
# 用 $(...) 捕获返回值会把进度一起吞进去。
PING_AVG=""
_run_ping_list() {
  local table="$1" list="$2"
  local label ip grp res avg loss sum=0 n=0
  PING_AVG=""
  while IFS='|' read -r label ip grp; do
    [ -z "$label" ] && continue
    inline "$label ($ip) ..."
    res="$(_ping_one "$ip" 5)"
    if [ -n "$res" ]; then
      IFS='|' read -r avg loss <<< "$res"
      if [ -n "$avg" ]; then
        inline_done "$(calc "$avg" 1) ms / 丢包 ${loss}%"
        row_add "$table" "$label" "$grp" "$(calc "$avg" 1) ms" "${loss}%"
        sum="$(calc "$sum+$avg" 2)"; n=$((n + 1))
      else
        inline_done "超时"
        row_add "$table" "$label" "$grp" "超时" "${loss}%"
      fi
    else
      inline_done "不可达"
      row_add "$table" "$label" "$grp" "不可达" "100%"
    fi
  done <<< "$list"
  [ "$n" -gt 0 ] && PING_AVG="$(calc "$sum/$n" 1)"
}

test_ping() {
  module_enabled ping || { log_info "跳过延迟测试"; return 0; }
  if ! have ping; then
    log_warn "系统缺少 ping 命令，跳过延迟测试"
    return 0
  fi

  step "三网延迟与丢包"
  _run_ping_list ping_cn "$(_ping_targets_cn)"
  [ -n "$PING_AVG" ] && { kv_set ping.cn.avg "$PING_AVG"; log_ok "国内均值: ${PING_AVG} ms"; }

  if [ "$FAST_MODE" != "1" ]; then
    step "全球节点延迟"
    _run_ping_list ping_gl "$(_ping_targets_global)"
    [ -n "$PING_AVG" ] && { kv_set ping.global.avg "$PING_AVG"; log_ok "全球均值: ${PING_AVG} ms"; }
  fi
}

# ===== 62_route.sh =====
# ============================================================
# 62_route.sh — 三网回程路由追踪（nexttrace，回退 traceroute/mtr）
# ============================================================

NT_BIN=""

install_nexttrace() {
  have nexttrace && { NT_BIN="$(command -v nexttrace)"; return 0; }
  local arch; arch="$(arch_tag)"
  case "$arch" in
    amd64) a="amd64" ;; arm64) a="arm64" ;; armv7) a="armv7" ;; i386) a="386" ;;
    *) log_warn "nexttrace 不支持架构 $(uname -m)"; return 1 ;;
  esac
  local f="$BIN_DIR/nexttrace"
  log_info "下载 nexttrace ($a) ..."
  if fetch_first "$f" \
      "https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${a}" \
      "https://ghfast.top/https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${a}" \
      "https://gh-proxy.com/https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${a}"; then
    chmod +x "$f" 2>/dev/null
    if "$f" --version >/dev/null 2>&1; then NT_BIN="$f"; return 0; fi
  fi
  log_warn "nexttrace 下载失败，将回退到 traceroute/mtr"
  return 1
}

# 回程路由目标
_route_targets() {
  cat <<'EOF'
北京电信|219.141.140.10
上海电信|202.96.209.133
广州电信|58.60.188.222
北京联通|202.106.195.68
上海联通|210.22.97.1
广州联通|210.21.196.6
北京移动|221.183.129.101
上海移动|211.136.112.200
广州移动|120.196.165.24
EOF
}

_trace_one() {
  local ip="$1" out
  if [ -n "$NT_BIN" ]; then
    out="$(run_to 90 "$NT_BIN" -M -q 1 -n --map=false "$ip" 2>/dev/null)"
    [ -z "$out" ] && out="$(run_to 90 "$NT_BIN" -q 1 "$ip" 2>/dev/null)"
  elif have mtr; then
    out="$(run_to 90 mtr -r -c 3 -n "$ip" 2>/dev/null)"
  elif have traceroute; then
    out="$(run_to 90 traceroute -q 1 -w 2 -m 20 "$ip" 2>/dev/null)"
  elif have tracepath; then
    out="$(run_to 90 tracepath -m 20 "$ip" 2>/dev/null)"
  fi
  printf '%s' "$out"
}

# 从路由文本粗略识别线路类型
_guess_line() {
  local txt="$1"
  local hit=""
  case "$txt" in
    *59.43.*)                      hit="CN2 GIA (AS4809/59.43)" ;;
    *202.97.*)                     hit="电信 163 骨干 (AS4134)" ;;
  esac
  case "$txt" in
    *"AS9929"*|*9929*)             hit="${hit:+$hit / }联通 A网 CUII (AS9929)" ;;
  esac
  case "$txt" in
    *"AS4837"*|*219.158.*)         hit="${hit:+$hit / }联通 169 骨干 (AS4837)" ;;
  esac
  case "$txt" in
    *"AS58807"*|*"CMIN2"*)         hit="${hit:+$hit / }移动 CMIN2 (AS58807)" ;;
  esac
  case "$txt" in
    *"AS58453"*|*223.120.*)        hit="${hit:+$hit / }移动 CMI (AS58453)" ;;
  esac
  [ -z "$hit" ] && hit="常规路由"
  printf '%s' "$hit"
}

test_route() {
  module_enabled route || { log_info "跳过路由追踪"; return 0; }
  step "三网回程路由追踪"

  if [ "$(id -u)" != "0" ]; then
    log_warn "非 root 运行，路由追踪可能无法发送 ICMP 探测包"
  fi
  install_nexttrace || true
  if [ -z "$NT_BIN" ] && ! have mtr && ! have traceroute && ! have tracepath; then
    log_warn "无可用的路由追踪工具，跳过"
    return 0
  fi

  local label ip out line n=0
  while IFS='|' read -r label ip; do
    [ -z "$label" ] && continue
    n=$((n + 1))
    [ "$FAST_MODE" = "1" ] && [ "$n" -gt 3 ] && break
    inline "$label ($ip) ..."
    out="$(_trace_one "$ip")"
    if [ -n "$out" ]; then
      line="$(_guess_line "$out")"
      inline_done "$line"
      row_add route "$label" "$ip" "$line"
      raw_add "回程路由 · $label ($ip)" "$out"
    else
      inline_done "失败"
      row_add route "$label" "$ip" "追踪失败"
    fi
  done <<< "$(_route_targets)"
}

# ===== 65_score.sh =====
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

# ===== 70_report_md.sh =====
# ============================================================
# 70_report_md.sh — Markdown 报告（适配博客 / GitHub / Hexo）
# ============================================================

# md_table <表名> <表头1> <表头2> ...
md_table() {
  local t="$1"; shift
  rows_have "$t" || return 0
  local h sep
  h="|"; sep="|"
  for h2 in "$@"; do h="$h $h2 |"; sep="$sep :--- |"; done
  printf '%s\n%s\n' "$h" "$sep"
  local line f
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    printf '|'
    for f in "${ROW_F[@]}"; do printf ' %s |' "${f//|/\\|}"; done
    printf '\n'
  done <<< "$(rows_get "$t")"
  printf '\n'
}

md_kv_row() { printf '| %s | %s |\n' "$1" "$2"; }

gen_markdown() {
  local title
  title="$(kv_or meta.node_name "$(kv_get sys.cpu.model)")"

  cat <<EOF
# ${title} 服务器测评报告

> 测试时间：**$(kv_get meta.time_local)**（$(kv_get meta.time_utc)）
> 测试工具：[${VPSTEST_NAME} v${VPSTEST_VERSION}](${VPSTEST_REPO})
> 出口位置：$(kv_get net.location) · $(kv_or net.as '未知 ASN')

---

## 📊 综合评分

EOF

  if rows_have score; then
    printf '**总分：%s / 100 —— %s**\n\n' "$(kv_get score.total)" "$(kv_get score.grade)"
    md_table score "评分项" "得分" "满分"
  fi

  cat <<EOF
---

## 一、系统与硬件信息

| 项目 | 内容 |
| :--- | :--- |
EOF
  md_kv_row "CPU 型号"    "$(kv_get sys.cpu.model)"
  md_kv_row "CPU 核心数"  "$(kv_get sys.cpu.cores) 核"
  md_kv_row "CPU 频率"    "$(kv_get sys.cpu.freq)"
  md_kv_row "CPU 缓存"    "$(kv_get sys.cpu.cache)"
  md_kv_row "AES-NI"      "$(kv_get sys.cpu.aes)"
  md_kv_row "硬件虚拟化"  "$(kv_get sys.cpu.virt)"
  md_kv_row "内存"        "$(kv_get sys.mem.summary)"
  md_kv_row "Swap"        "$(kv_get sys.swap.summary)"
  md_kv_row "硬盘空间"    "$(kv_get sys.disk.summary)"
  md_kv_row "文件系统"    "$(kv_get sys.disk.fs)"
  md_kv_row "操作系统"    "$(kv_get sys.os)"
  md_kv_row "系统架构"    "$(kv_get sys.arch)"
  md_kv_row "内核版本"    "$(kv_get sys.kernel)"
  md_kv_row "虚拟化架构"  "$(kv_get sys.virt)"
  md_kv_row "TCP 加速"    "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  md_kv_row "协议栈"      "$(kv_get net.stack)"
  md_kv_row "系统负载"    "$(kv_get sys.load)"
  md_kv_row "运行时间"    "$(kv_get sys.uptime)"
  printf '\n'

  if rows_have cpu; then
    printf -- '---\n\n## 二、CPU 性能测试\n\n'
    md_table cpu "测试项" "结果"
    [ -n "$(kv_get cpu.sysbench.scale)" ] &&
      printf '> 多核扩展比：**%s**（理想值接近核心数）\n\n' "$(kv_get cpu.sysbench.scale)"
  fi

  if rows_have memory; then
    printf -- '---\n\n## 三、内存性能测试\n\n'
    md_table memory "测试项" "结果"
  fi

  if rows_have disk_dd || rows_have disk_fio; then
    printf -- '---\n\n## 四、磁盘 I/O 测试\n\n'
    if rows_have disk_dd; then
      printf '### 4.1 顺序读写（dd）\n\n'
      md_table disk_dd "块大小 × 数量" "写入速度" "读取速度"
    fi
    if rows_have disk_fio; then
      printf '### 4.2 随机读写（fio · 混合读写 iodepth=64）\n\n'
      md_table disk_fio "块大小" "读取" "写入" "合计"
    fi
  fi

  if rows_have ipq_base; then
    printf -- '---\n\n## 五、IP 质量体检\n\n'
    printf '### 5.1 基础画像\n\n'
    md_table ipq_base "项目" "内容"
    if rows_have ipq_type; then
      printf '### 5.2 IP 类型判定\n\n'
      md_table ipq_type "检测项" "结果"
    fi
    if rows_have ipq_risk; then
      printf '### 5.3 风险与信誉\n\n'
      md_table ipq_risk "检测项" "结果"
    fi
    if rows_have ipq_rbl; then
      printf '### 5.4 邮件黑名单（DNSBL）\n\n'
      printf '> 汇总：**%s**\n\n' "$(kv_get ipq.rbl_summary)"
      md_table ipq_rbl "黑名单库" "状态"
    fi
    if rows_have ipq_port; then
      printf '### 5.5 出站端口与连通性\n\n'
      md_table ipq_port "检测项" "结果"
    fi
  fi

  if rows_have unlock4 || rows_have unlock6; then
    printf -- '---\n\n## 六、流媒体 / AI 服务解锁\n\n'
    if rows_have unlock4; then
      printf '### 6.1 IPv4 解锁（通过率 %s）\n\n' "$(kv_or unlock.v4.summary 'N/A')"
      md_table unlock4 "服务" "结果"
      [ -n "$(kv_get unlock.v4.ytcdn)" ] &&
        printf '> YouTube CDN 节点：**%s**\n\n' "$(kv_get unlock.v4.ytcdn)"
    fi
    if rows_have unlock6; then
      printf '### 6.2 IPv6 解锁（通过率 %s）\n\n' "$(kv_or unlock.v6.summary 'N/A')"
      md_table unlock6 "服务" "结果"
    fi
  fi

  if rows_have ping_cn || rows_have ping_gl; then
    printf -- '---\n\n## 七、延迟与丢包\n\n'
    if rows_have ping_cn; then
      printf '### 7.1 国内三网（均值 %s ms）\n\n' "$(kv_or ping.cn.avg 'N/A')"
      md_table ping_cn "节点" "线路" "平均延迟" "丢包率"
    fi
    if rows_have ping_gl; then
      printf '### 7.2 全球节点（均值 %s ms）\n\n' "$(kv_or ping.global.avg 'N/A')"
      md_table ping_gl "节点" "区域" "平均延迟" "丢包率"
    fi
  fi

  if rows_have speed_auto || rows_have speed_cn || rows_have speed_gl; then
    printf -- '---\n\n## 八、网络测速（Speedtest）\n\n'
    if rows_have speed_auto; then
      printf '### 8.1 就近节点\n\n'
      md_table speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"
    fi
    if rows_have speed_cn; then
      printf '### 8.2 国内三网节点\n\n'
      md_table speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"
    fi
    if rows_have speed_gl; then
      printf '### 8.3 国际节点\n\n'
      md_table speed_gl "节点" "下载" "上传" "延迟" "抖动" "服务器"
    fi
  fi

  if rows_have route; then
    printf -- '---\n\n## 九、三网回程路由\n\n'
    md_table route "目标" "IP" "线路判定"
    if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
      printf '<details>\n<summary>展开完整路由追踪原始输出</summary>\n\n'
      local k
      for k in "${RAW_ORDER[@]}"; do
        printf '**%s**\n\n```\n%s\n```\n\n' "$k" "${RAWS[$k]}"
      done
      printf '</details>\n\n'
    fi
  fi

  cat <<EOF
---

## 测试说明

- 测试环境：$(kv_get sys.os) / $(kv_get sys.kernel) / $(kv_get sys.virt)
- 依赖情况：$(kv_or meta.deps '未记录')
- 总耗时：$(kv_or meta.duration '未记录')
- 测速与路由结果受测试时段、对端节点负载影响，建议在不同时段多次复测取平均。
- 本报告由 [${VPSTEST_NAME}](${VPSTEST_REPO}) 一键脚本自动生成。

\`\`\`bash
bash <(curl -sL ${VPSTEST_REPO}/raw/main/dist/vpstest.sh)
\`\`\`
EOF
}

# ===== 71_report_bbcode.sh =====
# ============================================================
# 71_report_bbcode.sh — BBCode 报告（Discuz / hostloc / NodeSeek 等论坛）
# ============================================================

# 论坛里 emoji 表现不稳定，统一替换为纯文本标记
bb_plain() {
  local s="$*"
  s="${s//✅/[OK] }"; s="${s//❌/[NO] }"; s="${s//⚠️/[?] }"
  s="${s//✔/[Y] }";  s="${s//✘/[N] }"
  printf '%s' "$s"
}

bb_table() {
  local t="$1"; shift
  rows_have "$t" || return 0
  printf '[table]\n[tr]'
  local h
  for h in "$@"; do printf '[td][b]%s[/b][/td]' "$h"; done
  printf '[/tr]\n'
  local line f
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    printf '[tr]'
    for f in "${ROW_F[@]}"; do printf '[td]%s[/td]' "$(bb_plain "$f")"; done
    printf '[/tr]\n'
  done <<< "$(rows_get "$t")"
  printf '[/table]\n\n'
}

bb_h() { printf '[size=4][b][color=#2b6cb0]%s[/color][/b][/size]\n' "$*"; }
bb_h2() { printf '[b]%s[/b]\n' "$*"; }
bb_kv() { printf '[tr][td][b]%s[/b][/td][td]%s[/td][/tr]\n' "$1" "$(bb_plain "$2")"; }

gen_bbcode() {
  local title
  title="$(kv_or meta.node_name "$(kv_get sys.cpu.model)")"

  printf '[align=center][size=5][b]%s 服务器测评报告[/b][/size][/align]\n' "$title"
  printf '[align=center][color=#888]测试时间：%s ｜ 出口：%s ｜ %s[/color][/align]\n\n' \
    "$(kv_get meta.time_local)" "$(kv_get net.location)" "$(kv_or net.as '未知 ASN')"

  if rows_have score; then
    bb_h "综合评分"
    printf '[size=4][b][color=#c53030]总分：%s / 100 —— %s[/color][/b][/size]\n\n' \
      "$(kv_get score.total)" "$(kv_get score.grade)"
    bb_table score "评分项" "得分" "满分"
  fi

  bb_h "一、系统与硬件信息"
  printf '[table]\n'
  bb_kv "CPU 型号"   "$(kv_get sys.cpu.model)"
  bb_kv "CPU 核心数" "$(kv_get sys.cpu.cores) 核"
  bb_kv "CPU 频率"   "$(kv_get sys.cpu.freq)"
  bb_kv "CPU 缓存"   "$(kv_get sys.cpu.cache)"
  bb_kv "AES-NI"     "$(kv_get sys.cpu.aes)"
  bb_kv "硬件虚拟化" "$(kv_get sys.cpu.virt)"
  bb_kv "内存"       "$(kv_get sys.mem.summary)"
  bb_kv "Swap"       "$(kv_get sys.swap.summary)"
  bb_kv "硬盘空间"   "$(kv_get sys.disk.summary)（$(kv_get sys.disk.fs)）"
  bb_kv "操作系统"   "$(kv_get sys.os)"
  bb_kv "内核版本"   "$(kv_get sys.kernel)"
  bb_kv "虚拟化架构" "$(kv_get sys.virt)"
  bb_kv "TCP 加速"   "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  bb_kv "协议栈"     "$(kv_get net.stack)"
  printf '[/table]\n\n'

  if rows_have cpu; then
    bb_h "二、CPU 性能测试"
    bb_table cpu "测试项" "结果"
  fi

  if rows_have memory; then
    bb_h "三、内存性能测试"
    bb_table memory "测试项" "结果"
  fi

  if rows_have disk_dd || rows_have disk_fio; then
    bb_h "四、磁盘 I/O 测试"
    rows_have disk_dd  && { bb_h2 "顺序读写（dd）";   bb_table disk_dd "块大小 × 数量" "写入" "读取"; }
    rows_have disk_fio && { bb_h2 "随机读写（fio）"; bb_table disk_fio "块大小" "读取" "写入" "合计"; }
  fi

  if rows_have ipq_base; then
    bb_h "五、IP 质量体检"
    bb_table ipq_base "项目" "内容"
    rows_have ipq_type && { bb_h2 "IP 类型判定"; bb_table ipq_type "检测项" "结果"; }
    rows_have ipq_risk && { bb_h2 "风险与信誉"; bb_table ipq_risk "检测项" "结果"; }
    if rows_have ipq_rbl; then
      bb_h2 "邮件黑名单（$(kv_get ipq.rbl_summary)）"
      bb_table ipq_rbl "黑名单库" "状态"
    fi
    rows_have ipq_port && { bb_h2 "出站端口与连通性"; bb_table ipq_port "检测项" "结果"; }
  fi

  if rows_have unlock4 || rows_have unlock6; then
    bb_h "六、流媒体 / AI 解锁"
    if rows_have unlock4; then
      bb_h2 "IPv4（通过率 $(kv_or unlock.v4.summary 'N/A')）"
      bb_table unlock4 "服务" "结果"
    fi
    if rows_have unlock6; then
      bb_h2 "IPv6（通过率 $(kv_or unlock.v6.summary 'N/A')）"
      bb_table unlock6 "服务" "结果"
    fi
  fi

  if rows_have ping_cn || rows_have ping_gl; then
    bb_h "七、延迟与丢包"
    rows_have ping_cn && {
      bb_h2 "国内三网（均值 $(kv_or ping.cn.avg 'N/A') ms）"
      bb_table ping_cn "节点" "线路" "平均延迟" "丢包率"; }
    rows_have ping_gl && {
      bb_h2 "全球节点（均值 $(kv_or ping.global.avg 'N/A') ms）"
      bb_table ping_gl "节点" "区域" "平均延迟" "丢包率"; }
  fi

  if rows_have speed_auto || rows_have speed_cn || rows_have speed_gl; then
    bb_h "八、网络测速"
    rows_have speed_auto && bb_table speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"
    rows_have speed_cn   && { bb_h2 "国内三网"; bb_table speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
    rows_have speed_gl   && { bb_h2 "国际节点"; bb_table speed_gl "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  fi

  if rows_have route; then
    bb_h "九、三网回程路由"
    bb_table route "目标" "IP" "线路判定"
    if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
      local k
      for k in "${RAW_ORDER[@]}"; do
        printf '[b]%s[/b]\n[code]%s[/code]\n' "$k" "${RAWS[$k]}"
      done
      printf '\n'
    fi
  fi

  printf '[hr]\n'
  printf '[color=#888]测试环境：%s / %s / %s ｜ 总耗时：%s[/color]\n' \
    "$(kv_get sys.os)" "$(kv_get sys.kernel)" "$(kv_get sys.virt)" "$(kv_or meta.duration '未记录')"
  printf '[color=#888]本报告由 [url=%s]%s v%s[/url] 一键脚本生成：[/color]\n' \
    "$VPSTEST_REPO" "$VPSTEST_NAME" "$VPSTEST_VERSION"
  printf '[code]bash <(curl -sL %s/raw/main/dist/vpstest.sh)[/code]\n' "$VPSTEST_REPO"
}

# ===== 72_report_html.sh =====
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

# ===== 73_report_json.sh =====
# ============================================================
# 73_report_json.sh — JSON（机器可读）与纯文本报告
# ============================================================

gen_json() {
  printf '{\n'
  printf '  "tool": {"name": "%s", "version": "%s", "repo": "%s"},\n' \
    "$VPSTEST_NAME" "$VPSTEST_VERSION" "$VPSTEST_REPO"

  # --- 单值区 ---
  printf '  "kv": {\n'
  local first=1 k
  for k in $(printf '%s\n' "${!KV[@]}" | sort); do
    [ "$first" = "1" ] || printf ',\n'
    first=0
    printf '    "%s": "%s"' "$(json_escape "$k")" "$(json_escape "${KV[$k]}")"
  done
  printf '\n  },\n'

  # --- 表格区 ---
  printf '  "tables": {\n'
  first=1
  for k in $(printf '%s\n' "${!ROWS[@]}" | sort); do
    [ "$first" = "1" ] || printf ',\n'
    first=0
    printf '    "%s": [' "$(json_escape "$k")"
    local rfirst=1 line
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      [ "$rfirst" = "1" ] || printf ','
      rfirst=0
      printf '\n      ['
      local ffirst=1 f
      row_split "$line"
      for f in "${ROW_F[@]}"; do
        [ "$ffirst" = "1" ] || printf ', '
        ffirst=0
        printf '"%s"' "$(json_escape "$f")"
      done
      printf ']'
    done <<< "${ROWS[$k]}"
    printf '\n    ]'
  done
  printf '\n  },\n'

  # --- 原始输出区 ---
  printf '  "raw": {\n'
  first=1
  if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
    for k in "${RAW_ORDER[@]}"; do
      [ "$first" = "1" ] || printf ',\n'
      first=0
      printf '    "%s": "%s"' "$(json_escape "$k")" "$(json_escape "${RAWS[$k]}")"
    done
  fi
  printf '\n  }\n'
  printf '}\n'
}

# ---------- 纯文本（终端友好 / 粘贴到任何地方） ----------
txt_line() { printf '%s\n' "----------------------------------------------------------------------"; }

txt_table() {
  local t="$1"; shift
  rows_have "$t" || return 0
  local line
  printf '%-30s' "$1"; shift
  local h
  for h in "$@"; do printf '%-22s' "$h"; done
  printf '\n'
  txt_line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local first=1 f
    row_split "$line"
    for f in "${ROW_F[@]}"; do
      if [ "$first" = "1" ]; then printf '%-30s' "$f"; first=0
      else printf '%-22s' "$f"; fi
    done
    printf '\n'
  done <<< "$(rows_get "$t")"
  printf '\n'
}

txt_kv() { printf ' %-14s : %s\n' "$1" "$2"; }

gen_txt() {
  local title; title="$(kv_or meta.node_name "$(kv_get sys.cpu.model)")"
  txt_line
  printf ' %s 服务器测评报告\n' "$title"
  printf ' 测试时间: %s\n' "$(kv_get meta.time_local)"
  printf ' 出口位置: %s | %s\n' "$(kv_get net.location)" "$(kv_or net.as '未知 ASN')"
  printf ' 测试工具: %s v%s  %s\n' "$VPSTEST_NAME" "$VPSTEST_VERSION" "$VPSTEST_REPO"
  txt_line

  if rows_have score; then
    printf '\n[ 综合评分 ]  %s / 100  —  %s\n\n' "$(kv_get score.total)" "$(kv_get score.grade)"
    txt_table score "评分项" "得分" "满分"
  fi

  printf '\n[ 一、系统与硬件信息 ]\n'
  txt_kv "CPU 型号"   "$(kv_get sys.cpu.model)"
  txt_kv "CPU 核心数" "$(kv_get sys.cpu.cores) 核"
  txt_kv "CPU 频率"   "$(kv_get sys.cpu.freq)"
  txt_kv "CPU 缓存"   "$(kv_get sys.cpu.cache)"
  txt_kv "AES-NI"     "$(kv_get sys.cpu.aes)"
  txt_kv "硬件虚拟化" "$(kv_get sys.cpu.virt)"
  txt_kv "内存"       "$(kv_get sys.mem.summary)"
  txt_kv "Swap"       "$(kv_get sys.swap.summary)"
  txt_kv "硬盘空间"   "$(kv_get sys.disk.summary) ($(kv_get sys.disk.fs))"
  txt_kv "操作系统"   "$(kv_get sys.os)"
  txt_kv "内核版本"   "$(kv_get sys.kernel)"
  txt_kv "虚拟化架构" "$(kv_get sys.virt)"
  txt_kv "TCP 加速"   "$(kv_get sys.tcp.cc) + $(kv_get sys.tcp.qdisc)"
  txt_kv "协议栈"     "$(kv_get net.stack)"
  printf '\n'

  rows_have cpu      && { printf '[ 二、CPU 性能 ]\n';      txt_table cpu "测试项" "结果"; }
  rows_have memory   && { printf '[ 三、内存性能 ]\n';      txt_table memory "测试项" "结果"; }
  rows_have disk_dd  && { printf '[ 四、磁盘顺序读写 ]\n';  txt_table disk_dd "块大小×数量" "写入" "读取"; }
  rows_have disk_fio && { printf '[ 四、磁盘随机读写 ]\n';  txt_table disk_fio "块大小" "读取" "写入" "合计"; }
  rows_have ipq_base && { printf '[ 五、IP 基础画像 ]\n';   txt_table ipq_base "项目" "内容"; }
  rows_have ipq_type && { printf '[ 五、IP 类型判定 ]\n';   txt_table ipq_type "检测项" "结果"; }
  rows_have ipq_risk && { printf '[ 五、风险与信誉 ]\n';    txt_table ipq_risk "检测项" "结果"; }
  rows_have ipq_rbl  && { printf '[ 五、邮件黑名单 ] %s\n' "$(kv_get ipq.rbl_summary)"
                          txt_table ipq_rbl "黑名单库" "状态"; }
  rows_have ipq_port && { printf '[ 五、端口与连通性 ]\n';  txt_table ipq_port "检测项" "结果"; }
  rows_have unlock4  && { printf '[ 六、IPv4 解锁 ] 通过率 %s\n' "$(kv_or unlock.v4.summary 'N/A')"
                          txt_table unlock4 "服务" "结果"; }
  rows_have unlock6  && { printf '[ 六、IPv6 解锁 ] 通过率 %s\n' "$(kv_or unlock.v6.summary 'N/A')"
                          txt_table unlock6 "服务" "结果"; }
  rows_have ping_cn  && { printf '[ 七、国内三网延迟 ] 均值 %s ms\n' "$(kv_or ping.cn.avg 'N/A')"
                          txt_table ping_cn "节点" "线路" "延迟" "丢包"; }
  rows_have ping_gl  && { printf '[ 七、全球节点延迟 ] 均值 %s ms\n' "$(kv_or ping.global.avg 'N/A')"
                          txt_table ping_gl "节点" "区域" "延迟" "丢包"; }
  rows_have speed_auto && { printf '[ 八、就近节点测速 ]\n'; txt_table speed_auto "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  rows_have speed_cn   && { printf '[ 八、国内三网测速 ]\n'; txt_table speed_cn "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  rows_have speed_gl   && { printf '[ 八、国际节点测速 ]\n'; txt_table speed_gl "节点" "下载" "上传" "延迟" "抖动" "服务器"; }
  rows_have route      && { printf '[ 九、三网回程路由 ]\n'; txt_table route "目标" "IP" "线路判定"; }

  if [ "${#RAW_ORDER[@]}" -gt 0 ]; then
    printf '\n[ 路由追踪原始输出 ]\n'
    local k
    for k in "${RAW_ORDER[@]}"; do
      printf '\n--- %s ---\n%s\n' "$k" "${RAWS[$k]}"
    done
  fi

  txt_line
  printf ' 总耗时: %s | 依赖: %s\n' "$(kv_or meta.duration '未记录')" "$(kv_or meta.deps '未记录')"
  txt_line
}

# ===== 90_main.sh =====
# ============================================================
# 90_main.sh — 参数解析、主流程、报告落盘
# ============================================================

MASK_IP="${MASK_IP:-1}"

usage() {
  cat <<EOF
${VPSTEST_NAME} v${VPSTEST_VERSION} — VPS / 服务器一键全能测评

用法:
  bash vpstest.sh [选项]
  bash <(curl -sL ${VPSTEST_REPO}/raw/main/dist/vpstest.sh) [选项]

测试内容:
  系统硬件信息 · CPU/内存/磁盘性能 · IP 质量体检 · 流媒体与 AI 解锁
  三网延迟丢包 · 三网与国际测速 · 三网回程路由 · 综合评分

选项:
  -n, --name <名称>       报告标题使用的机器名（如 "DMIT HKG.AN5.EB.Tiny"）
  -o, --output <目录>     报告输出目录（默认 ./vpstest-result）
  -m, --only <模块,...>   只跑指定模块
  -s, --skip <模块,...>   跳过指定模块
      --fast              快速模式（缩短时长、减少节点）
      --full              完整模式（含 Geekbench，耗时最长）
      --speedtest <模式>  cn | global | all | off（默认 cn）
      --geekbench         启用 Geekbench 6 跑分（联网上传结果）
      --show-ip           报告中显示完整出口 IP（默认部分遮蔽）
      --no-color          关闭彩色输出
  -q, --quiet             安静模式，只输出最终结果路径
  -h, --help              显示本帮助
  -v, --version           显示版本

可用模块名:
  cpu memory disk ipquality unlock ping speedtest route

示例:
  # 全量测试
  bash vpstest.sh -n "DMIT HKG.AN5.EB.Tiny"
  # 只测解锁和 IP 质量
  bash vpstest.sh --only unlock,ipquality
  # 不跑测速（省流量）
  bash vpstest.sh --speedtest off
  # 国内 + 国际全测速
  bash vpstest.sh --speedtest all --full
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--name)      NODE_NAME="$2"; shift 2 ;;
      -o|--output)    OUT_DIR="$2"; shift 2 ;;
      -m|--only)      ONLY_MODULES="$2"; shift 2 ;;
      -s|--skip)      SKIP_MODULES="$2"; shift 2 ;;
      --fast)         FAST_MODE=1; shift ;;
      --full)         FAST_MODE=0; ENABLE_GEEKBENCH=1; SPEEDTEST_MODE="all"; shift ;;
      --speedtest)    SPEEDTEST_MODE="$2"; shift 2 ;;
      --geekbench)    ENABLE_GEEKBENCH=1; shift ;;
      --show-ip)      MASK_IP=0; shift ;;
      --no-color)     USE_COLOR=0; _c_init; shift ;;
      -q|--quiet)     QUIET=1; USE_COLOR=0; _c_init; shift ;;
      -h|--help)      usage; exit 0 ;;
      -v|--version)   printf '%s v%s\n' "$VPSTEST_NAME" "$VPSTEST_VERSION"; exit 0 ;;
      *)              log_err "未知参数: $1"; usage; exit 1 ;;
    esac
  done
  case "$SPEEDTEST_MODE" in
    cn|global|all|off) ;;
    *) log_err "--speedtest 仅支持 cn / global / all / off"; exit 1 ;;
  esac
}

banner() {
  [ "$QUIET" = "1" ] && return 0
  cat <<EOF
${C_B}${C_C}
 ╦  ╦╔═╗╔═╗  ╔╦╗╔═╗╔═╗╔╦╗
 ╚╗╔╝╠═╝╚═╗   ║ ║╣ ╚═╗ ║
  ╚╝ ╩  ╚═╝   ╩ ╚═╝╚═╝ ╩   ${C_RST}${C_DIM}v${VPSTEST_VERSION}${C_RST}
${C_DIM} 一键全能服务器测评 · 输出适配博客/论坛
 ${VPSTEST_REPO}${C_RST}

EOF
}

cleanup() {
  [ -n "$BIN_DIR" ] && [ -d "$BIN_DIR" ] && rm -rf "$BIN_DIR" 2>/dev/null
  [ -n "$DISK_WORKDIR" ] && rm -f "$DISK_WORKDIR/.vpstest_dd" "$DISK_WORKDIR/.vpstest_fio" 2>/dev/null
}

write_reports() {
  step "生成报告"
  mkdir -p "$OUT_DIR" 2>/dev/null || {
    log_err "无法创建输出目录: $OUT_DIR"; OUT_DIR="$(mktemp -d)"; log_warn "改用: $OUT_DIR"; }

  local stamp base
  stamp="$(date '+%Y%m%d-%H%M%S')"
  base="$OUT_DIR/report-$stamp"

  gen_markdown > "${base}.md"       2>/dev/null && log_ok "Markdown : ${base}.md"
  gen_bbcode   > "${base}.bbcode"   2>/dev/null && log_ok "BBCode   : ${base}.bbcode"
  gen_html     > "${base}.html"     2>/dev/null && log_ok "HTML     : ${base}.html"
  gen_json     > "${base}.json"     2>/dev/null && log_ok "JSON     : ${base}.json"
  gen_txt      > "${base}.txt"      2>/dev/null && log_ok "纯文本   : ${base}.txt"

  # 同时维护一份 latest.* 方便脚本化取用
  local ext
  for ext in md bbcode html json txt; do
    cp -f "${base}.${ext}" "$OUT_DIR/latest.${ext}" 2>/dev/null
  done

  kv_set meta.report_base "$base"
  REPORT_BASE="$base"
}

print_summary() {
  [ "$QUIET" = "1" ] && { printf '%s\n' "$REPORT_BASE"; return 0; }
  printf '\n%s%s══════════════ 测试完成 ══════════════%s\n' "$C_B" "$C_G" "$C_RST"
  printf '  机器      : %s\n' "$(kv_or meta.node_name "$(kv_get sys.cpu.model)")"
  printf '  出口      : %s | %s\n' "$(kv_get net.location)" "$(kv_or net.as 'N/A')"
  printf '  综合评分  : %s%s / 100 — %s%s\n' "$C_B" "$(kv_or score.total 'N/A')" "$(kv_or score.grade '')" "$C_RST"
  printf '  总耗时    : %s\n' "$(kv_or meta.duration 'N/A')"
  printf '\n  报告文件:\n'
  printf '    博客 Markdown : %s.md\n'     "$REPORT_BASE"
  printf '    论坛 BBCode   : %s.bbcode\n' "$REPORT_BASE"
  printf '    网页 HTML     : %s.html\n'   "$REPORT_BASE"
  printf '    数据 JSON     : %s.json\n'   "$REPORT_BASE"
  printf '    纯文本 TXT    : %s.txt\n'    "$REPORT_BASE"
  printf '\n  %s发论坛直接复制:%s cat %s.bbcode\n' "$C_C" "$C_RST" "$REPORT_BASE"
  printf '  %s发博客直接复制:%s cat %s.md\n\n'     "$C_C" "$C_RST" "$REPORT_BASE"
}

main() {
  parse_args "$@"
  banner

  if [ -z "$BASH_VERSION" ]; then
    log_err "请使用 bash 运行本脚本（当前不是 bash）"; exit 1
  fi
  case "$BASH_VERSION" in
    [123].*) log_err "需要 bash 4.0 及以上版本，当前 $BASH_VERSION"; exit 1 ;;
  esac

  trap cleanup EXIT INT TERM
  local t_start; t_start="$(date +%s)"

  setup_bin_dir
  install_deps
  collect_sysinfo
  [ -n "$NODE_NAME" ] && kv_set meta.node_name "$NODE_NAME"

  detect_ip
  test_cpu
  test_memory
  test_disk
  test_ipquality
  test_unlock
  test_ping
  test_speedtest
  test_route

  local dur=$(( $(date +%s) - t_start ))
  kv_set meta.duration "$((dur / 60)) 分 $((dur % 60)) 秒"

  calc_score
  write_reports
  print_summary
}

# ===== 入口 =====
main "$@"
