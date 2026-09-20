#!/usr/bin/env bash
# ============================================================
# 80_upload.sh — 把 HTML 报告传到公网，拿一个可分享的链接
#
# 报告躺在服务器上要 cat 出来再复制，太麻烦。传上去之后打开网页，
# 点一下按钮就能复制各种格式，直接粘到论坛。
#
# ⚠️ 上传 = 公开发布。链接是公开可访问的（知道链接的人都能看），
#    而且第十二章的路由原始输出里通常带着本机首跳/网关的真实 IP，
#    摘要里的遮蔽对它无效。所以必须用户显式 --upload 才传。
# ============================================================

ENABLE_UPLOAD=0
UPLOAD_URL=""

# 各家图床/文件站的行为不一样，关键看会不会按 text/html 渲染：
#   catbox    按扩展名给 Content-Type，.html 能正常渲染 —— 首选
#   0x0.st    HTML 一律当 text/plain 返回，只能看源码，作兜底
_upload_catbox() {
  local f="$1" u
  u="$(run_to 120 curl -sS --connect-timeout 10 --max-time 110 \
       -F "reqtype=fileupload" -F "fileToUpload=@${f}" \
       "https://catbox.moe/user/api.php" 2>/dev/null)"
  case "$u" in
    https://*catbox*) printf '%s' "$(trim "$u")"; return 0 ;;
  esac
  return 1
}

_upload_0x0() {
  local f="$1" u
  u="$(run_to 120 curl -sS --connect-timeout 10 --max-time 110 \
       -F "file=@${f}" "https://0x0.st" 2>/dev/null)"
  case "$u" in
    https://0x0.st/*) printf '%s' "$(trim "$u")"; return 0 ;;
  esac
  return 1
}

_upload_tempsh() {
  local f="$1" u
  u="$(run_to 120 curl -sS --connect-timeout 10 --max-time 110 \
       -T "$f" "https://temp.sh/upload" 2>/dev/null)"
  case "$u" in
    https://temp.sh/*) printf '%s' "$(trim "$u")"; return 0 ;;
  esac
  return 1
}

upload_report() {
  [ "$ENABLE_UPLOAD" = "1" ] || return 0
  local f="${REPORT_BASE}.html"
  [ -r "$f" ] || { log_warn "找不到 HTML 报告，跳过上传"; return 0; }

  step "上传报告"
  log_warn "上传即公开发布：链接任何人都能打开"
  log_warn "路由原始输出里通常含本机首跳的真实 IP，摘要的遮蔽对它无效"

  local size; size="$(wc -c < "$f" 2>/dev/null)"
  log_info "文件大小 $(human_bytes "${size:-0}")，依次尝试可用的图床 ..."

  local u=""
  inline "catbox.moe"
  u="$(_upload_catbox "$f")" && inline_done "✅" || inline_done "失败"
  if [ -z "$u" ]; then
    inline "temp.sh"
    u="$(_upload_tempsh "$f")" && inline_done "✅" || inline_done "失败"
  fi
  if [ -z "$u" ]; then
    inline "0x0.st"
    u="$(_upload_0x0 "$f")" && inline_done "✅（只能看源码）" || inline_done "失败"
  fi

  if [ -n "$u" ]; then
    UPLOAD_URL="$u"
    kv_set meta.upload_url "$u"
    log_ok "报告已上传：$u"
  else
    log_warn "所有图床都传不上去，报告仍在本地：$f"
    log_warn "可以自己传：curl -F 'reqtype=fileupload' -F \"fileToUpload=@$f\" https://catbox.moe/user/api.php"
  fi
}
