#!/usr/bin/env bash
# ============================================================
# 50_unlock.sh — 流媒体 / AI 服务解锁检测（IPv4 与 IPv6 分别测）
# ============================================================

UA_UNLOCK="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

# 当前检测使用的协议栈：4 或 6
UL_STACK=4
# 首轮用短超时抢速度，对「待确认」的再用长超时重试一次。
# 只重试没结论的，代价可控，又不会因为慢站点误判成待确认。
UL_CONNECT=4
UL_MAXTIME=7
ucurl() {
  curl -sS -"$UL_STACK" --connect-timeout "$UL_CONNECT" --max-time "$UL_MAXTIME" \
    -A "$UA_UNLOCK" "$@" 2>/dev/null
}
ucode() { # 只取 HTTP 状态码
  curl -sS -"$UL_STACK" -o /dev/null -w '%{http_code}' \
    --connect-timeout "$UL_CONNECT" --max-time "$UL_MAXTIME" -A "$UA_UNLOCK" "$@" 2>/dev/null
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

# 维基百科可编辑性：IP 段被全域封禁时编辑页会给出封禁提示
u_wikipedia_edit() {
  local body
  body="$(ucurl "https://en.wikipedia.org/w/index.php?title=Special:MyPage&action=edit")"
  [ -z "$body" ] && { printf '%s' "$NA"; return; }
  case "$body" in
    *"currently unable to edit"*|*"Your IP address is in a range that has been blocked"*|\
    *"blockedtext"*)
        # *blockedtext* 已经覆盖 autoblockedtext，不用单列
        printf '❌ 不可编辑（IP 段被封）' ;;
    *"wpTextbox1"*|*"editform"*)
        printf '✅ 可编辑' ;;
    *)  printf '%s' "$NA" ;;
  esac
}

# Netflix 优选 CDN：fast.com 的公开测速接口会返回实际分配的 CDN 主机名
u_netflix_cdn() {
  local j host
  j="$(ucurl "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=1")"
  [ -z "$j" ] && { printf '未知'; return; }
  host="$(jget "$j" '.targets[0].location.city')"
  local url; url="$(jget "$j" '.targets[0].url')"
  local node; node="$(printf '%s' "$url" | grep -oE 'ipv[46]-c[0-9]+-[a-z]{3}[0-9]+' | head -1)"
  if [ -n "$host" ] && [ -n "$node" ]; then printf '%s (%s)' "$node" "$host"
  elif [ -n "$node" ]; then printf '%s' "$node"
  elif [ -n "$host" ]; then printf '%s' "$host"
  else printf '未知'; fi
}

u_viu_com() {
  local j cc
  j="$(ucurl "https://www.viu.com/ott/web/api/container/load?platform_flag_label=web&area_id=5&language_flag_id=1&os_flag_id=1&containerId=playlist-24856884")"
  if [ -n "$j" ]; then
    case "$j" in *'"status":"success"'*|*'"data"'*) printf '%s' "$OK"; return ;; esac
  fi
  cc="$(ucode "https://www.viu.com/")"
  case "$cc" in 200) printf '%s' "$NA" ;; *) printf '%s' "$NO" ;; esac
}

u_viu_tv() {
  local body
  body="$(ucurl "https://api.viu.now.com/p8/3/getLiveURL" -X POST \
    -H 'Content-Type: application/json' \
    -d '{"callerReferenceNo":"20210208","channelno":"001","mode":"prod","deviceId":"0","deviceType":"ANDROID_WEB"}')"
  case "$body" in
    *'"responseCode":"SUCCESS"'*) printf '%s（香港）' "$OK" ;;
    *GEO_CHECK_FAIL*|*NOT_IN_COVERAGE*) printf '%s' "$NO" ;;
    "") printf '%s' "$NA" ;;
    *)  printf '%s' "$NA" ;;
  esac
}

u_mytvsuper() {
  local j region
  j="$(ucurl "https://www.mytvsuper.com/api/auth/getSession/self/?platform=web")"
  region="$(jget "$j" '.region')"
  [ -z "$region" ] && region="$(printf '%s' "$j" | grep -oE '"region":"[A-Za-z]+"' | head -1 | cut -d'"' -f4)"
  case "$region" in
    HK|hk) printf '%s（香港）' "$OK" ;;
    "")    printf '%s' "$NO" ;;
    *)     printf '⚠️ 非港区（%s）' "$region" ;;
  esac
}

u_nowe() {
  local body
  body="$(ucurl -X POST -H 'Content-Type: application/json' \
    -d '{"contentId":"202105121001","contentType":"Vod","pin":"","deviceName":"Browser","deviceId":"","deviceType":"WEB","secureCookie":null,"callerReferenceNo":"","profileId":null}' \
    "https://webtvapi.nowe.com/16/1/getVodURL")"
  case "$body" in
    *'"responseCode":"SUCCESS"'*)       printf '%s（香港）' "$OK" ;;
    *GEO_CHECK_FAIL*|*'"responseCode"'*) printf '%s' "$NO" ;;
    *) printf '%s' "$NA" ;;
  esac
}

u_sonyliv() {
  local j cc
  j="$(ucurl "https://apiv2.sonyliv.com/AGL/1.4/A/ENG/WEB/IN/CONTENT/DETAIL/BUNDLE/1700000001")"
  cc="$(jget "$j" '.resultObj.location.country')"
  case "$j" in
    *"geo"*"block"*|*GEO_LOCATION_BLOCKED*) printf '%s' "$NO"; return ;;
  esac
  if [ -n "$cc" ]; then printf '%s（区域: %s）' "$OK" "$cc"
  else
    local c; c="$(ucode "https://www.sonyliv.com/")"
    case "$c" in 200) printf '%s' "$NA" ;; *) printf '%s' "$NO" ;; esac
  fi
}

u_iqiyi() {
  local hdr region
  hdr="$(ucurl -D - -o /dev/null "https://www.iq.com/")"
  region="$(printf '%s' "$hdr" | grep -i '^set-cookie:' | grep -oE 'mod=[a-z_]+' | head -1 | cut -d= -f2)"
  case "$region" in
    "")            printf '%s' "$NO" ;;
    intl|intl_*)   printf '%s（国际版: %s）' "$OK" "$region" ;;
    *)             printf '%s（%s）' "$OK" "$region" ;;
  esac
}

u_gundam_gge() {
  # SD Gundam G Generation Eternal：官方站点做了地区限制
  local c; c="$(ucode "https://www.gundam-gge.jp/")"
  case "$c" in
    200)     printf '%s' "$OK" ;;
    403|451) printf '%s' "$NO" ;;
    *)       printf '%s' "$NA" ;;
  esac
}

u_google_play() {
  local body cc
  body="$(ucurl "https://play.google.com/store/apps")"
  cc="$(printf '%s' "$body" | grep -oE '"countryCode":"[A-Z]{2}"' | head -1 | cut -d'"' -f4)"
  [ -z "$cc" ] && cc="$(printf '%s' "$body" | grep -oE 'gl=[A-Z]{2}' | head -1 | cut -d= -f2)"
  if [ -n "$cc" ]; then printf '✅ %s' "$cc"; else printf '%s' "$NA"; fi
}

u_apple_region() {
  # Apple 的地理定位端点，直接返回两位国家码
  local cc; cc="$(ucurl "https://gspe1-ssl.ls.apple.com/pep/gcc")"
  cc="$(trim "$cc")"
  case "$cc" in
    [A-Z][A-Z]) printf '✅ %s' "$cc" ;;
    *)          printf '%s' "$NA" ;;
  esac
}

u_bing_region() {
  local body cc
  body="$(ucurl -D - "https://www.bing.com/")"
  cc="$(printf '%s' "$body" | grep -oE 'Region:"?[A-Z]{2}' | head -1 | grep -oE '[A-Z]{2}$')"
  [ -z "$cc" ] && cc="$(printf '%s' "$body" | grep -oE '"countryCode":"[A-Z]{2}"' | head -1 | cut -d'"' -f4)"
  if [ -n "$cc" ]; then printf '✅ %s' "$cc"; else printf '%s' "$NA"; fi
}

u_onetrust_region() {
  local j cc st
  j="$(ucurl "https://geolocation.onetrust.com/cookieconsentpub/v1/geo/location")"
  # 返回体可能带 JSONP 包裹，先剥掉
  j="$(printf '%s' "$j" | sed 's/^[^{]*//; s/[^}]*$//')"
  cc="$(jget "$j" '.country')"
  st="$(jget "$j" '.state')"
  if [ -n "$cc" ]; then printf '✅ %s%s' "$cc" "${st:+ / $st}"; else printf '%s' "$NA"; fi
}

u_reddit() {
  local c; c="$(ucode "https://www.reddit.com/")"
  case "$c" in
    200|301|302) printf '%s' "$OK" ;;
    403|451)     printf '%s' "$NO" ;;
    *)           printf '%s' "$NA" ;;
  esac
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
    # —— 流媒体 / 视频 ——
    "Netflix|u_netflix"
    "Netflix 优选 CDN|u_netflix_cdn"
    "Disney+|u_disney"
    "YouTube Premium|u_youtube_premium"
    "YouTube CDN 节点|u_youtube_cdn"
    "Amazon Prime Video|u_primevideo"
    "Max (HBO Max)|u_hbomax"
    "Paramount+|u_paramount"
    "DAZN|u_dazn"
    "Viu.com|u_viu_com"
    "Viu.TV|u_viu_tv"
    "MyTVSuper|u_mytvsuper"
    "Now E|u_nowe"
    "TVB Anywhere+|u_tvbanywhere"
    "巴哈姆特動畫瘋|u_bahamut"
    "Bilibili 港澳台|u_bilibili_hkmotw"
    "Bilibili 台湾限定|u_bilibili_tw"
    "AbemaTV|u_abema"
    "DMM|u_dmm"
    "Hulu 日本|u_hulujp"
    "SonyLiv|u_sonyliv"
    "iQiyi 海外版|u_iqiyi"
    "SD Gundam G Generation Eternal|u_gundam_gge"
    "TikTok|u_tiktok"
    # —— AI / 账号地区 / 其他 ——
    "ChatGPT|u_chatgpt"
    "Google Gemini|u_gemini"
    "Claude AI|u_claude"
    "Google 搜索无验证码|u_google_search"
    "Google Play 商店地区|u_google_play"
    "Apple 地区|u_apple_region"
    "Bing 地区|u_bing_region"
    "OneTrust 地区|u_onetrust_region"
    "Spotify 注册|u_spotify"
    "Steam 货币区|u_steam"
    "Reddit|u_reddit"
    "维基百科访问|u_wikipedia"
    "维基百科可编辑性|u_wikipedia_edit"
  )
  # 先跑一轮（短超时），结果存起来先不落表
  local -a names=() fns=() results=()
  local it name fn r i
  for it in "${items[@]}"; do
    name="${it%%|*}"; fn="${it##*|}"
    inline "$name"
    r="$($fn 2>/dev/null)"
    [ -z "$r" ] && r="$NA"
    inline_done "$r"
    names+=("$name"); fns+=("$fn"); results+=("$r")
  done

  # 第二轮：只重试「待确认」的，用长一倍的超时。
  # 慢站点在首轮被超时误判成待确认，这轮能把它们捞回来。
  local retry_n=0
  for i in "${!results[@]}"; do
    case "${results[$i]}" in ⚠️*) retry_n=$((retry_n + 1)) ;; esac
  done
  if [ "$retry_n" -gt 0 ]; then
    log_info "${retry_n} 项待确认，用更长超时重试一次（最多 90 秒）..."
    local old_c="$UL_CONNECT" old_t="$UL_MAXTIME"
    UL_CONNECT=8; UL_MAXTIME=18
    # 整轮重试给 90 秒预算：网络整体不通时 37 项全超时会拖十几分钟
    local rt_deadline=$(( $(date +%s) + 90 )) rt_done=0
    for i in "${!results[@]}"; do
      case "${results[$i]}" in ⚠️*) ;; *) continue ;; esac
      if [ "$(date +%s)" -ge "$rt_deadline" ]; then
        log_warn "重试已用满 90 秒，剩余 $((retry_n - rt_done)) 项保持待确认"
        break
      fi
      inline "重试 ${names[$i]}"
      r="$(${fns[$i]} 2>/dev/null)"
      [ -z "$r" ] && r="$NA"
      inline_done "$r"
      results[$i]="$r"
      rt_done=$((rt_done + 1))
    done
    UL_CONNECT="$old_c"; UL_MAXTIME="$old_t"
  fi

  # 落表与归类
  local total=0 pass=0 fail=0 err=0 misc=0
  for i in "${!results[@]}"; do
    name="${names[$i]}"; r="${results[$i]}"
    res_add "$table" "$name" "$r"
    total=$((total + 1))
    # 按结果归类：可用 / 不可用 / 待确认 / 难归类（返回的是地区码等信息）
    case "$r" in
      ✅*)  pass=$((pass + 1)); res_add "${table}_ok"   "$name" "$r" ;;
      ❌*)  fail=$((fail + 1)); res_add "${table}_no"   "$name" "$r" ;;
      ⚠️*)  err=$((err + 1));   res_add "${table}_err"  "$name" "$r" ;;
      *)    misc=$((misc + 1)); res_add "${table}_misc" "$name" "$r" ;;
    esac
  done
  UNLOCK_RATE="${pass}/${total}"
  kv_set "${table}.ok"   "$pass"
  kv_set "${table}.no"   "$fail"
  kv_set "${table}.err"  "$err"
  kv_set "${table}.misc" "$misc"
}

test_unlock() {
  module_enabled unlock || { log_info "跳过流媒体解锁检测"
    skip_note "$SKIP_REASON_OPT" unlock4 unlock6 unlock_net; return 0; }

  # 网络识别：解锁结果跟出口网络强相关，先把网络身份记下来
  row_add unlock_net "出口网络"   "$(kv_or net.as '未知')"
  row_add unlock_net "归属组织"   "$(kv_or net.org '未知')"
  row_add unlock_net "IPv4 出口"  "$(kv_or net.ip4 '无')"
  row_add unlock_net "IPv6 出口"  "$(kv_or net.ip6 '无')"
  [ -n "$(kv_get nq.prefix)" ] && row_add unlock_net "IPv4 前缀" "$(kv_get nq.prefix)"

  if [ "$IPV4_OK" = "1" ]; then
    step "流媒体 / AI 解锁检测（IPv4）"
    UL_STACK=4
    _run_unlock_suite unlock4
    kv_set unlock.v4.summary "$UNLOCK_RATE"
    log_ok "IPv4 解锁通过率: $UNLOCK_RATE（可用 $(kv_get unlock4.ok) / 不可用 $(kv_get unlock4.no) / 待确认 $(kv_get unlock4.err) / 难归类 $(kv_get unlock4.misc)）"
  else
    skip_note "本机无 IPv4 公网出口，未做 IPv4 解锁检测" unlock4
    log_warn "无 IPv4 出口，跳过 IPv4 解锁检测"
  fi

  if [ "$IPV6_OK" = "1" ]; then
    step "流媒体 / AI 解锁检测（IPv6）"
    UL_STACK=6
    _run_unlock_suite unlock6
    kv_set unlock.v6.summary "$UNLOCK_RATE"
    log_ok "IPv6 解锁通过率: $UNLOCK_RATE"
  else
    kv_set unlock.v6.summary "无 IPv6 出口"
    skip_note "本机无 IPv6 公网出口，未做 IPv6 解锁检测" unlock6
  fi
  UL_STACK=4
}
