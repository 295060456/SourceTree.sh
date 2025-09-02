#!/usr/bin/env zsh

# ============================== 配置开关（可用环境变量覆盖） ==============================
WATCH="${WATCH:-0}"     # 交互时可 WATCH=1 开启 build_runner watch；非交互一律关闭
PROJECT_DIR="${PROJECT_DIR:-}"  # 指定项目根；不指定则自动探测

# ============================== 工具链选择（FVM 优先） ==============================
typeset -ga flutter_cmd dart_cmd
_set_toolchain() {
  if command -v fvm >/dev/null 2>&1 && [[ -f ".fvmrc" || -d ".fvm" ]]; then
    flutter_cmd=(fvm flutter)
    dart_cmd=(fvm dart)
  else
    if ! command -v flutter >/dev/null 2>&1; then
      echo "❌ 未找到 flutter 命令；请确认 PATH 或安装 FVM/Flutter。"; exit 1
    fi
    flutter_cmd=(flutter)
    # 优先使用 Flutter 内置的 dart（避免系统 dart 版本不一致）
    local dart_in_flutter
    dart_in_flutter="$(dirname "$(command -v "${flutter_cmd[@]}")")/../cache/dart-sdk/bin/dart"
    if [[ -x "$dart_in_flutter" ]]; then
      dart_cmd=("$dart_in_flutter")
    else
      dart_cmd=(dart)
    fi
  fi
}

# ============================== TTY 检测 & 说明 ==============================
_is_tty() { [[ -t 0 && -t 1 ]]; }

print_description() {
  cat <<'DESC'
[目的]
1) 确保你在 Flutter 项目根目录（同时存在 lib/ 与 pubspec.yaml）。
2) 交互模式下会等待你按回车并支持拖拽路径；非交互模式自动探测项目根。
3) 根据项目配置自动跑：pub get、build_runner、图标、Splash、l10n、FFI、Pigeon、Protobuf。

[提示]
- 非交互环境（如 SourceTree 自定义动作）不会等待输入，也不会进入 watch。
- 使用 FVM 时自动用 FVM 的 flutter/dart；否则用系统 flutter 与其内置 dart。
DESC
}

wait_for_user_to_start() {
  echo ""
  read "?👉 按下回车开始执行（Ctrl+C 取消）"
  echo ""
}

# ============================== 项目根判断 & 查找 ==============================
_is_flutter_root() { [[ -d "$1/lib" && -f "$1/pubspec.yaml" ]]; }

_find_flutter_root_upwards() {
  local d="$1"
  while [[ "$d" != "/" && -n "$d" ]]; do
    _is_flutter_root "$d" && { echo "$d"; return 0; }
    d="${d:h}"
  done
  return 1
}

detect_and_cd_flutter_root() {
  # 优先显式指定
  if [[ -n "$PROJECT_DIR" ]]; then
    if _is_flutter_root "$PROJECT_DIR"; then
      cd "$PROJECT_DIR" || { echo "❌ 切换失败：$PROJECT_DIR"; exit 1; }
      echo "✅ 已切换到 Flutter 项目目录：$PWD"
      return 0
    else
      echo "❌ 指定的 PROJECT_DIR 不是 Flutter 根：$PROJECT_DIR"; exit 1
    fi
  fi

  if _is_tty; then
    # 交互模式：循环询问
    while true; do
      if _is_flutter_root "$PWD"; then
        echo "✅ 已确认 Flutter 项目目录：$PWD"; return 0
      fi
      echo "❌ 当前目录不是 Flutter 根：$PWD（需有 lib/ 与 pubspec.yaml）"
      echo "提示：可将项目根目录从 Finder 拖入后回车。"
      read "input_path?👉 请输入 Flutter 项目路径（或直接回车重新检测当前目录）： "
      [[ -z "$input_path" ]] && continue
      # 去引号与空格转义
      local p="${input_path//\\ / }"; p="${p%\"}"; p="${p#\"}"; p="${p%\'}"; p="${p#\'}"
      [[ "$p" = ~* ]] && p="${p/#\~/$HOME}"
      if _is_flutter_root "$p"; then
        cd "$p" || { echo "❌ 切换失败：$p"; echo ""; continue; }
        echo "✅ 已切换到 Flutter 项目目录：$PWD"; return 0
      else
        echo "❌ [$p] 不是合法 Flutter 根"; echo ""
      fi
    done
  else
    # 非交互模式：自动探测（当前目录 → git 根）
    if _is_flutter_root "$PWD"; then
      echo "✅ 非交互：使用当前目录作为 Flutter 根：$PWD"; return 0
    fi
    local git_root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$git_root" ]]; then
      local found
      found="$(_find_flutter_root_upwards "$git_root")" || true
      if [[ -n "$found" ]]; then
        cd "$found" || { echo "❌ 切换失败：$found"; exit 1; }
        echo "✅ 非交互：已定位 Flutter 根：$PWD"; return 0
      fi
    fi
    echo "❌ 非交互：未能自动定位 Flutter 根，请设置 PROJECT_DIR=路径 后重试。"; exit 1
  fi
}

# ============================== 运行辅助 ==============================
run_step() {
  local title="$1"; shift
  echo "==> $title"
  if "$@"; then
    echo "✅ $title 完成"; echo ""
  else
    echo "⚠️  $title 失败（忽略继续）"; echo ""
  fi
}

exists() { command -v "$1" >/dev/null 2>&1; }

has_yaml_key() { grep -qE "^[[:space:]]*$1[[:space:]]*:" pubspec.yaml; }

# ============================== 图标产物汇总 ==============================
show_icon_summary() {
  echo "—— 图标产物汇总 ——"

  echo "Android:"
  ls -1 android/app/src/main/res/mipmap-*/ic_launcher.* 2>/dev/null || echo "（未找到 Android ic_launcher 图标）"

  echo ""
  echo "iOS:"
  ls -lh ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png 2>/dev/null || echo "（未找到 iOS 图标 PNG）"

  echo "—— 结束 ——"
  echo ""
}

# ============================== 主流程 ==============================
main() {
  _set_toolchain
  if _is_tty; then clear; print_description; wait_for_user_to_start; else echo "ℹ 非交互模式（SourceTree 等）"; fi
  detect_and_cd_flutter_root

  # 1) 清理 & 依赖
  run_step "flutter clean" "${flutter_cmd[@]}" clean
  run_step "flutter pub get" "${flutter_cmd[@]}" pub get

  # 2) build_runner（一次性；watch 仅交互+显式开启）
  if grep -q 'build_runner' pubspec.yaml; then
    run_step "build_runner build" "${dart_cmd[@]}" run build_runner build --delete-conflicting-outputs
    if _is_tty && [[ "$WATCH" == "1" ]]; then
      echo "==> build_runner watch（按 Ctrl+C 结束）"
      exec "${dart_cmd[@]}" run build_runner watch --delete-conflicting-outputs
    fi
  fi

  # 3) App Icon（flutter_launcher_icons）
  if has_yaml_key "flutter_launcher_icons"; then
    # 清残留，避免 v26 xml 搞事
    find android/app/src/main/res -name 'ic_launcher*' -delete 2>/dev/null || true
    run_step "生成 App Icon (flutter_launcher_icons)" \
      "${flutter_cmd[@]}" pub run flutter_launcher_icons:main
    # ✅ 同时打印 Android + iOS 产物
    show_icon_summary
  fi

  # 4) Splash（flutter_native_splash）
  if grep -q 'flutter_native_splash' pubspec.yaml; then
    run_step "生成启动页 (flutter_native_splash)" \
      "${flutter_cmd[@]}" pub run flutter_native_splash:create
  fi

  # 5) 官方 l10n
  if [[ -d "lib/l10n" || -f "l10n.yaml" ]]; then
    run_step "生成本地化 (flutter gen-l10n)" "${flutter_cmd[@]}" gen-l10n
  fi

  # 6) ffigen（需配置）
  if grep -q 'ffigen' pubspec.yaml; then
    run_step "FFI 绑定生成 (ffigen)" "${dart_cmd[@]}" run ffigen
  fi

  # 7) Pigeon（若有 pigeons 目录）
  if [[ -d "pigeons" ]]; then
    mkdir -p lib/pigeon
    run_step "Pigeon 生成" "${dart_cmd[@]}" run pigeon \
      --input pigeons/messages.dart \
      --dart_out lib/pigeon/messages.g.dart
  fi

  # 8) Protobuf（若有 protos 且安装了 protoc）
  if [[ -d "protos" ]] && exists protoc; then
    mkdir -p lib/generated
    run_step "Protobuf/gRPC 生成" protoc --dart_out=grpc:lib/generated -Iprotos protos/*.proto
  fi

  echo "🎯 全部完成。"
}

main "$@"
