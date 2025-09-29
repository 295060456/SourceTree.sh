#!/bin/zsh
# shellcheck shell=zsh

set -euo pipefail

# ================================== 配置与默认值 ==================================
CONFIG="Release"           # Debug / Release
OUT_DIR="${HOME}/Desktop"  # 输出目录
PROJECT_PATH=""            # 指定 .xcodeproj 或 .xcworkspace
CONFIRM="0"                # 交互确认：0=关闭(适配 SourceTree)，1=开启
LOG_FILE="/tmp/package_ipa.log"

# ================================== 语义化输出 ==================================
_color() { local c="$1"; shift; printf "\033[%sm%s\033[0m\n" "$c" "$*"; }
info_echo()    { _color "34" "ℹ️  $*";  }
success_echo() { _color "32" "✅ $*";   }
warn_echo()    { _color "33" "⚠️  $*";  }
error_echo()   { _color "31" "❌ $*";  }
log()          { printf "%s %s\n" "$(date '+%F %T')" "$*" >> "$LOG_FILE"; }

# ================================== 帮助 ==================================
usage() {
  cat <<EOF
用法:
  $(basename "$0") [--config Debug|Release] [--out 输出目录] [--project 路径] [--confirm]

参数:
  --config   构建配置，默认 Release
  --out      .ipa 输出目录，默认 \$HOME/Desktop
  --project  指定 .xcodeproj 或 .xcworkspace 的完整路径
  --confirm  运行前交互确认（终端友好；SourceTree 里不要加）

示例:
  $(basename "$0") --config Release --out ~/Desktop
  $(basename "$0") --project ./MyApp.xcodeproj
EOF
}

# ================================== 解析参数 ==================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CONFIG="${2:-Release}"; shift 2 ;;
    --out)     OUT_DIR="${2:-$OUT_DIR}"; shift 2 ;;
    --project) PROJECT_PATH="${2:-}"; shift 2 ;;
    --confirm) CONFIRM="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn_echo "忽略未知参数：$1"; shift ;;
  esac
done

mkdir -p "$OUT_DIR"
: > "$LOG_FILE"

# ================================== 当前目录（优先仓库根） ==================================
if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
else
  REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
fi
info_echo "📂 工作目录：$REPO_ROOT"; log "repo_root=$REPO_ROOT"

# ================================== 选择工程文件 ==================================
if [[ -z "$PROJECT_PATH" ]]; then
  set +e
  # 优先 workspace
  WORKSPACES=($(find "$REPO_ROOT" -maxdepth 2 -name "*.xcworkspace" -print 2>/dev/null))
  PROJECTS=($(find "$REPO_ROOT" -maxdepth 2 -name "*.xcodeproj" -print 2>/dev/null))
  set -e

  if [[ ${#WORKSPACES[@]} -gt 0 ]]; then
    PROJECT_PATH="${WORKSPACES[1]}"
  elif [[ ${#PROJECTS[@]} -gt 0 ]]; then
    PROJECT_PATH="${PROJECTS[1]}"
  else
    error_echo "未在 $REPO_ROOT 找到 .xcworkspace / .xcodeproj"
    exit 1
  fi
fi

if [[ ! -e "$PROJECT_PATH" ]]; then
  error_echo "--project 指定的路径不存在：$PROJECT_PATH"
  exit 1
fi

PROJECT_BASENAME="$(basename "$PROJECT_PATH")"
success_echo "发现工程：$PROJECT_BASENAME"
log "project=$PROJECT_PATH"

# ================================== 交互确认（可选） ==================================
if [[ "$CONFIRM" == "1" ]]; then
  echo ""
  info_echo "🛠️ 功能：自动打包最新 .app 为 .ipa"
  info_echo "🔧 配置：CONFIG=$CONFIG  输出目录=$OUT_DIR"
  read -r "?👉 按回车继续，Ctrl+C 取消..."
fi

# ================================== 查找最新 .app ==================================
DERIVED_BASE="${HOME}/Library/Developer/Xcode/DerivedData"
if [[ ! -d "$DERIVED_BASE" ]]; then
  error_echo "未找到 DerivedData：$DERIVED_BASE。请先在 Xcode 完成一次真机构建。"
  exit 1
fi

# 搜索 <CONFIG>-iphoneos/*.app，按修改时间倒序取第一个
set +e
LATEST_APP=$(ls -td "${DERIVED_BASE}"/*/Build/Products/"${CONFIG}"-iphoneos/*.app 2>/dev/null | head -n 1)
set -e

if [[ -z "${LATEST_APP:-}" || ! -d "$LATEST_APP" ]]; then
  warn_echo "未在 ${DERIVED_BASE}/**/Build/Products/${CONFIG}-iphoneos/ 找到 .app。尝试使用 Debug..."
  set +e
  LATEST_APP=$(ls -td "${DERIVED_BASE}"/*/Build/Products/Debug-iphoneos/*.app 2>/dev/null | head -n 1)
  set -e
fi

if [[ -z "${LATEST_APP:-}" || ! -d "$LATEST_APP" ]]; then
  error_echo "还是找不到 .app。请确认你已用 Xcode 对真机目标完成构建（Product > Build）。"
  exit 1
fi

success_echo "✅ 最新 .app：$LATEST_APP"
log "app=$LATEST_APP"

# ================================== 读取 Bundle 名称（用于 .ipa 命名） ==================================
APP_PLIST="$LATEST_APP/Info.plist"
IPA_NAME=""
if [[ -f "$APP_PLIST" ]]; then
  # 取 CFBundleDisplayName > CFBundleName > 工程名
  DISP_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$APP_PLIST" 2>/dev/null || true)
  BUNDLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$APP_PLIST" 2>/dev/null || true)
  IPA_NAME="${DISP_NAME:-$BUNDLE_NAME}"
fi
if [[ -z "$IPA_NAME" ]]; then
  IPA_NAME="${PROJECT_BASENAME%.*}"
fi

IPA_PATH="${OUT_DIR}/${IPA_NAME}.ipa"
TMP_DIR="$(mktemp -d)"
PAYLOAD_DIR="${TMP_DIR}/Payload"

# ================================== 组包并压缩 ==================================
mkdir -p "$PAYLOAD_DIR"
cp -R "$LATEST_APP" "$PAYLOAD_DIR/"
info_echo "📦 正在打包为 .ipa ..."
(
  cd "$TMP_DIR"
  /usr/bin/zip -qry "$IPA_PATH" "Payload"
)
rm -rf "$TMP_DIR"

success_echo "🎉 打包完成：$IPA_PATH"
log "ipa=$IPA_PATH"
open -R "$IPA_PATH" 2>/dev/null || true
