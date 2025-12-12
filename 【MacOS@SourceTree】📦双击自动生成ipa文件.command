#!/bin/zsh
# shellcheck shell=zsh

set -euo pipefail

# ===============================================================
# 默认配置
# ===============================================================
CONFIG="Release"           # Debug / Release
OUT_DIR="${HOME}/Desktop"  # .ipa 输出目录
PROJECT_PATH=""            # 指定 .xcodeproj 或 .xcworkspace 的完整路径
LOG_FILE="/tmp/package_ipa.log"

# ===============================================================
# 语义化输出 & 日志
# ===============================================================
_color()        { local c="$1"; shift; printf "\033[%sm%s\033[0m\n" "$c" "$*"; }
info_echo()    { _color "34" "ℹ️  $*";  }
success_echo() { _color "32" "✅ $*";   }
warn_echo()    { _color "33" "⚠️  $*";  }
error_echo()   { _color "31" "❌ $*";   }
log()          { printf "%s %s\n" "$(date '+%F %T')" "$*" >> "$LOG_FILE"; }

# ===============================================================
# 帮助
# ===============================================================
usage() {
  cat <<EOF
用法:
  $(basename "$0") [--config Debug|Release] [--out 输出目录] [--project 路径]

参数:
  --config   构建配置，默认 Release
  --out      .ipa 输出目录，默认 \$HOME/Desktop
  --project  指定 .xcodeproj 或 .xcworkspace 的完整路径

示例:
  $(basename "$0") --config Release --out ~/Desktop
  $(basename "$0") --project ./MyApp.xcodeproj
EOF
}

# ===============================================================
# 参数解析
# ===============================================================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)  CONFIG="${2:-Release}"; shift 2 ;;
      --out)     OUT_DIR="${2:-$OUT_DIR}"; shift 2 ;;
      --project) PROJECT_PATH="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *)         warn_echo "忽略未知参数：$1"; shift ;;
    esac
  done
}

# ===============================================================
# 准备环境
# ===============================================================
prepare_env() {
  mkdir -p "$OUT_DIR"
  : > "$LOG_FILE"
}

# ===============================================================
# 获取仓库根目录（优先 git）
# ===============================================================
find_repo_root() {
  if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    cd "$(dirname "$0")"
    pwd
  fi
}

# ===============================================================
# 选择工程文件（优先 .xcworkspace）
# ===============================================================
choose_project_path() {
  local root="$1"
  local path="$PROJECT_PATH"

  if [[ -z "$path" ]]; then
    set +e
    local WORKSPACES=($(find "$root" -maxdepth 2 -name "*.xcworkspace" -print 2>/dev/null))
    local PROJECTS=($(find "$root" -maxdepth 2 -name "*.xcodeproj"   -print 2>/dev/null))
    set -e

    if [[ ${#WORKSPACES[@]} -gt 0 ]]; then
      path="${WORKSPACES[1]}"
    elif [[ ${#PROJECTS[@]} -gt 0 ]]; then
      path="${PROJECTS[1]}"
    else
      error_echo "未在 $root 找到 .xcworkspace / .xcodeproj"
      exit 1
    fi
  fi

  if [[ ! -e "$path" ]]; then
    error_echo "--project 指定的路径不存在：$path"
    exit 1
  fi

  echo "$path"
}

# ===============================================================
# 查找最新 .app（优先 CONFIG，再回退 Debug）
# ===============================================================
find_latest_app() {
  local derived="${HOME}/Library/Developer/Xcode/DerivedData"
  [[ -d "$derived" ]] || { error_echo "未找到 DerivedData：$derived。请先在 Xcode 做一次真机构建。"; exit 1; }

  set +e
  local app_path
  app_path=$(ls -td "${derived}"/*/Build/Products/${CONFIG}-iphoneos/*.app 2>/dev/null | head -n 1)
  set -e

  if [[ -z "${app_path:-}" || ! -d "$app_path" ]]; then
    warn_echo "未在 ${derived}/**/Build/Products/${CONFIG}-iphoneos/ 找到 .app，尝试使用 Debug..."
    set +e
    app_path=$(ls -td "${derived}"/*/Build/Products/Debug-iphoneos/*.app 2>/dev/null | head -n 1)
    set -e
  fi

  if [[ -z "${app_path:-}" || ! -d "$app_path" ]]; then
    error_echo "还是找不到 .app。请确认你已对真机目标完成构建（Product > Build）。"
    exit 1
  fi

  echo "$app_path"
}

# ===============================================================
# 推断 IPA 名称（CFBundleDisplayName > CFBundleName > 工程名）
# ===============================================================
infer_ipa_name() {
  local app_dir="$1"
  local fallback="$2"
  local plist="$app_dir/Info.plist"
  local name=""

  if [[ -f "$plist" ]]; then
    name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist" 2>/dev/null || true)
    [[ -z "$name" ]] && name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist" 2>/dev/null || true)
  fi
  [[ -n "$name" ]] || name="$fallback"
  echo "$name"
}

# ===============================================================
# 打包 .ipa
# ===============================================================
package_ipa() {
  local app_dir="$1"
  local ipa_path="$2"

  local tmp_dir payload_dir
  tmp_dir="$(mktemp -d)"
  payload_dir="${tmp_dir}/Payload"

  mkdir -p "$payload_dir"
  cp -R "$app_dir" "$payload_dir/"

  info_echo "📦 正在打包为 .ipa ..."
  (
    cd "$tmp_dir"
    /usr/bin/zip -qry "$ipa_path" "Payload"
  )
  rm -rf "$tmp_dir"
}

# ===============================================================
# main：统一调度
# ===============================================================
main() {
  parse_args "$@"
  prepare_env

  local repo_root project_path project_base latest_app ipa_name ipa_path

  repo_root="$(find_repo_root)"
  info_echo "📂 工作目录：$repo_root"; log "repo_root=$repo_root"

  project_path="$(choose_project_path "$repo_root")"
  project_base="$(basename "$project_path")"
  success_echo "发现工程：$project_base"
  log "project=$project_path"

  latest_app="$(find_latest_app)"
  success_echo "✅ 最新 .app：$latest_app"
  log "app=$latest_app"

  ipa_name="$(infer_ipa_name "$latest_app" "${project_base%.*}")"
  ipa_path="${OUT_DIR}/${ipa_name}.ipa"

  package_ipa "$latest_app" "$ipa_path"
  success_echo "🎉 打包完成：$ipa_path"
  log "ipa=$ipa_path"

  open -R "$ipa_path" 2>/dev/null || true
}

# ===============================================================
# 执行入口
# ===============================================================
main "$@"
