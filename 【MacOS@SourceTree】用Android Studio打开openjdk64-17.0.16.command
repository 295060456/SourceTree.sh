#!/bin/zsh
set -euo pipefail

# 统一切到仓库根/传入目录
cd "${1:-$PWD}" || exit 1

# 1) 初始化 jenv & 插件
eval "$(jenv init -)"
jenv enable-plugin export || true

# 2) 确保有 JDK 17：先从系统找，没有再用 jenv add 纳管一次（幂等）
if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
  echo "❌ 系统未安装 JDK 17"; exit 1
fi
jenv add "$(/usr/libexec/java_home -v 17)" >/dev/null 2>&1 || true
jenv rehash

# 3) 动态挑一个“名字里带 17”的 jenv 版本（兼容 openjdk/temurin/zulu 命名差异）
pick_17="$(jenv versions --bare | grep -E '(^|[[:space:]])(.*17(\.|$).*)' | head -n1 || true)"
if [[ -z "${pick_17:-}" ]]; then
  echo "❌ jenv 里找不到 JDK 17，请检查 jenv versions"; exit 1
fi

# 4) 使用 shell 级覆盖（最高优先级），并**手动导出 JAVA_HOME**避免插件失效时的摇摆
jenv shell "$pick_17"
export JENV_VERSION="$pick_17"
export JAVA_HOME="$(jenv prefix)"   # 直接取 jenv 的前缀作为 JAVA_HOME，最稳
export PATH="$JAVA_HOME/bin:$PATH"  # 确保优先用到该 JDK

# 5) 本目录锁定（写 .java-version），防止父目录/global 干扰
echo "$pick_17" > .java-version

# 6) 打印诊断（确认真的是 17）
echo "JENV_VERSION=$JENV_VERSION"
echo "JAVA_HOME=$JAVA_HOME"
java -version

# 7) 打开 Android Studio（优先用 `studio` 以继承上面的 env；否则退回到 .app；最后跳官网）
open_android_studio() {
  local target_path="."
  # A) 有 jetbrains 的 CLI 启动器：最可靠，能继承当前进程环境变量
  if command -v studio >/dev/null 2>&1; then
    echo "▶ 使用 CLI：studio ${target_path}（可继承 JAVA_HOME 等环境变量）"
    exec studio "${target_path}"
  fi

  # B) 退回到 .app（注意：通过 open 启动 GUI 应用通常**不继承**当前 shell 的 env）
  local -a CANDIDATES=(
    "/Applications/Android Studio.app"
    "$HOME/Applications/Android Studio.app"
    "/Applications/Android Studio Beta.app"
    "$HOME/Applications/Android Studio Beta.app"
    "/Applications/Android Studio Preview.app"
    "$HOME/Applications/Android Studio Preview.app"
  )
  for app in "${CANDIDATES[@]}"; do
    if [[ -d "$app" ]]; then
      echo "ℹ️ 未发现 CLI 启动器，改用 GUI：$app（可能不继承当前环境变量）"
      exec open -a "$app" "${target_path}"
    fi
  done

  # C) 都没有 -> 跳转官网下载
  echo "⚠️ 未找到 Android Studio，前往官网下载。"
  exec open "https://developer.android.com/studio"
}

open_android_studio
