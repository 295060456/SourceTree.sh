#!/bin/zsh
set -euo pipefail

# -------- 纯文本日志函数（无颜色/无 emoji/兼容非TTY） --------
info() { echo "[INFO] $*"; }
ok()   { echo "[OK]   $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERR]  $*" >&2; }

ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    ok "检测到 Homebrew，跳过安装。"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    return
  fi
  warn "未检测到 Homebrew，开始安装…"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    err "Homebrew 安装后未找到可执行文件。"; exit 1
  fi
  ok "Homebrew 已安装。"
}

ensure_jenv() {
  if ! command -v jenv >/dev/null 2>&1; then
    info "未检测到 jenv，使用 brew 安装…"
    brew install jenv
    ok "jenv 已安装。"
  fi
  eval "$(jenv init -)"
  jenv enable-plugin export >/dev/null 2>&1 || true
}

ensure_jdk17() {
  if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
    err "系统未安装 JDK 17；请先安装（Temurin 17 / Zulu 17 等）。"
    exit 1
  fi

  jenv add "$(/usr/libexec/java_home -v 17)" >/dev/null 2>&1 || true
  jenv rehash

  local pick_17
  pick_17="$(jenv versions --bare | grep -E '(^|[[:space:]])(.*17(\.|$).*)' | head -n1 || true)"
  [[ -z "${pick_17:-}" ]] && { err "jenv 中未发现 JDK 17。"; exit 1; }

  jenv shell "$pick_17"
  export JENV_VERSION="$pick_17"
  export JAVA_HOME="$(jenv prefix)"
  export PATH="$JAVA_HOME/bin:$PATH"

  echo "$pick_17" > .java-version

  info "JENV_VERSION=$JENV_VERSION"
  info "JAVA_HOME=$JAVA_HOME"
  java -version
}

open_vscode() {
  local target="."
  if command -v code >/dev/null 2>&1; then
    ok "使用 VS Code CLI：code -n ${target}"
    exec code -n "${target}"
  fi

  local -a CANDIDATES=(
    "/Applications/Visual Studio Code.app"
    "$HOME/Applications/Visual Studio Code.app"
    "/Applications/Visual Studio Code - Insiders.app"
    "$HOME/Applications/Visual Studio Code - Exploration.app"
  )
  local app
  for app in "${CANDIDATES[@]}"; do
    if [[ -d "$app" ]]; then
      warn "未检测到 VS Code CLI，改用 GUI：$app"
      exec open -a "$app" "${target}"
    fi
  done

  warn "未发现 VS Code，打开官网…"
  exec open "https://code.visualstudio.com/"
}

main() {
  cd "${1:-$PWD}" || { err "目标目录不存在：${1:-$PWD}"; exit 1; }
  ensure_brew
  ensure_jenv
  ensure_jdk17
  open_vscode
}

main "$@"
