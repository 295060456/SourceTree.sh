#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

log() { echo -e "$1" | tee -a "$LOG_FILE"; }
success_echo() { log "✔ $1"; }
error_echo() { log "❌ $1"; }

# ======================= 参数 =======================
PROJECT_DIR="${1:-}"

if [[ -z "$PROJECT_DIR" ]]; then
  error_echo "请传入 Flutter 项目根目录"
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/pubspec.yaml" ]]; then
  error_echo "目标目录不是 Flutter 项目：$PROJECT_DIR"
  exit 1
fi

# ======================= 执行 =======================
cd "$PROJECT_DIR"

success_echo "进入目录：$PROJECT_DIR"
log "开始执行 flutter clean..."
flutter clean | tee -a "$LOG_FILE"

log "开始执行 flutter pub get..."
flutter pub get | tee -a "$LOG_FILE"

success_echo "执行完成 ✅"
