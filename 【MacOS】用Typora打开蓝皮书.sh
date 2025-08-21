#!/bin/zsh

# 功能：Typora 自动打开 README.md
# 1. 检查 Typora 是否存在
# 2. 存在则用 Typora 打开 README.md
# 3. 不存在则下载 JobsSoftware.MacOS.git 到当前目录，并打开 Finder

SCRIPT_DIR="$(pwd)"  # 当前目录
REPO_URL="https://github.com/295060456/JobsSoftware.MacOS.git"

# ========== 检查 Typora ==========
if command -v typora >/dev/null 2>&1 || [ -d "/Applications/Typora.app" ]; then
  echo "✔ Typora 已安装，正在打开 README.md ..."
  open -a Typora "$SCRIPT_DIR/README.md"
else
  echo "⚠ Typora 未安装，准备下载 JobsSoftware.MacOS.git ..."
  git clone "$REPO_URL" "$SCRIPT_DIR/JobsSoftware.MacOS" || {
    echo "❌ 下载失败，请检查网络或仓库地址。"
    exit 1
  }
  echo "✔ 下载完成，正在打开当前目录 ..."
  open "$SCRIPT_DIR"
fi
