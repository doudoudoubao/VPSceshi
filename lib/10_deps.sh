#!/usr/bin/env bash
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
