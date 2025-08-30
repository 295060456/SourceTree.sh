#!/bin/zsh
set -euo pipefail

# ---------- 纯文本日志（SourceTree 友好，无颜色/无 emoji） ----------
info() { echo "[INFO] $*"; }
ok()   { echo "[OK]   $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERR]  $*" >&2; }

# ---------- 入口与目录 ----------
cd "${1:-$PWD}" || { err "目标目录不存在：${1:-$PWD}"; exit 1; }

# ---------- Homebrew 安装/初始化 ----------
ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    ok "检测到 Homebrew，跳过安装。"
  else
    warn "未检测到 Homebrew，开始安装（需网络）……"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    err "Homebrew 安装后未找到可执行文件，请检查安装输出。"
    exit 1
  fi
}

# ---------- jenv 安装/初始化 ----------
ensure_jenv() {
  if ! command -v jenv >/dev/null 2>&1; then
    info "未检测到 jenv，使用 brew 安装……"
    brew install jenv
    ok "jenv 已安装。"
  fi
  eval "$(jenv init -)"               # 初始化到当前 shell
  jenv enable-plugin export >/dev/null 2>&1 || true   # 可选：导出 JAVA_HOME
}

# ---------- 确保 JDK 17 可用并绑定到 jenv ----------
ensure_jdk17() {
  if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
    err "系统未安装 JDK 17；请先安装（例如 Temurin 17 / Zulu 17）。"
    exit 1
  fi

  # 纳入 jenv 管理（幂等）
  jenv add "$(/usr/libexec/java_home -v 17)" >/dev/null 2>&1 || true
  jenv rehash

  # 选择一个包含“17”的版本（兼容 openjdk/temurin/zulu 命名）
  local pick_17
  pick_17="$(jenv versions --bare | grep -E '(^|[[:space:]])(.*17(\.|$).*)' | head -n1 || true)"
  if [[ -z "${pick_17:-}" ]]; then
    err "jenv 中未发现 JDK 17，请检查 \`jenv versions\` 输出。"
    exit 1
  fi

  # 仅对当前 shell 生效；同时写 .java-version 锁定目录
  jenv shell "$pick_17"
  export JENV_VERSION="$pick_17"
  export JAVA_HOME="$(jenv prefix)"
  export PATH="$JAVA_HOME/bin:$PATH"
  echo "$pick_17" > .java-version

  info "JENV_VERSION=$JENV_VERSION"
  info "JAVA_HOME=$JAVA_HOME"
  java -version
}

# ---------- 打开 Trae（CLI 优先，其次 GUI，最后跳官网） ----------
open_trae() {
  local target="."
  # A) CLI：可继承当前 shell 的 JAVA_HOME 等环境
  if command -v trae >/dev/null 2>&1; then
    ok "使用 Trae CLI：trae ${target}"
    exec trae "${target}"
  fi

  # B) GUI .app：若无 CLI，尝试 GUI（注意 GUI 可能不继承当前 shell 环境）
  local -a CANDIDATES=(
    "/Applications/Trae.app"
    "$HOME/Applications/Trae.app"
  )
  local app
  for app in "${CANDIDATES[@]}"; do
    if [[ -d "$app" ]]; then
      warn "未检测到 Trae CLI，改用 GUI：$app"
      exec open -a "$app" "${target}"
    fi
  done

  # C) 都没有 → 打开官网
  warn "未找到 Trae，打开官网下载……"
  exec open "https://www.trae.cn/"
}

main() {
  ensure_brew
  ensure_jenv
  ensure_jdk17
  open_trae
}

main "$@"
