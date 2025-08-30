#!/bin/zsh

file="${1:-$PWD}"

if [[ -d "/Applications/Android Studio.app" || -d "$HOME/Applications/Android Studio.app" ]]; then
  # 系统已安装 Android Studio（支持系统级和用户级安装）
  open -a "Android Studio" "$file"
else
  # 没有安装 Android Studio，打开官网下载页面
  open "https://developer.android.com/studio"
fi
