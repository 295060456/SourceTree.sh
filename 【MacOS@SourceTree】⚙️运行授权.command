#!/usr/bin/env zsh
# 【macOS | SourceTree 专用】为 .command 脚本添加执行权限（纯文本输出）

set -euo pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# -------------------- 日志与纯文本输出 --------------------
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

log()  { echo "$1" | tee -a "$LOG_FILE"; }
info() { log "[INFO] $1"; }
ok()   { log "[OK]   $1"; }
warn() { log "[WARN] $1"; }
err()  { log "[ERR]  $1"; }

trap '
  code=$?
  script_path=${0:A}
  err "失败（退出码 $code） at ${script_path}:${LINENO}"
  [[ ${#funcfiletrace[@]} -gt 0 ]] && { echo "—— 调用栈 ——"; print -l -- "${(F)funcfiletrace}"; } | tee -a "$LOG_FILE"
  echo "—— 日志尾部（最近 80 行）——"
  tail -n 80 "$LOG_FILE" 2>/dev/null || true
  exit $code
' ERR

# -------------------- PATH（SourceTree 非登录 Shell） --------------------
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true

# -------------------- 工具函数 --------------------
abs_path() {
  local p="${1:-}"
  p="${p//\"/}"
  [[ -z "$p" ]] && return 1
  [[ -f "$p" ]] && p="$(dirname "$p")"
  cd "$p" 2>/dev/null && pwd -P
}

list_targets_in_dir() {
  # 参数：$1=目录  $2=是否递归(0/1)
  setopt localoptions extended_glob null_glob
  local dir="$1" rec="$2"
  local files=()
  if [[ "$rec" == "1" ]]; then
    files=("$dir"/**/*.command(N))
  else
    files=("$dir"/*.command(N))
  fi
  reply=("${files[@]}")
}

remove_quarantine_if_possible() {
  # xattr 在极少数精简系统上可能不存在，先探测
  if command -v xattr >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$1" 2>>"$LOG_FILE" || true
  fi
}

# -------------------- 主逻辑 --------------------
main() {
  local SCRIPT_DIR; SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd -P)"

  # —— 基准目录优先级：
  # 1) 显式第一个参数（如果提供，则消费并 shift）
  # 2) 环境变量 $REPO
  # 3) 脚本所在目录（独立运行时兜底；在 SourceTree 步骤脚本里也安全）
  local BASE_DIR=""
  if [[ -n "${1:-}" ]]; then
    BASE_DIR="$(abs_path "$1" || true)"
    [[ -z "$BASE_DIR" ]] && { err "参数路径无效：$1"; exit 1; }
    shift   # ✅ 只有在确实使用了 $1 时才 shift，避免“shift count must be <= $#”
  elif [[ -n "${REPO:-}" ]]; then
    BASE_DIR="$(abs_path "$REPO" || true)"
    [[ -z "$BASE_DIR" ]] && { err "环境变量 REPO 路径无效：$REPO"; exit 1; }
  else
    BASE_DIR="$SCRIPT_DIR"
  fi

  local RECUR="${RECURSIVE:-0}"
  [[ "$RECUR" == "1" ]] && info "模式：递归授权" || info "模式：当前目录授权"
  info "基准目录：$BASE_DIR"

  # —— 收集目标：如果后续还传了参数，则把它们当作文件/目录；否则枚举 BASE_DIR
  typeset -a targets=()
  if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
      local raw="$1"; shift
      if [[ -f "$raw" ]]; then
        targets+=("${raw}")
      elif [[ -d "$raw" ]]; then
        list_targets_in_dir "$(abs_path "$raw")" "$RECUR"
        targets+=("${reply[@]}")
      else
        warn "忽略无效路径：$raw"
      fi
    done
  else
    list_targets_in_dir "$BASE_DIR" "$RECUR"
    targets+=("${reply[@]}")
  fi

  if [[ ${#targets[@]} -eq 0 ]]; then
    warn "未找到任何 .command 文件"
    ok "完成（无操作）。日志：$LOG_FILE"
    return 0
  fi

  info "待授权文件数：${#targets[@]}"

  # 去重
  typeset -A seen; typeset -a uniq_targets=()
  for f in "${targets[@]}"; do
    [[ -z "${seen[$f]:-}" ]] && { uniq_targets+=("$f"); seen[$f]=1; }
  done
  targets=("${uniq_targets[@]}")

  local ok_cnt=0 fail_cnt=0
  for f in "${targets[@]}"; do
    if [[ -x "$f" ]]; then
      ok "[skip] 已可执行：$f"
      remove_quarantine_if_possible "$f"
      ok_cnt=$((ok_cnt+1))
    else
      if chmod +x "$f" 2>>"$LOG_FILE"; then
        remove_quarantine_if_possible "$f"
        ok "[+x] 授权成功：$f"
        ok_cnt=$((ok_cnt+1))
      else
        err "[FAIL] 授权失败：$f"
        fail_cnt=$((fail_cnt+1))
      fi
    fi
  done

  info "统计：成功 $ok_cnt 个；失败 $fail_cnt 个"
  ok "完成。日志：$LOG_FILE"
}

main "$@"
