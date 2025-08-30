#!/usr/bin/env zsh
# 【MacOS】修复 Flutter 项目中 import 中文被 URI 编码的路径（SourceTree 专用 / 无颜色无 emoji）
set -euo pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# 错误输出
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"; : > "$LOG_FILE"
trap '
  code=$?
  script_path=${0:A}
  echo "✖ 失败（退出码 $code） at ${script_path}:${LINENO}"
  [[ ${#funcfiletrace[@]} -gt 0 ]] && { echo "—— 调用栈 ——"; print -l -- "${(F)funcfiletrace}"; }
  echo "—— 日志尾部（最近 80 行）——"; tail -n 80 "$LOG_FILE" 2>/dev/null || true
  exit $code
' ERR

# SourceTree 下补 PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true

# 输出函数（纯文本）
log()        { echo "$1" | tee -a "$LOG_FILE"; }
info_echo()  { log "[INFO] $1"; }
success_echo(){ log "[OK]   $1"; }
warn_echo()  { log "[WARN] $1"; }
error_echo() { log "[ERR]  $1"; }
debug_echo() { [[ "${DEBUG:-0}" == "1" ]] && log "[DBG]  $1"; }

# 判断 Flutter 项目
is_flutter_project_root() { [[ -f "$1/pubspec.yaml" && -d "$1/lib" ]]; }

# 解析项目根（参数/REPO 优先，找不到就全仓库搜索）
typeset -g FLUTTER_ROOT=""
typeset -g ENTRY_FILE=""
resolve_project_root() {
  set +e
  local arg="${1:-}" repo_root cand
  if [[ -n "$arg" ]]; then
    [[ -f "$arg" ]] && arg="$(dirname "$arg")"
    if cd "$arg" 2>/dev/null; then
      repo_root="$(pwd -P)"
      if is_flutter_project_root "$repo_root"; then
        FLUTTER_ROOT="$repo_root"; ENTRY_FILE="$repo_root/lib/main.dart"; set -e; return 0
      fi
    fi
  fi
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  else
    repo_root="$(pwd -P)"
  fi
  if [[ -f "$repo_root/pubspec.yaml" && -d "$repo_root/lib" ]]; then
    FLUTTER_ROOT="$repo_root"; ENTRY_FILE="$repo_root/lib/main.dart"; set -e; return 0
  fi
  cand="$(/usr/bin/find "$repo_root" -name pubspec.yaml -type f -print 2>/dev/null | head -n1)"
  if [[ -n "$cand" ]]; then
    FLUTTER_ROOT="$(dirname "$cand")"; ENTRY_FILE="$FLUTTER_ROOT/lib/main.dart"; set -e; return 0
  fi
  set -e
  error_echo "未找到 Flutter 项目（缺 pubspec.yaml 或 lib）"
  exit 1
}

# Perl 检测（有就用，没有就 Python 兜底）
typeset -g USE_PERL_URI_ESCAPE=0
ensure_perl_and_module() {
  if command -v perl >/dev/null 2>&1 && perl -MURI::Escape -e 1 >/dev/null 2>&1; then
    USE_PERL_URI_ESCAPE=1; info_echo "Perl + URI::Escape 可用"
  else
    USE_PERL_URI_ESCAPE=0; info_echo "未检测到 Perl 模块，使用 Python3 兜底"
  fi
}

# 修复 import（zsh glob）
replace_uri_imports() {
  cd "$FLUTTER_ROOT"
  local BACKUP_DIR=".import_backup"; mkdir -p "$BACKUP_DIR"
  local changed=0
  for file in **/*.dart(N); do
    if grep -q "import 'package:[^']*%[0-9A-Fa-f][0-9A-Fa-f]" "$file"; then
      mkdir -p "$BACKUP_DIR/$(dirname "$file")"
      cp "$file" "$BACKUP_DIR/$file"
      if [[ "$USE_PERL_URI_ESCAPE" == "1" ]]; then
        perl -i -pe "use URI::Escape; s|(import\\s+'package:[^']*)|uri_unescape(\$1)|ge" "$file"
      else
        /usr/bin/env python3 - "$file" <<'PY'
import sys, re, urllib.parse, io
p = sys.argv[1]
with io.open(p,'r',encoding='utf-8',errors='ignore') as f:s=f.read()
def unq(m):return urllib.parse.unquote(m.group(0))
def repl(m):inner=m.group(1);return "import '"+re.sub(r'%[0-9A-Fa-f]{2}',unq,inner)+"'"
s2=re.sub(r"import\s+'(package:[^']*)'",repl,s)
if s2!=s:
  with io.open(p,'w',encoding='utf-8') as f:f.write(s2)
PY
      fi
      info_echo "修复：$file"; changed=$((changed+1))
    fi
  done
  [[ "$changed" -gt 0 ]] && success_echo "完成：修复 $changed 个文件；备份在 $BACKUP_DIR" || info_echo "未发现需要修复的 import"
}

# 自述
print_banner() {
  echo "[RUN] 修复 Flutter 项目 import 中文路径"
  echo " - 自动识别项目根（参数/ \$REPO 优先，找不到就全仓库搜索）"
  echo " - Perl 模块缺失自动 Python3 兜底"
  echo " - 按相对路径备份到 .import_backup/"
}

main() {
  print_banner
  resolve_project_root "${1:-${REPO:-}}"
  success_echo "项目路径：$FLUTTER_ROOT"
  ensure_perl_and_module
  replace_uri_imports
  success_echo "完成。日志：$LOG_FILE"
}

main "$@"
