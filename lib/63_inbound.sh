#!/usr/bin/env bash
# ============================================================
# 63_inbound.sh — 第 3/4/5 章：去程延迟、去程路由、去程 MTR
#
# 「去程」是国内节点访问 VPS 的方向，只能由国内探针发起，
# VPS 自己测不到。所以这三节走这个流程：
#   1) 有 --import-ping / --import-route / --import-mtr 就解析导入
#   2) 没有就把章节保留下来，写明「本次未取得有效数据」
# 导入格式见 docs/import-format.md，itdog / ipip 的结果整理成
# CSV 后喂进来即可。
# ============================================================

IMPORT_PING=""   # 去程延迟 CSV
IMPORT_ROUTE=""  # 去程路由原始文本
IMPORT_MTR=""    # 去程 MTR 原始文本

# ---------- 大区归类 ----------
_region_of() {
  local prov="$1"
  case "$prov" in
    *上海*|*江苏*|*浙江*|*安徽*|*福建*|*江西*|*山东*|*台湾*) printf '华东' ;;
    *北京*|*天津*|*河北*|*山西*|*内蒙古*)                      printf '华北' ;;
    *广东*|*广西*|*海南*|*香港*|*澳门*)                        printf '华南' ;;
    *河南*|*湖北*|*湖南*)                                      printf '华中' ;;
    *陕西*|*甘肃*|*青海*|*宁夏*|*新疆*)                        printf '西北' ;;
    *重庆*|*四川*|*贵州*|*云南*|*西藏*)                        printf '西南' ;;
    *辽宁*|*吉林*|*黑龙江*)                                    printf '东北' ;;
    *)                                                          printf '其他' ;;
  esac
}

_isp_of() {
  case "$1" in
    *电信*) printf '中国电信' ;;
    *联通*) printf '中国联通' ;;
    *移动*) printf '中国移动' ;;
    *教育*) printf '教育网' ;;
    *)      printf '%s' "$1" ;;
  esac
}

# ---------- 去程延迟 ----------
# CSV: 节点名,运营商,省份/地区,延迟ms
parse_inbound_ping() {
  local f="$1"
  [ -r "$f" ] || { log_err "导入文件不可读: $f"; return 1; }

  # ISP 与大区的累计：用普通变量模拟二维累加
  declare -A cnt sum min max fast slow
  local line node isp prov lat region key total=0 gsum=0

  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    IFS=',' read -r node isp prov lat <<< "$line"
    node="$(trim "$node")"; isp="$(_isp_of "$(trim "$isp")")"
    prov="$(trim "$prov")"; lat="$(trim "$lat")"
    # 延迟必须是数字，否则当成无效样本跳过
    case "$lat" in ''|*[!0-9.]*) continue ;; esac
    region="$(_region_of "$prov")"

    row_add inbound_raw "$node" "$isp" "$prov" "$region" "${lat} ms"
    total=$((total + 1)); gsum="$(calc "$gsum+$lat" 3)"

    for key in "isp:$isp" "region:$region"; do
      cnt["$key"]=$(( ${cnt[$key]:-0} + 1 ))
      sum["$key"]="$(calc "${sum[$key]:-0}+$lat" 3)"
      if [ -z "${min[$key]}" ] || awk -v a="$lat" -v b="${min[$key]}" 'BEGIN{exit !(a<b)}'; then
        min["$key"]="$lat"; fast["$key"]="$node"
      fi
      if [ -z "${max[$key]}" ] || awk -v a="$lat" -v b="${max[$key]}" 'BEGIN{exit !(a>b)}'; then
        max["$key"]="$lat"; slow["$key"]="$node"
      fi
    done
  done < "$f"

  if [ "$total" = "0" ]; then
    na_set inbound_isp "导入文件中没有有效样本"
    return 1
  fi

  # 分运营商汇总
  local i
  for i in 中国电信 中国联通 中国移动 教育网; do
    key="isp:$i"
    [ -z "${cnt[$key]}" ] && continue
    row_add inbound_isp "$i" "${cnt[$key]}" \
      "$(calc "${sum[$key]}/${cnt[$key]}" 1) ms" \
      "${min[$key]} ms（${fast[$key]}）" \
      "${max[$key]} ms（${slow[$key]}）"
  done

  # 分大区汇总
  for i in 华东 华北 华南 华中 西北 西南 东北 其他; do
    key="region:$i"
    [ -z "${cnt[$key]}" ] && continue
    row_add inbound_region "$i" "${cnt[$key]}" \
      "$(calc "${sum[$key]}/${cnt[$key]}" 1) ms" \
      "${min[$key]} ms" "${max[$key]} ms"
  done

  kv_set inbound.samples "$total"
  kv_set inbound.avg "$(calc "$gsum/$total" 1)"
  log_ok "去程延迟：${total} 个样本，整体均值 $(kv_get inbound.avg) ms"
  return 0
}

# ---------- 去程路由（IPIP 探针原始文本）----------
# 文本里用 "=== 节点名 ===" 分隔不同探针的 traceroute 输出
parse_inbound_route() {
  local f="$1"
  [ -r "$f" ] || { log_err "导入文件不可读: $f"; return 1; }
  local line cur="" buf="" n=0
  while IFS= read -r line; do
    case "$line" in
      '==='*'===')
        if [ -n "$cur" ] && [ -n "$buf" ]; then
          row_add inbound_route "$cur" "$(_guess_line "$buf")"
          raw_add "去程路由 · $cur" "$buf"
          n=$((n + 1))
        fi
        cur="$(trim "$(printf '%s' "$line" | sed 's/^===*//; s/=*$//')")"
        buf=""
        ;;
      *) [ -n "$cur" ] && buf="${buf}${line}"$'\n' ;;
    esac
  done < "$f"
  if [ -n "$cur" ] && [ -n "$buf" ]; then
    row_add inbound_route "$cur" "$(_guess_line "$buf")"
    raw_add "去程路由 · $cur" "$buf"
    n=$((n + 1))
  fi
  if [ "$n" = "0" ]; then
    na_set inbound_route "导入文件中未解析出任何探针段落"
    return 1
  fi
  log_ok "去程路由：解析出 ${n} 个探针节点"
  _summarize_route inbound_route inbound.route_verdict
  return 0
}

# 汇总某张路由表里出现的线路类型，给一句结论。
# 只统计真正识别出骨干的条目——「追踪受阻」「未识别到已知骨干」这些是
# 诊断信息，混进结论里会让人以为那就是线路名。
_summarize_route() {
  local table="$1" outkey="$2"
  local line seen="" v total=0 named=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    row_split "$line"
    v="${ROW_F[${#ROW_F[@]}-1]}"
    total=$((total + 1))
    # 只有带 AS 号的才算识别出了骨干
    case "$v" in
      *AS[0-9]*) ;;
      *) continue ;;
    esac
    named=$((named + 1))
    case "$seen" in
      *"$v"*) ;;
      *) seen="${seen:+$seen；}$v" ;;
    esac
  done <<< "$(rows_get "$table")"

  if [ -n "$seen" ]; then
    # 有一部分没识别出来的话说明白，别让读者以为全测出来了
    if [ "$named" -lt "$total" ]; then
      seen="$seen（${total} 个目标中 ${named} 个识别出骨干）"
    fi
    kv_set "$outkey" "$seen"
  elif [ "$total" -gt 0 ]; then
    kv_set "$outkey" "${total} 个目标均未识别出已知骨干（可能是 ICMP 受限或线路不在识别表内，详见原始输出）"
  fi
}

test_inbound() {
  module_enabled inbound || { log_info "跳过去程测试"
    skip_note "$SKIP_REASON_OPT" inbound_isp inbound_region inbound_route inbound_mtr; return 0; }
  step "去程延迟 / 去程路由 / 去程 MTR（国内 → VPS）"

  # --- 去程延迟 ---
  if [ -n "$IMPORT_PING" ]; then
    log_info "解析去程延迟导入文件: $IMPORT_PING"
    parse_inbound_ping "$IMPORT_PING" || log_warn "去程延迟导入失败"
  else
    na_set inbound_isp "本次未取得有效去程延迟数据（去程需由国内探针发起，VPS 侧无法自测；可用 --import-ping 导入 itdog / ipip 结果）"
    na_set inbound_region "$(na_get inbound_isp)"
    log_warn "未提供去程延迟数据，该章节标记为未取得"
  fi

  # --- 去程路由 ---
  if [ -n "$IMPORT_ROUTE" ]; then
    log_info "解析去程路由导入文件: $IMPORT_ROUTE"
    parse_inbound_route "$IMPORT_ROUTE" || log_warn "去程路由导入失败"
  else
    na_set inbound_route "本次未取得有效去程路由数据（可用 --import-route 导入 IPIP 探针 traceroute 输出）"
    log_warn "未提供去程路由数据，该章节标记为未取得"
  fi

  # --- 去程 MTR ---
  if [ -n "$IMPORT_MTR" ] && [ -r "$IMPORT_MTR" ]; then
    raw_add "去程 MTR（导入）" "$(cat "$IMPORT_MTR")"
    kv_set inbound.mtr "已导入"
    log_ok "去程 MTR 已导入"
  else
    na_set inbound_mtr "本次未取得有效去程 MTR 数据，丢包与抖动未评估"
    log_warn "未提供去程 MTR 数据，丢包/抖动未评估"
  fi
}
