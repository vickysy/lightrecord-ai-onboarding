#!/bin/bash
# 轻镜录屏 LightRecord 1.14.1 上手助手
#
# 做两件事：检查这台 Mac 能不能用轻镜；准备讲解字幕要用的本机语音模型。
# 只读系统信息，只往「~/Library/Application Support/LightRecord/Speech/」里放模型文件。
# 不改系统设置，不要管理员密码，不上传任何文件。
#
# 用法（在「终端」或 AI 工具里运行）：
#   bash lightrecord.sh check             检查系统版本、芯片、轻镜安装位置、磁盘空间、字幕模型
#   bash lightrecord.sh model             只看字幕模型是否就绪（会核对大小和 SHA-256）
#   bash lightrecord.sh download [地址]   下载字幕模型：断点续传、自动换地址、下完自动核对
#   bash lightrecord.sh status            看下载进度（下载放在后台跑时用）
#   bash lightrecord.sh verify <文件>     核对一个自己下好的 ggml-small.bin
#   bash lightrecord.sh install <文件>    核对后，把它放到轻镜找模型的位置
#   bash lightrecord.sh latest            列出最近几次「讲解布局」录制的文件夹

MODEL_SIZE=487601967
MODEL_SHA256=1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b
EN_MODEL_SIZE=487614201   # 英文版 ggml-small.en.bin 的大小，轻镜不能用
MIN_MACOS=15
MIN_APP_VERSION=1.14.1
BUNDLE_ID=com.mumaaidea.MumaShot
RECORD_RESERVE=3000000000   # 轻镜开始录制要求的可用空间

# 测试时才用：LIGHTRECORD_SPEECH_DIR / LIGHTRECORD_LAYOUT_DIR 换位置，LIGHTRECORD_TEST=1 不读轻镜的设置。
SPEECH_DIR="${LIGHTRECORD_SPEECH_DIR:-$HOME/Library/Application Support/LightRecord/Speech}"
MODEL="$SPEECH_DIR/ggml-small.bin"
# 轻镜软件自己「没下完」的文件。脚本从不和软件同时写它：
# 开始时，软件没在用它，脚本就把它接过来接着下；脚本没下完就停下时，再把已下的部分交还给它，
# 这样在软件里点「继续下载」也能接着下。
APP_PART="$SPEECH_DIR/ggml-small.bin.download"
PART="$SPEECH_DIR/ggml-small.bin.script-download"   # 脚本自己的临时文件
LOCK="$SPEECH_DIR/.lightrecord-script.lock"
# 别的软件（hyperframes）可能已经下过同一个模型。轻镜不会去这里找，但可以直接复制过去，不用再联网。
OTHER_MODEL="$HOME/.cache/hyperframes/whisper/models/ggml-small.bin"

# ===== 下载地址 =====
# 和轻镜 1.14.1 软件里的地址、顺序一致，改的时候两边一起改。
# 从上往下试，一个不行就换下一个，已下的部分留着接着用。
# 这些地址给的必须是同一个文件；下完一律核对大小和 SHA-256，所以就算某个地址出了问题，也放不进错的文件。
#
# 作者自己的下载地址（可选），必须是 https，留空就跳过。
# 也可以用 defaults write com.mumaaidea.MumaShot layoutCaptions.modelSource https://… 临时指定，软件和脚本都会先试它。
MUMA_URL=""
# 魔搭上是个人仓库，不保证一直都在，所以后面还有备用地址。
MODELSCOPE_URL="https://modelscope.cn/models/cjc1887415157/whisper.cpp/resolve/master/ggml-small.bin"
MODELSCOPE_BACKUP_URL="https://modelscope.cn/models/viggocx/whisper.cpp/resolve/master/ggml-small.bin"
# Hugging Face 固定到一个版本，不用 resolve/main，免得文件被换掉。
PINNED_COMMIT=5359861c739e955e79d9a303bcbc70fb988958b1
HF_MIRROR_URL="https://hf-mirror.com/ggerganov/whisper.cpp/resolve/$PINNED_COMMIT/ggml-small.bin"
HUGGINGFACE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/$PINNED_COMMIT/ggml-small.bin"

# -q 必须放第一个：不读用户自己的 ~/.curlrc，下载行为只由这个脚本决定。只走 https，跳转也只能跳到 https。
CURL=(/usr/bin/curl -q -sS -L --proto =https --proto-redir =https)

say()  { printf '%s\n' "$*"; }
ok()   { say "✅ $*"; }
warn() { say "⚠️  $*"; }
bad()  { say "❌ $*"; }

size_of() { stat -f %z "$1" 2>/dev/null || echo 0; }
mb()      { echo $(( ($1 + 500000) / 1000000 )); }   # 和「访达」显示的 MB 一致
gb()      { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1000000000 }'; }
sha_of()  { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }
free_bytes() { df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4 * 1024}'; }
app_pref() { [ -n "$LIGHTRECORD_TEST" ] && return; defaults read "$BUNDLE_ID" "$1" 2>/dev/null; }
RESTART_HINT="下一步：先保存手上的工作，再完全退出轻镜（在轻镜窗口按 ⌘Q，或点菜单栏轻镜图标 →「退出轻镜录屏」；只关窗口不算），然后从「应用程序」重新打开，轻镜才会认到模型。"

# 返回 0 通过，1 文件不存在，2 大小不对，3 SHA-256 不对
model_state() {
  [ -f "$1" ] || return 1
  [ "$(size_of "$1")" = "$MODEL_SIZE" ] || return 2
  [ "$(sha_of "$1")" = "$MODEL_SHA256" ] || return 3
  return 0
}

version_ge() {   # $1 >= $2 ?
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)" = "$2" ]
}

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }

find_apps() {
  {
    for dir in "/Applications" "$HOME/Applications"; do
      for name in "轻镜录屏 LightRecord.app" "屏刻 ScreenMori.app"; do
        [ -d "$dir/$name" ] && echo "$dir/$name"
      done
    done
    for dir in "/Applications" "$HOME/Applications"; do
      [ -d "$dir" ] && mdfind -onlyin "$dir" "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null
    done
    # 「下载」里只看刚解压的那一层，不翻更深的文件夹
    [ -d "$HOME/Downloads" ] && mdfind -onlyin "$HOME/Downloads" "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null \
      | awk -v p="$HOME/Downloads/" 'index($0, p) == 1 { rest = substr($0, length(p) + 1); if (gsub("/", "/", rest) <= 1) print }'
  } | grep '\.app$' | awk '!seen[$0]++'
}

# 轻镜（或别的程序）是不是正以「写入」方式开着它自己的下载文件。
# 没有 lsof 时没法判断，只要轻镜开着就当它在写。
app_writing() {
  [ -f "$APP_PART" ] || return 1
  if [ ! -x /usr/sbin/lsof ]; then pgrep -x MumaShot >/dev/null 2>&1; return; fi
  /usr/sbin/lsof -F a -- "$APP_PART" 2>/dev/null | grep -q '^a[wu]'
}

partial_bytes() {   # 两份「没下完」的文件里，较大的那份有多少
  local a p
  a=$(size_of "$APP_PART"); p=$(size_of "$PART")
  [ "$a" -gt "$p" ] && echo "$a" || echo "$p"
}

# ===== 锁：同一时间只让一个脚本写模型文件夹 =====
LOCK_OWNED=0
stop_stale_curl() {   # 上一次脚本被强行结束时，可能留下一个还在写临时文件的 curl
  local p
  for p in $(pgrep -x curl 2>/dev/null); do
    ps -p "$p" -o command= 2>/dev/null | grep -qF -- "$PART" && kill "$p" 2>/dev/null
  done
  sleep 1
}
take_lock() {
  local other waited=0
  mkdir -p "$SPEECH_DIR" 2>/dev/null || { bad "无法创建 $SPEECH_DIR。如果 AI 工具在沙箱里运行，请允许它写入这个位置。"; return 1; }
  while ! mkdir "$LOCK" 2>/dev/null; do
    other=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
      warn "脚本已经在别处运行（进程 $other）。等它结束，或者用 status 看进度，不要同时开两个。"
      return 1
    fi
    if [ -z "$other" ] && [ "$waited" -lt 5 ]; then   # 另一个脚本刚建好锁、还没写进程号，等它一下
      waited=$((waited + 1)); sleep 1; continue
    fi
    stop_stale_curl
    rm -rf "${LOCK:?}"
  done
  echo $$ > "$LOCK/pid"
  LOCK_OWNED=1
}
release_lock() {
  [ "$LOCK_OWNED" = 1 ] || return 0
  LOCK_OWNED=0
  [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ] && rm -rf "${LOCK:?}"
}

# 核对后复制到模型位置：先复制成一个唯一的临时文件，复制完再核对一次，才替换正式模型。
copy_into_place() {
  local tmp
  tmp=$(mktemp "$SPEECH_DIR/.copying.XXXXXX") || { bad "无法在 $SPEECH_DIR 里建临时文件。"; return 1; }
  if ! cp "$1" "$tmp"; then rm -f "$tmp"; bad "复制失败，请检查磁盘空间。"; return 1; fi
  if ! model_state "$tmp"; then rm -f "$tmp"; bad "复制出来的文件没有通过核对，请再试一次。"; return 1; fi
  mv -f "$tmp" "$MODEL" || { rm -f "$tmp"; bad "放不进 $MODEL，请检查磁盘空间和权限。"; return 1; }
}

# 模型放好以后，两份「没下完」的文件都用不上了（轻镜正在写的那份不碰）
drop_partials() {
  [ -f "$PART" ] && rm -f "${PART:?}"
  [ -f "$APP_PART" ] && ! app_writing && rm -f "${APP_PART:?}"
  return 0
}

cmd_check() {
  local problems=0 no_captions=0

  say "【1】系统版本"
  local ver major
  ver=$(sw_vers -productVersion)
  major=${ver%%.*}
  if [ "$major" -ge "$MIN_MACOS" ] 2>/dev/null; then
    ok "macOS $ver（轻镜需要 macOS $MIN_MACOS 或以上）"
  else
    bad "macOS $ver。轻镜需要 macOS $MIN_MACOS 或以上，这台电脑现在用不了。能升级系统的话，先在「系统设置 → 通用 → 软件更新」里升级。"
    problems=$((problems + 1))
  fi

  say ""
  say "【2】芯片"
  local brand
  brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
    ok "Apple 芯片（$brand）"
  else
    ok "Intel 芯片（$brand）。安装包同时支持 Intel，可以用；本机识别字幕会比 Apple 芯片慢一些。"
  fi

  say ""
  say "【3】轻镜录屏是否已安装"
  local apps app found_good=0 v b
  apps=$(find_apps)
  if [ -z "$apps" ]; then
    bad "在「应用程序」和「下载」里都没找到轻镜录屏。请先从官网 https://lightrecord.nativeailab.cn/ 下载，解压后把「轻镜录屏 LightRecord.app」拖进「应用程序」文件夹。"
    problems=$((problems + 1))
  else
    while IFS= read -r app; do
      [ -n "$app" ] || continue
      v=$(plist_value "$app" CFBundleShortVersionString)
      b=$(plist_value "$app" CFBundleVersion)
      say "  找到：$app"
      say "        版本 ${v:-未知}（build ${b:-未知}）"
      case "$app" in
        /Applications/*|"$HOME/Applications/"*)
          found_good=1
          if [ -n "$v" ] && version_ge "$v" "$MIN_APP_VERSION"; then
            ok "  位置在「应用程序」，版本够新"
          elif [ -n "$v" ] && version_ge "$v" "1.14.0"; then
            warn "  比 $MIN_APP_VERSION 旧一点：有讲解字幕，但讲解布局左上角还没有「返回」。官网有新版时可以下载替换。"
          else
            warn "  这一版还没有讲解字幕（从 1.14 开始才有）。截图和录屏照常能用，字幕的步骤先跳过；官网有 1.14 或更新的版本时再下载替换。"
            no_captions=1
          fi ;;
        *)
          warn "  这一份不在「应用程序」里。请把它拖进「应用程序」文件夹再打开，不要直接在「下载」里打开。" ;;
      esac
      if [ -n "$(xattr -p com.apple.quarantine "$app" 2>/dev/null)" ]; then
        say "        这一份是从网上下载的，第一次打开时 macOS 会拦一下。先确认它是从官网 lightrecord.nativeailab.cn 下载的，再按说明处理。"
      fi
    done <<EOF
$apps
EOF
    if [ "$found_good" = 0 ]; then problems=$((problems + 1)); fi
  fi
  if pgrep -x MumaShot >/dev/null 2>&1; then
    say "  轻镜现在正开着。"
  fi

  say ""
  say "【4】磁盘空间"
  local free need
  free=$(free_bytes "$HOME")
  need=$RECORD_RESERVE
  model_state "$MODEL" || need=$(( need + MODEL_SIZE ))
  if [ -z "$free" ]; then
    warn "看不到还剩多少空间。"
  elif [ "$free" -ge $(( need + 1000000000 )) ]; then
    ok "还剩约 $(gb "$free") GB"
  elif [ "$free" -ge "$need" ]; then
    warn "还剩约 $(gb "$free") GB，刚够用：轻镜开始录制要求至少 3 GB 可用空间，字幕模型还要约 0.5 GB。建议再清理一些。"
  elif [ "$free" -ge "$MODEL_SIZE" ]; then
    warn "还剩约 $(gb "$free") GB。能放下字幕模型，但轻镜开始录制要求至少 3 GB 可用空间，录之前要先清理磁盘。"
  else
    bad "只剩约 $(mb "$free") MB，放不下字幕模型（约 488 MB），也录不了。请先清理磁盘。"
    problems=$((problems + 1))
  fi

  say ""
  say "【5】讲解字幕用的语音模型"
  cmd_model || true

  say ""
  if [ "$problems" = 0 ]; then
    if [ "$no_captions" = 1 ]; then
      say "小结：这台电脑可以用轻镜。装的这一版还没有讲解字幕，第 3 步和第 5 步先跳过。"
    else
      say "小结：这台电脑可以用轻镜。字幕模型的情况见第 5 项。"
    fi
    return 0
  fi
  say "小结：有 $problems 项要先处理（看上面带 ❌ 或 ⚠️ 的行）。"
  return 1
}

cmd_model() {
  model_state "$MODEL"; local state=$?
  case $state in
    0) ok "字幕模型已就绪，大小和 SHA-256 都对：$MODEL"; return 0 ;;
    2) bad "$MODEL 大小不对（$(size_of "$MODEL") 字节，应为 $MODEL_SIZE）。轻镜不会用它，运行 download 重新下载即可。" ;;
    3) bad "$MODEL 大小对，但 SHA-256 对不上，文件坏了。运行 download 重新下载即可。" ;;
  esac
  # 用户以前在轻镜里「导入模型」时，轻镜会记住那个位置
  local remembered have
  remembered=$(app_pref layoutCaptions.model)
  if [ -n "$remembered" ] && [ "$remembered" != "$MODEL" ] && model_state "$remembered"; then
    ok "字幕模型已就绪：轻镜记着的位置 $remembered，大小和 SHA-256 都对。"
    return 0
  fi
  if model_state "$OTHER_MODEL"; then
    warn "这台电脑别处有一份同款模型（$OTHER_MODEL，别的软件下的），但轻镜不会去那里找。运行 download 会直接把它复制过去，不用联网。"
  elif [ "$state" = 1 ]; then
    warn "还没有字幕模型（ggml-small.bin，约 488 MB）。只用截图和普通录屏的话不需要它。"
  fi
  have=$(partial_bytes)
  if [ "$have" -gt 0 ]; then
    say "   有一份没下完的：$(mb "$have") MB / $(mb $MODEL_SIZE) MB。运行 download，或者在轻镜里点「继续下载」，都会接着下。"
  fi
  return 1
}

cmd_status() {
  local pid="" have
  [ -f "$LOCK/pid" ] && pid=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    have=$(size_of "$PART")
    say "脚本正在下载：$(mb "$have") MB / $(mb $MODEL_SIZE) MB（$(( have * 100 / MODEL_SIZE ))%）"
    return 0
  fi
  if app_writing; then
    have=$(size_of "$APP_PART")
    say "轻镜正在下载：$(mb "$have") MB / $(mb $MODEL_SIZE) MB（$(( have * 100 / MODEL_SIZE ))%）。看轻镜字幕页里的进度就行。"
    return 0
  fi
  say "现在没有在下载。运行 model 看模型是否已经放好并通过核对。"
  have=$(partial_bytes)
  [ "$have" -gt 0 ] && say "   有一份没下完的：$(mb "$have") MB / $(mb $MODEL_SIZE) MB。"
  return 1
}

label_of() {
  case "$1" in
    "$MODELSCOPE_URL") echo "魔搭社区" ;;
    "$MODELSCOPE_BACKUP_URL") echo "魔搭社区（备用）" ;;
    "$HF_MIRROR_URL") echo "hf-mirror" ;;
    "$HUGGINGFACE_URL") echo "Hugging Face" ;;
    *) echo "$1" | awk -F/ '{print $3}' ;;
  esac
}

truncate_part() { [ -f "$PART" ] && dd if=/dev/null of="$PART" bs=1 seek="$1" 2>/dev/null; }

# 读 curl 记下的响应头，取最后一次回应：状态码|内容类型|Content-Range|Content-Length
last_response() {
  tr -d '\r' < "$1" 2>/dev/null | awk '
    /^HTTP\// { code = $2; type = ""; range = ""; len = ""; next }
    { line = tolower($0) }
    line ~ /^content-type:/   { sub(/^[^:]*:[ \t]*/, ""); type = $0 }
    line ~ /^content-range:/  { sub(/^[^:]*:[ \t]*/, ""); range = $0 }
    line ~ /^content-length:/ { sub(/^[^:]*:[ \t]*/, ""); len = $0 }
    END { print code "|" type "|" range "|" len }'
}

# 服务器这次的回应能不能收下（和软件的判断一样）：要是模型文件本身，并且正好从断点接着给。
# $1 状态码  $2 内容类型  $3 Content-Range  $4 Content-Length  $5 这次开始前已有的字节数
response_ok() {
  local code="$1" lower range length before="$5"
  lower=$(printf '%s' "$2" | tr 'A-Z' 'a-z')
  range=$(printf '%s' "$3" | tr 'A-Z' 'a-z' | tr -d ' ')
  length=$(printf '%s' "$4" | tr -d ' ')
  case "$lower" in text/*|*html*|*json*) return 1 ;; esac
  case "$code" in
    206) [ "$range" = "bytes$before-$(( MODEL_SIZE - 1 ))/$MODEL_SIZE" ] ;;
    200) [ "$before" = 0 ] && { [ -z "$length" ] || [ "$length" = "$MODEL_SIZE" ]; } ;;
    *) return 1 ;;
  esac
}

CURL_PID=""; ATTEMPT_BEFORE=""; ATTEMPT_OK=0; DOWNLOAD_DONE=0; CLEANED=0; APP_NOTICED=0
stop_curl() {
  [ -n "$CURL_PID" ] || return 0
  kill "$CURL_PID" 2>/dev/null; wait "$CURL_PID" 2>/dev/null; CURL_PID=""
  # 这一轮服务器给的内容还没核对过、或者不对，就不留
  [ "$ATTEMPT_OK" = 1 ] || { [ -n "$ATTEMPT_BEFORE" ] && truncate_part "$ATTEMPT_BEFORE"; }
}
# 脚本没下完就结束时，把已下的部分交还给轻镜，在轻镜里点「继续下载」也能接着下
hand_back() {
  [ -f "$PART" ] || return 0
  local have
  have=$(size_of "$PART")
  if [ "$have" = 0 ]; then rm -f "${PART:?}"; return 0; fi
  if [ ! -e "$APP_PART" ]; then
    mv "$PART" "$APP_PART" && say "已下的 $(mb "$have") MB 留着：再运行 download，或者在轻镜里点「继续下载」，都会接着下。"
  else
    say "已下的 $(mb "$have") MB 留着，再运行 download 会接着下。"
  fi
}
cleanup() {
  [ "$CLEANED" = 1 ] && return 0
  CLEANED=1
  stop_curl
  [ "$DOWNLOAD_DONE" = 1 ] || hand_back
  release_lock
}

# 把临时文件下完。返回 0 表示大小已经对了，SHA-256 由调用方核对。
# 不用 curl 自带的 --retry：它重试时会把这一轮已下的部分截掉。这里每一轮都从已下的地方接着下。
fetch_from() {
  local url="$1" rc have before tick stalls=0 restarted=0 headers="$LOCK/headers" resp code ctype crange clength
  while :; do
    have=$(size_of "$PART")
    if [ "$have" -gt "$MODEL_SIZE" ]; then rm -f "${PART:?}"; have=0; fi
    if [ "$have" = "$MODEL_SIZE" ]; then return 0; fi
    before=$have
    [ "$have" -gt 0 ] && say "   接着已下的 $(mb "$have") MB 往下下…"
    : > "$headers"
    ATTEMPT_BEFORE=$before; ATTEMPT_OK=0
    "${CURL[@]}" --fail -C - --connect-timeout 20 --speed-limit 20000 --speed-time 60 \
         --max-filesize "$MODEL_SIZE" -D "$headers" -o "$PART" "$url" &
    CURL_PID=$!
    tick=0
    while kill -0 "$CURL_PID" 2>/dev/null; do
      sleep 1 & wait $!   # 这样写，停止下载时能马上响应
      tick=$((tick + 1))
      # 一收到最终回应就核对，不对马上停，不让错误内容写进来
      if [ "$ATTEMPT_OK" = 0 ]; then
        resp=$(last_response "$headers")
        code=${resp%%|*}
        if [ "$code" = 200 ] && [ "$before" -gt 0 ]; then
          :   # 服务器不支持接着下：curl 会自己退出，交给下面的处理
        else
          case "$code" in
            ""|1??|3??) ;;
            *) IFS='|' read -r code ctype crange clength <<EOF
$resp
EOF
               if response_ok "$code" "$ctype" "$crange" "$clength" "$before"; then ATTEMPT_OK=1
               else stop_curl; break; fi ;;
          esac
        fi
      fi
      if [ $((tick % 5)) = 0 ]; then
        if model_ready_elsewhere; then stop_curl; return 2; fi
        if [ "$APP_NOTICED" = 0 ] && app_writing; then
          APP_NOTICED=1
          warn "轻镜也在下载（它从头下）。两边各写各的文件，不会弄坏，但会抢网速；可以请用户在轻镜里点「暂停下载」。"
        fi
      fi
      if [ $((tick % 30)) = 0 ]; then
        have=$(size_of "$PART")
        say "   已下载 $(mb "$have") MB / $(mb $MODEL_SIZE) MB（$(( have * 100 / MODEL_SIZE ))%）"
      fi
    done
    if [ -n "$CURL_PID" ]; then wait "$CURL_PID"; rc=$?; CURL_PID=""; else rc=99; fi
    resp=$(last_response "$headers")
    IFS='|' read -r code ctype crange clength <<EOF
$resp
EOF
    have=$(size_of "$PART")
    if [ "$rc" = 33 ]; then
      # 服务器不支持接着下。只有它给的正是完整模型时，才像软件一样从头下；否则保留已下的部分，换地址。
      truncate_part "$before"
      if [ "$restarted" = 0 ] && [ -n "$clength" ] && response_ok 200 "$ctype" "" "$clength" 0; then
        say "   这个地址不支持接着下，从头下一次…"
        rm -f "${PART:?}"; restarted=1; continue
      fi
      warn "$(label_of "$url") 不支持接着下，保留已下的 $(mb "$before") MB，换下一个地址。"
      return 1
    fi
    case "$code" in
      ""|000) ;;   # 没连上，下面按「没下动」处理
      4??) truncate_part "$before"
           warn "$(label_of "$url") 现在拿不到这个文件（HTTP $code），换下一个地址。"
           return 1 ;;
      *)
        if ! response_ok "$code" "$ctype" "$crange" "$clength" "$before" || [ "$rc" = 63 ]; then
          truncate_part "$before"
          warn "$(label_of "$url") 给的不是模型文件，或者没有从断点接着给（HTTP $code ${ctype}），这部分没有收下，换下一个地址。"
          return 1
        fi ;;
    esac
    ATTEMPT_BEFORE=""
    if [ "$have" = "$MODEL_SIZE" ]; then return 0; fi
    if [ "$have" -gt "$MODEL_SIZE" ]; then rm -f "${PART:?}"; warn "$(label_of "$url") 给的文件比应有的大，已删掉。"; return 1; fi
    if [ $(( have - before )) -ge 5000000 ]; then
      say "   断了一下（curl 返回 $rc），接着下…"
      stalls=0; sleep 3; continue
    fi
    stalls=$((stalls + 1))
    if [ "$stalls" -lt 2 ]; then
      say "   没下动（curl 返回 $rc），再试一次…"
      sleep 5; continue
    fi
    case $rc in
      28) warn "$(label_of "$url") 太慢（低于约 20 KB/秒持续 1 分钟），换下一个地址。" ;;
      *)  warn "$(label_of "$url") 连不上或下不动（curl 返回 $rc），换下一个地址。" ;;
    esac
    return 1
  done
}

# 下载途中，轻镜自己已经把模型下好了。只在模型文件有变化时才算一次校验值，不反复读 488 MB。
MODEL_SEEN=""
model_ready_elsewhere() {
  [ -f "$MODEL" ] && [ "$(size_of "$MODEL")" = "$MODEL_SIZE" ] || return 1
  local stamp
  stamp=$(stat -f '%i-%m' "$MODEL" 2>/dev/null)
  [ "$stamp" = "$MODEL_SEEN" ] && return 1
  MODEL_SEEN=$stamp
  model_state "$MODEL"
}

cmd_download() {
  local first="$1"
  if model_state "$MODEL"; then
    ok "字幕模型已经在了，并且校验通过，不用再下。"
    return 0
  fi
  MODEL_SEEN=$(stat -f '%i-%m' "$MODEL" 2>/dev/null)   # 已有的坏文件不用再算一遍
  take_lock || return 1
  trap cleanup EXIT
  trap 'say "下载已停止。"; cleanup; exit 130' INT TERM

  if app_writing; then
    warn "轻镜正在下载这个模型（字幕页里显示「暂停下载」）。让轻镜下完就行；想改用脚本下，先请用户在轻镜里点「暂停下载」，再运行 download。"
    DOWNLOAD_DONE=1   # 没动任何文件，不用交还
    return 1
  fi
  # 接过轻镜下了一半的部分（两份都有时，留大的那份）
  local a p
  a=$(size_of "$APP_PART"); p=$(size_of "$PART")
  if [ -f "$APP_PART" ]; then
    if [ "$a" -gt "$p" ] && [ "$a" -le "$MODEL_SIZE" ]; then
      mv -f "$APP_PART" "$PART" && say "接着轻镜已下的 $(mb "$a") MB 往下下。"
    else
      rm -f "${APP_PART:?}"
    fi
  fi

  local free need
  free=$(free_bytes "$SPEECH_DIR")
  need=$(( MODEL_SIZE - $(size_of "$PART") + 100000000 ))
  if [ -n "$free" ] && [ "$free" -lt "$need" ]; then
    bad "磁盘空间不够：还要约 $(mb "$need") MB，只剩 $(mb "$free") MB。请先清理磁盘。"
    return 1
  fi

  if model_state "$OTHER_MODEL"; then
    say "这台电脑里已经有一份同款模型（$OTHER_MODEL），直接复制过去，不用联网…"
    if copy_into_place "$OTHER_MODEL"; then
      DOWNLOAD_DONE=1; drop_partials
      ok "字幕模型已放好，大小和 SHA-256 都对：$MODEL"
      say "$RESTART_HINT"
      return 0
    fi
    warn "复制没成功，改成联网下载。"
  fi

  local custom url list="$LOCK/urls" start clean r
  custom=$(app_pref layoutCaptions.modelSource)
  [ -n "$custom" ] || custom="$MUMA_URL"
  : > "$list"
  for url in "$first" "$custom" "$MODELSCOPE_URL" "$MODELSCOPE_BACKUP_URL" "$HF_MIRROR_URL" "$HUGGINGFACE_URL"; do
    url=$(printf '%s' "$url" | tr -d '[:space:]')
    [ -n "$url" ] || continue
    case "$url" in
      https://?*) grep -qxF "$url" "$list" || echo "$url" >> "$list" ;;
      *) warn "跳过 $url：下载地址必须以 https:// 开头。" ;;
    esac
  done

  while IFS= read -r url; do
    [ -n "$url" ] || continue
    clean=0
    while :; do
      start=$(size_of "$PART")
      say ""
      say "从 $(label_of "$url") 下载…"
      fetch_from "$url"; r=$?
      if [ "$r" = 2 ]; then
        DOWNLOAD_DONE=1; drop_partials
        ok "轻镜已经把模型下好了，核对通过：$MODEL。脚本停下，不用再下。"
        return 0
      fi
      [ "$r" = 0 ] || break
      say "   下完了，正在核对 SHA-256（几秒钟）…"
      if [ "$(sha_of "$PART")" = "$MODEL_SHA256" ]; then
        if mv -f "$PART" "$MODEL"; then
          DOWNLOAD_DONE=1; drop_partials
          ok "字幕模型已放好，大小和 SHA-256 都对：$MODEL"
          say "$RESTART_HINT"
          return 0
        fi
        bad "放不进 $MODEL，请检查磁盘空间和权限。"
        return 1
      fi
      bad "SHA-256 对不上，这份文件不能用，已经删掉。"
      rm -f "${PART:?}"
      # 坏的部分可能来自之前的地址：如果这次是接着之前的部分下的，就从头再试这个地址一次
      if [ "$start" -gt 0 ] && [ "$clean" = 0 ]; then
        clean=1; say "   从头再试一次这个地址…"; continue
      fi
      break
    done
  done < "$list"
  say ""
  if [ -f "$PART" ] && [ "$(size_of "$PART")" -gt 0 ]; then
    bad "这次没下完。"
  else
    bad "这次没下成。过一会儿再运行 download；或者用浏览器下载 ggml-small.bin，再用 verify 和 install（或在轻镜里点「导入模型」）。"
  fi
  return 1
}

cmd_verify() {
  local file="$1" size
  if [ -z "$file" ]; then bad "请告诉我文件在哪：bash lightrecord.sh verify <文件路径>"; return 1; fi
  if [ ! -f "$file" ]; then bad "找不到这个文件：$file"; return 1; fi
  size=$(size_of "$file")
  if [ "$size" = "$EN_MODEL_SIZE" ]; then
    bad "这是英文版 ggml-small.en.bin，轻镜要的是多语言版 ggml-small.bin（$MODEL_SIZE 字节）。"
    return 1
  fi
  if [ "$size" != "$MODEL_SIZE" ]; then
    bad "大小是 $size 字节，应为 $MODEL_SIZE 字节（约 488 MB）。可能没下完，或者不是这个模型。"
    return 1
  fi
  say "大小对，正在核对 SHA-256（几秒钟）…"
  if [ "$(sha_of "$file")" = "$MODEL_SHA256" ]; then
    ok "核对通过，这就是轻镜要的 ggml-small.bin。"
    return 0
  fi
  bad "大小对，但 SHA-256 对不上，文件坏了或者被改过。请删掉重下。"
  return 1
}

cmd_install() {
  local file="$1"
  cmd_verify "$file" || return 1
  take_lock || return 1
  trap release_lock EXIT
  if app_writing; then
    warn "轻镜正在下载这个模型。先请用户在轻镜里点「暂停下载」，再运行 install。"
    return 1
  fi
  local src dst
  src=$(cd "$(dirname "$file")" && pwd)/$(basename "$file")
  dst=$(cd "$SPEECH_DIR" && pwd)/ggml-small.bin
  if [ "$src" = "$dst" ]; then
    ok "它已经在轻镜找模型的位置了。"
  else
    copy_into_place "$file" || return 1
    ok "已放好：$MODEL（原来那份可以删，也可以留着）"
  fi
  drop_partials
  say "$RESTART_HINT"
}

cmd_latest() {
  local dir list f n folder
  dir="${LIGHTRECORD_LAYOUT_DIR:-$(app_pref layoutRecording.output)}"
  [ -n "$dir" ] || dir="$HOME/Desktop/屏刻"
  # 文件夹名里带着录制开始的时间，按名字排就是按录制时间排（改字幕、重新导出不会打乱顺序）
  list=$(ls -d "$dir"/布局录制_* 2>/dev/null | sort -r | head -n 3)
  if [ -z "$list" ]; then
    warn "在 $dir 里还没找到讲解布局的录制。实际保存位置以讲解布局窗口底部「保存到：」为准。"
    return 1
  fi
  say "在 $dir 里找到的讲解布局录制（最新的在最上面，名字里是录制开始的日期和时间）："
  n=0
  while IFS= read -r folder; do
    n=$((n + 1))
    say ""
    say "$n. $(basename "$folder")"
    say "   位置：$folder"
    [ -f "$folder/成片.mp4" ] && say "   成片.mp4（原片，没有字幕）$(mb "$(size_of "$folder/成片.mp4")") MB"
    if [ -f "$folder/讲解字幕.srt" ]; then
      say "   讲解字幕.srt：$(grep -c -- '-->' "$folder/讲解字幕.srt") 句字幕"
    else
      say "   还没有字幕文件（没识别完，或者没开「录完自动生成字幕」）"
    fi
    f=$(ls -t "$folder"/讲解成片_*.mp4 2>/dev/null | head -n1)
    if [ -n "$f" ]; then
      say "   带字幕的成片：$(basename "$f")（$(mb "$(size_of "$f")") MB）"
    else
      say "   还没有导出带字幕的成片"
    fi
  done <<EOF
$list
EOF
  say ""
  say "读里面的字幕之前，先和用户确认是哪一个。"
}

case "$1" in
  check)    cmd_check ;;
  model)    cmd_model ;;
  download) cmd_download "$2" ;;
  status)   cmd_status ;;
  verify)   cmd_verify "$2" ;;
  install)  cmd_install "$2" ;;
  latest)   cmd_latest ;;
  *)
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 1 ;;
esac
