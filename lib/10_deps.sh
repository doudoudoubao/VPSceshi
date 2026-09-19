#!/usr/bin/env bash
# ============================================================
# 10_deps.sh — 依赖检测与自动安装
# ============================================================

PKG_MGR=""
PKG_INSTALL=""
PKG_UPDATED=0
SKIP_DEPS=0          # --no-deps：完全不装依赖
DEP_TIMEOUT=120      # 单个包安装的上限秒数
DEP_BUDGET=300       # 整个依赖阶段的总预算秒数
DEP_DEADLINE=0       # 由 install_deps 设置的截止时间戳

detect_pkg_mgr() {
  if have apt-get; then
    PKG_MGR=apt
    # 关键三件事，少一个都可能让脚本卡死：
    #   DEBIAN_FRONTEND=noninteractive  不弹 debconf 配置界面
    #   DPkg::Lock::Timeout=30          拿不到 dpkg 锁就放弃，别无限等
    #     （Debian/Ubuntu 新机开机后 unattended-upgrades 会占着锁）
    #   --force-confold                 配置文件冲突时保留旧的，不交互询问
    export DEBIAN_FRONTEND=noninteractive
    PKG_INSTALL="apt-get install -y -qq -o DPkg::Lock::Timeout=30 -o Dpkg::Options::=--force-confold"
  elif have dnf;     then PKG_MGR=dnf;    PKG_INSTALL="dnf install -y -q"
  elif have yum;     then PKG_MGR=yum;    PKG_INSTALL="yum install -y -q"
  elif have apk;     then PKG_MGR=apk;    PKG_INSTALL="apk add --no-cache"
  elif have pacman;  then PKG_MGR=pacman; PKG_INSTALL="pacman -S --noconfirm --needed"
  elif have zypper;  then PKG_MGR=zypper; PKG_INSTALL="zypper --non-interactive install"
  elif have opkg;    then PKG_MGR=opkg;   PKG_INSTALL="opkg install"
  else PKG_MGR=""; fi
}

# dpkg 锁被别人占着的话，apt 会一直干等。新装的 Debian/Ubuntu 开机后
# unattended-upgrades 常占着锁好几分钟，那段时间脚本看起来就是死机。
# 这里先探一下，等不到就直接放弃安装，让后面的测试走降级路径。
_pkg_busy() {
  pgrep -x apt        >/dev/null 2>&1 && return 0
  pgrep -x apt-get    >/dev/null 2>&1 && return 0
  pgrep -x dpkg       >/dev/null 2>&1 && return 0
  pgrep -f unattended-upgr >/dev/null 2>&1 && return 0
  # 有 fuser 就再确认一次锁文件
  if have fuser; then
    run_to 5 fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && return 0
  fi
  return 1
}

_wait_pkg_lock() {
  [ "$PKG_MGR" = "apt" ] || return 0
  _pkg_busy || return 0
  log_warn "系统正在执行 apt / unattended-upgrades，等待其完成（最多 60 秒）..."
  local waited=0
  while [ "$waited" -lt 60 ]; do
    sleep 5
    waited=$((waited + 5))
    if ! _pkg_busy; then
      log_ok "包管理器已空闲（等待 ${waited} 秒）"
      return 0
    fi
  done
  log_warn "包管理器仍被占用，跳过自动安装依赖；缺失的工具会走降级方案"
  log_warn "想自己处理：Ctrl+C 后执行 systemctl stop unattended-upgrades，再重跑"
  return 1
}

pkg_update_once() {
  [ "$PKG_UPDATED" = "1" ] && return 0
  PKG_UPDATED=1
  log_info "更新软件包索引（最多 90 秒）..."
  case "$PKG_MGR" in
    apt)    run_to 90 apt-get update -qq -o DPkg::Lock::Timeout=30 >/dev/null 2>&1 ;;
    apk)    run_to 90 apk update >/dev/null 2>&1 ;;
    pacman) run_to 90 pacman -Sy --noconfirm >/dev/null 2>&1 ;;
  esac
  return 0
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
  [ "$SKIP_DEPS" = "1" ] && return 1
  [ -z "$PKG_MGR" ] && return 1
  [ "$(id -u)" != "0" ] && return 1
  [ -z "$pkg" ] && pkg="$(pkg_name_for "$cmd")"

  # 整个依赖阶段有总预算，网络烂的机器上不能把时间全耗在装包上
  if [ "$DEP_DEADLINE" -gt 0 ] && [ "$(date +%s)" -ge "$DEP_DEADLINE" ]; then
    [ "$SKIP_DEPS" != "1" ] && {
      SKIP_DEPS=1
      log_warn "依赖安装已超过 ${DEP_BUDGET} 秒预算，剩余的包不再尝试（缺的走降级）"
    }
    return 1
  fi

  pkg_update_once
  inline "安装 $pkg ..."
  # shellcheck disable=SC2086
  run_to "$DEP_TIMEOUT" $PKG_INSTALL "$pkg" >/dev/null 2>&1
  if have "$cmd"; then inline_done "✅"; return 0; fi
  inline_done "失败（跳过）"
  return 1
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

  if [ "$SKIP_DEPS" = "1" ]; then
    log_info "已指定 --no-deps，跳过依赖安装，只用系统现有工具"
  elif [ -n "$PKG_MGR" ] && [ "$(id -u)" = "0" ]; then
    # 拿不到包管理器就别装了，硬等只会让脚本看起来死掉
    _wait_pkg_lock || SKIP_DEPS=1
    DEP_DEADLINE=$(( $(date +%s) + DEP_BUDGET ))
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
