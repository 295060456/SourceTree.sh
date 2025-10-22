#!/bin/zsh
# ============================== 基本配置 ==============================
umask 022
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"; : > "$LOG_FILE"

log()  { echo "$*"; echo "$*" >>"$LOG_FILE"; }
info() { log "ℹ️  $*"; }
ok()   { log "✅ $*"; }
warn() { log "⚠️  $*"; }
err()  { log "❌ $*"; }

# 修复 SourceTree 的精简 PATH
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# 可选：强制只开 .xcodeproj（1=只开 project；默认=0）
FORCE_XCODEPROJ="${FORCE_XCODEPROJ:-0}"

# ============================== 入口路径 ==============================
ROOT="${REPO:-${1:-$PWD}}"
[ -d "$ROOT" ] || { err "路径无效：$ROOT"; exit 1; }
cd "$ROOT" || { err "无法进入目录：$ROOT"; exit 1; }
ROOT="$PWD"; REPO_NAME="$(/usr/bin/basename "$ROOT")"
ok "仓库根目录：$ROOT（仅检测当前目录，不递归）"

# ============================== 工具函数 ==============================
resolve_cmd(){
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }
    [ -x "$c" ] && { echo "$c"; return; }
  done
  return 1
}

do_pod_install(){
  local dir="$1"
  if command -v bundle >/dev/null 2>&1 && [ -f "$dir/Gemfile" ]; then
    info "bundle exec pod install @ $dir"
    (cd "$dir" && bundle exec pod install)
  else
    local pod_cmd
    pod_cmd=$(resolve_cmd pod /opt/homebrew/bin/pod /usr/local/bin/pod) || { warn "未找到 pod，跳过"; return 127; }
    info "pod install @ $dir"
    (cd "$dir" && "$pod_cmd" install)
  fi
}

open_in_xcode(){ info "打开：$1"; /usr/bin/open -a "Xcode" "$1"; }

has_workspace(){
  local dir="$1" proj="$2" prefer="$dir/$(/usr/bin/basename "$proj" .xcodeproj).xcworkspace"
  [ -d "$prefer" ] && return 0
  /usr/bin/find "$dir" -maxdepth 1 -type d -name "*.xcworkspace" -print -quit | grep -q .
}

# --- 清除 SwiftPM 缓存的隔离标记（解决 devicekit-manifest 被拦截） ---
clear_spm_quarantine() {
  if [ -d "$HOME/Library/org.swift.swiftpm" ]; then
    xattr -dr com.apple.quarantine "$HOME/Library/org.swift.swiftpm" 2>/dev/null || true
  fi
  if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
    /usr/bin/find "$HOME/Library/Developer/Xcode/DerivedData" -type d -name "SourcePackages" -maxdepth 3 -print0 2>/dev/null \
      | xargs -0 xattr -dr com.apple.quarantine 2>/dev/null || true
  fi
  /usr/bin/find "$HOME/Library/Developer" -type f -name "devicekit-manifest" -perm -111 -print0 2>/dev/null \
    | xargs -0 xattr -dr com.apple.quarantine 2>/dev/null || true
}

# --- 显式解析 SwiftPM，确保 Package Dependencies 出现 ---
resolve_swiftpm_for_workspace() {
  local ws="$1" scheme=""
  command -v xcodebuild >/dev/null 2>&1 || { warn "缺少 xcodebuild，跳过 SwiftPM 解析"; return; }

  local json
  json=$(xcodebuild -workspace "$ws" -list -json 2>/dev/null)
  scheme=$(/usr/bin/python3 - <<'PY'
import json,sys
j=sys.stdin.read().strip()
if not j:
    print("")
    sys.exit(0)
data=json.loads(j)
schemes=(data.get("workspace",{}) or {}).get("schemes",[]) or []
cands=[s for s in schemes if not s.lower().startswith("pods")]
print((cands[0] if cands else (schemes[0] if schemes else "")))
PY
<<<"$json")

  if [ -n "$scheme" ]; then
    info "解析 SwiftPM：scheme=$scheme"
    xcodebuild -quiet -resolvePackageDependencies -workspace "$ws" -scheme "$scheme" >/dev/null 2>&1 || \
      warn "xcodebuild 解析 SwiftPM 失败（可忽略）"
  else
    warn "未找到可用 Scheme，跳过 SwiftPM 解析"
  fi
}

# 统一动作：打开 workspace（先清隔离 → 解析 SPM → open）
open_workspace_properly() {
  local ws="$1"
  clear_spm_quarantine
  resolve_swiftpm_for_workspace "$ws"
  open_in_xcode "$ws"
}

# ============================== 仅当前目录查找 .xcodeproj ==============================
PROJ_LIST=()
FIND_OUT=$(/usr/bin/find "$ROOT" -maxdepth 1 -type d -name "*.xcodeproj" -print 2>/dev/null)
[ -n "$FIND_OUT" ] && IFS=$'\n' PROJ_LIST=($FIND_OUT)
[ ${#PROJ_LIST[@]} -gt 0 ] || { err "当前目录未找到任何 .xcodeproj"; exit 2; }

# ============================== 评分选择最佳工程（无交互，当前目录内） ==============================
BEST_PROJ=""; BEST_SCORE=999999
for proj in "${PROJ_LIST[@]}"; do
  dir="$(/usr/bin/dirname "$proj")"
  base="$(/usr/bin/basename "$proj" .xcodeproj)"
  score=0
  has_workspace "$dir" "$proj" && (( score -= 100 ))             # workspace 优先
  [ -f "$dir/Podfile" ] && (( score -= 10 ))                     # 有 Podfile 次优
  [[ "$base" == "$REPO_NAME" ]] && (( score -= 5 ))              # 工程名=仓库名，微调
  (( score += ${#proj} / 1000 ))                                 # 稳定排序
  if (( score < BEST_SCORE )); then BEST_SCORE=$score; BEST_PROJ="$proj"; fi
done

TARGET_PROJ="$BEST_PROJ"; TARGET_DIR="$(/usr/bin/dirname "$TARGET_PROJ")"
ok "选中工程：$TARGET_PROJ"

# ============================== 打开逻辑 ==============================
PODFILE="$TARGET_DIR/Podfile"

# 如需强制只开 .xcodeproj（你想看“项目视图+Package Dependencies”而非 Pods 工程）
if [ "$FORCE_XCODEPROJ" = "1" ]; then
  ok "FORCE_XCODEPROJ=1，强制打开 .xcodeproj"
  open_in_xcode "$TARGET_PROJ"
  exit 0
fi

if [ -f "$PODFILE" ]; then
  prefer="$TARGET_DIR/$(/usr/bin/basename "$TARGET_PROJ" .xcodeproj).xcworkspace"
  if [ -d "$prefer" ]; then
    open_workspace_properly "$prefer"; exit 0
  fi
  if ws=$(/usr/bin/find "$TARGET_DIR" -maxdepth 1 -type d -name "*.xcworkspace" -print -quit); then
    [ -n "$ws" ] && { open_workspace_properly "$ws"; exit 0; }
  fi
  warn "存在 Podfile 但无 .xcworkspace，执行 pod install..."
  if do_pod_install "$TARGET_DIR"; then
    if [ -d "$prefer" ]; then open_workspace_properly "$prefer"; exit 0; fi
    if ws=$(/usr/bin/find "$TARGET_DIR" -maxdepth 1 -type d -name "*.xcworkspace" -print -quit); then
      [ -n "$ws" ] && { open_workspace_properly "$ws"; exit 0; }
    fi
    warn "pod install 后仍无 .xcworkspace，回退打开 .xcodeproj"; open_in_xcode "$TARGET_PROJ"; exit 0
  else
    err "pod install 失败，回退打开 .xcodeproj"; open_in_xcode "$TARGET_PROJ"; exit 0
  fi
fi

# 无 Podfile → 直接打开 .xcodeproj
open_in_xcode "$TARGET_PROJ"
exit 0
