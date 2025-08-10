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

# 5) 可选：本目录锁定（写 .java-version），防止父目录/global 干扰
echo "$pick_17" > .java-version

# 6) 打印诊断（确认真的是 17）
echo "JENV_VERSION=$JENV_VERSION"
echo "JAVA_HOME=$JAVA_HOME"
java -version

# 7) 打开 Android Studio 继承以上 env）
exec studio -n .
