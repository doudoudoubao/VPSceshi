#!/usr/bin/env bash
# ============================================================
# 00_core.sh — 核心工具：日志、结果存储、通用函数
# ============================================================

VPSTEST_VERSION="1.0.0"
VPSTEST_NAME="VPSceshi"
VPSTEST_REPO="https://github.com/doudoudoubao/VPSceshi"

# ---------- 运行时参数（可被命令行覆盖） ----------
OUT_DIR="${OUT_DIR:-$PWD/vpstest-result}"
CURL_TIMEOUT="${CURL_TIMEOUT:-8}"
CURL_CONNECT="${CURL_CONNECT:-4}"
USE_COLOR=1
QUIET=0
NODE_NAME=""          # 机器名，用于报告标题
ONLY_MODULES=""       # 逗号分隔白名单
SKIP_MODULES=""       # 逗号分隔黑名单
ENABLE_GEEKBENCH=0
ENABLE_IPERF=0
SPEEDTEST_FULL=0   # 测速跑满 10 个节点
ROUTE_FULL=0       # 回程路由跑满 10 个目标
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
RUN_T0=0     # 由 main 设置的开跑时间戳
step() {
  STEP_NO=$((STEP_NO + 1))
  [ "$QUIET" = "1" ] && return 0
  # 带上累计耗时，卡住时一眼看出卡了多久
  local el="" elw=0
  if [ "$RUN_T0" -gt 0 ]; then
    local s=$(( $(date +%s) - RUN_T0 ))
    el="$(printf '[+%d:%02d]' $((s/60)) $((s%60)))"
    elw=${#el}
  fi
  # 不用 ━ 铺满行：这类制表符属于「东亚模糊宽度」，
  # 中文环境的终端可能按 2 列渲染，铺满就必然折行。
  # 短前缀 + 不留尾巴，任何宽度都不会乱。
  printf '\n%s%s▌[%02d] %s%s %s%s%s\n' \
    "$C_B" "$C_BL" "$STEP_NO" "$*" "$C_RST" "$C_DIM" "$el" "$C_RST"
}

# ---------- 结果存储 ----------
declare -A KV      # 单值：KV[section.key]=value
declare -A ROWS    # 表格：ROWS[table]=多行，字段以 | 分隔

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

# 「本次未取得有效数据」标记。
# 测评页面里很多章节会因为探针不可用而拿不到数据，报告要照样把
# 章节列出来并写清原因，而不是整节消失。
# na_set <章节键> <原因>
na_set() { kv_set "na.$1" "$2"; }
na_get() { kv_get "na.$1"; }
na_has() { [ -n "$(kv_get "na.$1")" ]; }
# 章节是否需要渲染：有数据，或有「未取得」说明
sect_show() { rows_have "$1" || na_has "$1"; }

# ---------- 通用工具 ----------
have() { command -v "$1" >/dev/null 2>&1; }

# 带超时执行，失败不影响主流程（丢弃 stderr）
#
# stdin 一律接 /dev/null：脚本常以 bash <(curl ...) 方式运行，
# 此时 stdin 还连着终端。子进程（尤其 apt 的维护脚本）一旦去读
# stdin 就会永久阻塞，而 timeout 只杀得掉直接子进程，孙子进程
# 仍占着终端——表现就是整个脚本卡死不动。接 /dev/null 后任何
# 读取立刻拿到 EOF，不会卡住。
run_to() {
  local sec="$1"; shift
  if have timeout; then
    timeout --signal=KILL "$sec" "$@" </dev/null 2>/dev/null
  else
    "$@" </dev/null 2>/dev/null
  fi
}

# 同上，但把 stderr 合并进 stdout。
# dd 之类把统计信息写在 stderr 的命令必须用这个，否则拿不到结果。
run_to2() {
  local sec="$1"; shift
  if have timeout; then
    timeout --signal=KILL "$sec" "$@" </dev/null 2>&1
  else
    "$@" </dev/null 2>&1
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
  # 除零会得到 inf/nan，这种值绝不能流进报告
  awk -v v="$v" -v s="$scale" 'BEGIN{
    if (v + 0 != v || v == "inf" || v == "-inf" || v == "nan") { printf "0"; exit }
    printf "%.*f", s, v }' 2>/dev/null
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

# 「没测」和「测了但没结果」是两回事，报告里必须分清楚：
# 前者写「本次未启用」，后者才写「未取得有效数据」。
# 混着说等于在公开的测评里谎报，所以模块被跳过时统一走这里。
# skip_note <原因> <章节键...>
skip_note() {
  local reason="$1"; shift
  local k
  for k in "$@"; do na_set "$k" "$reason"; done
}
# 模块被 --only / --skip 排除
SKIP_REASON_OPT="本次未运行该测试项（被 --only / --skip 排除）"

# 结果标记：解锁类统一符号
mark_yes()  { printf '是'; }
mark_no()   { printf '否'; }

# 计时
timer_start() { _T0=$(date +%s); }
timer_end()   { echo $(( $(date +%s) - ${_T0:-0} )); }

# ---------- 终端宽度自适应排版 ----------
#
# printf 的 %-32s 按字节补位，而中文一个字占 3 字节却只显示 2 列，
# 补出来的宽度全是错的；再碰上手机 SSH 那种 40 列的窄终端，
# 每行都在乱折。所以这里按「显示宽度」自己算补位。

TERM_W=80      # 终端列数
LABEL_W=28     # 进度行标签列宽

_detect_term() {
  local w=""
  [ -n "$COLUMNS" ] && w="$COLUMNS"
  [ -z "$w" ] && have tput && w="$(tput cols 2>/dev/null)"
  [ -z "$w" ] && have stty && w="$(stty size 2>/dev/null | awk '{print $2}')"
  case "$w" in ''|*[!0-9]*) w=80 ;; esac
  [ "$w" -lt 32 ] && w=32
  [ "$w" -gt 140 ] && w=140
  TERM_W="$w"
  # 标签列宽随终端走：窄屏就别留那么宽的空档
  if   [ "$TERM_W" -ge 78 ]; then LABEL_W=30
  elif [ "$TERM_W" -ge 60 ]; then LABEL_W=24
  elif [ "$TERM_W" -ge 46 ]; then LABEL_W=18
  else                            LABEL_W=14
  fi
}
_detect_term

# 字符串的终端显示宽度：CJK / emoji 算 2 列，ASCII 算 1 列
_dw() {
  # 纯 ASCII 走快路径，省掉一次 awk
  case "$1" in
    *[^\ -~]*) ;;
    *) printf '%s' "${#1}"; return ;;
  esac
  LC_ALL=C awk -v s="$1" 'BEGIN{
    w=0
    for (i=1; i<=length(s); i++) {
      c = substr(s,i,1)
      if      (c <  "\200") w++      # ASCII
      else if (c <  "\300") ;        # UTF-8 连续字节，不计宽
      else if (c <  "\340") w++      # 2 字节序列 = 1 列
      else                  w += 2   # 3/4 字节（CJK / emoji）= 2 列
    }
    print w }'
}

# 把字符串按显示宽度补到 n 列；超长就截断加省略号
_pad() {
  local s="$1" n="$2" w
  w="$(_dw "$s")"
  if [ "$w" -gt "$n" ]; then
    # 超宽时按字符逐个截，直到显示宽度放得下
    local out="" c cw=0
    local i len=${#s}
    for (( i=0; i<len; i++ )); do
      c="${s:i:1}"
      local d; d="$(_dw "$c")"
      [ $((cw + d)) -gt $((n - 1)) ] && break
      out="$out$c"; cw=$((cw + d))
    done
    printf '%s…%*s' "$out" $(( n - cw - 1 )) ''
    return
  fi
  printf '%s%*s' "$s" $(( n - w )) ''
}

# 进度条式的行内提示
inline() {
  [ "$QUIET" = "1" ] && return 0
  printf '  %s%s%s ' "$C_DIM" "$(_pad "$1" "$LABEL_W")" "$C_RST"
}
inline_done() { [ "$QUIET" = "1" ] && return 0; printf '%s\n' "$1"; }
