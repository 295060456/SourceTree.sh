#!/bin/zsh
# 用于 SourceTree 自定义动作：递归查找并在后台用 Xcode 打开工程，然后立刻退出
set -euo pipefail
IFS=$'\n\t'

# 1) 解析根目录：优先入参 > $REPO/$WORKING_DIR > git 根 > 当前目录
has_cmd(){ command -v "$1" >/dev/null 2>&1; }
resolve_root() {
  local root="${1:-}"
  [[ -n "$root" && -d "$root" ]] && { echo "$root"; return; }
  [[ -n "${REPO:-}" && -d "$REPO" ]] && { echo "$REPO"; return; }
  [[ -n "${WORKING_DIR:-}" && -d "$WORKING_DIR" ]] && { echo "$WORKING_DIR"; return; }
  if has_cmd git; then
    local top; top=$(git rev-parse --show-toplevel 2>/dev/null || true)
    [[ -n "$top" ]] && { echo "$top"; return; }
  fi
  pwd
}

ROOT="$(resolve_root "${1:-}")"
MAXDEPTH="${2:-8}"

# 2) 递归找工程（排除无关目录），优先 .xcworkspace；同目录有 workspace 就过滤掉 .xcodeproj
typeset -a WORKSPACES PROJECTS ALL
typeset -A HAS_WS_DIR

while IFS= read -r -d '' w; do
  WORKSPACES+=("$w"); HAS_WS_DIR["$(dirname "$w")"]=1
done < <(find "$ROOT" -maxdepth "$MAXDEPTH" \
  \( -name ".git" -o -name "Pods" -o -name "Carthage" -o -name "DerivedData" -o -name "build" -o -name ".build" \) -prune -o \
  -type d -name "*.xcworkspace" -print0)

while IFS= read -r -d '' p; do
  local d; d="$(dirname "$p")"
  [[ -n "${HAS_WS_DIR[$d]:-}" ]] && continue
  PROJECTS+=("$p")
done < <(find "$ROOT" -maxdepth "$MAXDEPTH" \
  \( -name ".git" -o -name "Pods" -o -name "Carthage" -o -name "DerivedData" -o -name "build" -o -name ".build" \) -prune -o \
  -type d -name "*.xcodeproj" -print0)

ALL=("${WORKSPACES[@]}" "${PROJECTS[@]}")

# 3) 没找到就直接退出（让 SourceTree 窗口结束）
[[ ${#ALL[@]} -eq 0 ]] && { echo "未找到 .xcworkspace / .xcodeproj"; exit 0; }

# 4) 选择第一个（无交互，保证不阻塞；如需排序可在这里自定义权重）
TARGET="${ALL[1]}"

# 5) 后台打开并立即退出（关键点：& + disown）
open -a "Xcode" "$TARGET" >/dev/null 2>&1 &
disown || true

# 可选：把 Xcode 抛到前台（不阻塞）
# /usr/bin/osascript -e 'tell application "Xcode" to activate' >/dev/null 2>&1 || true

exit 0
