#!/bin/zsh
# ================================== Pod Install 简化版（带UTF-8环境） ==================================
set -euo pipefail

# 强制 UTF-8，防止 SourceTree 环境丢失
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export RUBYOPT="-EUTF-8:UTF-8"

ROOT_DIR="${1:-$PWD}"
LOG_FILE="/tmp/Pod_Install.log"
: > "$LOG_FILE"

log()     { echo -e "$1" | tee -a "$LOG_FILE"; }
info()    { log "ℹ️  $1"; }
success() { log "✅ $1"; }
error()   { log "❌ $1"; }

process_dir() {
  local d="$1"
  info "处理目录：$d"
  if [[ -f "$d/Podfile" ]] && find "$d" -maxdepth 1 -name "*.xcodeproj" | grep -q .; then
    (cd "$d" && pod install --no-repo-update 2>&1 | tee -a "$LOG_FILE") \
      && success "pod install 成功：$d" \
      || error "pod install 失败：$d"
  else
    info "跳过：无 Podfile 或无 xcodeproj"
  fi
}

main() {
  info "起始目录：$ROOT_DIR"
  while IFS= read -r -d '' podfile; do
    process_dir "$(dirname "$podfile")"
  done < <(find "$ROOT_DIR" -type f -name "Podfile" -print0)
  success "任务完成，日志：$LOG_FILE"
}

main "$@"
