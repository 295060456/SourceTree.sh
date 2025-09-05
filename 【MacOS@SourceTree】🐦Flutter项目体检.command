#!/usr/bin/env zsh
set -euo pipefail

# ================================== 全局 ==================================
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

log()          { echo -e "$1" | tee -a "$LOG_FILE"; }
success_echo() { log "✔ $1"; }
error_echo()   { log "❌ $1"; }
info_echo()    { log "ℹ $1"; }

# ================================== 参数检查 ==================================
check_args() {
  local PROJECT_DIR="${1:-}"
  local ACTION="${2:-doctor}"  # 可选: doctor | clean-get | pub-get

  if [[ -z "$PROJECT_DIR" ]]; then
    error_echo "请传入 Flutter 项目根目录"
    exit 1
  fi
  if [[ ! -f "$PROJECT_DIR/pubspec.yaml" ]]; then
    error_echo "目标目录不是 Flutter 项目：$PROJECT_DIR"
    exit 1
  fi

  echo "$PROJECT_DIR|$ACTION"
}

# ================================== 注入环境（为 SourceTree） ==================================
ensure_env() {
  # SourceTree 下常见：不加载登录 shell，PATH 缺失 brew/fvm
  # Apple Silicon
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  # Intel
  if [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  # 常见本地 bin
  export PATH="$HOME/.fvm/bin:$HOME/.pub-cache/bin:$PATH"
}

# ================================== 工具链选择（FVM 优先） ==================================
# 产出：全局数组 flutter_cmd dart_cmd
typeset -ga flutter_cmd dart_cmd
set_toolchain() {
  local dir="$1"
  cd "$dir"  # 必须先进入项目目录，FVM 才能读 .fvmrc

  # 1) 优先 fvm wrapper（识别 .fvmrc / .fvm）
  if command -v fvm >/dev/null 2>&1 && [[ -f ".fvmrc" || -d ".fvm" ]]; then
    flutter_cmd=(fvm flutter)
    dart_cmd=(fvm dart)
    info_echo "使用 FVM：$(fvm flutter --version | head -n1)"
    return
  fi

  # 2) 直接使用本地链接的 .fvm/flutter_sdk
  if [[ -x ".fvm/flutter_sdk/bin/flutter" ]]; then
    flutter_cmd=(".fvm/flutter_sdk/bin/flutter")
    dart_cmd=(".fvm/flutter_sdk/bin/dart")
    info_echo "使用本地 .fvm/flutter_sdk：$(".fvm/flutter_sdk/bin/flutter" --version | head -n1)"
    return
  fi

  # 3) 兜底：系统 flutter
  if command -v flutter >/dev/null 2>&1; then
    flutter_cmd=(flutter)
    dart_cmd=(dart)  # 会优先用 Flutter 自带 dart
    warn_echo() { log "⚠ $1"; }
    warn_echo "未检测到 FVM 环境，回退到系统 flutter：$(flutter --version | head -n1)"
    return
  fi

  error_echo "未找到可用的 Flutter。请安装 FVM 或配置 PATH。"
  exit 1
}

# ================================== 业务动作 ==================================
run_doctor() {
  success_echo "进入目录：$(pwd)"
  log "开始执行 flutter doctor..."
  "${flutter_cmd[@]}" doctor | tee -a "$LOG_FILE"
  success_echo "执行完成 ✅"
}

run_clean_get() {
  success_echo "进入目录：$(pwd)"

  log "开始执行 flutter clean..."
  "${flutter_cmd[@]}" clean | tee -a "$LOG_FILE"

  log "开始执行 flutter pub get..."
  "${flutter_cmd[@]}" pub get | tee -a "$LOG_FILE"

  success_echo "执行完成 ✅"
}

run_pub_get_only() {
  success_echo "进入目录：$(pwd)"
  log "开始执行 flutter pub get..."
  "${flutter_cmd[@]}" pub get | tee -a "$LOG_FILE"
  success_echo "执行完成 ✅"
}

# ================================== 主函数 ==================================
main() {
  local args; args=$(check_args "$@")
  local project_dir="${args%%|*}"
  local action="${args##*|}"

  ensure_env
  set_toolchain "$project_dir"

  case "$action" in
    doctor)     run_doctor ;;
    clean-get)  run_clean_get ;;
    pub-get)    run_pub_get_only ;;
    *)          error_echo "未知动作：$action（可选：doctor | clean-get | pub-get）"; exit 2 ;;
  esac
}

main "$@"
