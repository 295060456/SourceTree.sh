#!/bin/zsh

file="${1:-$PWD}"

if [[ -d "/Applications/Visual Studio Code.app" || -d "$HOME/Applications/Visual Studio Code.app" ]]; then
  # 系统已安装 VS Code（支持系统级和用户级安装）
  open -a "Visual Studio Code" "$file"
else
  # 没有安装 VS Code，打开官网下载页面
  open "https://code.visualstudio.com/"
fi
