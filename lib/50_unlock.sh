#!/usr/bin/env bash
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
