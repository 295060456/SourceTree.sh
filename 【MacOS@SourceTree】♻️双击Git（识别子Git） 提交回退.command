#!/bin/zsh
set -euo pipefail

# ============================================================
# 🧰 Git 提交回退助手（双击+SourceTree 一套脚本）
#  - 双击 .command：交互式多模式
#  - SourceTree Custom Action：直接把未推送提交打回到“提交”面板
# ============================================================

SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

# 运行模式：standalone / sourcetree
RUN_MODE="standalone"
REPO_FROM_ARG=""

# 如果第一个参数是一个 Git 仓库路径，认为是 SourceTree 调用
if [[ $# -ge 1 ]]; then
  if [[ -d "$1" ]]; then
    if git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      RUN_MODE="sourcetree"
      REPO_FROM_ARG="$(cd "$1" && pwd)"
    fi
  fi
fi

# =============== 彩色输出 ===============
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
warm_echo()      { log "\033[1;33m$1\033[0m"; }
note_echo()      { log "\033[1;36m📝 $1\033[0m"; }
error_echo()     { log "\033[1;31m❌ $1\033[0m"; }
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
highlight_echo() { log "\033[1;35m✨ $1\033[0m"; }
bold_echo()      { log "\033[1m$1\033[0m"; }

# =============== 自述 ===============
print_git_reset_intro() {
  echo ""
  bold_echo "==============================================="
  bold_echo "  🧰 Git 提交回退助手（支持多种模式 & 子 Git）"
  bold_echo "==============================================="
  echo ""
  info_echo "本工具支持："
  echo "  1️⃣ soft 回退到远端（提交打回到“待提交”，已暂存）"
  echo "  2️⃣ hard 回退到远端（丢弃本地提交 + 修改）"
  echo "  3️⃣ 通过 fzf 选择任意提交回退"
  echo "  4️⃣ 通过 tag 回退"
  echo "  5️⃣ 通过 reflog 回退到任意历史状态"
  echo ""
}

# =============== 基础工具 ===============
get_cpu_arch() {
  uname -m
}

inject_shellenv_block() {
  local file="$1"
  local line="$2"
  if [[ -z "$file" || -z "$line" ]]; then
    error_echo "❌ 用法错误：inject_shellenv_block <file> <line>"
    return 1
  fi

  if grep -Fq "$line" "$file" 2>/dev/null; then
    info_echo "📌 已存在：$line"
  else
    echo "" >> "$file"
    echo "$line" >> "$file"
    success_echo "✅ 已写入到 $file：$line"
  fi

  if [[ "$line" == export* || "$line" == eval* ]]; then
    eval "$line"
    success_echo "🟢 当前终端已生效"
  fi
}

# =============== Homebrew（回车跳过） ===============
install_homebrew() {
  warm_echo "🍺 是否执行 Homebrew 检测 / 安装 / 更新？"
  warm_echo "👉 直接回车 = 跳过；输入任意字符再回车 = 执行 Homebrew 步骤。"
  printf "选择："
  local answer=""
  read -r answer
  if [[ -z "$answer" ]]; then
    info_echo "⏭ 已跳过 Homebrew 检测 / 安装 / 更新。"
    return 0
  fi

  local arch="$(get_cpu_arch)"
  local shell_path="${SHELL##*/}"
  local profile_file=""
  local brew_bin=""
  local shellenv_cmd=""

  if ! command -v brew &>/dev/null; then
    warn_echo "🧩 未检测到 Homebrew，准备安装中...（架构：$arch）"

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      error_echo "❌ Homebrew 安装失败"
      exit 1
    }

    if [[ "$arch" == "arm64" ]]; then
      brew_bin="/opt/homebrew/bin/brew"
    else
      brew_bin="/usr/local/bin/brew"
    fi
    if [[ ! -x "$brew_bin" ]]; then
      brew_bin="$(command -v brew 2>/dev/null || true)"
    fi
    if [[ -z "$brew_bin" || ! -x "$brew_bin" ]]; then
      error_echo "❌ 无法找到 Homebrew 可执行文件，请检查安装日志。"
      exit 1
    fi

    shellenv_cmd="eval \"$($brew_bin shellenv)\""
    case "$shell_path" in
      zsh)  profile_file="$HOME/.zprofile" ;;
      bash) profile_file="$HOME/.bash_profile" ;;
      *)    profile_file="$HOME/.profile" ;;
    esac

    inject_shellenv_block "$profile_file" "$shellenv_cmd"
    success_echo "✅ Homebrew 安装完成"

  else
    info_echo "🔄 检测到已安装 Homebrew，开始执行更新..."
    brew update && brew upgrade && brew cleanup && brew doctor && brew -v
    success_echo "✅ Homebrew 已更新"
  fi
}

# =============== fzf（回车跳过） ===============
install_fzf() {
  warm_echo "🔍 是否检查 / 安装 / 升级 fzf？"
  warm_echo "👉 直接回车 = 跳过；输入任意字符再回车 = 执行 fzf 步骤。"
  printf "选择："
  local answer=""
  read -r answer
  if [[ -z "$answer" ]]; then
    info_echo "⏭ 已跳过 fzf 检查 / 安装 / 升级。"
    return 0
  fi

  if ! command -v fzf &>/dev/null; then
    if ! command -v brew &>/dev/null; then
      error_echo "❌ 未检测到 fzf，且系统未安装 Homebrew，无法自动安装 fzf。"
      warm_echo "如需安装，请先手动安装 Homebrew 或在脚本中执行 Homebrew 安装步骤。"
      return 1
    fi
    note_echo "📦 未检测到 fzf，正在通过 Homebrew 安装..."
    brew install fzf || { error_echo "❌ fzf 安装失败"; exit 1; }
    success_echo "✅ fzf 安装成功"
  else
    if command -v brew &>/dev/null; then
      info_echo "🔄 fzf 已安装，正在通过 Homebrew 升级..."
      brew upgrade fzf && brew cleanup
      success_echo "✅ fzf 已是最新版"
    else
      info_echo "ℹ 检测到 fzf 已安装，且未使用 Homebrew 管理，跳过升级。"
    fi
  fi
}

# =============== 获取 Git 仓库路径（兼容子 git / 子目录） ===============
resolve_git_repo_path() {
  while true; do
    # 1️⃣ 尝试：脚本所在目录向上找最近的 Git 仓库
    local script_dir="$SCRIPT_DIR"
    local toplevel
    toplevel=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$toplevel" ]]; then
      echo "$toplevel"
      return
    fi

    # 2️⃣ 不在仓库里 → 让用户拖路径
    warn_echo "📂 当前脚本目录不在任何 Git 仓库内。"
    warm_echo "请将【Git 仓库文件夹】或其子目录拖入终端，然后按回车："
    printf "👉 路径："

    local input_path=""
    if ! read -r input_path; then
      error_echo "❌ 未读取到路径，已取消。"
      exit 1
    fi

    # 去掉引号、首尾空白，并把 '\ ' 还原为空格
    input_path="${input_path//\"/}"
    input_path="${input_path#"${input_path%%[![:space:]]*}"}"
    input_path="${input_path%"${input_path##*[![:space:]]}"}"
    input_path="${input_path//\\ / }"

    if [[ -z "$input_path" ]]; then
      warn_echo "⚠ 路径为空，请重新拖入。"
      continue
    fi

    local abs_path
    if ! abs_path="$(cd "$input_path" 2>/dev/null && pwd)"; then
      error_echo "❌ 无法进入路径：$input_path，请重新拖入。"
      continue
    fi

    toplevel=$(git -C "$abs_path" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$toplevel" ]]; then
      echo "$toplevel"
      return
    else
      error_echo "❌ 该路径不在任何 Git 仓库内，请重新拖入。"
    fi
  done
}

# =============== 进入 Git 仓库目录（兼容 SourceTree） ===============
enter_git_repo_dir() {
  local git_root=""

  if [[ "$RUN_MODE" == "sourcetree" && -n "${REPO_FROM_ARG:-}" ]]; then
    local toplevel
    toplevel=$(git -C "$REPO_FROM_ARG" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -z "$toplevel" ]]; then
      error_echo "❌ SourceTree 传入的路径不是 Git 仓库：$REPO_FROM_ARG"
      exit 1
    fi
    git_root="$toplevel"
  else
    git_root="$(resolve_git_repo_path)"
  fi

  cd "$git_root" || {
    error_echo "❌ 进入 Git 仓库失败：$git_root"
    exit 1
  }
  highlight_echo "当前 Git 仓库：$git_root"
}

# =============== 检查暂存区（仅交互模式用） ===============
check_staged_changes() {
  if ! git diff --cached --quiet 2>/dev/null; then
    warn_echo "⚠ 检测到暂存区存在变更（staged changes）。"
    warm_echo "建议先处理这些变更再执行回退，以免混乱。"
    read "ans?👉 仍要继续回退？(y/N)："
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      info_echo "⏹ 已取消回退操作。"
      exit 0
    fi
  fi
}

# =============== soft 回退到远端（你要的“推送打回提交”） ===============
reset_soft_to_remote() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  local upstream="origin/${branch}"

  if ! git rev-parse --verify "$upstream" &>/dev/null; then
    error_echo "❌ 远端分支 $upstream 不存在，无法 soft 回退。"
    return 1
  fi

  local ahead
  ahead=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo "0")

  info_echo "当前分支：$branch"
  info_echo "远端分支：$upstream"
  info_echo "本地比远端多了 ${ahead} 个提交。"
  info_echo "执行：git reset --soft $upstream"

  git reset --soft "$upstream"

  success_echo "✅ 已 soft 回退到远端 $upstream"
  note_echo "   - 所有未推送的提交已被撤销"
  note_echo "   - 对应改动现在处于【已暂存】状态，会出现在提交面板里"
}

# =============== hard 回退到远端（交互模式可选） ===============
reset_hard_to_remote() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  local upstream="origin/${branch}"

  if ! git rev-parse --verify "$upstream" &>/dev/null; then
    error_echo "❌ 远端分支 $upstream 不存在，无法 hard 回退。"
    return 1
  fi

  warn_echo "⚠ 警告：即将硬回退到 $upstream，本地未提交变更会丢失！"
  read "ans?👉 确认继续？(y/N)："
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    info_echo "⏹ 已取消 hard 回退。"
    return 0
  fi

  info_echo "🔁 执行：git reset --hard $upstream"
  git reset --hard "$upstream"
  success_echo "✅ 已 hard 回退到远端 $upstream"
}

# =============== 选择 Commit / Tag / Reflog 的几个函数（只在交互模式用） ===============
reset_to_selected_commit() {
  local commits
  commits=$(git log --oneline --decorate --graph --all | head -200)

  if [[ -z "$commits" ]]; then
    error_echo "❌ 没有可供选择的提交记录。"
    return 1
  fi

  local selected
  selected=$(printf "%s\n" "$commits" | fzf --no-sort --reverse --ansi \
             --prompt="🔍 选择目标提交：" \
             --header="↑↓ 移动，回车确认")
  if [[ -z "$selected" ]]; then
    info_echo "ℹ 未选择任何提交，已取消操作。"
    return 0
  fi

  local target_hash
  target_hash=$(echo "$selected" | awk '{print $2}')

  warn_echo "⚠ 将要回退到提交：$selected"
  read "ans?👉 确认回退到此提交？(y/N)："
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    info_echo "⏹ 已取消回退。"
    return 0
  fi

  git reset --hard "$target_hash"
  success_echo "✅ 已回退到提交：$selected"
}

reset_to_tag() {
  local tags
  tags=$(git tag --sort=-creatordate)

  if [[ -z "$tags" ]]; then
    error_echo "❌ 当前仓库没有任何 tag。"
    return 1
  fi

  local selected
  selected=$(printf "%s\n" "$tags" | fzf \
             --prompt="🏷 选择目标 tag：" \
             --header="选择要回退到的 tag")
  if [[ -z "$selected" ]]; then
    info_echo "ℹ 未选择任何 tag，已取消操作。"
    return 0
  fi

  warn_echo "⚠ 将要回退到 tag：$selected"
  read "ans?👉 确认回退到该 tag 对应的提交？(y/N)："
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    info_echo "⏹ 已取消回退。"
    return 0
  fi

  git reset --hard "$selected"
  success_echo "✅ 已回退到 tag：$selected"
}

reset_via_reflog() {
  local reflogs
  reflogs=$(git reflog --date=local | head -200)

  if [[ -z "$reflogs" ]]; then
    error_echo "❌ 没有可供选择的 reflog 记录。"
    return 1
  fi

  local selected
  selected=$(printf "%s\n" "$reflogs" | fzf --no-sort --reverse --ansi \
             --prompt="🕰 选择目标位置：" \
             --header="通过 reflog 回到任意历史状态")
  if [[ -z "$selected" ]]; then
    info_echo "ℹ 未选择任何记录，已取消操作。"
    return 0
  fi

  local target_hash
  target_hash=$(echo "$selected" | awk '{print $1}')

  warn_echo "⚠ 将要通过 reflog 回退到：$selected"
  read "ans?👉 确认回退到该状态？(y/N)："
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    info_echo "⏹ 已取消回退。"
    return 0
  fi

  git reset --hard "$target_hash"
  success_echo "✅ 已通过 reflog 回退到：$selected"
}

# =============== 模式选择（交互用） ===============
select_reset_mode() {
  local choice
  choice=$(printf "%s\n" \
    "1) soft 回退到远端（保留变更为暂存）" \
    "2) hard 回退到远端（丢弃本地变更）" \
    "3) 选择某个提交回退（git log + fzf）" \
    "4) 选择某个 tag 回退" \
    "5) 通过 reflog 回退到任意历史状态" \
    | fzf --prompt="🎯 选择回退模式：" \
          --header="↑↓ 选择，回车确认")

  case "$choice" in
    "1) "* ) reset_soft_to_remote ;;
    "2) "* ) reset_hard_to_remote ;;
    "3) "* ) reset_to_selected_commit ;;
    "4) "* ) reset_to_tag ;;
    "5) "* ) reset_via_reflog ;;
    * ) info_echo "ℹ 未选择任何模式，已退出。";;
  esac
}

# =============== 主流程 ===============
main() {
  if [[ "$RUN_MODE" == "sourcetree" ]]; then
    # 👉 SourceTree 调用：非交互，只做一件事：把未推送的提交打回提交面板
    enter_git_repo_dir
    reset_soft_to_remote
  else
    # 👉 双击 .command：完整交互模式
    clear
    print_git_reset_intro
    install_homebrew      # 回车跳过
    install_fzf           # 回车跳过
    enter_git_repo_dir
    check_staged_changes
    select_reset_mode
  fi
}

main "$@"
