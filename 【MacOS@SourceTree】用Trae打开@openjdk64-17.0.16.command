#!/bin/zsh
set -euo pipefail

# ================================== 公共输出函数 ==================================
info()  { print -P "ℹ️  %F{cyan}$*%f"; }
ok()    { print -P "✅ %F{green}$*%f"; }
warn()  { print -P "⚠️  %F{yellow}$*%f"; }
err()   { print -P "❌ %F{red}$*%f" >&2; }

# ================================== 入口与目录 ==================================
cd "${1:-$PWD}" || { err "目标目录不存在：${1:-$PWD}"; exit 1; }

# ================================== Homebrew 安装/初始化 ==================================
if ! command -v brew >/dev/null 2>&1; then
  warn "未检测到 Homebrew，开始安装（需网络，约几分钟）…"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # 将 brew 写入当前 shell 环境（不修改你的 dotfiles）
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    err "Homebrew 安装后未找到可执行文件，请检查安装输出。"; exit 1
  fi
  ok "Homebrew 已安装。"
else
  # 让当前 shell 拿到 brew 的环境（兼容用户没在 rc 文件里配置的情况）
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  ok "检测到 Homebrew。"
fi

# ================================== jenv 安装/初始化 ==================================
if ! command -v jenv >/dev/null 2>&1; then
  info "未检测到 jenv，使用 brew 安装…"
  brew install jenv
  ok "jenv 已安装。"
fi

# 初始化 jenv（zsh）
eval "$(jenv init -)"

# 可选 export 插件：不阻断
jenv enable-plugin export >/dev/null 2>&1 || true

# ================================== 确保 JDK 17 可用 ==================================
if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
  err "系统未安装 JDK 17；请先安装（如 Temurin 17 / Zulu 17）。"
  exit 1
fi

# 将 JDK17 纳入 jenv 管理（幂等）
jenv add "$(/usr/libexec/java_home -v 17)" >/dev/null 2>&1 || true
jenv rehash

# 选择一个包含“17”的版本（兼容 openjdk/temurin/zulu 命名）
pick_17="$(jenv versions --bare | grep -E '(^|[[:space:]])(.*17(\.|$).*)' | head -n1 || true)"
if [[ -z "${pick_17:-}" ]]; then
  err "jenv 中未发现 JDK 17，请检查 \`jenv versions\` 输出。"
  exit 1
fi

# ================================== 设定当前 Shell 使用 17 ==================================
jenv shell "$pick_17"
export JENV_VERSION="$pick_17"
export JAVA_HOME="$(jenv prefix)"
export PATH="$JAVA_HOME/bin:$PATH"

# 目录锁定，避免父目录/global 干扰
echo "$pick_17" > .java-version

# 诊断输出
info "JENV_VERSION=$JENV_VERSION"
info "JAVA_HOME=$JAVA_HOME"
java -version

# ================================== 打开 Trae（优先 CLI） ==================================
open_trae() {
  local target="."
  # A) CLI：可继承当前 shell 的 JAVA_HOME 等环境
  if command -v trae >/dev/null 2>&1; then
    ok "使用 Trae CLI 启动：trae ${target}"
    exec trae "${target}"
  fi

  # B) GUI .app：可能不继承当前 shell 的临时环境
  local -a CANDIDATES=(
    "/Applications/Trae.app"
    "$HOME/Applications/Trae.app"
  )
  for app in "${CANDIDATES[@]}"; do
    if [[ -d "$app" ]]; then
      warn "未检测到 Trae CLI；改用 GUI 启动：$app"
      exec open -a "$app" "${target}"
    fi
  done

  # C) 都没有 -> 跳转官网下载
  warn "未找到 Trae，跳转官网下载…"
  exec open "https://www.trae.cn/"
}

open_trae
