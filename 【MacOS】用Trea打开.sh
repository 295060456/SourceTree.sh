#!/bin/zsh

file="${1:-$PWD}"

if [[ -d "/Applications/Trae.app" ]]; then
  # 系统已安装 Trae.app
  open -a "Trae" "$file"
else
  # 没有安装 Trae，打开官网下载页面
  open "https://www.trae.cn/"
fi
