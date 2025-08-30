#!/bin/zsh
# Android Studio 启动脚本（SourceTree 友好版）
# - 纯文本日志，无颜色/emoji
# - 模块化函数，main 里统一调用
# - 逻辑：进入目录 -> 初始化 jenv -> 确认/纳管 JDK17 -> 选择与激活 -> 诊断 -> 启动 Android Studio

set -euo pipefail

# ========================= 公共日志 =========================
info() { echo "[INFO] $*"; }
ok()   { echo "[OK]   $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERR]  $*" >&2; }

# ========================= 模块：工作目录 =========================
WORKDIR=""
init_workdir() {
  local target="${1:-$PWD}"
  if ! cd "$target" 2>/dev/null; then
    err "目标目录不存在：$target"
    exit 1
  fi
  WORKDIR="$(pwd -P)"
  info "工作目录：$WORKDIR"
}

# ========================= 模块：jenv 初始化 =========================
init_jenv() {
  if ! command -v jenv >/dev/null 2>&1; then
    err "未检测到 jenv。请先安装：brew install jenv"
    exit 1
  fi
  eval "$(jenv init -)"
  # 可选插件：导出 JAVA_HOME；失败不阻断
  jenv enable-plugin export >/dev/null 2>&1 || true
  ok "jenv 已初始化"
}

# ========================= 模块：确保系统存在 JDK 17 =========================
ensure_system_jdk17() {
  if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
    err "系统未安装 JDK 17；请先安装（Temurin 17 / Zulu 17 等）。"
    exit 1
  fi
  ok "检测到系统可用的 JDK 17"
}

# ========================= 模块：将 JDK 17 纳入 jenv 管理（幂等） =========================
adopt_jdk17_into_jenv() {
  jenv add "$(/usr/libexec/java_home -v 17)" >/dev/null 2>&1 || true
  jenv rehash
  ok "JDK 17 已纳入 jenv（或已存在）"
}

# ========================= 模块：选择 jenv 内的 JDK 17 版本 =========================
PICK_17=""
select_jdk17() {
  # 兼容 openjdk/temurin/zulu 的命名；挑一个“名字里带 17”的版本
  PICK_17="$(jenv versions --bare | grep -E '(^|[[:space:]])(.*17(\.|$).*)' | head -n1 || true)"
  if [[ -z "${PICK_17:-}" ]]; then
    err "jenv 中未发现 JDK 17；请检查：jenv versions"
    exit 1
  fi
  ok "选择 JDK 版本：$PICK_17"
}

# ========================= 模块：激活 JDK 17（shell 级 + 目录锁定） =========================
activate_jdk17() {
  jenv shell "$PICK_17"
  export JENV_VERSION="$PICK_17"
  export JAVA_HOME="$(jenv prefix)"
  export PATH="$JAVA_HOME/bin:$PATH"
  echo "$PICK_17" > .java-version
  ok "已激活 JDK 17，并写入 .java-version"
}

# ========================= 模块：诊断输出 =========================
print_diagnostics() {
  info "JENV_VERSION=$JENV_VERSION"
  info "JAVA_HOME=$JAVA_HOME"
  java -version
}

# ========================= 模块：启动 Android Studio =========================
open_android_studio() {
  local target_path="."

  # A) JetBrains CLI 启动器（可继承当前 shell 环境）
  if command -v studio >/dev/null 2>&1; then
    ok "使用 CLI 启动：studio ${target_path}"
    exec studio "${target_path}"
  fi

  # B) GUI .app（注意：GUI 可能不继承当前 shell 的 JAVA_HOME）
  local -a CANDIDATES=(
    "/Applications/Android Studio.app"
    "$HOME/Applications/Android Studio.app"
    "/Applications/Android Studio Beta.app"
    "$HOME/Applications/Android Studio Beta.app"
    "/Applications/Android Studio Preview.app"
    "$HOME/Applications/Android Studio Preview.app"
  )
  local app
  for app in "${CANDIDATES[@]}"; do
    if [[ -d "$app" ]]; then
      warn "未检测到 CLI 启动器，改用 GUI：$app"
      exec open -a "$app" "${target_path}"
    fi
  done

  # C) 都没有 → 打开官网下载
  warn "未找到 Android Studio，打开官网下载页面。"
  exec open "https://developer.android.com/studio"
}

# ========================= 主流程 =========================
main() {
  init_workdir "${1:-$PWD}"
  init_jenv
  ensure_system_jdk17()
  adopt_jdk17_into_jenv
  select_jdk17
  activate_jdk17
  print_diagnostics
  open_android_studio
}

main "$@"
