#!/bin/zsh
# 【SourceTree 专用】Flutter iOS 打包（自动发现子项目，纯文本；全局心跳 + 分阶段耗时）

set -euo pipefail

# ================= 日志/工具 =================
SCRIPT_BASENAME="macos_sourcetree_build_ios"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"; : > "$LOG_FILE"
BUILD_LOG="/tmp/flutter_build_ios.log"; : > "$BUILD_LOG"

log()      { echo "$1" | tee -a "$LOG_FILE"; }
info()     { log "[INFO] $*"; }
ok()       { log "[OK]   $*"; }
warn()     { log "[WARN] $*"; }
err()      { log "[ERR]  $*" >&2; }
hr()       { log "----------------------------------------------------------------"; }
section()  { hr; log "== $* =="; hr; }
ts()       { date "+%Y-%m-%d %H:%M:%S"; }

HEARTBEAT_SECS="${HEARTBEAT_SECS:-15}"   # 心跳间隔（秒）
OPEN_AFTER_BUILD="${OPEN_AFTER_BUILD:-1}" # 1=成功后打开产物目录
STEP="init"

# ======== 全局存活心跳（无论卡哪都能看到） ========
HB_PID=""
start_global_hb() {
  (
    while :; do
      sleep "$HEARTBEAT_SECS"
      echo "[HB] $(ts) alive pid=$$ step=$STEP" | tee -a "$LOG_FILE"
    done
  ) & HB_PID=$!
}
stop_global_hb() { [[ -n "${HB_PID:-}" ]] && kill "$HB_PID" 2>/dev/null || true; }

cleanup() { stop_global_hb; }
trap cleanup EXIT INT TERM

# ================= 选项 =================
BUILD_MODE="${BUILD_MODE:-release}"   # release | debug | profile
FLAVOR="${FLAVOR:-}"                  # 可为空

# 命令行覆盖
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)   BUILD_MODE="${2:-$BUILD_MODE}"; shift 2;;
    --flavor) FLAVOR="${2:-$FLAVOR}";         shift 2;;
    --)       shift; break;;
    *)        break;;
  esac
done

BASE_DIR="${1:-$PWD}"

# ================= 辅助函数 =================
is_flutter_root() { [[ -f "$1/pubspec.yaml" && -d "$1/lib" ]]; }

# 带心跳的长任务执行器（阶段心跳 + 耗时 + 保留退出码）
run_with_heartbeat() {
  local title="$1"; shift
  local wdir="$1"; shift
  local start=$(date +%s)
  STEP="$title"

  section "$title"
  info "start: $(ts)"
  info "workdir: $wdir"
  info "heartbeat: ${HEARTBEAT_SECS}s"

  (
    cd "$wdir" && "$@"
  ) 2>&1 | tee -a "$BUILD_LOG" &
  local pid=$!

  (
    while kill -0 "$pid" 2>/dev/null; do
      sleep "$HEARTBEAT_SECS"
      kill -0 "$pid" 2>/dev/null || break
      echo "[HB] $(ts) running: $title (pid=$pid)" | tee -a "$LOG_FILE"
    done
  ) & local local_hb=$!

  wait "$pid"; local ec=$?
  kill "$local_hb" 2>/dev/null || true

  local end=$(date +%s)
  local dur=$(( end - start ))
  if [[ $ec -eq 0 ]]; then
    ok "$title done (duration ${dur}s)"
  else
    err "$title failed (duration ${dur}s, ec=$ec). See $BUILD_LOG"
  fi
  return $ec
}

# ================= 定位 Flutter 项目（自动向下搜索） =================
resolve_flutter_root() {
  STEP="resolve"
  local base="$1"
  if ! cd "$base" 2>/dev/null; then
    err "无法进入目录：$base"; exit 1
  fi
  base="$(pwd -P)"
  section "定位 Flutter 项目"
  info "基准目录：$base"

  if is_flutter_root "$base"; then
    FLUTTER_ROOT="$base"; ok "命中：$FLUTTER_ROOT"; return 0
  fi

  local hit
  hit="$(/usr/bin/find "$base" -name pubspec.yaml -type f -print 2>/dev/null | head -n1 || true)"
  if [[ -n "$hit" ]]; then
    FLUTTER_ROOT="$(dirname "$hit")"
    if is_flutter_root "$FLUTTER_ROOT"; then
      ok "在子目录中找到：$FLUTTER_ROOT"; return 0
    fi
  fi

  err "未找到 Flutter 项目（缺 pubspec.yaml 或 lib/）"
  exit 1
}

# ================= 选择 flutter 命令 =================
choose_flutter_cmd() {
  STEP="choose_flutter"
  if command -v fvm >/dev/null 2>&1 && [[ -f "$FLUTTER_ROOT/.fvm/fvm_config.json" ]]; then
    FLUTTER_CMD=("fvm" "flutter"); info "使用：fvm flutter"
  else
    FLUTTER_CMD=("flutter"); info "使用：flutter"
  fi
}

# ================= 环境检查 =================
check_env() {
  STEP="check_env"
  section "检查 Xcode / CocoaPods"
  if ! command -v xcodebuild >/dev/null 2>&1; then
    err "未检测到 Xcode（xcodebuild）。请安装 Xcode 并同意许可（首次需运行一次 xcodebuild）。"
    exit 1
  fi
  if ! command -v pod >/dev/null 2>&1; then
    warn "未检测到 CocoaPods（pod）。如项目使用 Pods，构建可能失败。"
  fi
  ok "环境检查完成"
}

# ================= 版本打印（安全，不早退） =================
print_versions() {
  STEP="versions"
  section "环境版本"
  set +e
  info "xcodebuild -version："
  xcodebuild -version | tee -a "$LOG_FILE" || true

  info "flutter --version："
  (cd "$FLUTTER_ROOT" && "${FLUTTER_CMD[@]}" --version) | tee -a "$LOG_FILE" || true

  # 兼容新旧：优先静默试 flutter dart，失败再试系统 dart
  if (cd "$FLUTTER_ROOT" && "${FLUTTER_CMD[@]}" dart --version >/dev/null 2>&1); then
    info "flutter dart --version："
    (cd "$FLUTTER_ROOT" && "${FLUTTER_CMD[@]}" dart --version) | tee -a "$LOG_FILE" || true
  elif command -v dart >/dev/null 2>&1; then
    info "dart --version："
    dart --version | tee -a "$LOG_FILE" || true
  else
    warn "未检测到 dart 命令（新版本 Flutter 已移除 'flutter dart' 子命令）"
  fi
  set -e
}

# ================= pub get & build ipa =================
pub_get()   { run_with_heartbeat "flutter pub get" "$FLUTTER_ROOT" "${FLUTTER_CMD[@]}" pub get; }
build_ios() {
  local args=(build ipa "--$BUILD_MODE")
  [[ -n "$FLAVOR" ]] && args+=(--flavor "$FLAVOR")
  run_with_heartbeat "flutter build ipa ($BUILD_MODE${FLAVOR:+ / flavor=$FLAVOR})" \
                     "$FLUTTER_ROOT" "${FLUTTER_CMD[@]}" "${args[@]}"
}

# ================= 打开产物（存在才开） =================
open_if_exists() {
  local p="$1"
  if [[ -e "$p" ]]; then
    info "打开：$p"
    open "$p" 2>/dev/null || true
  else
    warn "不存在：$p"
  fi
}

open_outputs() {
  STEP="open_outputs"
  local ipa_dir="$FLUTTER_ROOT/build/ios/ipa"
  local first_ipa=""
  if [[ -d "$ipa_dir" ]]; then
    first_ipa="$(/usr/bin/find "$ipa_dir" -type f -name '*.ipa' -print 2>/dev/null | head -n1 || true)"
  fi

  if [[ -n "$first_ipa" ]]; then
    ok "已生成 IPA：$(basename "$first_ipa")"
    [[ "$OPEN_AFTER_BUILD" == "1" ]] && open_if_exists "$ipa_dir"
    return 0
  fi

  local archive_dir="$FLUTTER_ROOT/build/ios/archive"
  local first_archive=""
  if [[ -d "$archive_dir" ]]; then
    first_archive="$(/usr/bin/find "$archive_dir" -type d -name '*.xcarchive' -print 2>/dev/null | head -n1 || true)"
  fi

  if [[ -n "$first_archive" ]]; then
    ok "生成了 xcarchive：$(basename "$first_archive")"
    [[ "$OPEN_AFTER_BUILD" == "1" ]] && open_if_exists "$archive_dir"
    return 0
  fi

  warn "未发现 IPA 或 xcarchive。请查看构建日志：$BUILD_LOG"
}

# ================= 主流程 =================
main() {
  start_global_hb

  section "启动参数"
  info "mode=$BUILD_MODE  flavor=${FLAVOR:-<none>}  heartbeat=${HEARTBEAT_SECS}s"
  info "脚本日志：$LOG_FILE"
  info "构建日志：$BUILD_LOG"

  resolve_flutter_root "$BASE_DIR"
  choose_flutter_cmd
  check_env
  print_versions
  pub_get   || { err "pub get 失败，见：$BUILD_LOG"; exit 1; }
  build_ios || { err "构建失败，见：$BUILD_LOG"; exit 1; }

  if [[ -d "$FLUTTER_ROOT/build/ios" ]]; then
    section "产物列表：$FLUTTER_ROOT/build/ios"
    (cd "$FLUTTER_ROOT/build/ios" && ls -lhR) | tee -a "$LOG_FILE" || true
  fi

  open_outputs
  ok "完成。构建日志：$BUILD_LOG ；脚本日志：$LOG_FILE"
  STEP="done"
}

main "$@"
